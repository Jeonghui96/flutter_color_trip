import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:palette_generator/palette_generator.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final TextEditingController countryController = TextEditingController();
  final TextEditingController cityController = TextEditingController();
  final TextEditingController reviewController = TextEditingController();
  final TextEditingController colorController = TextEditingController();

  DateTime? selectedDate;
  File? _selectedImage;
  List<Color> extractedColors = [];

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final imageFile = File(picked.path);
      setState(() {
        _selectedImage = imageFile;
      });
      await _extractColors(imageFile);
    }
  }

  Future<void> _extractColors(File imageFile) async {
    final image = Image.file(imageFile);
    final palette = await PaletteGenerator.fromImageProvider(
      image.image,
      size: const Size(200, 200),
      maximumColorCount: 5,
    );

    setState(() {
      extractedColors = palette.colors.toList();
    });
  }

  Future<void> _pickDate() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (date != null) {
      setState(() {
        selectedDate = date;
      });
    }
  }

  Future<void> uploadTripData() async {
    if (_selectedImage == null ||
        countryController.text.isEmpty ||
        cityController.text.isEmpty ||
        selectedDate == null ||
        colorController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모든 필드를 입력하세요.')),
      );
      return;
    }

    try {
      final uid = "test_user_id"; // 실제 로그인 사용자 ID로 교체
      final tripId = const Uuid().v4();

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('users/$uid/trips/$tripId.jpg');
      await storageRef.putFile(_selectedImage!);
      final photoUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('trips')
          .doc(tripId)
          .set({
        'photo_url': photoUrl,
        'country': countryController.text.trim(),
        'city': cityController.text.trim(),
        'review': reviewController.text.trim(),
        'color': colorController.text.trim(),
        'date': selectedDate!.toIso8601String(),
        'tripId': tripId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('업로드 성공')),
      );
      countryController.clear();
      cityController.clear();
      reviewController.clear();
      colorController.clear();
      setState(() {
        selectedDate = null;
        _selectedImage = null;
        extractedColors = [];
      });
    } catch (e) {
      debugPrint('Error uploading: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('업로드 실패')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateText = selectedDate != null
        ? DateFormat('yyyy-MM-dd').format(selectedDate!)
        : '날짜 선택';

    return Scaffold(
      appBar: AppBar(title: const Text('여행 기록 업로드')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _selectedImage != null
                ? Image.file(_selectedImage!, height: 200)
                : const Placeholder(fallbackHeight: 200),
            ElevatedButton(onPressed: _pickImage, child: const Text('사진 선택')),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: extractedColors.map((color) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      colorController.text = color.value.toRadixString(16);
                    });
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      border: Border.all(width: 2, color: Colors.black),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            TextField(controller: countryController, decoration: const InputDecoration(labelText: '국가')),
            TextField(controller: cityController, decoration: const InputDecoration(labelText: '도시')),
            TextField(controller: reviewController, decoration: const InputDecoration(labelText: '리뷰')),
            TextField(controller: colorController, decoration: const InputDecoration(labelText: '선택한 색상(hex)')),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: _pickDate, child: Text(dateText)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: uploadTripData,
              child: const Text('업로드'),
            ),
          ],
        ),
      ),
    );
  }
}
