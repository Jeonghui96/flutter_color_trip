import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('홈'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.group, size: 80, color: Colors.teal),
            SizedBox(height: 20),
            Text(
              '그룹으로 함께 여행 기록을 만들어보세요!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}
