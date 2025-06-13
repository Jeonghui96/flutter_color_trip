import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colortrip_app/screens/map_screen.dart';
import 'package:flutter_colortrip_app/screens/upload_screen.dart';
import 'package:flutter_colortrip_app/screens/settings_screen.dart';
import 'package:flutter_colortrip_app/screens/ai_recommendation_screen.dart';
import '../providers/auth_provider.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final uid = authProvider.user?.uid ?? '';

    final List<Widget> _screens = [
      MapScreen(uid: uid),
      UploadScreen(uid: uid, groupId: null),
      const AiRecommendationScreen(), // AI 추천 탭 추가
      const SettingsScreen(),
    ];

    final List<BottomNavigationBarItem> _bottomItems = [
      const BottomNavigationBarItem(icon: Icon(Icons.map), label: '지도'),
      const BottomNavigationBarItem(icon: Icon(Icons.upload_file), label: '업로드'),
      const BottomNavigationBarItem(icon: Icon(Icons.travel_explore), label: '추천'),
      const BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정'),
    ];

    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: Colors.deepPurpleAccent,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: _bottomItems,
      ),
    );
  }
}
