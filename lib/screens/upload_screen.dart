import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:flutter_exif_rotation/flutter_exif_rotation.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:fluttertoast/fluttertoast.dart';


class UploadScreen extends StatefulWidget {
  final String uid;
  final String? groupId;
  final VoidCallback? onUploadComplete;

  const UploadScreen({
    super.key,
    required this.uid,
    this.groupId,
    this.onUploadComplete,
  });

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? _image;
  bool _isLoading = false;
  List<Color> _extractedColors = [];
  Color? _selectedColor;
  String? _selectedColorName;

  final _placeController = TextEditingController();
  final _memoController = TextEditingController();

  String? _selectedSido; // 선택된 시/도
  String? _selectedSigungu; // 선택된 시/군/구 (드롭다운 표시용, 예: '연동면')

  List<String> _sidoNames = []; // 모든 시도 이름 리스트
  Map<String, List<String>> _sigunguNamesMap = {}; // 시도별 시군구 이름 맵
  Map<String, String> _sidoCodeMap = {}; // 시도 이름으로 코드 찾기 (시군구 필터링용)

  // GeoJSON에서 파싱된 중심 좌표를 저장할 맵 추가
  Map<String, GeoPoint> _sidoCentroids = {}; // 시도별 중심 좌표
  // 이 맵에는 '연동면'과 같이 드롭다운에 표시되는 이름이 키로 사용됩니다.
  Map<String, GeoPoint> _sigunguCentroids = {}; // 시군구/세종시 읍면동별 중심 좌표

  // 세종시의 경우 원본 adm_nm을 저장하기 위한 맵 추가
  // 드롭다운에 표시되는 이름(key)과 GeoJSON의 원본 adm_nm(value)을 매핑합니다.
  Map<String, String> _sejongDisplayToRawNameMap = {};

  @override
  void initState() {
    super.initState();
    _loadGeoJsonData(); // GeoJSON 데이터 로드
  }

