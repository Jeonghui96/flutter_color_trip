import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart'; // Clipboard 사용을 위해 import
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'my_trips_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? groupName;
  String? groupId;
  String? groupPassword;
  String? groupOwnerId; // 그룹장 UID
  List<Map<String, String>> groupMembersWithId = []; // 그룹 멤버 목록 (UID 포함)
  String? _nickname;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      debugPrint("로그인 유지됨: ${user.email ?? user.uid}");
    } else {
      debugPrint("로그인되어 있지 않음");
    }
    _loadUserInfoAndGroupInfo();
  }

  Future<void> _loadUserInfoAndGroupInfo() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _nickname = null;
        groupId = null;
        groupName = null;
        groupPassword = null;
        groupOwnerId = null;
        groupMembersWithId.clear();
      });
      return;
    }

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final userData = userDoc.data();
    
    setState(() {
      _nickname = userData?['nickname'] as String?;
    });

    final gid = userData?['groupId'] as String?;

    if (gid == null) {
      setState(() {
        groupId = null;
        groupName = null;
        groupPassword = null;
        groupOwnerId = null;
        groupMembersWithId.clear();
      });
      return;
    }

    final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(gid).get();
    final groupData = groupDoc.data();

    // 그룹 멤버 정보 불러오기 (UID와 닉네임/이메일 함께 저장)
    List<Map<String, String>> currentMembersWithId = [];
    final usersInGroup = await FirebaseFirestore.instance.collection('users')
        .where('groupId', isEqualTo: gid)
        .get();
    for (var memberUserDoc in usersInGroup.docs) {
      final memberUserData = memberUserDoc.data();
      String memberDisplayName = memberUserData['nickname'] as String? ?? memberUserData['email'] as String? ?? memberUserDoc.id;
      
      if (memberDisplayName.isNotEmpty) {
        currentMembersWithId.add({
          'uid': memberUserDoc.id,
          'displayName': memberDisplayName,
        });
      }
    }

    setState(() {
      groupId = gid;
      groupName = groupData?['name'] as String?;
      groupPassword = groupData?['password'] as String?;
      groupOwnerId = groupData?['ownerId'] as String?;
      groupMembersWithId = currentMembersWithId;
    });
  }

  Future<void> _createGroup(BuildContext context) async {
    if (groupId != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이미 그룹에 가입되어 있어요')));
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final userEmail = FirebaseAuth.instance.currentUser?.email;
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
                'ownerId': uid,
              });
              await FirebaseFirestore.instance.collection('users').doc(uid).set(
                {'groupId': gid, 'email': userEmail ?? 'unknown'},
                SetOptions(merge: true),
              );
              
              String currentMemberDisplayName = _nickname ?? userEmail ?? uid;
              List<Map<String, String>> newGroupMembersWithId = [];
              if (currentMemberDisplayName.isNotEmpty) {
                newGroupMembersWithId.add({
                  'uid': uid,
                  'displayName': currentMemberDisplayName,
                });
              }

              setState(() {
                groupId = gid;
                groupName = name;
                groupPassword = password;
                groupOwnerId = uid;
                groupMembersWithId = newGroupMembersWithId;
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('그룹 생성 완료! 코드: $gid')));
            },
            child: const Text('생성'),
          ),
        ],
      ),
    );
  }

  Future<void> _joinGroup(BuildContext context) async {
    if (groupId != null) { // 이미 그룹에 가입되어 있다면 리턴
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이미 그룹에 가입되어 있어요')));
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final userEmail = FirebaseAuth.instance.currentUser?.email;
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
              await FirebaseFirestore.instance.collection('users').doc(uid).set(
                {'groupId': code, 'email': userEmail ?? 'unknown'},
                SetOptions(merge: true),
              );
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('그룹에 참여하였습니다')));
              _loadUserInfoAndGroupInfo();
            },
            child: const Text('참여'),
          ),
        ],
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
      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null && user.email != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {'email': user.email},
          SetOptions(merge: true),
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('구글 로그인 완료')));
      _loadUserInfoAndGroupInfo();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('로그인 실패: $e')));
    }
  }

  Future<void> _setNickname(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final nicknameController = TextEditingController(text: _nickname);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('닉네임 설정'),
        content: TextField(
          controller: nicknameController,
          decoration: const InputDecoration(labelText: '새 닉네임'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(
            onPressed: () async {
              final newNickname = nicknameController.text.trim();
              if (newNickname.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('닉네임을 입력해주세요.')));
                return;
              }
              await FirebaseFirestore.instance.collection('users').doc(uid).set(
                {'nickname': newNickname},
                SetOptions(merge: true),
              );
              setState(() {
                _nickname = newNickname;
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('닉네임이 설정되었습니다.')));
              _loadUserInfoAndGroupInfo();
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  Future<void> _exitGroup() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || groupId == null) return;

    final isOwner = (uid == groupOwnerId);

    String confirmMessage = '정말로 이 그룹을 나가시겠습니까?';
    if (isOwner) {
      confirmMessage = '그룹장님이 나가시면 그룹이 영구적으로 삭제됩니다. 계속하시겠습니까?';
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('그룹 나가기'),
        content: Text(confirmMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isOwner ? '그룹 삭제 및 나가기' : '나가기'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (isOwner) {
        try {
          final usersInGroupSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .where('groupId', isEqualTo: groupId)
              .get();

          final batch = FirebaseFirestore.instance.batch();
          for (var doc in usersInGroupSnapshot.docs) {
            batch.update(doc.reference, {'groupId': FieldValue.delete()});
          }
          await batch.commit();

          await FirebaseFirestore.instance.collection('groups').doc(groupId).delete();

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('그룹장으로 그룹을 삭제하고 나갔습니다.')),
          );
        } catch (e) {
          print('그룹 삭제 중 오류 발생: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('그룹 삭제 중 오류 발생: $e')),
          );
        }
      } else {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'groupId': FieldValue.delete(),
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('그룹에서 나갔습니다.')),
        );
      }

      setState(() {
        groupId = null;
        groupName = null;
        groupPassword = null;
        groupOwnerId = null;
        groupMembersWithId.clear();
      });
    }
  }

  // 그룹 멤버 강퇴 로직 (그룹장만 가능)
  Future<void> _kickMember(String memberUid, String memberDisplayName) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || groupId == null || uid != groupOwnerId) { // 그룹장이 아니면 강퇴 불가
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('그룹장만 멤버를 강퇴할 수 있습니다.')));
      return;
    }
    if (memberUid == uid) { // 그룹장 본인은 강퇴할 수 없음
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('자기 자신을 강퇴할 수 없습니다. 그룹을 나가려면 그룹 나가기 버튼을 이용해주세요.')));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('멤버 강퇴'),
        content: Text('$memberDisplayName 님을 그룹에서 강퇴하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('강퇴', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(memberUid).update({
          'groupId': FieldValue.delete(), // 해당 멤버의 groupId 필드 삭제
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$memberDisplayName 님이 그룹에서 강퇴되었습니다.')),
        );
        _loadUserInfoAndGroupInfo(); // 변경된 그룹 멤버 목록 다시 불러오기
      } catch (e) {
        print('멤버 강퇴 중 오류 발생: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('멤버 강퇴 중 오류 발생: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final String? currentUid = user?.uid;

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
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('닉네임 설정'),
            subtitle: Text(_nickname ?? '닉네임을 설정해주세요'),
            onTap: user != null ? () => _setNickname(context) : null,
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
            Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            groupName ?? '그룹 이름 없음',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.share, color: Colors.deepPurple),
                          onPressed: () {
                            if (groupId != null && groupPassword != null) {
                              Share.share('우리 그룹에 참여하세요!\n그룹 이름: ${groupName ?? ''}\n코드: $groupId\n비밀번호: $groupPassword');
                            } else if (groupId != null) {
                              Share.share('우리 그룹에 참여하세요!\n그룹 이름: ${groupName ?? ''}\n코드: $groupId');
                            }
                          },
                        ),
                      ],
                    ),
                    // 그룹장 표시 (카드 내부에 명확히)
                    if (groupOwnerId != null && currentUid == groupOwnerId)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                        child: Text(
                          '👑 당신은 그룹장입니다!',
                          style: TextStyle(fontSize: 14, color: Colors.deepPurple.shade700, fontWeight: FontWeight.bold),
                        ),
                      )
                    else if (groupOwnerId != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                        child: FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance.collection('users').doc(groupOwnerId).get(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Text('그룹장: 로딩 중...', style: TextStyle(fontSize: 14, color: Colors.grey));
                            }
                            if (snapshot.hasError) {
                              return const Text('그룹장 정보 로드 오류', style: TextStyle(fontSize: 14, color: Colors.red));
                            }
                            if (snapshot.hasData && snapshot.data!.exists) {
                              final ownerData = snapshot.data!.data() as Map<String, dynamic>;
                              final ownerDisplayName = ownerData['nickname'] as String? ?? ownerData['email'] as String? ?? '알 수 없음';
                              return Text(
                                '그룹장: $ownerDisplayName',
                                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                              );
                            }
                            return const Text('그룹장: 알 수 없음', style: TextStyle(fontSize: 14, color: Colors.grey));
                          },
                        ),
                      ),
                    
                    // ✅ GestureDetector로 감싸서 터치 시 복사 기능 추가
                    GestureDetector(
                      onTap: () {
                        if (groupId != null && groupPassword != null) {
                          final textToCopy = '그룹 코드: $groupId\n비밀번호: $groupPassword';
                          Clipboard.setData(ClipboardData(text: textToCopy));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('그룹 코드와 비밀번호가 복사되었습니다.')),
                          );
                        } else if (groupId != null) {
                          final textToCopy = '그룹 코드: $groupId';
                          Clipboard.setData(ClipboardData(text: textToCopy));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('그룹 코드가 복사되었습니다.')),
                          );
                        }
                      },
                      child: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: '코드: ', style: TextStyle(fontWeight: FontWeight.bold)),
                            TextSpan(text: '${groupId ?? ''}'),
                            const TextSpan(text: '   비밀번호: ', style: TextStyle(fontWeight: FontWeight.bold)),
                            TextSpan(text: '${groupPassword ?? ''}'),
                          ],
                        ),
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                    ),
                    const Divider(height: 24),
                    const Text('그룹 멤버:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      children: groupMembersWithId.isEmpty
                          ? [const Text('멤버 없음', style: TextStyle(color: Colors.grey))]
                          : groupMembersWithId.map((member) {
                              final memberUid = member['uid'];
                              final displayName = member['displayName'] ?? '';
                              final isCurrentMemberOwner = (memberUid == groupOwnerId);
                              
                              // ✅ GestureDetector로 감싸서 터치 시 강퇴 기능 추가
                              return GestureDetector(
                                onTap: () {
                                  // 자신을 강퇴하지 못하도록, 그룹장이 아니면 강퇴 버튼을 누르지 못하도록
                                  if (currentUid == groupOwnerId && memberUid != currentUid) {
                                    _kickMember(memberUid!, displayName);
                                  } else if (memberUid == currentUid) {
                                     // 자기 자신을 터치했을 때 메시지 (선택 사항)
                                     ScaffoldMessenger.of(context).showSnackBar(
                                       const SnackBar(content: Text('자기 자신을 강퇴할 수 없습니다. 그룹 나가기는 아래 버튼을 이용하세요.')),
                                     );
                                  } else {
                                     ScaffoldMessenger.of(context).showSnackBar(
                                       const SnackBar(content: Text('그룹장만 멤버를 강퇴할 수 있습니다.')),
                                     );
                                  }
                                },
                                child: Chip(
                                  label: Text(isCurrentMemberOwner ? '👑 $displayName' : displayName),
                                  backgroundColor: Colors.deepPurple.shade50,
                                  labelStyle: TextStyle(
                                    color: isCurrentMemberOwner ? Colors.deepPurple.shade900 : Colors.deepPurple.shade800,
                                    fontWeight: isCurrentMemberOwner ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 13,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              );
                            }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.exit_to_app, color: currentUid == groupOwnerId ? Colors.red : Colors.orange),
              title: Text(currentUid == groupOwnerId ? '그룹 삭제 및 나가기' : '그룹 나가기', style: TextStyle(color: Colors.black)),
              onTap: _exitGroup,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ],
          const SizedBox(height: 24),
          const Text('내 여행 기록', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ListTile(
            leading: const Icon(Icons.map),
            title: const Text('내가 업로드한 여행 보기', style: TextStyle(color: Colors.black)),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MyTripsScreen()),
              );
            },
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
              setState(() {
                _nickname = null;
                groupId = null;
                groupName = null;
                groupPassword = null;
                groupOwnerId = null;
                groupMembersWithId.clear();
              });
            },
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ],
      ),
    );
  }
}