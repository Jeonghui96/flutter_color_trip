import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Firebase Firestore import
import 'package:geocoding/geocoding.dart'; // 역지오코딩을 위해 필요합니다.

class MapScreen extends StatefulWidget {
  final String uid; // 사용자 UID를 받아와야 합니다.
  const MapScreen({Key? key, required this.uid}) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  final LatLng _initialPosition = const LatLng(36.5, 127.8);
  Set<Polygon> _polygons = {};
  Map<String, dynamic> _sidoGeoJson = {};
  bool _isLoading = true;
  String? _selectedSido;
  double _currentZoom = 6.8;

  // 지역별 사용자 여행 기록 색상 저장 (key: 지역 이름, value: Color 리스트)
  Map<String, List<Color>> _userTripColors = {};

  final Map<String, String> sidoCodeMap = {
    "서울특별시": "11",
    "부산광역시": "21",
    "대구광역시": "22",
    "인천광역시": "23",
    "광주광역시": "24",
    "대전광역시": "25",
    "울산광역시": "26",
    "세종특별자치시": "29",
    "경기도": "31",
    "강원도": "32",
    "충청북도": "33",
    "충청남도": "34",
    "전라북도": "35",
    "전라남도": "36",
    "경상북도": "37",
    "경상남도": "38",
    "제주특별자치도": "39",
  };

  @override
  void initState() {
    super.initState();
    _loadSidoGeoJson(); // GeoJSON 로드 (초기 지도 그리기)
    _loadTripData(); // 여행 기록 데이터 로드 및 색상 매핑
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

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final int? colorValue = data['color'];
        final String? city = data['city']; // 예: "대구"
        final GeoPoint? location = data['location']; // GeoPoint 활용이 더 정확함

        if (colorValue != null && (city != null || location != null)) {
          final Color tripColor = Color(colorValue);

          String? standardizedRegionName;

          // 1. GeoPoint가 있다면 역지오코딩을 통해 정확한 행정구역 이름을 얻습니다. (더 권장)
          if (location != null) {
            try {
              List<Placemark> placemarks = await placemarkFromCoordinates(location.latitude, location.longitude);
              if (placemarks.isNotEmpty) {
                // placemarks.first.administrativeArea: 시/도 (예: "서울특별시", "부산광역시")
                // placemarks.first.locality: 시/군/구 (예: "중구", "성남시")
                // GeoJSON의 properties.name과 일치하는 필드를 사용해야 합니다.
                // 초기 지도는 시도 단위이므로 administrativeArea를 우선 사용합니다.
                standardizedRegionName = placemarks.first.administrativeArea;

                // 시군구 상세 지도를 위한 대비 (필요하다면 locality/subLocality도 처리 가능)
                // 현재 시도 지도를 칠하는 목적이므로 administrativeArea로 충분합니다.
              }
            } catch (e) {
              debugPrint('역지오코딩 오류: $e');
              // 역지오코딩 실패 시 city 이름으로 대체 시도
            }
          }

          // 2. GeoPoint가 없거나 역지오코딩 실패 시, city 이름을 표준화하여 사용합니다.
          if (standardizedRegionName == null && city != null) {
            // Firestore의 'city' 필드값을 GeoJSON의 'name' 필드값과 일치시키기 위한 매핑
            if (city == "서울") standardizedRegionName = "서울특별시";
            else if (city == "부산") standardizedRegionName = "부산광역시";
            else if (city == "대구") standardizedRegionName = "대구광역시";
            else if (city == "인천") standardizedRegionName = "인천광역시";
            else if (city == "광주") standardizedRegionName = "광주광역시";
            else if (city == "대전") standardizedRegionName = "대전광역시";
            else if (city == "울산") standardizedRegionName = "울산광역시";
            else if (city == "세종") standardizedRegionName = "세종특별자치시"; // 세종은 '시'까지
            else if (city == "경기") standardizedRegionName = "경기도";
            else if (city == "강원") standardizedRegionName = "강원도";
            else if (city == "충북") standardizedRegionName = "충청북도";
            else if (city == "충남") standardizedRegionName = "충청남도";
            else if (city == "전북") standardizedRegionName = "전라북도";
            else if (city == "전남") standardizedRegionName = "전라남도";
            else if (city == "경북") standardizedRegionName = "경상북도";
            else if (city == "경남") standardizedRegionName = "경상남도";
            else if (city == "제주") standardizedRegionName = "제주특별자치도"; // 제주도 '도'까지
            else standardizedRegionName = city; // 매핑되지 않은 경우 원래 이름 사용 (주의: 이 경우 일치 안될 수 있음)
          }

          if (standardizedRegionName != null) {
            if (!tempTripColors.containsKey(standardizedRegionName)) {
              tempTripColors[standardizedRegionName!] = [];
            }
            tempTripColors[standardizedRegionName!]!.add(tripColor);
          }
        }
      }