  @override
  void dispose() {
    _placeController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  // GeoJSON Feature에서 중심 좌표를 추출하는 헬퍼 함수
  // MultiPolygon, Polygon 타입만 처리하며, 간단히 첫 번째 좌표를 반환 (정확한 centroid는 아님)
  GeoPoint? _getCentroidFromGeoJsonFeature(Map<String, dynamic> feature) {
    try {
      final geometry = feature['geometry'];
      if (geometry == null || geometry['coordinates'] == null) {
        return null;
      }

      final type = geometry['type'] as String;
      List<dynamic>? coords;

      if (type == 'Polygon') {
        // Polygon의 경우, 첫 번째 링의 좌표들 (외부 링)
        coords = geometry['coordinates'][0];
      } else if (type == 'MultiPolygon') {
        // MultiPolygon의 경우, 첫 번째 Polygon의 첫 번째 링을 사용
        // GeoJSON MultiPolygon 구조는 [[[coord,coord],[coord,coord]],[[...]]]
        if ((geometry['coordinates'] as List).isNotEmpty &&
            (geometry['coordinates'][0] as List).isNotEmpty &&
            (geometry['coordinates'][0][0] as List).isNotEmpty) {
          coords = geometry['coordinates'][0][0];
        }
      } else if (type == 'Point') {
        // Point 타입인 경우, 바로 좌표를 사용
        final pointCoords = geometry['coordinates']; // [경도, 위도]
        if (pointCoords.length >= 2) {
          final double longitude = (pointCoords[0] as num).toDouble();
          final double latitude = (pointCoords[1] as num).toDouble();
          return GeoPoint(latitude, longitude); // 위도, 경도 순서로 GeoPoint 생성
        }
      }

      // Polygon 또는 MultiPolygon에서 추출된 coords가 유효한 경우
      if (coords != null && coords.isNotEmpty) {
        final List<dynamic> firstPoint =
            coords[0]; // firstPoint는 [경도, 위도] 형태의 List<dynamic>

        if (firstPoint.length >= 2) {
          // 경도(longitude)와 위도(latitude)는 num 타입일 수 있으므로 toDouble()로 명시적 변환
          final double longitude = (firstPoint[0] as num).toDouble();
          final double latitude = (firstPoint[1] as num).toDouble();

          return GeoPoint(latitude, longitude); // 위도, 경도 순서로 GeoPoint 생성
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
        _isLoading = true; // 데이터 로드 시작
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
        // FeatureCollection이 아닌 경우 (바로 Feature 리스트일 경우)
        sidoFeatures = decodedSidoJson as List<dynamic>;
      }

      List<String> tempSidoNames = [];
      Map<String, String> tempSidoCodeMap = {};

      for (var feature in sidoFeatures) {
        final props = feature['properties'];
        final name = props['name'] as String;
        final code = props['code'].toString(); // 시도 코드
        tempSidoNames.add(name);
        tempSidoCodeMap[name] = code;

        // 시도 중심 좌표 저장
        final centroid = _getCentroidFromGeoJsonFeature(
          feature as Map<String, dynamic>,
        );
        if (centroid != null) {
          _sidoCentroids[name] = centroid;
          // debugPrint('Sido Centroid: $name -> ${centroid.latitude}, ${centroid.longitude}');
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
        // FeatureCollection이 아닌 경우 (바로 Feature 리스트일 경우)
        sigunguFeatures = decodedSigunguJson as List<dynamic>;
      }

      Map<String, List<String>> tempSigunguNamesMap = {};

      for (var feature in sigunguFeatures) {
        final props = feature['properties'];
        final name = props['name'] as String; // 시군구 이름 (예: "동구", "수원시")
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

          // 시군구 중심 좌표 저장
          final centroid = _getCentroidFromGeoJsonFeature(
            feature as Map<String, dynamic>,
          );
          if (centroid != null) {
            _sigunguCentroids[name] = centroid;
            // debugPrint('Sigungu Centroid: $name -> ${centroid.latitude}, ${centroid.longitude}');
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
        // 세종 GeoJSON은 바로 Feature 리스트로 시작할 수도 있음.
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

          // 드롭다운에 표시될 이름 (접두사 제거)
          String displaySubRegionName = rawSubRegionName;
          if (displaySubRegionName.startsWith('세종특별자치시 세종시 ')) {
            displaySubRegionName = displaySubRegionName.substring(
              '세종특별자치시 세종시 '.length,
            );
          } else if (displaySubRegionName.startsWith('세종특별자치시 ')) {
            // 혹시 '세종시' 부분이 없을 경우 대비
            displaySubRegionName = displaySubRegionName.substring(
              '세종특별자치시 '.length,
            );
          }

          sejongSubRegions.add(displaySubRegionName); // 드롭다운에 표시될 이름
          // 드롭다운 표시 이름과 원본 이름 매핑 저장
          _sejongDisplayToRawNameMap[displaySubRegionName] = rawSubRegionName;

          // 중심 좌표 맵에는 처리된 이름(displaySubRegionName)을 키로 사용
          final centroid = _getCentroidFromGeoJsonFeature(
            feature as Map<String, dynamic>,
          );
          if (centroid != null) {
            _sigunguCentroids[displaySubRegionName] =
                centroid; // 키를 수정된 이름으로 변경
          }
        }
        tempSigunguNamesMap['세종특별자치시'] = sejongSubRegions;
      } catch (e) {
        debugPrint("세종 GeoJSON 로드 및 파싱 중 오류 발생: $e");
      }

      // --- **각 시/도 이름을 시/군/구 목록의 맨 앞에 포함** ---
      // 세종특별자치시는 읍면동만 표시할 것이므로, 이 루프에서 제외하거나 조정합니다.
      tempSidoNames.forEach((sidoName) {
        if (sidoName == '세종특별자치시') {
          // 세종특별자치시는 읍면동만 표시할 것이므로, 시도 이름 자체를 세부 지역에 넣지 않음
          if (!tempSigunguNamesMap.containsKey(sidoName)) {
            tempSigunguNamesMap[sidoName] = [];
          }
          return; // 다음 시도로 넘어감 (아래의 삽입 로직을 건너뜀)
        }

        if (!tempSigunguNamesMap.containsKey(sidoName)) {
          tempSigunguNamesMap[sidoName] = [];
        }
        // 각 시/도 목록의 맨 앞에 해당 시/도 이름을 추가 (중복 방지)
        if (!tempSigunguNamesMap[sidoName]!.contains(sidoName)) {
          tempSigunguNamesMap[sidoName]!.insert(0, sidoName);
        }
      });
      // --- **추가된 로직 끝** ---

      // 시군구 목록 정렬 (선택 사항)
      tempSigunguNamesMap.forEach((key, value) {
        // 세종특별자치시가 아닌 경우에만 첫 번째 요소(시도 이름)를 유지하고 정렬
        if (key != '세종특별자치시' && value.length > 1) {
          final sidoName = value[0];
          final subList = value.sublist(1)..sort();
          value
            ..clear()
            ..add(sidoName)
            ..addAll(subList);
        } else if (key == '세종특별자치시' && value.length > 1) {
          // 세종시는 전체를 정렬 (시도 이름이 앞에 없으므로)
          value.sort();
        }
      });

      setState(() {
        _sidoNames = tempSidoNames..sort();
        _sigunguNamesMap = tempSigunguNamesMap;
        _sidoCodeMap = tempSidoCodeMap;
        _isLoading = false; // 데이터 로드 완료
      });
    } catch (e) {
      debugPrint('GeoJSON 데이터 로드 오류: $e');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('지역 정보 로드에 실패했습니다: ${e.toString()}')),
      );
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (pickedFile != null) {
      final rotatedImage = await FlutterExifRotation.rotateImage(
        path: pickedFile.path,
      );
      final extracted = await _extractColorsFromImage(rotatedImage);
      setState(() {
        _image = rotatedImage;
        _extractedColors = extracted;
        _selectedColor = extracted.isNotEmpty ? extracted.first : null;
        _selectedColorName =
            _selectedColor != null ? getColorName(_selectedColor!) : null;
      });
    }
  }

  Future<List<Color>> _extractColorsFromImage(File imageFile) async {
    final image = Image.file(imageFile);
    final palette = await PaletteGenerator.fromImageProvider(
      image.image,
      size: const Size(200, 200),
      maximumColorCount: 5,
    );
    return palette.colors.take(5).toList();
  }

  // GeoPoint는 선택된 시/도, 시/군/구, 장소 정보를 기반으로 생성
  Future<GeoPoint?> _getLatLngFromAddress(
    String sido,
    String? sigungu,
    String place,
  ) async {
    // 1. 세부 지역 (시/군/구 또는 세종시 읍면동)의 중심 좌표 확인
    // _sigunguCentroids 맵은 드롭다운 표시 이름(예: '연동면')을 키로 사용
    if (sigungu != null && sigungu.isNotEmpty) {
      if (_sigunguCentroids.containsKey(sigungu)) {
        debugPrint('Found centroid for sigungu: $sigungu from GeoJSON.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$sigungu"의 행정구역 중심 좌표로 저장됩니다.')),
        );
        return _sigunguCentroids[sigungu];
      }
    }

    // 2. 시/도의 중심 좌표 확인
    if (_sidoCentroids.containsKey(sido)) {
      debugPrint('Found centroid for sido: $sido from GeoJSON.');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"$sido"의 행정구역 중심 좌표로 저장됩니다.')));
      return _sidoCentroids[sido];
    }

    // 3. GeoJSON에서 찾을 수 없으면, geocoding 패키지를 사용하여 상세 주소 검색
    String fullAddress = sido;
    // 세종시인 경우, 원본 adm_nm을 사용하여 지오코딩 시도
    if (sido == '세종특별자치시' && sigungu != null && _sejongDisplayToRawNameMap.containsKey(sigungu)) {
      fullAddress = _sejongDisplayToRawNameMap[sigungu]!; // 예: "세종특별자치시 세종시 연동면"
    } else if (sigungu != null && sigungu.isNotEmpty && sigungu != sido) {
      fullAddress += ' $sigungu';
    }
    if (place.isNotEmpty) {
      fullAddress += ' $place';
    }

    debugPrint('Attempting geocoding for: $fullAddress');
    try {
     List<Location> locations = await locationFromAddress(fullAddress);

      if (locations.isNotEmpty) {
        debugPrint(
          'Found location via geocoding: ${locations.first.latitude}, ${locations.first.longitude}',
        );
        return GeoPoint(locations.first.latitude, locations.first.longitude);
      } else {
        debugPrint('Geocoding successful, but no locations found for: $fullAddress');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${fullAddress}"에 대한 정확한 위치를 찾을 수 없습니다. 행정구역의 중심 좌표로 저장됩니다.')),
        );
        return _sidoCentroids[sido];
      }
    } catch (e) {
      // geocoding 자체에서 오류가 나거나 결과를 못 찾을 때
      debugPrint('Geocoding failed for $fullAddress: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '세부 장소("$place")의 정확한 위치를 찾을 수 없습니다. 행정구역의 중심 좌표로 저장됩니다.',
          ),
        ),
      );
      // 최후의 수단으로 시/도 중심 좌표 반환 (이전 단계에서 null이 아니었다면)
      return _sidoCentroids[sido]; // 이 경우, _sidoCentroids[sido]도 null일 수 있음.
    }
  }

  Future<void> _upload() async {
  if (_image == null ||
      _selectedSido == null ||
      _placeController.text.isEmpty ||
      _selectedColor == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('이미지, 지역 (시/도), 장소, 색상을 모두 선택해주세요.')),
    );
    return;
  }

  setState(() => _isLoading = true);

  final geoPoint = await _getLatLngFromAddress(
    _selectedSido!,
    _selectedSigungu,
    _placeController.text,
  );

  // 세종시 원본 명칭 저장
  String? sigunguToSave = _selectedSigungu;
  if (_selectedSido == '세종특별자치시' && _selectedSigungu != null) {
    sigunguToSave = _sejongDisplayToRawNameMap[_selectedSigungu];
  }

  final fileName = path.basename(_image!.path);
  final ref = FirebaseStorage.instance.ref().child(
    'uploads/${widget.uid}/$fileName',
  );

  try {
    await ref.putFile(_image!);
    final downloadUrl = await ref.getDownloadURL();

    final docId = const Uuid().v4();

    final isCityLevel = _selectedSigungu == null || _selectedSigungu == _selectedSido;

    final tripData = {
      'imageUrl': downloadUrl,
      'country': '대한민국',
      'sigungu': sigunguToSave,
      'place': _placeController.text,
      'memo': _memoController.text,
      'color': _selectedColor?.value,
      'timestamp': Timestamp.now(),
      if (widget.groupId != null) 'groupId': widget.groupId,
      if (geoPoint != null) 'location': geoPoint,
      if (isCityLevel) 'city': _selectedSido!,
    };

    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('trips')
        .doc(docId)
        .set(tripData);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('여행 기록이 성공적으로 업로드되었습니다!')),
    );

    _resetForm();
    if (widget.onUploadComplete != null) {
      widget.onUploadComplete!();
    }
  } catch (e) {
    debugPrint('업로드 실패: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('업로드에 실패했습니다: ${e.toString()}')),
    );
  } finally {
    setState(() => _isLoading = false);
  }
}


  void _resetForm() {
    setState(() {
      _image = null;
      _selectedSido = null;
      _selectedSigungu = null;
      _placeController.clear();
      _memoController.clear();
      _extractedColors.clear();
      _selectedColor = null;
      _selectedColorName = null;
    });
  }

  Widget _buildColorCircles() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children:
          _extractedColors.map((color) {
            final isSelected = _selectedColor == color;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedColor = color;
                  _selectedColorName = getColorName(color);
                });
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.black : Colors.grey.shade300,
                    width: isSelected ? 3 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }

  String getColorName(Color color) {
    int r = color.red, g = color.green, b = color.blue;
    double brightness = (0.2126 * r + 0.7152 * g + 0.0722 * b);
    double maxVal = [r, g, b].reduce((a, b) => a > b ? a : b).toDouble();
    double minVal = [r, g, b].reduce((a, b) => a < b ? a : b).toDouble();
    double saturation = (maxVal - minVal) / maxVal;
    if (maxVal == 0) saturation = 0;

    if (brightness > 220 && saturation < 0.2) return '흰색';
    if (brightness < 30) return '검정색';
    if (saturation < 0.2) return '회색';

    if (r > g && r > b) {
      if (g > b) return '주황색';
      return '빨간색';
    }
    if (g > r && g > b) {
      if (r > b) return '연두색';
      return '초록색';
    }
    if (b > r && b > g) {
      if (r > g) return '보라색';
      return '파란색';
    }

    if (r > 200 && g > 200 && b < 100) return '노란색';
    if (r > 150 && b > 150) return '자주색';

    return '기타';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _sidoNames.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('여행 기록 업로드')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('여행 기록 업로드')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 200,
                width: double.infinity,
                color: Colors.grey[300],
                child:
                    _image == null
                        ? const Center(child: Text('이미지를 선택하세요'))
                        : Image.file(_image!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 12),
            if (_extractedColors.isNotEmpty) _buildColorCircles(),
            if (_selectedColorName != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  '선택된 색상: $_selectedColorName',
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
              ),
            const SizedBox(height: 16),

            // 시/도 선택 드롭다운 (필수)
            DropdownButtonFormField<String>(
              value: _selectedSido,
              hint: const Text('지역 (시/도) 선택 *'),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '지역 (시/도) *',
              ),
              items:
                  _sidoNames.map((String sido) {
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

            // 세부 지역 드롭다운 (선택된 시도에 따라 필터링, 세종시의 경우 '동/면'만 나옴)
            DropdownButtonFormField<String>(
              value: _selectedSigungu,
              hint: const Text('세부 지역 (시/군/구/읍/면/동) 선택'),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '세부 지역 (시/군/구/읍/면/동)',
              ),
              items:
                  _selectedSido != null
                      ? (_sigunguNamesMap[_selectedSido!] ?? []).map((
                        String sigungu,
                      ) {
                        return DropdownMenuItem<String>(
                          value: sigungu,
                          child: Text(sigungu),
                        );
                      }).toList()
                      : [],
              onChanged:
                  _selectedSido != null
                      ? (String? newValue) {
                        setState(() {
                          _selectedSigungu = newValue;
                        });
                        // 토스트 메시지 띄우기
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

            const SizedBox(height: 8),

            TextField(
              controller: _placeController,
              decoration: const InputDecoration(
                labelText: '세부 장소 (예: 특정 건물, 공원 이름) *',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _memoController,
              decoration: const InputDecoration(labelText: '메모 (선택 사항)'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _upload,
              child:
                  _isLoading
                      ? const CircularProgressIndicator()
                      : const Text('업로드'),
            ),
          ],
        ),
      ),
    );
  }
}