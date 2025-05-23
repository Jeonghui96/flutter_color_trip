import 'package:flutter/material.dart';

class MapColoredScreen extends StatelessWidget {
  const MapColoredScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('색칠된 지도')),
      body: const Center(
        child: Text('지도에 색칠된 지역이 표시됩니다.'),
      ),
    );
  }
}
