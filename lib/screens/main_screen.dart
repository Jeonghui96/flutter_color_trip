import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'map_screen.dart'; // map_screen.dart의 정확한 경로
import 'upload_screen.dart'; // upload_screen.dart의 정확한 경로
import 'settings_screen.dart'; // settings_screen.dart의 정확한 경로

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    // AuthProvider에서 uid를 가져옵니다.
    // listen: false를 사용하여 불필요한 위젯 리빌드를 방지할 수 있습니다.
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final String uid = authProvider.user?.uid ?? ''; // 유저가 없으면 빈 문자열 (실제 앱에서는 로그인 강제)

    // _screens 리스트의 MapScreen에 uid를 전달합니다.
    final List<Widget> _screens = [
      // MapScreen에 uid를 전달하도록 수정
      MapScreen(uid: uid), // 여기에 uid를 전달합니다.
      UploadScreen(uid: uid, groupId: null), // 이미 uid를 전달하고 있었네요.
      const SettingsScreen(),
    ];

    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: Colors.deepPurpleAccent,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: '지도'),
          BottomNavigationBarItem(icon: Icon(Icons.add_a_photo), label: '추가하기'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '더보기'),
        ],
      ),
    );
  }
}