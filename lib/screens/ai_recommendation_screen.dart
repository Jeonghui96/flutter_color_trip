import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart'; // GeoPoint 때문에 필요하면 유지
import 'package:fluttertoast/fluttertoast.dart'; // 토스트 메시지 때문에 필요하면 유지
import 'package:flutter_dotenv/flutter_dotenv.dart'; // API 키 로드를 위해 필요 (GeminiService에서 사용)

// 정적 메서드를 사용하는 GeminiService를 import 합니다.
import '../services/gemini_service.dart';

class AiRecommendationScreen extends StatefulWidget {
  const AiRecommendationScreen({super.key});

  @override
  State<AiRecommendationScreen> createState() => _AiRecommendationScreenState();
}

class _AiRecommendationScreenState extends State<AiRecommendationScreen> {
  // --- UploadScreen에서 가져온 GeoJSON 관련 변수들 ---
  String? _selectedSido; // 선택된 시/도
  String? _selectedSigungu; // 선택된 시/군/구 (드롭다운 표시용)

  List<String> _sidoNames = []; // 모든 시도 이름 리스트
  Map<String, List<String>> _sigunguNamesMap = {}; // 시도별 시군구 이름 맵
  Map<String, String> _sidoCodeMap = {}; // 시도 이름으로 코드 찾기
  Map<String, GeoPoint> _sidoCentroids = {}; // 시도별 중심 좌표
  Map<String, GeoPoint> _sigunguCentroids = {}; // 시군구/세종시 읍면동별 중심 좌표
  Map<String, String> _sejongDisplayToRawNameMap = {}; // 세종시 원본 adm_nm 저장
  // --- 끝 ---

  bool _isLoadingGeoJson = true; // GeoJSON 로딩 상태
  bool _isGeneratingRecommendation = false; // AI 추천 생성 중 상태

  String _aiRecommendationResult = ''; // AI 추천 결과 텍스트

  @override
  void initState() {
    super.initState();
    // dotenv.load()는 main() 함수에서 앱 시작 시 한 번만 호출되도록 권장됩니다.
    // 여기서는 GeoJSON 데이터만 로드합니다.
    _loadGeoJsonData();
  }

  // --- UploadScreen에서 가져온 GeoJSON 관련 함수들 ---
  // GeoJSON Feature에서 중심 좌표를 추출하는 헬퍼 함수
  GeoPoint? _getCentroidFromGeoJsonFeature(Map<String, dynamic> feature) {
    try {
      final geometry = feature['geometry'];
      if (geometry == null || geometry['coordinates'] == null) {
        return null;
      }

      final type = geometry['type'] as String;
      List<dynamic>? coords;

      if (type == 'Polygon') {
        coords = geometry['coordinates'][0];
      } else if (type == 'MultiPolygon') {
        if ((geometry['coordinates'] as List).isNotEmpty &&
            (geometry['coordinates'][0] as List).isNotEmpty &&
            (geometry['coordinates'][0][0] as List).isNotEmpty) {
          coords = geometry['coordinates'][0][0];
        }
      } else if (type == 'Point') {
        final pointCoords = geometry['coordinates']; // [경도, 위도]
        if (pointCoords.length >= 2) {
          final double longitude = (pointCoords[0] as num).toDouble();
          final double latitude = (pointCoords[1] as num).toDouble();
          return GeoPoint(latitude, longitude);
        }
      }

      if (coords != null && coords.isNotEmpty) {
        final List<dynamic> firstPoint = coords[0];
        if (firstPoint.length >= 2) {
          final double longitude = (firstPoint[0] as num).toDouble();
          final double latitude = (firstPoint[1] as num).toDouble();
          return GeoPoint(latitude, longitude);
        }
      }
    } catch (e) {
      debugPrint(
        'Error parsing centroid from feature: $e, Feature properties: ${feature['properties']}',
      );
    }
    return null;
  }

