import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../services/gemini_service.dart';

class AiRecommendationScreen extends StatefulWidget {
  const AiRecommendationScreen({super.key});

  @override
  State<AiRecommendationScreen> createState() => _AiRecommendationScreenState();
}

class _AiRecommendationScreenState extends State<AiRecommendationScreen> {
  String? _selectedSido;
  String? _selectedSigungu;

  List<String> _sidoNames = [];
  Map<String, List<String>> _sigunguNamesMap = {};
  Map<String, String> _sidoCodeMap = {};
  Map<String, GeoPoint?> _sidoCentroids = {};
  Map<String, GeoPoint?> _sigunguCentroids = {};
  Map<String, String> _sejongDisplayToRawNameMap = {};

  bool _isLoadingGeoJson = true;
  bool _isGeneratingLocationRecommendation = false;
  bool _isGeneratingRestaurantRecommendation = false;

  List<Map<String, String>> _parsedRecommendedLocations = [];
  List<Map<String, String>> _parsedRecommendedRestaurants = [];

  String _rawAiLocationRecommendationResult = '';
  String _rawAiRestaurantRecommendationResult = '';

  String? _currentRecommendationType;

  @override
  void initState() {
    super.initState();
    _loadGeoJsonData();
  }

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

  Future<void> _loadGeoJsonData() async {
    try {
      setState(() {
        _isLoadingGeoJson = true;
      });

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

  void _parseRecommendedItems(String recommendation, String type) {
    final lines = recommendation.split('\n');
    List<Map<String, String>> currentList = [];

    // The parsing now begins from the first line that matches the expected item format
    // regardless of a preceding "명소:" or "맛집:" header.
    // This makes it more resilient to slight variations in the AI's header output.
    final RegExp itemRegExp = RegExp(r'^\s*\d+\.\s*([^\[\]]+?)\s*-\s*(.+)$');

    for (var line in lines) {
      final String trimmedLine = line.trim();
      Match? match = itemRegExp.firstMatch(trimmedLine);

      if (match != null && match.group(1) != null && match.group(2) != null) {
        final name = match.group(1)!.trim();
        // Remove unnecessary newlines and collapse multiple spaces into a single space
        final description = match.group(2)!.trim().replaceAll(RegExp(r'\s+'), ' ');
        currentList.add({'name': name, 'description': description});
      }
    }

    // Update the state variables based on the type of recommendation
    if (type == 'location') {
      setState(() { // setState inside to ensure UI updates after parsing
        _parsedRecommendedLocations = List.from(currentList);
        // Clear raw result if parsed list is not empty, otherwise keep for debugging
        _rawAiLocationRecommendationResult = _parsedRecommendedLocations.isEmpty ? recommendation : '';
      });
    } else if (type == 'restaurant') {
      setState(() { // setState inside to ensure UI updates after parsing
        _parsedRecommendedRestaurants = List.from(currentList);
        // Clear raw result if parsed list is not empty, otherwise keep for debugging
        _rawAiRestaurantRecommendationResult = _parsedRecommendedRestaurants.isEmpty ? recommendation : '';
      });
    }
  }


  Future<void> _getAiLocationRecommendations() async {
    if (_selectedSido == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('시/도를 선택해주세요.')),
      );
      return;
    }

    setState(() {
      _isGeneratingLocationRecommendation = true;
      _parsedRecommendedLocations.clear();
      _rawAiLocationRecommendationResult = '';

      _parsedRecommendedRestaurants.clear(); // Clear other type's data
      _rawAiRestaurantRecommendationResult = ''; // Clear other type's raw data
      _currentRecommendationType = 'location'; // Set current type
    });

    try {
      String locationPrompt = _selectedSido!;
      if (_selectedSido == '세종특별자치시' && _selectedSigungu != null && _sejongDisplayToRawNameMap.containsKey(_selectedSigungu!)) {
        locationPrompt = _sejongDisplayToRawNameMap[_selectedSigungu!]!;
      } else if (_selectedSigungu != null && _selectedSigungu!.isNotEmpty && _selectedSigungu! != _selectedSido!) {
        locationPrompt += ' $_selectedSigungu';
      }

      // Updated prompt to explicitly request the format.
      // Removed the "명소:" header from the format request in the prompt
      // to make parsing more robust, as the regex doesn't rely on it.
      String userPrompt = "$locationPrompt 에 있는 명소 3군데를 추천해줘. 각 추천에는 간단한 설명도 포함해줘. "
                          "응답은 반드시 다음 형식으로 해줘: "
                          "1. [명소1 이름] - [간단 설명]\n2. [명소2 이름] - [간단 설명]\n3. [명소3 이름] - [간단 설명]";

      final response = await GeminiService.getRecommendation(userPrompt);

      debugPrint('--- Gemini Raw Response (Location) ---');
      debugPrint(response);
      debugPrint('------------------------------------');

      // The _parseRecommendedItems method now calls setState internally.
      _parseRecommendedItems(response, 'location');

    } catch (e) {
      debugPrint('명소 추천 생성 실패: $e');
      setState(() {
        _rawAiLocationRecommendationResult = '명소 추천을 생성하는 중 오류가 발생했습니다: ${e.toString()}';
        _parsedRecommendedLocations.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('명소 추천 생성에 실패했습니다: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isGeneratingLocationRecommendation = false;
      });
    }
  }

  Future<void> _getAiRestaurantRecommendations() async {
    if (_selectedSido == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('시/도를 선택해주세요.')),
      );
      return;
    }

