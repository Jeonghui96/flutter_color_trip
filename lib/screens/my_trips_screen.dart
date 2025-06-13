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

class _MyTripsScreenState extends State<MyTripsScreen> with AutomaticKeepAliveClientMixin {
  bool _isEditMode = false;
  final Set<String> _selectedTripIds = {};
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

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
          content: Text("선택된 \${_selectedTripIds.length}개의 여행 기록을 삭제하시겠습니까?"),
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
          SnackBar(content: Text("삭제 실패: \$e")),
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
    super.build(context);
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
              controller: _scrollController,
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
                          const Text('색칠하기', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                  trailing: TextButton(
                    child: const Text("색칠하기"),
                    onPressed: () async {
                      String regionNameToApply = sigungu.isNotEmpty ? sigungu : city;
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
                        widget.onApplyColor!(regionNameToApply, tripColor);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("\$regionNameToApply 에 색상이 적용되었습니다.")),
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