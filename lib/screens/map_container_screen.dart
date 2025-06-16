import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';

import 'my_trips_screen.dart';

class MapContainerScreen extends StatefulWidget {
  const MapContainerScreen({super.key});

  @override
  State<MapContainerScreen> createState() => _MapContainerScreenState();
}

class _MapContainerScreenState extends State<MapContainerScreen> {
  GoogleMapController? mapController;
  Map<String, Polygon> _polygons = {};
  Map<String, Color> _regionColors = {};

  @override
  void initState() {
    super.initState();
    _loadMapData();
  }

  Future<void> _loadMapData() async {
    try {
      final String response = await rootBundle.loadString('assets/data/sigungu_polygons.json');
      final data = await json.decode(response);

      Set<Polygon> loadedPolygons = {};
      Map<String, Color> initialRegionColors = {};

      for (var feature in data['features']) {
        String regionName = feature['properties']['name'];
        List<LatLng> points = [];

        var geometry = feature['geometry'];
        if (geometry['type'] == 'Polygon') {
          for (var coordRing in geometry['coordinates']) {
            for (var coord in coordRing) {
              if (coord is List && coord.length >= 2) {
                points.add(LatLng(coord[1], coord[0]));
              }
            }
          }
        } else if (geometry['type'] == 'MultiPolygon') {
          for (var polyCoords in geometry['coordinates']) {
            for (var ringCoords in polyCoords) {
                for (var coord in ringCoords) {
                    if (coord is List && coord.length >= 2) {
                        points.add(LatLng(coord[1], coord[0]));
                    }
                }
            }
          }
        } else {
            debugPrint('Unsupported geometry type: ${geometry['type']} for region: $regionName');
            continue;
        }

        Color initialColor = Colors.grey.withOpacity(0.3);
        initialRegionColors[regionName] = initialColor;

        loadedPolygons.add(
          Polygon(
            polygonId: PolygonId(regionName),
            points: points,
            strokeWidth: 2,
            strokeColor: Colors.black54,
            fillColor: initialColor,
            consumeTapEvents: true,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _polygons = { for (var p in loadedPolygons) p.polygonId.value : p };
        _regionColors = initialRegionColors;
        debugPrint('Map data loaded. Polygons: ${_polygons.length}');
      });

    } catch (e) {
      debugPrint('Error loading map data: $e');
    }
  }

  void _applyColorToMapRegion(String regionName, Color color) {
    debugPrint('MapContainerScreen: Received color application request for "$regionName" with color $color');
    if (_polygons.containsKey(regionName)) {
      if (!mounted) return;
      setState(() {
        _polygons[regionName] = _polygons[regionName]!.copyWith(
          fillColorParam: color.withOpacity(0.5),
          strokeColorParam: color,
        );
        _regionColors[regionName] = color;
        debugPrint('MapContainerScreen: Successfully updated polygon for $regionName.');
      });
    } else {
      debugPrint('MapContainerScreen: Region "$regionName" not found in existing polygons. Cannot apply color.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('지도 & 내 여행'),
      ),
      body: PageView(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: const CameraPosition(
              target: LatLng(35.9078, 127.7669),
              zoom: 7,
            ),
            onMapCreated: (GoogleMapController controller) {
              mapController = controller;
            },
            polygons: Set<Polygon>.of(_polygons.values),
          ),
          MyTripsScreen(
            onApplyColor: _applyColorToMapRegion,
          ),
        ],
      ),
    );
  }
}