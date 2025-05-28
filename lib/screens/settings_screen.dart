import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? groupName;
  String? groupId;
  String? groupPassword;

  @override
  void initState() {
    super.initState();
    _loadGroupInfo();
  }

  Future<void> _loadGroupInfo() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final gid = userDoc.data()?['groupId'];
    if (gid == null) return;

    final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(gid).get();
    final data = groupDoc.data();

    setState(() {
      groupId = gid;
      groupName = data?['name'];
      groupPassword = data?['password'];
    });
  }

  Future<void> _createGroup(BuildContext context) async {
    if (groupId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 그룹에 가입되어 있어요')),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final nameController = TextEditingController();
    final passwordController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('그룹 생성'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '그룹 이름'),
            ),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: '비밀번호'),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final password = passwordController.text.trim();

              if (name.isEmpty || password.isEmpty) return;

              final gid = const Uuid().v4().substring(0, 8); // 그룹 코드 길이 8자리

              await FirebaseFirestore.instance.collection('groups').doc(gid).set({
                'name': name,
                'password': password,
                'createdAt': FieldValue.serverTimestamp(),
              });

              await FirebaseFirestore.instance.collection('users').doc(uid).set({
                'groupId': gid,
              }, SetOptions(merge: true));

              setState(() {
                groupId = gid;
                groupName = name;
                groupPassword = password;
              });

              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('그룹 생성 완료! 코드: $gid')),
              );
            },
            child: const Text('생성'),
          ),
        ],
      ),
    );
  }

  Future<void> _leaveGroup() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || groupId == null) return;

    final leavingGroupId = groupId;

    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'groupId': FieldValue.delete(),
    });

    // 그룹 탈퇴 후 해당 그룹에 남은 사용자가 없으면 그룹 문서 삭제
    final remainingUsersInGroup = await FirebaseFirestore.instance
        .collection('users')
        .where('groupId', isEqualTo: leavingGroupId)
        .get();

    if (remainingUsersInGroup.docs.isEmpty) {
      await FirebaseFirestore.instance.collection('groups').doc(leavingGroupId).delete();
    }

    setState(() {
      groupId = null;
      groupName = null;
      groupPassword = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('그룹에서 탈퇴했습니다')),
    );
  }

  Future<void> _renameGroup(BuildContext context) async {
    final controller = TextEditingController(text: groupName ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('그룹 이름 변경'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '새 그룹 이름'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (groupId != null && newName.isNotEmpty) {
                await FirebaseFirestore.instance.collection('groups').doc(groupId).update({
                  'name': newName,
                });
                setState(() {
                  groupName = newName;
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('그룹 이름이 변경되었습니다')),
                );
              }
            },
            child: const Text('변경'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareGroupInvite() async {
    if (groupId != null && groupPassword != null) {
      final message = '''
ColorTrip에서 나랑 여행 지도를 함께 꾸며요! 🗺️

그룹 코드: $groupId
비밀번호: $groupPassword

앱 설치하기:
Android → https://play.google.com/store/apps/details?id=com.example.colortrip
iOS → https://apps.apple.com/app/id1234567890

ColorTrip 앱을 설치한 뒤 '그룹 참여' 메뉴에서 코드와 비밀번호를 입력하세요!
''';
      await Share.share(message);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('그룹 정보가 없습니다')),
      );
    }
  }

  Future<void> _copyToClipboard(String label, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label 복사됨')));
  }

  String getColorName(Color color) {
    int r = color.red, g = color.green, b = color.blue;
    if (r > 200 && g < 100 && b < 100) return '빨간색';
    if (r > 200 && g > 200 && b < 100) return '노란색';
    if (r < 100 && g > 200 && b < 100) return '초록색';
    if (r < 100 && g < 100 && b > 200) return '파란색';
    if (r > 180 && b > 180 && g < 100) return '자주색';
    if (r > 200 && g > 200 && b > 200) return '흰색';
    if (r < 50 && g < 50 && b < 50) return '검정색';
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  // 나의 여행 기록 목록을 표시하는 위젯
  Widget _buildTripListContent() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text("로그인 필요"),
      );
    }

    return StreamBuilder<QuerySnapshot>(
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
        if (snapshot.hasError) {
          return Center(child: Text('오류: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("아직 여행 기록이 없어요."),
          );
        }

        final docs = snapshot.data!.docs;

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(), // ListView 안에 ListView가 있을 때 스크롤 충돌 방지
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final imageUrl = data['imageUrl'];
            final place = data['place'] ?? '';
            final city = data['city'] ?? '';
            final memo = data['memo'] ?? '';

            final dynamic rawColor = data['color'];
            Color color;
            if (rawColor is String) {
              try {
                color = Color(int.parse(rawColor.replaceFirst('#', '0xff')));
              } catch (e) {
                color = const Color(0xFFCCCCCC);
              }
            } else if (rawColor is int) {
              color = Color(rawColor);
            } else {
              color = const Color(0xFFCCCCCC);
            }

            return ListTile(
              leading: imageUrl != null && imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.image_not_supported, size: 50);
                      },
                    )
                  : const Icon(Icons.image_not_supported, size: 50),
              title: Text('$city - $place'),
              subtitle: Text('색상: ${getColorName(color)}'),
              trailing: CircleAvatar(backgroundColor: color),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('$city - $place'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (imageUrl != null && imageUrl.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(imageUrl, height: 150, fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(Icons.image_not_supported, size: 150);
                              },
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text('메모: $memo'),
                        Text('색상: ${getColorName(color)}'),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('닫기'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // 나의 여행 기록 다이얼로그를 표시하는 함수
  void _showMyTripsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('나의 여행 기록'),
          content: ConstrainedBox( // 다이얼로그 내용의 최대 높이 제한
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6, // 화면 높이의 60%
            ),
            child: _buildTripListContent(), // 여행 기록 목록 위젯
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // 다이얼로그 닫기
              },
              child: const Text('닫기'),
            ),
          ],
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('더보기'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 계정 섹션
          const Text(
            '계정',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('계정정보'),
            subtitle: Text(user?.email ?? '이메일 없음'),
          ),
          const SizedBox(height: 8),
          if (groupId == null)
            OutlinedButton.icon(
              onPressed: () => _createGroup(context),
              icon: const Icon(Icons.group_add),
              label: const Text('그룹 만들기'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                side: const BorderSide(color: Colors.deepPurple),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          const SizedBox(height: 24),

          // 내 그룹 정보 섹션
          const Text('내 그룹 정보', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          if (groupId != null) ...[
            ListTile(
              title: const Text('그룹 이름'),
              subtitle: Text(groupName ?? ''),
              trailing: IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _renameGroup(context),
              ),
            ),
            ListTile(
              title: const Text('그룹 코드'),
              subtitle: Text(groupId ?? ''),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () => _copyToClipboard('그룹 코드', groupId ?? ''),
              ),
            ),
            ListTile(
              title: const Text('비밀번호'),
              subtitle: Text(groupPassword ?? ''),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () => _copyToClipboard('비밀번호', groupPassword ?? ''),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('초대 링크 공유'),
              onTap: _shareGroupInvite,
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('그룹 탈퇴'),
              onTap: _leaveGroup,
            ),
          ] else ...[
            const Text('현재 가입한 그룹이 없습니다.'),
          ],
          const SizedBox(height: 24),

          // 나의 여행기록 섹션 (클릭 시 다이얼로그 표시)
          const Text('나의 여행기록', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.map), // 적절한 아이콘 선택
            title: const Text('내가 업로드한 여행 보기'),
            onTap: () => _showMyTripsDialog(context), // 클릭 시 다이얼로그 호출
            trailing: const Icon(Icons.chevron_right),
          ),
          const SizedBox(height: 20),

          // 기타 섹션
          const Text('기타', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('앱 정보'),
            subtitle: const Text('버전 1.0.0'),
          ),
          ListTile(
            leading: const Icon(Icons.exit_to_app),
            title: const Text('로그아웃'),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('로그아웃 되었습니다')),
              );
              // 로그아웃 후 로그인 화면으로 이동 또는 앱 종료
              // Navigator.of(context).popUntil((route) => route.isFirst); // 모든 스택 제거
              // Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => LoginScreen())); // 로그인 화면으로 이동 예시
            },
          ),
        ],
      ),
    );
  }
}