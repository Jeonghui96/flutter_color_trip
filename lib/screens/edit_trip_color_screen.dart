import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:palette_generator/palette_generator.dart';

class EditTripColorScreen extends StatefulWidget {
  final String uid;
  final String tripId;

  const EditTripColorScreen({
    super.key,
    required this.uid,
    required this.tripId,
  });

  @override
  State<EditTripColorScreen> createState() => _EditTripColorScreenState();
}

class _EditTripColorScreenState extends State<EditTripColorScreen> {
  Map<String, dynamic>? _tripData;
  Color? _selectedColor;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTripData();
  }

  Future<void> _loadTripData() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('trips')
        .doc(widget.tripId)
        .get();

    if (doc.exists) {
      setState(() {
        _tripData = doc.data();
        if (_tripData!["color"] != null) {
          _selectedColor = Color(_tripData!["color"]);
        }
        _isLoading = false;
      });
    } else {
      Fluttertoast.showToast(msg: "여행 기록을 찾을 수 없습니다.");
      Navigator.pop(context);
    }
  }

  Future<void> _saveColor() async {
    if (_selectedColor == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .collection('trips')
          .doc(widget.tripId)
          .update({"color": _selectedColor!.value});

      Fluttertoast.showToast(msg: "색상이 성공적으로 변경되었습니다.");
      Navigator.pop(context, true);
    } catch (e) {
      Fluttertoast.showToast(msg: "저장 실패: $e");
    }
  }

  Widget _buildColorCircles(List<Color> colors) {
    return Wrap(
      spacing: 8,
      children: colors.map((color) {
        final isSelected = _selectedColor == color;
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedColor = color;
            });
          },
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.black : Colors.grey.shade300,
                width: isSelected ? 3 : 1,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _tripData == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final imageUrl = _tripData!["imageUrl"] ?? "";
    final sigungu = _tripData!["sigungu"] ?? "-";
    final place = _tripData!["place"] ?? "-";

    final defaultColors = [
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.blue,
      Colors.purple,
      Colors.pink,
      Colors.brown,
      Colors.grey,
      Colors.black,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("색상 다시 선택하기")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl.isNotEmpty)
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage(imageUrl),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text("지역: $sigungu", style: const TextStyle(fontSize: 16)),
            Text("장소: $place", style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            const Text("색상 선택:", style: TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            _buildColorCircles(defaultColors),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton(
                onPressed: _saveColor,
                child: const Text("저장하기"),
              ),
            )
          ],
        ),
      ),
    );
  }
}
