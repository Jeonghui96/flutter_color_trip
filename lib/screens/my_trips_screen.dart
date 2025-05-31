import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MyTripsScreen extends StatefulWidget {
  const MyTripsScreen({super.key});

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  bool _isEditMode = false; // 편집 모드 여부
  final Set<String> _selectedTripIds = {}; // 선택된 여행 기록의 ID 목록

  // --- 편집 모드 관련 함수 ---
  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
      if (!_isEditMode) {
        // 편집 모드 종료 시 선택된 항목 초기화
        _selectedTripIds.clear();
      }
    });
  }

  void _toggleSelectTrip(String tripId) {
    setState(() {
      if (_selectedTripIds.contains(tripId)) {
        _selectedTripIds.remove(tripId);
      } else {
        _selectedTripIds.add(tripId);
      }
    });
  }

  Future<void> _deleteSelectedTrips(String uid) async {
    if (_selectedTripIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("선택된 여행 기록이 없습니다.")),
      );
      return;
    }

    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("선택된 기록 삭제"),
          content: Text("선택된 ${_selectedTripIds.length}개의 여행 기록을 삭제하시겠습니까?"),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("취소"),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("삭제"),
            ),
          ],
        );
      },
    );

    if (confirmDelete == true) {
      try {
        final batch = FirebaseFirestore.instance.batch(); // 일괄 삭제를 위한 Batch 쓰기

        for (final tripId in _selectedTripIds) {
          batch.delete(
            FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .collection('trips')
                .doc(tripId),
          );
        }
        await batch.commit(); // Batch 실행

        setState(() {
          _selectedTripIds.clear(); // 삭제 후 선택된 항목 초기화
          _isEditMode = false; // 편집 모드 종료
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("선택된 여행 기록이 삭제되었습니다.")),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("삭제 실패: $e")),
        );
      }
    }
  }

  // --- 뒤로 가기 동작 재정의 ---
  Future<bool> _onWillPop() async {
    if (_isEditMode) {
      // 편집 모드일 때 뒤로 가기 누르면 편집 모드 종료
      _toggleEditMode();
      return false; // 뒤로 가기 이벤트를 소비하고 화면을 닫지 않음
    }
    // 편집 모드가 아닐 때 뒤로 가기 누르면 기본 뒤로 가기 동작 수행 (이전 화면으로 이동)
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text("로그인이 필요합니다.")),
      );
    }

    return PopScope( // 뒤로 가기 동작을 제어하는 위젯
      canPop: true, // 기본적으로는 pop 가능하게 설정
      onPopInvoked: (didPop) {
        if(didPop) return; // 시스템 뒤로가기가 이미 발생했다면 아무것도 하지 않음
        _onWillPop(); // 뒤로 가기 동작을 우리가 정의한 대로 처리
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("내 여행 기록"),
          leading: _isEditMode // 편집 모드일 때만 커스텀 뒤로 가기 버튼 표시
              ? IconButton(
                  icon: const Icon(Icons.arrow_back), // 뒤로 가기 화살표
                  onPressed: _toggleEditMode, // 뒤로 가기 버튼 누르면 편집 모드 종료
                )
              : null, // 편집 모드가 아닐 때는 기본 뒤로 가기 버튼 사용
          actions: [
            if (!_isEditMode) // 편집 모드가 아닐 때만 "기록 삭제" 버튼 (외곽선 휴지통) 표시
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.black), // 외곽선 휴지통 아이콘, 검정색
                onPressed: _toggleEditMode,
              ),
            if (_isEditMode) // 편집 모드일 때만 "취소" 버튼 표시
              TextButton(
                onPressed: _toggleEditMode, // 편집 모드 종료
                child: const Text("취소", style: TextStyle(color: Colors.white)),
              ),
            if (_isEditMode) // 편집 모드일 때 "삭제" 버튼 (채워진 휴지통) 표시
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.black), // 채워진 휴지통 아이콘, 검정색
                onPressed: () => _deleteSelectedTrips(uid),
              ),
          ],
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('trips')
              .orderBy('timestamp', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Center(child: Text("업로드한 여행이 없습니다."));
            }

            return ListView.separated(
              itemCount: docs.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final doc = docs[index];
                final tripId = doc.id;
                final data = doc.data() as Map<String, dynamic>;
                final imageUrl = data['imageUrl'] ?? '';
                final country = data['country'] ?? '';
                final city = data['city'] ?? '';
                final place = data['place'] ?? '';
                final memo = data['memo'] ?? '';
                final colorValue = data['color'];
                final tripColor = colorValue != null ? Color(colorValue) : Colors.grey;

                return ListTile(
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isEditMode)
                        Checkbox(
                          value: _selectedTripIds.contains(tripId),
                          onChanged: (bool? checked) {
                            _toggleSelectTrip(tripId);
                          },
                        ),
                      imageUrl.isNotEmpty
                          ? Image.network(imageUrl, width: 50, height: 50, fit: BoxFit.cover)
                          : const Icon(Icons.image, size: 50),
                    ],
                  ),
                  title: Text('$country $city $place'),
                  subtitle: Text(memo),
                  trailing: Container( // 기존 색상 원
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: tripColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black26),
                    ),
                  ),
                  onTap: _isEditMode
                      ? () => _toggleSelectTrip(tripId)
                      : null,
                );
              },
            );
          },
        ),
      ),
    );
  }
}