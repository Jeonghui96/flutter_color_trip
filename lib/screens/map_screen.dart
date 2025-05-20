import 'package:flutter/material.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('지도'),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => SimpleDialog(
                title: const Text('지도 작업 선택'),
                children: [
                  SimpleDialogOption(
                    onPressed: () {
                      Navigator.pop(context);
                      // 나중에 색칠 모드로 이동
                    },
                    child: const Text('색칠하기'),
                  ),
                  SimpleDialogOption(
                    onPressed: () {
                      Navigator.pop(context);
                      // 나중에 행정구역 모드로 이동
                    },
                    child: const Text('행정구역 보기'),
                  ),
                ],
              ),
            );
          },
          child: const Text('지도 작업 시작하기'),
        ),
      ),
    );
  }
}
