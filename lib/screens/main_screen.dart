// main_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colortrip_app/screens/map_screen.dart'; // 수정된 MapScreen import
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
  // PageController는 MapScreen 내부에 없으므로 MainScreen에서도 필요 없습니다.
  // late PageController _mapScreenPageController; // 이 줄을 제거합니다.

  @override
  void initState() {
    super.initState();
    // _mapScreenPageController 초기화 로직 제거
  }

  @override
  void dispose() {
    // _mapScreenPageController dispose 로직 제거
    super.dispose();
  }

  // SettingsScreen에서 '내가 업로드한 여행 보기'를 눌렀을 때 호출될 콜백 함수
  // 이 함수는 이제 MainScreen의 탭 인덱스만 변경합니다.
  void _goToMapTabAndTripsScreen() {
    setState(() {
      _currentIndex = 0; // '지도' 탭 (인덱스 0)으로 이동
    });
    // MapScreen 내부의 PageView를 제어하는 로직은 이제 MapScreen 자체에서 담당하지 않습니다.
    // MyTripsScreen으로 이동하는 것은 MapScreen 내부의 버튼에서 처리합니다.
  }

  final List<Widget> _screens = [
    // MapScreen에 mapPageController를 더 이상 전달하지 않습니다.
    const MapScreen(), // mapPageController 파라미터 제거
    const UploadScreen(groupId: null),
    const AiRecommendationScreen(),
    const SettingsScreen(),
  ];

  final List<BottomNavigationBarItem> _bottomItems = [
    const BottomNavigationBarItem(icon: Icon(Icons.map), label: '지도'),
    const BottomNavigationBarItem(icon: Icon(Icons.upload_file), label: '업로드'),
    const BottomNavigationBarItem(
      icon: Icon(Icons.travel_explore),
      label: '추천',
    ),
    const BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정'),
  ];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(children: _screens, index: _currentIndex),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
          // MapScreen 내부 PageView를 제어하는 로직 제거
          // if (index == 0) {
          //   _mapScreenPageController.jumpToPage(0);
          // }
        },
        selectedItemColor: Colors.deepPurpleAccent,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: _bottomItems,
      ),
    );
  }
}
