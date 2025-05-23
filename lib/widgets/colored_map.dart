import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ColoredMap extends StatefulWidget {
  const ColoredMap({Key? key}) : super(key: key);

  @override
  State<ColoredMap> createState() => _ColoredMapState();
}

class _ColoredMapState extends State<ColoredMap> {
  GoogleMapController? mapController;
  final Set<Polygon> _polygons = {};

  @override
  void initState() {
    super.initState();
    _loadVisitedAreas();
  }

  Future<void> _loadVisitedAreas() async {
    final snapshot = await FirebaseFirestore.instance.collection('visited_areas').get();

    Set<Polygon> loadedPolygons = {};

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final List<dynamic> points = data['polygon'] ?? [];

      loadedPolygons.add(
        Polygon(
          polygonId: PolygonId(doc.id),
          points: points.map((p) => LatLng(p['lat'], p['lng'])).toList(),
          fillColor: Color(int.parse(data['fillColor'])).withOpacity(0.5),
          strokeColor: Colors.black,
          strokeWidth: 1,
        ),
      );
    }

    setState(() {
      _polygons.addAll(loadedPolygons);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      onMapCreated: (controller) {
        mapController = controller;
      },
      initialCameraPosition: const CameraPosition(
        target: LatLng(37.5665, 126.9780), // 서울
        zoom: 3,
      ),
      polygons: _polygons,
      myLocationEnabled: true,
    );
  }
}