  // GeoJSON 파일을 로드하고 시도/시군구 목록 및 중심 좌표를 파싱하는 함수
  Future<void> _loadGeoJsonData() async {
    try {
      setState(() {
        _isLoadingGeoJson = true;
      });

      // 1. 시도 GeoJSON 로드
      final sidoData = await rootBundle.loadString(
        'assets/geo/skorea_provinces_2018_geo.json',
      );
      final decodedSidoJson = json.decode(sidoData);
      List<dynamic> sidoFeatures;
      if (decodedSidoJson is Map<String, dynamic> &&
          decodedSidoJson.containsKey('features')) {
        sidoFeatures = decodedSidoJson['features'] as List<dynamic>;
      } else {
        sidoFeatures = decodedSidoJson as List<dynamic>;
      }

      List<String> tempSidoNames = [];
      Map<String, String> tempSidoCodeMap = {};

      for (var feature in sidoFeatures) {
        final props = feature['properties'];
        final name = props['name'] as String;
        final code = props['code'].toString();
        tempSidoNames.add(name);
        tempSidoCodeMap[name] = code;

        final centroid = _getCentroidFromGeoJsonFeature(
          feature as Map<String, dynamic>,
        );
        if (centroid != null) {
          _sidoCentroids[name] = centroid;
        }
      }

      // 2. 시군구 GeoJSON 로드 (세종시 외 일반 시군구)
      final sigunguData = await rootBundle.loadString(
        'assets/geo/skorea_municipalities_2018_geo.json',
      );
      final decodedSigunguJson = json.decode(sigunguData);
      List<dynamic> sigunguFeatures;
      if (decodedSigunguJson is Map<String, dynamic> &&
          decodedSigunguJson.containsKey('features')) {
        sigunguFeatures = decodedSigunguJson['features'] as List<dynamic>;
      } else {
        sigunguFeatures = decodedSigunguJson as List<dynamic>;
      }

      Map<String, List<String>> tempSigunguNamesMap = {};

      for (var feature in sigunguFeatures) {
        final props = feature['properties'];
        final name = props['name'] as String;
        final code = props['code'].toString();

        String? parentSidoName;
        for (var entry in tempSidoCodeMap.entries) {
          if (code.startsWith(entry.value)) {
            parentSidoName = entry.key;
            break;
          }
        }

        if (parentSidoName != null) {
          if (!tempSigunguNamesMap.containsKey(parentSidoName)) {
            tempSigunguNamesMap[parentSidoName] = [];
          }
          tempSigunguNamesMap[parentSidoName]!.add(name);

          final centroid = _getCentroidFromGeoJsonFeature(
            feature as Map<String, dynamic>,
          );
          if (centroid != null) {
            _sigunguCentroids[name] = centroid;
          }
        }
      }

      // 3. 세종특별자치시 GeoJSON 로드 및 읍면동 추가 및 중심 좌표 저장
      try {
        final sejongData = await rootBundle.loadString(
          'assets/geo/sejong.geojson',
        );
        final decodedSejongJson = json.decode(sejongData);
        List<dynamic> sejongFeatures;
        if (decodedSejongJson is Map<String, dynamic> &&
            decodedSejongJson.containsKey('features')) {
          sejongFeatures = decodedSejongJson['features'] as List<dynamic>;
        } else if (decodedSejongJson is List<dynamic>) {
          sejongFeatures = decodedSejongJson;
        } else {
          throw FormatException(
            'Invalid GeoJSON format for Sejong. Expected a FeatureCollection or a list of Features.',
          );
        }

        List<String> sejongSubRegions = [];
        for (var feature in sejongFeatures) {
          final props = feature['properties'];
          String rawSubRegionName =
              props['adm_nm'] as String? ??
              props['name'] as String? ??
              '알 수 없는 세종 읍면동';

          String displaySubRegionName = rawSubRegionName;
          if (displaySubRegionName.startsWith('세종특별자치시 세종시 ')) {
            displaySubRegionName = displaySubRegionName.substring(
              '세종특별자치시 세종시 '.length,
            );
          } else if (displaySubRegionName.startsWith('세종특별자치시 ')) {
            displaySubRegionName = displaySubRegionName.substring(
              '세종특별자치시 '.length,
            );
          }

          sejongSubRegions.add(displaySubRegionName);
          _sejongDisplayToRawNameMap[displaySubRegionName] = rawSubRegionName;

          final centroid = _getCentroidFromGeoJsonFeature(
            feature as Map<String, dynamic>,
          );
          if (centroid != null) {
            _sigunguCentroids[displaySubRegionName] = centroid;
          }
        }
        tempSigunguNamesMap['세종특별자치시'] = sejongSubRegions;
      } catch (e) {
        debugPrint("세종 GeoJSON 로드 및 파싱 중 오류 발생: $e");
        // 세종시 GeoJSON 로드 실패 시에도 앱이 크래시되지 않도록 처리
      }

      tempSidoNames.forEach((sidoName) {
        if (sidoName == '세종특별자치시') {
          if (!tempSigunguNamesMap.containsKey(sidoName)) {
            tempSigunguNamesMap[sidoName] = [];
          }
          return;
        }

        if (!tempSigunguNamesMap.containsKey(sidoName)) {
          tempSigunguNamesMap[sidoName] = [];
        }
        if (!tempSigunguNamesMap[sidoName]!.contains(sidoName)) {
          tempSigunguNamesMap[sidoName]!.insert(0, sidoName);
        }
      });

      tempSigunguNamesMap.forEach((key, value) {
        if (key != '세종특별자치시' && value.length > 1) {
          final sidoName = value[0];
          final subList = value.sublist(1)..sort();
          value
            ..clear()
            ..add(sidoName)
            ..addAll(subList);
        } else if (key == '세종특별자치시' && value.length > 1) {
          value.sort();
        }
      });

      setState(() {
        _sidoNames = tempSidoNames..sort();
        _sigunguNamesMap = tempSigunguNamesMap;
        _isLoadingGeoJson = false;
      });
    } catch (e) {
      debugPrint('GeoJSON 데이터 로드 오류: $e');
      setState(() {
        _isLoadingGeoJson = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('지역 정보 로드에 실패했습니다: ${e.toString()}')),
      );
    }
  }
  // --- GeoJSON 관련 함수 끝 ---

