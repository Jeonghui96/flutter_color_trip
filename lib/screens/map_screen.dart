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
  Set<Polygon> _polygons = {};

  @override
  void initState() {
    super.initState();
    _loadGeoJsonData();
  }

  // 📍 GeoJSON 경계선 불러오기
  Future<void> _loadGeoJsonData() async {
    try {
      final String data = await rootBundle.loadString('assets/geo/서울특별시.geojson');
      final Map<String, dynamic> json = jsonDecode(data);

      Set<Polygon> polygons = {};

      for (var feature in json['features']) {
        final props = feature['properties'];
        final geometry = feature['geometry'];

        if (geometry == null || props == null) continue;

        final String name = props['name'] ?? '이름없음';
        final String type = geometry['type'];

        if (type == 'Polygon') {
          final List coords = geometry['coordinates'][0];
          final List<LatLng> points = coords.map<LatLng>((c) => LatLng(c[1], c[0])).toList();

          polygons.add(
            Polygon(
              polygonId: PolygonId(name),
              points: points,
              fillColor: Colors.transparent,
              strokeColor: Colors.black,
              strokeWidth: 1,
            ),
          );
        } else if (type == 'MultiPolygon') {
          final List polys = geometry['coordinates'];
          for (var poly in polys) {
            final List coords = poly[0];
            final List<LatLng> points = coords.map<LatLng>((c) => LatLng(c[1], c[0])).toList();

            polygons.add(
              Polygon(
                polygonId: PolygonId('$name-${polygons.length}'),
                points: points,
                fillColor: Colors.transparent,
                strokeColor: Colors.black,
                strokeWidth: 1,
              ),
            );
          }
        }
      }

      setState(() {
        _polygons = polygons;
      });
    } catch (e) {
      print("❌ Error loading GeoJSON: $e");
    }
  }

  // 🎨 흰색 지도 스타일 적용
  Future<void> _applyMapStyle() async {
    final String style = await rootBundle.loadString('assets/map_style.json');
    _mapController?.setMapStyle(style);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.8),
        elevation: 0,
        title: const Text(
          'ColorTrip',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) async {
              _mapController = controller;
              await _applyMapStyle();
            },
            initialCameraPosition: const CameraPosition(
              target: LatLng(37.5665, 126.9780),
              zoom: 10.0,
            ),
            polygons: _polygons,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
          ),

          // 📍 지역명 표시
          Positioned(
            top: 100,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  )
                ],
              ),
              child: const Text(
                '서울특별시',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // 👉 사진 업로드 화면으로 이동하도록 연결할 수 있음
        },
        backgroundColor: Colors.deepPurpleAccent,
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }
}
