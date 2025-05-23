import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: const Center(
        child: Text('앱 설정을 할 수 있습니다.'),
      ),
    );
  }
}