  Future<void> _getAiRecommendations() async {
    if (_selectedSido == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('시/도를 선택해주세요.')),
      );
      return;
    }

    setState(() {
      _isGeneratingRecommendation = true;
      _aiRecommendationResult = ''; // 이전 결과 초기화
    });

    try {
      String locationPrompt = _selectedSido!;
      // 세종시의 경우, 원본 adm_nm을 프롬프트에 포함하여 정확도를 높일 수 있습니다.
      if (_selectedSido == '세종특별자치시' && _selectedSigungu != null && _sejongDisplayToRawNameMap.containsKey(_selectedSigungu!)) {
        locationPrompt = _sejongDisplayToRawNameMap[_selectedSigungu!]!; // 예: "세종특별자치시 세종시 연동면"
      } else if (_selectedSigungu != null && _selectedSigungu!.isNotEmpty && _selectedSigungu! != _selectedSido!) {
        locationPrompt += ' $_selectedSigungu';
      }

      // 프롬프트 구성 (구체적으로 요청)
      // GeminiService의 systemInstruction이 마크다운 사용을 금지하므로, 답변 형식에 맞춰 요청합니다.
      final userPrompt = "$locationPrompt 에 있는 명소 3군데와 맛집 3군데를 추천해줘. 각 추천에는 간단한 설명도 포함해줘. "
                         "응답은 다음과 같은 형식으로 부탁해: "
                         "명소:\n1. [명소1 이름] - [간단 설명]\n2. [명소2 이름] - [간단 설명]\n3. [명소3 이름] - [간단 설명]\n\n맛집:\n1. [맛집1 이름] - [간단 설명]\n2. [맛집2 이름] - [간단 설명]\n3. [맛집3 이름] - [간단 설명]";

      // GeminiService의 static 메서드 호출
      final response = await GeminiService.getRecommendation(userPrompt);

      setState(() {
        _aiRecommendationResult = response;
      });

    } catch (e) {
      debugPrint('AI 추천 생성 실패: $e');
      setState(() {
        _aiRecommendationResult = '추천을 생성하는 중 오류가 발생했습니다: ${e.toString()}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI 추천 생성에 실패했습니다: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isGeneratingRecommendation = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingGeoJson) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI 여행지 추천')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('AI 여행지 추천')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '여행 지역을 선택하고 AI 추천을 받아보세요!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // 시/도 선택 드롭다운 (필수)
            DropdownButtonFormField<String>(
              value: _selectedSido,
              hint: const Text('지역 (시/도) 선택 *'),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '지역 (시/도) *',
              ),
              items: _sidoNames.map((String sido) {
                return DropdownMenuItem<String>(
                  value: sido,
                  child: Text(sido),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedSido = newValue;
                  _selectedSigungu = null; // 시도가 바뀌면 세부 지역 초기화
                });
              },
            ),
            const SizedBox(height: 8),

            // 세부 지역 드롭다운 (선택된 시도에 따라 필터링)
            DropdownButtonFormField<String>(
              value: _selectedSigungu,
              hint: const Text('세부 지역 (시/군/구/읍/면/동) 선택'),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '세부 지역 (시/군/구/읍/면/동)',
              ),
              items: _selectedSido != null
                  ? (_sigunguNamesMap[_selectedSido!] ?? []).map((String sigungu) {
                      return DropdownMenuItem<String>(
                        value: sigungu,
                        child: Text(sigungu),
                      );
                    }).toList()
                  : [],
              onChanged: _selectedSido != null
                  ? (String? newValue) {
                      setState(() {
                        _selectedSigungu = newValue;
                      });
                      if (newValue != null && newValue.isNotEmpty) {
                        Fluttertoast.showToast(
                          msg: "$newValue을(를) 선택했습니다.",
                          toastLength: Toast.LENGTH_SHORT,
                          gravity: ToastGravity.BOTTOM,
                          timeInSecForIosWeb: 1,
                          backgroundColor: Colors.black54,
                          textColor: Colors.white,
                          fontSize: 16.0,
                        );
                      }
                    }
                  : null, // 시도가 선택되지 않으면 비활성화
              isExpanded: true,
              menuMaxHeight: 300,
            ),

            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _isGeneratingRecommendation || _selectedSido == null
                  ? null
                  : _getAiRecommendations,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isGeneratingRecommendation
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(width: 16),
                        Text('추천 생성 중...', style: TextStyle(fontSize: 18)),
                      ],
                    )
                  : const Text('AI 추천 받기', style: TextStyle(fontSize: 18)),
            ),

            const SizedBox(height: 32),

            if (_aiRecommendationResult.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI 추천 결과:',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      _aiRecommendationResult,
                      style: const TextStyle(fontSize: 16, height: 1.5),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}