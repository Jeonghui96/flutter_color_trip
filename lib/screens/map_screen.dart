import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttertoast/fluttertoast.dart'; // Fluttertoast import 추가

// MyTripsScreen을 import하여 함수를 전달할 수 있도록 합니다.
// 'package:your_app_name/my_trips_screen.dart' 부분을 실제 프로젝트 경로에 맞게 수정해주세요.
import 'package:flutter_colortrip_app/screens/my_trips_screen.dart'; // 실제 프로젝트 경로에 맞게 수정


class MapScreen extends StatefulWidget {
  final String uid; // 사용자 UID를 받아야 합니다.
  const MapScreen({Key? key, required this.uid}) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  final LatLng _initialPosition = const LatLng(36.5, 127.8); // 대한민국 중심
  Set<Polygon> _polygons = {};
  Map<String, dynamic> _sidoGeoJson = {}; // 시도 GeoJSON 데이터
  bool _isLoading = true; // 초기 로딩 상태는 true
  String? _selectedSido; // 현재 상세 지도로 보고 있는 시도 이름 (null이면 전국 시도 지도)
  double _currentZoom = 6.8;

  // 지역별 사용자 여행 기록 색상 저장 (key: 지역 이름, value: Color 리스트)
  // key는 시도 이름 ("서울특별시") 또는 시군구/읍면동 이름 ("동구", "수원시", "세종특별자치시 세종시 연동면")
  Map<String, List<Color>> _userTripColors = {};

  // 방문 통계 변수
  int _visitedSidoCount = 0;
  final int _totalSidoCount = 17; // 대한민국 시도 총 개수
  int _visitedSigunguCount = 0; // 현재 뷰(전국 또는 특정 시도)의 방문 시군구/읍면동 수
  int _currentViewTotalSigunguCount = 0; // 현재 뷰(전국 또는 특정 시도)의 총 시군구/읍면동 개수

  // 시도 이름으로 코드 찾는 맵 (GeoJSON 시군구 필터링용)
  final Map<String, String> sidoCodeMap = {
    "서울특별시": "11", "부산광역시": "21", "대구광역시": "22", "인천광역시": "23", "광주광역시": "24",
    "대전광역시": "25", "울산광역시": "26", "세종특별자치시": "29", "경기도": "31", "강원도": "32",
    "충청북도": "33", "충청남도": "34", "전라북도": "35", "전라남도": "36", "경상북도": "37",
    "경상남도": "38", "제주특별자치도": "39",
  };

