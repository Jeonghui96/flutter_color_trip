import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/auth_provider.dart' as local_auth;
import 'providers/notification_provider.dart';
import 'screens/main_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .env 로드
  await dotenv.load();

  // Firebase 초기화
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // // 테스트 계정으로 자동 로그인
  // final auth = FirebaseAuth.instance;
  // if (auth.currentUser == null) {
  //   try {
  //     await auth.signInWithEmailAndPassword(
  //       email: 'testuser@colortrip.com',
  //       password: 'test1234',
  //     );
  //     print('✅ 테스트 계정 로그인 성공: ${auth.currentUser?.uid}');
  //   } catch (e) {
  //     print('🔥 테스트 계정 로그인 실패: $e');
  //   }
  // }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => local_auth.AuthProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ColorTrip',
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.light,
      ),
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
