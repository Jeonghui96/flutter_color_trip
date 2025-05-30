import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

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
    _loadSidoGeoJson();
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
      _drawSidoPolygons();
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
      final sido = props['name'] ?? '이름없음';
      final geometry = feature['geometry'];
      final type = geometry['type'];

      if (type == 'MultiPolygon') {
        for (var polygon in geometry['coordinates']) {
          for (var ring in polygon) {
            final points = _convertToLatLng(ring);
            polygons.add(_buildPolygon(id++, points, sido));
          }
        }
      } else if (type == 'Polygon') {
        for (var ring in geometry['coordinates']) {
          final points = _convertToLatLng(ring);
          polygons.add(_buildPolygon(id++, points, sido));
        }
      }
    }

    setState(() {
      _polygons = polygons;
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_initialPosition, _currentZoom),
      );
    });
  }

  Future<void> _drawSigunguPolygons(String sidoName) async {
    Set<Polygon> polygons = {};
    int id = 0;
    List<LatLng> allPoints = [];

    // 세종시 처리: 별도 파일 로드
    if (sidoName == "세종특별자치시") {
      final data = await rootBundle.loadString('assets/geo/sejong.geojson');
      final geoJson = json.decode(data);
      final features = geoJson['features'] as List;

      for (var feature in features) {
        final props = feature['properties'];
        final name = props['name'] ?? '이름없음';
        final geometry = feature['geometry'];
        final type = geometry['type'];

        if (type == 'Polygon') {
          for (var ring in geometry['coordinates']) {
            final points = _convertToLatLng(ring);
            polygons.add(_buildPolygon(id++, points, name));
            allPoints.addAll(points);
          }
        } else if (type == 'MultiPolygon') {
          for (var polygon in geometry['coordinates']) {
            for (var ring in polygon) {
              final points = _convertToLatLng(ring);
              polygons.add(_buildPolygon(id++, points, name));
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
      return;
    }

    // 일반 시도 처리
    final sidoPrefix = sidoCodeMap[sidoName];
    if (sidoPrefix == null) return;

    final data = await rootBundle.loadString(
      'assets/geo/skorea_municipalities_2018_geo.json',
    );
    final geoJson = json.decode(data);
    final features = geoJson['features'] as List;

    for (var feature in features) {
      final props = feature['properties'];
      final code = props['code'].toString();
      final name = props['name'] ?? '이름없음';
      if (!code.startsWith(sidoPrefix)) continue;

      final geometry = feature['geometry'];
      final type = geometry['type'];

      if (type == 'Polygon') {
        for (var ring in geometry['coordinates']) {
          final points = _convertToLatLng(ring);
          polygons.add(_buildPolygon(id++, points, name));
          allPoints.addAll(points);
        }
      } else if (type == 'MultiPolygon') {
        for (var polygon in geometry['coordinates']) {
          for (var ring in polygon) {
            final points = _convertToLatLng(ring);
            polygons.add(_buildPolygon(id++, points, name));
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

  Polygon _buildPolygon(int id, List<LatLng> points, String name) {
    return Polygon(
      polygonId: PolygonId(id.toString()),
      points: points,
      strokeWidth: 1,
      strokeColor: Colors.black,
      fillColor: Colors.transparent,
      consumeTapEvents: true,
      onTap: () {
        print("클릭한 지역: $name");
        if (_selectedSido == null) {
          _drawSigunguPolygons(name); // 전체 → 상세 전환만 허용
        }
        // 상세 상태에서는 터치해도 아무 작업 안 함
      },
    );
  }

  void _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;
    final style = await rootBundle.loadString('assets/map_style.json');
    _mapController?.setMapStyle(style);
  }

  void _zoomIn() {
    _currentZoom += 1;
    _mapController?.animateCamera(CameraUpdate.zoomTo(_currentZoom));
  }

  void _zoomOut() {
    _currentZoom -= 1;
    _mapController?.animateCamera(CameraUpdate.zoomTo(_currentZoom));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedSido ?? '지도'),
        leading:
            _selectedSido != null
                ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      _selectedSido = null;
                      _currentZoom = 6.8;
                    });
                    _drawSidoPolygons();
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