  // 모든 시군구/읍면동의 총 개수를 저장하는 맵 (시도별로)
  // key: 시도 이름, value: 해당 시도의 총 시군구/읍면동 개수
  Map<String, int> _allSigunguCountsBySido = {};
  // 전국 총 시군구/읍면동 개수 (세종시의 읍면동 포함)
  int _totalNationalSigunguCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeMapData();
  }

  /// 모든 필요한 데이터(GeoJSON, 여행 기록)를 로드하고 초기 지도를 그립니다.
  Future<void> _initializeMapData() async {
    setState(() {
      _isLoading = true; // 로딩 시작
    });
    try {
      await _loadAllSigunguCounts();
      await _loadSidoGeoJson();
      await _loadTripData();

      if (_selectedSido == null) {
        _drawSidoPolygons();
      } else {
        _drawSigunguPolygons(_selectedSido!);
      }
    } catch (e) {
      print("지도 데이터 초기화 중 오류 발생: $e");
      // 사용자에게 오류 메시지를 보여주는 로직 추가
    } finally {
      setState(() {
        _isLoading = false; // 로딩 완료
      });
    }
  }

  // MyTripsScreen에서 색상을 적용하기 위해 호출됩니다.
  void applyColorToMap(String regionName, Color color) {
    setState(() {
      // 해당 지역의 기존 색상을 지우고 새 색상을 추가합니다.
      // MyTripsScreen에서 한 번에 하나의 색상만 적용한다고 가정합니다.
      // 기존 색상에 추가하려면 이 로직을 수정해야 합니다.
      _userTripColors[regionName] = [color];
      print('applyColorToMap: $regionName 에 색상 ${color.value.toRadixString(16)} 적용됨');
      print('_userTripColors 업데이트 후: $_userTripColors');
    });

    // 새 색상을 반영하기 위해 폴리곤을 다시 그립니다.
    if (_selectedSido == null) {
      _drawSidoPolygons(); // 현재 시도 뷰이면 시도 폴리곤을 다시 그립니다.
    } else {
      // 현재 시군구 뷰이면 해당 시군구 뷰를 다시 그립니다.
      // applyColorToMap으로 전달된 regionName이 현재 _selectedSido (시도 이름)와 일치하는지 확인합니다.
      // 아니면, 전달된 regionName이 _selectedSido의 하위 행정구역일 수 있습니다.
      // 예: _selectedSido="대구광역시", regionName="동구"
      // 이 경우, _selectedSido의 상세 지도를 다시 그리는 것이 맞습니다.
      _drawSigunguPolygons(_selectedSido!);
    }
  }

  // 모든 시군구/읍면동의 총 개수를 미리 로드하여 통계에 사용
  Future<void> _loadAllSigunguCounts() async {
    try {
      Map<String, int> tempSidoTotalSigunguCounts = {};
      int nationalTotal = 0;

      // 1. 일반 시군구 GeoJSON 로드 (skorea_municipalities_2018_geo.json)
      final sigunguData = await rootBundle.loadString('assets/geo/skorea_municipalities_2018_geo.json');
      final sigunguGeoJson = json.decode(sigunguData);
      final features = sigunguGeoJson['features'] as List;

      for (var feature in features) {
        final props = feature['properties'];
        final code = props['code'].toString();
        String currentSidoCode = code.substring(0, 2);
        String? currentSidoName = sidoCodeMap.entries.firstWhere(
          (entry) => entry.value == currentSidoCode,
          orElse: () => const MapEntry("", "")
        ).key;

        if (currentSidoName.isNotEmpty) {
          tempSidoTotalSigunguCounts[currentSidoName] = (tempSidoTotalSigunguCounts[currentSidoName] ?? 0) + 1;
          nationalTotal++;
        }
      }

      // 2. 세종특별자치시 GeoJSON 로드 (sejong.geojson)
      try {
        final sejongData = await rootBundle.loadString('assets/geo/sejong.geojson');
        final sejongGeoJson = json.decode(sejongData);
        final sejongFeatures = sejongGeoJson['features'] as List;

        tempSidoTotalSigunguCounts["세종특별자치시"] = (tempSidoTotalSigunguCounts["세종특별자치시"] ?? 0); // 초기화
        for (var feature in sejongFeatures) {
          // 세종시의 각 읍면동을 1개로 카운트
          tempSidoTotalSigunguCounts["세종특별자치시"] = (tempSidoTotalSigunguCounts["세종특별자치시"] ?? 0) + 1;
          nationalTotal++;
        }
      } catch (e) {
        print("세종 GeoJSON 로드 중 오류 발생 (총 개수 계산용): $e");
      }

      setState(() {
        _allSigunguCountsBySido = tempSidoTotalSigunguCounts;
        _totalNationalSigunguCount = nationalTotal;
      });
      print("모든 시군구/읍면동 개수 로드 완료: $_allSigunguCountsBySido, 전국: $_totalNationalSigunguCount");
    } catch (e) {
      print("모든 시군구/읍면동 개수 로드 중 치명적 오류: $e");
    }
  }


  // Firebase에서 여행 기록 데이터를 로드하고 지역별 색상 맵을 채웁니다.
  Future<void> _loadTripData() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .collection('trips')
          .get();

      final Map<String, List<Color>> tempTripColors = {};
      Set<String> visitedSidos = {};     // 방문한 시도 집합 (중복 제거용)
      Set<String> visitedSigungus = {};  // 방문한 시군구/읍면동 집합 (중복 제거용, 전국 기준)

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final int? colorValue = data['color'];
        final String? firebaseSido = data['city'];    // Firestore에 저장된 시도 이름 (예: "대구광역시", "세종특별자치시")
        final String? firebaseSigungu = data['sigungu']; // Firestore에 저장된 시군구/읍면동 이름 (예: "동구", "수원시", "세종특별자치시 세종시 연동면")

        if (colorValue != null) {
          final Color tripColor = Color(colorValue);

          // 1. 시도 이름으로 색상 매핑 (전체 시도 지도에 색칠하기 위함)
          if (firebaseSido != null && firebaseSido.isNotEmpty) {
            if (!tempTripColors.containsKey(firebaseSido)) {
              tempTripColors[firebaseSido] = [];
            }
            tempTripColors[firebaseSido]!.add(tripColor);
            visitedSidos.add(firebaseSido); // 방문한 시도 카운트를 위해 추가
          }

          // 2. 시군구/읍면동 이름으로 색상 매핑 (세부 시군구 지도에 색칠하기 위함)
          // `skorea_municipalities_2018_geo.json`의 `properties.name` (예: "동구", "수원시")
          // `sejong.geojson`의 `properties.adm_nm` (예: "세종특별자치시 세종시 연동면")
          if (firebaseSigungu != null && firebaseSigungu.isNotEmpty) {
            // Firebase에 저장된 sigungu를 GeoJSON 이름에 맞게 조정 (로드 시점에도 필요)
            String regionKeyToLoad = firebaseSigungu;
            // 예시: "대구 동구"와 같이 GeoJSON에 "시도명 시군구명"으로 되어 있는 경우 처리
            // 현재 코드에서는 해당 로직이 없으니, GeoJSON의 'name' 속성을 그대로 사용한다고 가정
            // (즉, '동구'는 '동구'로, '수원시'는 '수원시'로 저장된다고 가정)

            // 만약 Firebase 저장 시 세종시 읍면동이 '연동면'처럼 짧게 저장되고
            // GeoJSON에는 '세종특별자치시 세종시 연동면'처럼 풀네임으로 되어있다면 매핑 필요
            // 이 부분은 UploadScreen의 _sejongDisplayToRawNameMap 로직과 연관
            // 현재 UploadScreen은 GeoJSON의 원본 adm_nm을 저장하므로 MapScreen에서 별도 처리 불필요
            // 단, GeoJSON을 로드할 때 세종 읍면동 이름을 어떻게 처리했는지에 따라 여기도 맞춰야 함.
            // 현재 UploadScreen은 GeoJSON 원본인 '세종특별자치시 세종시 연동면'을 그대로 Firestore에 저장하므로,
            // 별도 매핑 로직 없이 firebaseSigungu를 그대로 regionKeyToLoad로 사용.
            // 위에서 추가한 대구광역시 동구 예시와 세종 읍면동 예시는 실제 데이터 형태에 맞춰 수정해야 합니다.

            if (!tempTripColors.containsKey(regionKeyToLoad)) {
              tempTripColors[regionKeyToLoad] = [];
            }
            tempTripColors[regionKeyToLoad]!.add(tripColor);
            visitedSigungus.add(regionKeyToLoad); // 방문한 시군구/읍면동 카운트를 위해 추가
          }
        }
      }

      setState(() {
        _userTripColors = tempTripColors;
        _visitedSidoCount = visitedSidos.length;
        _visitedSigunguCount = visitedSigungus.length; // 전국 기준 방문 시군구/읍면동 수
        _currentViewTotalSigunguCount = _totalNationalSigunguCount; // 초기에는 전국 총 시군구/읍면동 수로 설정
      });
      print('여행 기록 로드 완료. _userTripColors: $_userTripColors');

    } catch (e) {
      print('여행 기록 로드 오류: $e');
    }
  }


  // 주어진 지역 이름에 해당하는 평균 색상을 계산합니다.
  Color _getColorForRegion(String regionName) {
    if (_userTripColors.containsKey(regionName) && _userTripColors[regionName]!.isNotEmpty) {
      final List<Color> colors = _userTripColors[regionName]!;
      int r = 0, g = 0, b = 0;
      for (var color in colors) {
        r += color.red;
        g += color.green;
        b += color.blue;
      }
      return Color.fromARGB(
        255, // 불투명도 (0-255)
        (r / colors.length).round(),
        (g / colors.length).round(),
        (b / colors.length).round(),
      );
    }
    // 여행 기록이 없는 지역의 기본 색상 (약간 더 어둡게 하여 색칠된 지역과 구분)
    return Colors.grey.shade200;
  }

  // 시도 GeoJSON 파일을 로드합니다.
  // 이 함수는 단순히 데이터를 로드하고 _sidoGeoJson에 할당만 하며,
  // setState나 _isLoading 상태 변경은 _initializeMapData에서 담당합니다.
  Future<void> _loadSidoGeoJson() async {
    try {
      final sidoData = await rootBundle.loadString(
        'assets/geo/skorea_provinces_2018_geo.json',
      );
      _sidoGeoJson = json.decode(sidoData);
      print('시도 GeoJSON 로드 완료');
    } catch (e) {
      print('시도 GeoJSON 로드 오류: $e');
    }
  }

  // 전국 시도 폴리곤을 그립니다.
  void _drawSidoPolygons() {
    // GeoJSON 데이터가 로드되었는지 확인
    if (_sidoGeoJson.isEmpty || _sidoGeoJson['features'] == null) {
      print("Error: 시도 GeoJSON 데이터가 로드되지 않았거나 유효하지 않습니다.");
      return;
    }

    final features = _sidoGeoJson['features'] as List;
    Set<Polygon> polygons = {};
    int id = 0;

    for (var feature in features.reversed) { // 순서를 뒤집어 그리면 작은 폴리곤이 큰 폴리곤 위에 그려질 수 있습니다.
      final props = feature['properties'];
      final sido = props['name'] ?? '이름없음'; // GeoJSON의 시도 이름
      final geometry = feature['geometry'];
      final type = geometry['type'];

      final fillColor = _getColorForRegion(sido); // GeoJSON 시도 이름으로 색상 가져오기

      if (type == 'MultiPolygon') {
        for (var polygon in geometry['coordinates']) {
          for (var ring in polygon) {
            final points = _convertToLatLng(ring);
            polygons.add(_buildPolygon(id++, points, sido, fillColor));
          }
        }
      } else if (type == 'Polygon') {
        for (var ring in geometry['coordinates']) {
          final points = _convertToLatLng(ring);
          polygons.add(_buildPolygon(id++, points, sido, fillColor));
        }
      }
    }

    setState(() {
      _polygons = polygons;
      _selectedSido = null; // 시도 지도 상태임을 명시
      _currentViewTotalSigunguCount = _totalNationalSigunguCount; // 전국 시군구 통계로 업데이트
    });

    if (_mapController != null) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_initialPosition, _currentZoom),
      );
    }
    print('시도 폴리곤 다시 그리기 완료');
  }

  // 특정 시도의 시군구/읍면동 폴리곤을 그립니다.
  Future<void> _drawSigunguPolygons(String sidoName) async {
    Set<Polygon> polygons = {};
    int id = 0;
    List<LatLng> allPoints = [];

    // 이 함수 내에서 해당 시도에 대한 방문 시군구/읍면동 수를 다시 계산합니다.
    Set<String> visitedRegionsInSelectedSido = {}; // 방문한 지역 이름 (읍면동 또는 시군구)
    int totalRegionsInSelectedSido = 0; // 해당 시도의 총 지역 수 (읍면동 또는 시군구)


    // 세종시 처리: 별도 파일 로드 (세종은 시도이자 내부 읍면동으로 구성)
    if (sidoName == "세종특별자치시") {
      print("세종특별자치시 상세 지도 로드 시도 (읍면동 단위)...");
      try {
        final data = await rootBundle.loadString('assets/geo/sejong.geojson');
        print("세종 GeoJSON 파일 로드 성공!");
        final geoJson = json.decode(data);
        final features = geoJson['features'] as List;

        totalRegionsInSelectedSido = _allSigunguCountsBySido[sidoName] ?? 0; // 미리 계산된 총 개수 사용

        for (var feature in features) {
          final props = feature['properties'];
          // 세종시의 읍면동 상세 이름 사용 (예: "세종특별자치시 세종시 연동면")
          final String regionName = props['adm_nm'] ?? '이름없음_세종_읍면동';

          // _userTripColors 맵에 해당 읍면동 이름이 있는지 확인하여 방문 여부 체크
          if (_userTripColors.containsKey(regionName) && _userTripColors[regionName]!.isNotEmpty) {
              visitedRegionsInSelectedSido.add(regionName);
          }

          final geometry = feature['geometry'];
          final type = geometry['type'];

          final fillColor = _getColorForRegion(regionName); // 읍면동 이름으로 색상 가져오기

          if (type == 'Polygon') {
            for (var ring in geometry['coordinates']) {
              final points = _convertToLatLng(ring);
              polygons.add(_buildPolygon(id++, points, regionName, fillColor));
              allPoints.addAll(points);
            }
          } else if (type == 'MultiPolygon') {
            for (var polygon in geometry['coordinates']) {
              for (var ring in polygon) {
                final points = _convertToLatLng(ring);
                polygons.add(_buildPolygon(id++, points, regionName, fillColor));
                allPoints.addAll(points);
              }
            }
          }
        }

        setState(() {
          _polygons = polygons;
          _selectedSido = sidoName;
          _visitedSigunguCount = visitedRegionsInSelectedSido.length; // 방문한 읍면동 수
          _currentViewTotalSigunguCount = totalRegionsInSelectedSido; // 총 읍면동 수
        });

        if (allPoints.isNotEmpty) {
          final bounds = _getLatLngBounds(allPoints);
          _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
        }
        print("세종 상세지도 로딩 완료 (읍면동 단위): $sidoName");
      } catch (e) {
        print('세종 GeoJSON 로드 오류: $e');
      }
      return;
    }

    // 일반 시도 (광역시, 도)의 시군구 처리
    final sidoPrefix = sidoCodeMap[sidoName];
    if (sidoPrefix == null) {
      print("Error: 시도 접두사 코드를 찾을 수 없습니다: $sidoName");
      return;
    }

    try {
      final data = await rootBundle.loadString(
        'assets/geo/skorea_municipalities_2018_geo.json',
      );
      final geoJson = json.decode(data);
      final features = geoJson['features'] as List;

      // 현재 시도에 해당하는 총 시군구 수 계산
      totalRegionsInSelectedSido = _allSigunguCountsBySido[sidoName] ?? 0;

      for (var feature in features) {
        final props = feature['properties'];
        final code = props['code'].toString();
        final name = props['name'] ?? '이름없음'; // GeoJSON 시군구 이름 (예: "동구", "수원시", "대구 동구")
        if (!code.startsWith(sidoPrefix)) continue; // 해당 시도에 속하는 시군구만 필터링

        if (_userTripColors.containsKey(name) && _userTripColors[name]!.isNotEmpty) {
            visitedRegionsInSelectedSido.add(name);
        }

        final geometry = feature['geometry'];
        final type = geometry['type'];

        final fillColor = _getColorForRegion(name);

        if (type == 'Polygon') {
          for (var ring in geometry['coordinates']) {
            final points = _convertToLatLng(ring);
            polygons.add(_buildPolygon(id++, points, name, fillColor));
            allPoints.addAll(points);
          }
        } else if (type == 'MultiPolygon') {
          for (var polygon in geometry['coordinates']) {
            for (var ring in polygon) {
              final points = _convertToLatLng(ring);
              polygons.add(_buildPolygon(id++, points, name, fillColor));
              allPoints.addAll(points);
            }
          }
        }
      }

      setState(() {
        _polygons = polygons;
        _selectedSido = sidoName;
        _visitedSigunguCount = visitedRegionsInSelectedSido.length; // 방문한 시군구 수
        _currentViewTotalSigunguCount = totalRegionsInSelectedSido; // 총 시군구 수
      });

      if (allPoints.isNotEmpty) {
        final bounds = _getLatLngBounds(allPoints);
        _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
      }

      print("세부 행정구역 로딩 완료: $sidoName");
    } catch (e) {
      print('시군구 GeoJSON 로드 오류: $e');
    }
  }

  // 폴리곤의 경계를 계산하여 카메라를 이동시키는 데 사용
  LatLngBounds _getLatLngBounds(List<LatLng> points) {
    double? minLat, maxLat, minLng, maxLng;
    for (var p in points) {
      minLat = minLat == null || p.latitude < minLat ? p.latitude : minLat;
      maxLat = maxLat == null || p.latitude > maxLat ? p.latitude : maxLat;
      minLng = minLng == null || p.longitude < minLng ? p.longitude : minLng;
      maxLng = maxLng == null || p.longitude > maxLng ? p.longitude : maxLng;
    }
    return LatLngBounds(
      southwest: LatLng(minLat!, minLng!),
      northeast: LatLng(maxLat!, maxLng!),
    );
  }

  // GeoJSON 좌표를 LatLng 객체로 변환
  List<LatLng> _convertToLatLng(List coords) {
    return coords.map<LatLng>((c) {
      final lat = c[1].toDouble();
      final lng = c[0].toDouble();
      return LatLng(lat, lng);
    }).toList();
  }

  // 폴리곤 생성 헬퍼 함수
  Polygon _buildPolygon(int id, List<LatLng> points, String name, Color fillColor) {
    return Polygon(
      polygonId: PolygonId(id.toString()),
      points: points,
      strokeWidth: 1,
      strokeColor: Colors.black,
      fillColor: fillColor.withOpacity(0.6), // 투명도를 60%로 설정
      consumeTapEvents: true,
      onTap: () {
        print("클릭한 지역: $name");
        // 토스트 메시지 띄우기
        Fluttertoast.showToast(
          msg: "$name을(를) 선택했습니다.",
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          timeInSecForIosWeb: 1,
          backgroundColor: Colors.black54,
          textColor: Colors.white,
          fontSize: 16.0,
        );

        if (_selectedSido == null) {
          // 시도 단계에서만 시군구 상세 지도로 전환
          _drawSigunguPolygons(name);
        }
        // 상세 상태에서는 터치해도 아무 작업 안 함 (원한다면 다른 동작 추가 가능)
      },
    );
  }

  // 맵 컨트롤러가 생성될 때 호출
  void _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;
    final style = await rootBundle.loadString('assets/map_style.json');
    _mapController?.setMapStyle(style);
  }

  // 줌인/줌아웃 함수
  void _zoomIn() {
    _currentZoom = (_currentZoom + 1).clamp(0.0, 18.0);
    _mapController?.animateCamera(CameraUpdate.zoomTo(_currentZoom));
  }

  void _zoomOut() {
    _currentZoom = (_currentZoom - 1).clamp(0.0, 18.0);
    _mapController?.animateCamera(CameraUpdate.zoomTo(_currentZoom));
  }

  @override
  Widget build(BuildContext context) {
    String statsText;
    if (_selectedSido == null) {
      // 전국 시도 지도일 때
      statsText = '시/도 ${_visitedSidoCount} / ${_totalSidoCount} | 시군구 ${_visitedSigunguCount} / ${_totalNationalSigunguCount}';
    } else {
      // 특정 시도 상세 지도일 때 (읍면동 단위 포함)
      statsText = '시군구 ${_visitedSigunguCount} / ${_currentViewTotalSigunguCount}';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedSido ?? '대한민국 지도'),
        centerTitle: true, // 제목 중앙 정렬
        leading: _selectedSido != null // 시군구 상세 지도일 때만 뒤로가기 버튼 표시
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _selectedSido = null; // 시도 선택 초기화
                    _currentZoom = 6.8; // 시도 맵으로 돌아갈 때 초기 줌 레벨로 설정
                  });
                  _drawSidoPolygons(); // 시도 지도로 돌아감
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLngZoom(
                      _initialPosition,
                      _currentZoom,
                    ),
                  );
                },
              )
            : null,
        bottom: PreferredSize( // Appbar 하단에 통계 표시
          preferredSize: const Size.fromHeight(24.0), // 원하는 높이 설정
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Text(
              statsText,
              style: const TextStyle(
                color: Colors.white70, // 글자색 (Appbar 배경에 맞춰)
                fontSize: 13.0,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator()) // 로딩 중 표시
              : GoogleMap(
                  onMapCreated: _onMapCreated,
                  initialCameraPosition: CameraPosition(
                    target: _initialPosition,
                    zoom: _currentZoom,
                  ),
                  polygons: _polygons,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  onCameraMove: (position) {
                    _currentZoom = position.zoom;
                  },
                ),
          Positioned(
            bottom: 30,
            right: 15,
            child: Column(
              children: [
                FloatingActionButton(
                  heroTag: "zoom_in",
                  mini: true,
                  onPressed: _zoomIn,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: "zoom_out",
                  mini: true,
                  onPressed: _zoomOut,
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}