      setState(() {
        _userTripColors = tempTripColors;
        print("로드된 여행 기록 색상 (표준화된 이름): $_userTripColors"); // 로그 확인
      });
      // 데이터 로드 후 폴리곤을 다시 그려 색상을 적용합니다.
      _drawSidoPolygons();

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
        255, // 투명도를 여기서 조절할 수 있습니다. (0-255)
        (r / colors.length).round(),
        (g / colors.length).round(),
        (b / colors.length).round(),
      );
    }
    // 여행 기록이 없는 지역의 기본 색상 (약간 더 어둡게 하여 색칠된 지역과 구분)
    return Colors.grey.shade200;
  }

  Future<void> _loadSidoGeoJson() async {
    try {
      final sidoData = await rootBundle.loadString(
        'assets/geo/skorea_provinces_2018_geo.json',
      );
      setState(() {
        _sidoGeoJson = json.decode(sidoData);
        _isLoading = false;
      });
      // _drawSidoPolygons(); // _loadTripData()에서 호출되므로 여기서 다시 호출할 필요 없음
    } catch (e) {
      print('GeoJSON 로드 오류: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _drawSidoPolygons() {
    final features = _sidoGeoJson['features'] as List;
    Set<Polygon> polygons = {};
    int id = 0;

    for (var feature in features.reversed) {
      final props = feature['properties'];
      final sido = props['name'] ?? '이름없음'; // GeoJSON의 시도 이름
      final geometry = feature['geometry'];
      final type = geometry['type'];

      final fillColor = _getColorForRegion(sido); // GeoJSON 시도 이름으로 색상 가져오기

      if (type == 'MultiPolygon') {
        for (var polygon in geometry['coordinates']) {
          for (var ring in polygon) {
            final points = _convertToLatLng(ring);
            polygons.add(_buildPolygon(id++, points, sido, fillColor)); // 색상 전달
          }
        }
      } else if (type == 'Polygon') {
        for (var ring in geometry['coordinates']) {
          final points = _convertToLatLng(ring);
          polygons.add(_buildPolygon(id++, points, sido, fillColor)); // 색상 전달
        }
      }
    }

    setState(() {
      _polygons = polygons;
      // 초기 로드 시에만 카메라 이동, 재로드 시에는 기존 줌 유지 (선택 사항)
      if (_mapController != null && _selectedSido == null) {
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(_initialPosition, _currentZoom),
        );
      }
    });
  }

  Future<void> _drawSigunguPolygons(String sidoName) async {
    Set<Polygon> polygons = {};
    int id = 0;
    List<LatLng> allPoints = [];

    // 세종시 처리: 별도 파일 로드
    if (sidoName == "세종특별자치시") {
      try {
        final data = await rootBundle.loadString('assets/geo/sejong.geojson');
        final geoJson = json.decode(data);
        final features = geoJson['features'] as List;

        for (var feature in features) {
          final props = feature['properties'];
          final name = props['name'] ?? '이름없음'; // 시군구 이름
          final geometry = feature['geometry'];
          final type = geometry['type'];

          final fillColor = _getColorForRegion(name); // 시군구 이름으로 색상 가져오기

          if (type == 'Polygon') {
            for (var ring in geometry['coordinates']) {
              final points = _convertToLatLng(ring);
              polygons.add(_buildPolygon(id++, points, name, fillColor)); // 색상 전달
              allPoints.addAll(points);
            }
          } else if (type == 'MultiPolygon') {
            for (var polygon in geometry['coordinates']) {
              for (var ring in polygon) {
                final points = _convertToLatLng(ring);
                polygons.add(_buildPolygon(id++, points, name, fillColor)); // 색상 전달
                allPoints.addAll(points);
              }
            }
          }
        }

        setState(() {
          _polygons = polygons;
          _selectedSido = sidoName;
        });

        if (allPoints.isNotEmpty) {
          final bounds = _getLatLngBounds(allPoints);
          _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
        }
        print("세종 상세지도 로딩 완료");
      } catch (e) {
        print('세종 GeoJSON 로드 오류: $e');
      }
      return;
    }

    // 일반 시도 처리
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

      for (var feature in features) {
        final props = feature['properties'];
        final code = props['code'].toString();
        final name = props['name'] ?? '이름없음'; // 시군구 이름
        if (!code.startsWith(sidoPrefix)) continue;

        final geometry = feature['geometry'];
        final type = geometry['type'];

        final fillColor = _getColorForRegion(name); // 시군구 이름으로 색상 가져오기

        if (type == 'Polygon') {
          for (var ring in geometry['coordinates']) {
            final points = _convertToLatLng(ring);
            polygons.add(_buildPolygon(id++, points, name, fillColor)); // 색상 전달
            allPoints.addAll(points);
          }
        } else if (type == 'MultiPolygon') {
          for (var polygon in geometry['coordinates']) {
            for (var ring in polygon) {
              final points = _convertToLatLng(ring);
              polygons.add(_buildPolygon(id++, points, name, fillColor)); // 색상 전달
              allPoints.addAll(points);
            }
          }
        }
      }

      setState(() {
        _polygons = polygons;
        _selectedSido = sidoName;
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

  LatLngBounds _getLatLngBounds(List<LatLng> points) {
    double? minLat, maxLat, minLng, maxLng;
    for (var p in points) {
      if (minLat == null || p.latitude < minLat) minLat = p.latitude;
      if (maxLat == null || p.latitude > maxLat) maxLat = p.latitude;
      if (minLng == null || p.longitude < minLng) minLng = p.longitude;
      if (maxLng == null || p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat!, minLng!),
      northeast: LatLng(maxLat!, maxLng!),
    );
  }

  List<LatLng> _convertToLatLng(List coords) {
    return coords.map<LatLng>((c) {
      final lat = c[1].toDouble();
      final lng = c[0].toDouble();
      return LatLng(lat, lng);
    }).toList();
  }

  // fillColor 파라미터가 추가된 _buildPolygon 함수
  Polygon _buildPolygon(int id, List<LatLng> points, String name, Color fillColor) {
    return Polygon(
      polygonId: PolygonId(id.toString()),
      points: points,
      strokeWidth: 1,
      strokeColor: Colors.black,
      fillColor: fillColor.withOpacity(0.6), // 투명도를 60%로 설정했습니다. 필요에 따라 조절하세요.
      consumeTapEvents: true,
      onTap: () {
        print("클릭한 지역: $name");
        if (_selectedSido == null) {
          // 시도 단계에서만 시군구 상세 지도로 전환
          _drawSigunguPolygons(name);
        }
        // 상세 상태에서는 터치해도 아무 작업 안 함 (원한다면 다른 동작 추가 가능)
      },
    );
  }

  void _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;
    final style = await rootBundle.loadString('assets/map_style.json');
    _mapController?.setMapStyle(style);
  }

  void _zoomIn() {
    _currentZoom = (_currentZoom + 1).clamp(0.0, 18.0); // 줌 제한
    _mapController?.animateCamera(CameraUpdate.zoomTo(_currentZoom));
  }

  void _zoomOut() {
    _currentZoom = (_currentZoom - 1).clamp(0.0, 18.0); // 줌 제한
    _mapController?.animateCamera(CameraUpdate.zoomTo(_currentZoom));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedSido ?? '지도'),
        leading: _selectedSido != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _selectedSido = null;
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
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : GoogleMap(
                  onMapCreated: _onMapCreated,
                  initialCameraPosition: CameraPosition(
                    target: _initialPosition,
                    zoom: _currentZoom,
                  ),
                  polygons: _polygons,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  onCameraMove: (position) { // 현재 줌 레벨을 추적하여 줌 버튼 동작에 반영
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