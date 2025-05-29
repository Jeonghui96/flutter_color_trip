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

  final Map<String, String> sidoCodeMap = {
    "서울특별시": "11",
    "부산광역시": "26",
    "대구광역시": "27",
    "인천광역시": "28",
    "광주광역시": "29",
    "대전광역시": "30",
    "울산광역시": "31",
    "세종특별자치시": "36",
    "경기도": "41",
    "강원도": "42",
    "충청북도": "43",
    "충청남도": "44",
    "전라북도": "45",
    "전라남도": "46",
    "경상북도": "47",
    "경상남도": "48",
    "제주특별자치도": "50",
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
        CameraUpdate.newLatLngZoom(_initialPosition, 7),
      );
    });
  }

  Future<void> _drawSigunguPolygons(String sidoName) async {
    final sidoPrefix = sidoCodeMap[sidoName];
    if (sidoPrefix == null) return;

    final data = await rootBundle.loadString(
      'assets/geo/skorea_municipalities_2018_geo.json',
    );
    final geoJson = json.decode(data);
    final features = geoJson['features'] as List;
    Set<Polygon> polygons = {};
    int id = 0;

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
        }
      } else if (type == 'MultiPolygon') {
        for (var polygon in geometry['coordinates']) {
          for (var ring in polygon) {
            final points = _convertToLatLng(ring);
            polygons.add(_buildPolygon(id++, points, name));
          }
        }
      }
    }

    setState(() {
      _polygons = polygons;
      _selectedSido = sidoName;
    });

    print("세부 행정구역 로딩 완료: $sidoName");
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
          _drawSigunguPolygons(name);
        } else {
          setState(() {
            _selectedSido = null;
          });
          _drawSidoPolygons();
        }
      },
    );
  }

  void _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;
    final style = await rootBundle.loadString('assets/map_style.json');
    _mapController?.setMapStyle(style);
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
                    });
                    _drawSidoPolygons();
                  },
                )
                : null,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : GoogleMap(
                onMapCreated: _onMapCreated,
                initialCameraPosition: CameraPosition(
                  target: _initialPosition,
                  zoom: 7,
                ),
                polygons: _polygons,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
              ),
    );
  }
}
