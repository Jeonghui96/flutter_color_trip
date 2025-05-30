import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      debugPrint("로그인 유지됨: \${user.email ?? user.uid}");
    } else {
      debugPrint("로그인되어 있지 않음");
    }
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이미 그룹에 가입되어 있어요')));
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
            TextField(controller: nameController, decoration: const InputDecoration(labelText: '그룹 이름')),
            TextField(controller: passwordController, decoration: const InputDecoration(labelText: '비밀번호'), obscureText: true),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final password = passwordController.text.trim();
              if (name.isEmpty || password.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('그룹 이름과 비밀번호를 입력해주세요.')));
                return;
              }
              final gid = const Uuid().v4().substring(0, 8);
              await FirebaseFirestore.instance.collection('groups').doc(gid).set({
                'name': name,
                'password': password,
                'createdAt': FieldValue.serverTimestamp(),
              });
              await FirebaseFirestore.instance.collection('users').doc(uid).set({'groupId': gid}, SetOptions(merge: true));
              setState(() {
                groupId = gid;
                groupName = name;
                groupPassword = password;
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('그룹 생성 완료! 코드: \$gid')));
            },
            child: const Text('생성'),
          ),
        ],
      ),
    );
  }

  Future<void> _joinGroup(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final codeController = TextEditingController();
    final passwordController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('그룹 참여'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: codeController, decoration: const InputDecoration(labelText: '그룹 코드')),
            TextField(controller: passwordController, decoration: const InputDecoration(labelText: '비밀번호'), obscureText: true),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(
            onPressed: () async {
              final code = codeController.text.trim();
              final password = passwordController.text.trim();
              if (code.isEmpty || password.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('그룹 코드와 비밀번호를 입력해주세요.')));
                return;
              }
              final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(code).get();
              if (!groupDoc.exists || groupDoc.data()?['password'] != password) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('그룹 코드 또는 비밀번호가 잘못되었습니다')));
                return;
              }
              await FirebaseFirestore.instance.collection('users').doc(uid).set({'groupId': code}, SetOptions(merge: true));
              setState(() {
                groupId = code;
                groupName = groupDoc.data()?['name'];
                groupPassword = password;
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('그룹에 참여하였습니다')));
            },
            child: const Text('참여'),
          ),
        ],
      ),
    );
  }

  void _showMyTripsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('내 여행 기록'),
        content: const Text('이곳에 사용자가 업로드한 여행 기록 목록이 표시될 예정입니다.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기'))],
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('구글 로그인 완료')));
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('로그인 실패: \$e')));
    }
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
          if (user == null) ...[
            const Text('로그인', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ListTile(
              leading: const Icon(Icons.login, color: Colors.green),
              title: const Text('구글로 로그인하기', style: TextStyle(color: Colors.black)),
              onTap: _signInWithGoogle,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            const SizedBox(height: 16),
          ],
          const Text('계정', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('계정정보'),
            subtitle: Text(user?.email ?? '이메일 없음'),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          const SizedBox(height: 8),
          if (groupId == null) ...[
            const Text('그룹 설정', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ListTile(
              leading: const Icon(Icons.group_add, color: Colors.deepPurple),
              title: const Text('그룹 만들기', style: TextStyle(color: Colors.black)),
              onTap: () => _createGroup(context),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.group, color: Colors.deepPurple),
              title: const Text('그룹 참여하기', style: TextStyle(color: Colors.black)),
              onTap: () => _joinGroup(context),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            const SizedBox(height: 16),
          ] else ...[
            const Text('내 그룹', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ListTile(
              leading: const Icon(Icons.group),
              title: Text(groupName ?? '그룹 이름 없음'),
              subtitle: Text('그룹 코드: \${groupId ?? ''}'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              trailing: IconButton(
                icon: const Icon(Icons.share),
                onPressed: () {
                  if (groupId != null && groupPassword != null) {
                    Share.share('우리 그룹에 참여하세요! 그룹 이름: \${groupName ?? ''}, 코드: \$groupId, 비밀번호: \$groupPassword');
                  } else if (groupId != null) {
                    Share.share('우리 그룹에 참여하세요! 그룹 이름: \${groupName ?? ''}, 코드: \$groupId');
                  }
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('그룹 나가기'),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('그룹 나가기'),
                    content: const Text('정말로 이 그룹을 나가시겠습니까?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('나가기')),
                    ],
                  ),
                );
                if (confirm == true) {
                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid != null) {
                    await FirebaseFirestore.instance.collection('users').doc(uid).update({
                      'groupId': FieldValue.delete(),
                    });
                    setState(() {
                      groupId = null;
                      groupName = null;
                      groupPassword = null;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('그룹에서 나갔습니다')));
                  }
                }
              },
            ),
          ],
          const SizedBox(height: 24),
          const Text('내 여행 기록', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ListTile(
            leading: const Icon(Icons.map),
            title: const Text('내가 업로드한 여행 보기', style: TextStyle(color: Colors.black)),
            onTap: () => _showMyTripsDialog(context),
            trailing: const Icon(Icons.chevron_right),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          const SizedBox(height: 24),
          const Text('기타', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('앱 정보'),
            subtitle: const Text('버전 1.0.0'),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          ListTile(
            leading: const Icon(Icons.exit_to_app),
            title: const Text('로그아웃'),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('로그아웃 되었습니다')),
              );
              setState(() {});
            },
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ],
      ),
    );
  }
}