    setState(() {
      _isGeneratingRestaurantRecommendation = true;
      _parsedRecommendedRestaurants.clear();
      _rawAiRestaurantRecommendationResult = '';

      _parsedRecommendedLocations.clear(); // Clear other type's data
      _rawAiLocationRecommendationResult = ''; // Clear other type's raw data
      _currentRecommendationType = 'restaurant'; // Set current type
    });

    try {
      String locationPrompt = _selectedSido!;
      if (_selectedSido == '세종특별자치시' && _selectedSigungu != null && _sejongDisplayToRawNameMap.containsKey(_selectedSigungu!)) {
        locationPrompt = _sejongDisplayToRawNameMap[_selectedSigungu!]!;
      } else if (_selectedSigungu != null && _selectedSigungu!.isNotEmpty && _selectedSigungu! != _selectedSido!) {
        locationPrompt += ' $_selectedSigungu';
      }

      // Updated prompt to explicitly request the format.
      // Removed the "맛집:" header from the format request in the prompt
      // to make parsing more robust, as the regex doesn't rely on it.
      String userPrompt = "$locationPrompt 에 있는 맛집 3군데를 추천해줘. 각 추천에는 간단한 설명도 포함해줘. "
                          "응답은 반드시 다음 형식으로 해줘: "
                          "1. [맛집1 이름] - [간단 설명]\n2. [맛집2 이름] - [간단 설명]\n3. [맛집3 이름] - [간단 설명]";

      final response = await GeminiService.getRecommendation(userPrompt);

      debugPrint('--- Gemini Raw Response (Restaurant) ---');
      debugPrint(response);
      debugPrint('------------------------------------');

      // The _parseRecommendedItems method now calls setState internally.
      _parseRecommendedItems(response, 'restaurant');

    } catch (e) {
      debugPrint('맛집 추천 생성 실패: $e');
      setState(() {
        _rawAiRestaurantRecommendationResult = '맛집 추천을 생성하는 중 오류가 발생했습니다: ${e.toString()}';
        _parsedRecommendedRestaurants.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('맛집 추천 생성에 실패했습니다: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isGeneratingRestaurantRecommendation = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingGeoJson) {
      return Scaffold(
        appBar: AppBar(title: const Text('여행지 추천')), // 변경: AI 여행지 추천 -> 여행지 추천
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('여행지 추천')), // 변경: AI 여행지 추천 -> 여행지 추천
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '여행 지역을 선택하고 추천을 받아보세요!', // 변경: AI 추천 -> 추천
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

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
                  _selectedSigungu = null;
                  // Clear all recommendation data when region changes
                  _parsedRecommendedLocations.clear();
                  _parsedRecommendedRestaurants.clear();
                  _rawAiLocationRecommendationResult = '';
                  _rawAiRestaurantRecommendationResult = '';
                  _currentRecommendationType = null;
                });
              },
            ),
            const SizedBox(height: 8),

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
                        // Clear all recommendation data when sub-region changes
                        _parsedRecommendedLocations.clear();
                        _parsedRecommendedRestaurants.clear();
                        _rawAiLocationRecommendationResult = '';
                        _rawAiRestaurantRecommendationResult = '';
                        _currentRecommendationType = null;
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
                  : null,
              isExpanded: true,
              menuMaxHeight: 300,
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isGeneratingLocationRecommendation || _selectedSido == null
                        ? null
                        : _getAiLocationRecommendations,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isGeneratingLocationRecommendation
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              SizedBox(width: 8),
                              Text('명소 추천 중...', style: TextStyle(fontSize: 16)),
                            ],
                          )
                        : const Text('명소 추천 받기', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isGeneratingRestaurantRecommendation || _selectedSido == null
                        ? null
                        : _getAiRestaurantRecommendations,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isGeneratingRestaurantRecommendation
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              SizedBox(width: 8),
                              Text('맛집 추천 중...', style: TextStyle(fontSize: 16)),
                            ],
                          )
                        : const Text('맛집 추천 받기', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Display parsed results if available for the current recommendation type
            if (_currentRecommendationType != null &&
                ((_currentRecommendationType == 'location' && _parsedRecommendedLocations.isNotEmpty) ||
                 (_currentRecommendationType == 'restaurant' && _parsedRecommendedRestaurants.isNotEmpty)))
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '추천 결과:', // 변경: AI 추천 결과 -> 추천 결과
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  if (_currentRecommendationType == 'location' && _parsedRecommendedLocations.isNotEmpty) ...[
                    const Text(
                      '명소:',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _parsedRecommendedLocations.length,
                      itemBuilder: (context, index) {
                        final item = _parsedRecommendedLocations[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${index + 1}. ', style: const TextStyle(fontSize: 16)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['name']!,
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      '- ${item['description']!}',
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],

                  if (_currentRecommendationType == 'restaurant' && _parsedRecommendedRestaurants.isNotEmpty) ...[
                    const Text(
                      '맛집:',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _parsedRecommendedRestaurants.length,
                      itemBuilder: (context, index) {
                        final item = _parsedRecommendedRestaurants[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${index + 1}. ', style: const TextStyle(fontSize: 16)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['name']!,
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      '- ${item['description']!}',
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            // Display "No recommendation found" message only if no items are parsed AND not currently generating
            if (_currentRecommendationType != null &&
                _parsedRecommendedLocations.isEmpty && _parsedRecommendedRestaurants.isEmpty &&
                !_isGeneratingLocationRecommendation && !_isGeneratingRestaurantRecommendation)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(
                  child: Text(
                    '추천 결과를 찾을 수 없습니다. 다시 시도해 주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}