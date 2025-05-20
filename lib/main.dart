// main.dart
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart';
import 'screens/profile_screen.dart';

void main() {
  runApp(const ColorTripApp());
}

class ColorTripApp extends StatelessWidget {
  const ColorTripApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ColorTrip',
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({Key? key}) : super(key: key);

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  final List<Widget> _pages = const [
    HomeScreen(),
    MapScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.teal,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: '지도'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '내 정보'),
        ],
      ),
    );
  }
}
