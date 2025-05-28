// 전체 시도 클릭 → 시군구 확대 지원 + '전체 보기' 버튼 추가
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  LatLng _initialPosition = const LatLng(36.5, 127.8); // 전국 중심
  Set<Polygon> _polygons = {};
  Map<String, dynamic> _sidoGeoJson = {};
  Map<String, dynamic> _sigunguGeoJson = {};
  bool _isLoading = true;
  String? _selectedSido;
  bool _showAllSido = false;

  final List<String> majorSido = [
    '서울특별시',
    '부산광역시',
    '대구광역시',
    '인천광역시',
    '광주광역시',
    '대전광역시',
    '울산광역시',
    '세종특별자치시',
    '제주특별자치도',
  ];

  @override
  void initState() {
    super.initState();
    _loadGeoJson();
  }

  Future<void> _loadGeoJson() async {
    try {
      final sidoData = await rootBundle.loadString(
        'assets/geo/korea_sido.geojson',
      );
      final sigunguData = await rootBundle.loadString(
        'assets/geo/korea_sigungu.geojson',
      );

      _sidoGeoJson = json.decode(sidoData);
      _sigunguGeoJson = json.decode(sigunguData);

      _drawSidoPolygons();
    } catch (e) {
      print('GeoJSON 로드 오류: \$e');
    }
  }

  void _drawSidoPolygons() {
    final features = _sidoGeoJson['features'] as List;
    Set<Polygon> polygons = {};
    int id = 0;

    for (var feature in features) {
      final props = feature['properties'];
      final name = props['CTP_KOR_NM'] ?? props['adm_nm'];
      if (!_showAllSido && !majorSido.contains(name)) continue;

      final geometry = feature['geometry'];
      final type = geometry['type'];

      List<List> allCoords = [];
      if (geometry['type'] == 'MultiPolygon') {
        final coords = geometry['coordinates'] as List;
        for (var polygon in coords) {
          if (polygon is List) {
            allCoords.addAll(polygon.cast<List>());
          }
        }
      } else if (geometry['type'] == 'Polygon') {
        allCoords = (geometry['coordinates'] as List).cast<List>();
      }

      for (var ring in allCoords) {
        final points =
            (ring as List)
                .map<LatLng>((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
                .toList();
        polygons.add(_buildPolygon(id++, points, name));
      }
    }

    setState(() {
      _polygons = polygons;
      _isLoading = false;
      _selectedSido = null;
    });
  }

  void _drawSigunguPolygons(String sidoName) {
    final features = _sigunguGeoJson['features'] as List;
    Set<Polygon> polygons = {};
    int id = 0;

    for (var feature in features) {
      final props = feature['properties'];
      final name = props['SIG_KOR_NM'] ?? props['adm_nm'];
      final upper = props['CTP_KOR_NM'] ?? props['upper_nm'];
      if (upper != sidoName) continue;

      final geometry = feature['geometry'];
      final type = geometry['type'];

      List<List> allCoords = [];
      if (type == 'MultiPolygon') {
        final coordsList = geometry['coordinates'] as List;
        for (var polygon in coordsList) {
          if (polygon is List) {
            allCoords.addAll(polygon.cast<List>());
          }
        }
      } else if (type == 'Polygon') {
        allCoords = (geometry['coordinates'] as List).cast<List>();
      }

      for (var ring in allCoords) {
        final points =
            (ring as List)
                .map<LatLng>((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
                .toList();
        polygons.add(_buildPolygon(id++, points, name));
      }
    }

    setState(() {
      _polygons = polygons;
      _selectedSido = sidoName;
    });

    _mapController?.animateCamera(CameraUpdate.zoomTo(10));
  }

  Polygon _buildPolygon(int id, List<LatLng> points, String name) {
    return Polygon(
      polygonId: PolygonId('poly_\$id'),
      points: points,
      strokeColor: Colors.black,
      strokeWidth: 1,
      fillColor: Colors.transparent,
      consumeTapEvents: true,
      onTap: () {
        print('Tapped: \$name');
        if (_selectedSido == null) {
          _drawSigunguPolygons(name);
        }
      },
    );
  }

  void _zoomIn() => _mapController?.animateCamera(CameraUpdate.zoomIn());
  void _zoomOut() => _mapController?.animateCamera(CameraUpdate.zoomOut());

  Future<bool> _onWillPop() async {
    if (_selectedSido != null) {
      _drawSidoPolygons();
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_initialPosition, 7),
      );
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_selectedSido ?? '내 여행지도'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          actions: [
            if (!_showAllSido && _selectedSido == null)
              TextButton(
                onPressed: () {
                  setState(() {
                    _showAllSido = true;
                  });
                  _drawSidoPolygons();
                },
                child: const Text('전체 시도 보기'),
              ),
          ],
        ),
        body: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _initialPosition,
                zoom: 7,
              ),
              polygons: _polygons,
              onMapCreated: (controller) async {
                _mapController = controller;
                final style = await rootBundle.loadString(
                  'assets/map_style.json',
                );
                _mapController?.setMapStyle(style);
              },
            ),
            if (_isLoading) const Center(child: CircularProgressIndicator()),
            Positioned(
              right: 16,
              bottom: 80,
              child: Column(
                children: [
                  FloatingActionButton(
                    heroTag: 'zoomIn',
                    mini: true,
                    onPressed: _zoomIn,
                    child: const Icon(Icons.add),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton(
                    heroTag: 'zoomOut',
                    mini: true,
                    onPressed: _zoomOut,
                    child: const Icon(Icons.remove),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
