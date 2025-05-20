import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 정보'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.person, size: 80, color: Colors.teal),
            SizedBox(height: 20),
            Text(
              '여행 기록과 설정을 확인하세요',
              style: TextStyle(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}
