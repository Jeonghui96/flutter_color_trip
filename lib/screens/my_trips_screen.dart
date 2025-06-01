import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';


class MyTripsScreen extends StatefulWidget {
  final void Function(String regionName, Color color)? onApplyColor;

  const MyTripsScreen({super.key, this.onApplyColor});

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  bool _isEditMode = false;
  final Set<String> _selectedTripIds = {};

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
      if (!_isEditMode) {
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
        final batch = FirebaseFirestore.instance.batch();

        for (final tripId in _selectedTripIds) {
          batch.delete(
            FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .collection('trips')
                .doc(tripId),
          );
        }
        await batch.commit();

        setState(() {
          _selectedTripIds.clear();
          _isEditMode = false;
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

  Future<bool> _onWillPop() async {
    if (_isEditMode) {
      _toggleEditMode();
      return false;
    }
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

    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _onWillPop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("내 여행 기록"),
          leading: _isEditMode
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _toggleEditMode,
                )
              : null,
          actions: [
            if (!_isEditMode)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.black),
                onPressed: _toggleEditMode,
              ),
            if (_isEditMode)
              TextButton(
                onPressed: _toggleEditMode,
                child: const Text("취소", style: TextStyle(color: Colors.white)),
              ),
            if (_isEditMode)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.black),
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
                final imageUrl = data['imageUrl'] ?? data['photo_url'] ?? '';
                final city = data['city'] as String? ?? '';
                final sigungu = data['sigungu'] as String? ?? '';
                final place = data['place'] as String? ?? '';
                final memo = data['memo'] ?? data['review'] ?? '';
                final colorValue = data['color'];
                final tripColor = colorValue is int ? Color(colorValue) : Colors.grey;
                final locationText = [city, sigungu].where((e) => e.isNotEmpty).join(' ');

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
                  title: Text(place, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(locationText),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: tripColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black26),
                            ),
                          ),
                          const Text( // 'const' 키워드 추가
                            '색상 적용',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                      if (memo.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            memo,
                            style: const TextStyle(fontSize: 12, color: Colors.black87),
                          ),
                        ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.brush_outlined),
                    onPressed: () async {
                      // ====== 핵심 수정 부분 시작 ======
                      String regionNameToApply = '';
                      // GeoJSON의 이름 체계에 맞춰 key를 조정
                      if (sigungu.isNotEmpty) {
                          // 세종시 읍면동 처리 (예: "세종특별자치시 세종시 연동면")
                          if (city == "세종특별자치시" && !sigungu.startsWith("세종특별자치시")) {
                              regionNameToApply = "$city $sigungu"; // 예: "세종특별자치시 연동면" -> "세종특별자치시 세종시 연동면"
                              // 만약 Firebase에 '세종시 연동면'처럼 '세종시'가 이미 포함되어 있다면 이 로직을 조정해야 합니다.
                              // GeoJSON의 'adm_nm'과 정확히 일치하는 것이 중요합니다.
                              // 가장 좋은 방법은 Firebase에 저장 시 GeoJSON의 'adm_nm' 값을 그대로 저장하는 것입니다.
                              // 현재 예시에서는 '세종특별자치시 세종시 연동면'이므로 '세종특별자치시 연동면'으로 Firebase에 저장되어 있다면 여기서는 아래처럼 처리할 수 있습니다.
                              // 예: Firebase: city="세종특별자치시", sigungu="세종시 연동면" -> GeoJSON: "세종특별자치시 세종시 연동면"
                              // 이 경우, GeoJSON의 adm_nm과 정확히 일치하는 문자열을 생성해야 합니다.
                              // 현재는 `세종특별자치시 세종시 연동면` 형태를 가정하고 가장 단순한 형태로 맞춰봅니다.
                              // 만약 Firebase에 "연동면"만 있다면, "세종특별자치시 세종시 연동면"이 되어야 합니다.
                              // 보다 견고한 방법은 모든 시군구 이름을 로드해서 미리 매핑 테이블을 만드는 것입니다.
                              // 하지만 여기서는 Firebase 'sigungu'가 '연동면'처럼 '시' 없이 저장될 경우를 대비해 '세종시'를 추가하는 형태로 가정합니다.
                              if (city == "세종특별자치시" && sigungu.contains("연동면") && !sigungu.contains("세종시")) {
                                regionNameToApply = "세종특별자치시 세종시 $sigungu";
                              } else {
                                regionNameToApply = sigungu;
                              }

                          }
                          // 대구 "동구" 처리 (예: GeoJSON에 "대구 동구"로 되어 있다면)
                          else if (city == "대구광역시" && sigungu == "동구") {
                              regionNameToApply = "대구 동구"; // GeoJSON에 "대구 동구"로 되어 있다면
                          }
                          // 기타 일반 시군구
                          else {
                              regionNameToApply = sigungu;
                          }
                      } else {
                          regionNameToApply = city; // 시군구가 없으면 시도 이름 사용
                      }
                      // ====== 핵심 수정 부분 끝 ======

                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text("지도 색상 적용"),
                          content: const Text("이 색상을 지도에 적용하시겠습니까?"),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text("취소"),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text("적용"),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && widget.onApplyColor != null) {
                        // 조정된 regionNameToApply를 MapScreen으로 전달
                        widget.onApplyColor!(regionNameToApply, tripColor);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("$regionNameToApply 에 색상이 적용되었습니다.")),
                        );
                      }
                    },
                  ),
                  onTap: _isEditMode ? () => _toggleSelectTrip(tripId) : null,
                );
              },
            );
          },
        ),
      ),
    );
  }
}