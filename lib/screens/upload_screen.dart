import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:flutter_exif_rotation/flutter_exif_rotation.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:geocoding/geocoding.dart';

class UploadScreen extends StatefulWidget {
  final String uid;
  final String? groupId;

  const UploadScreen({super.key, required this.uid, this.groupId});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? _image;
  bool _isLoading = false;
  List<Color> _extractedColors = [];
  Color? _selectedColor;
  String? _selectedColorName;

  final _countryController = TextEditingController();
  final _cityController = TextEditingController();
  final _placeController = TextEditingController();
  final _memoController = TextEditingController();

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final rotatedImage = await FlutterExifRotation.rotateImage(path: pickedFile.path);
      final extracted = await _extractColorsFromImage(rotatedImage);
      setState(() {
        _image = rotatedImage;
        _extractedColors = extracted;
        _selectedColor = extracted.isNotEmpty ? extracted.first : null;
        _selectedColorName = _selectedColor != null ? getColorName(_selectedColor!) : null;
      });
    }
  }

  Future<List<Color>> _extractColorsFromImage(File imageFile) async {
    final image = Image.file(imageFile);
    final palette = await PaletteGenerator.fromImageProvider(
      image.image,
      size: const Size(200, 200),
      maximumColorCount: 5,
    );
    return palette.colors.take(5).toList();
  }

  Future<GeoPoint?> _getLatLngFromAddress(String country, String city, String place) async {
    try {
      final address = '$country $city $place';
      final locations = await locationFromAddress(address);
      if (locations.isEmpty) return null;
      final location = locations.first;
      return GeoPoint(location.latitude, location.longitude);
    } catch (e) {
      debugPrint('주소 좌표 변환 실패: $e');
      return null;
    }
  }

  Future<void> _upload() async {
    if (_image == null ||
        _countryController.text.isEmpty ||
        _cityController.text.isEmpty ||
        _placeController.text.isEmpty) return;

    setState(() => _isLoading = true);

    final geoPoint = await _getLatLngFromAddress(
      _countryController.text,
      _cityController.text,
      _placeController.text,
    );

    final fileName = path.basename(_image!.path);
    final ref = FirebaseStorage.instance.ref().child('uploads/${widget.uid}/$fileName');
    await ref.putFile(_image!);
    final downloadUrl = await ref.getDownloadURL();

    final docId = const Uuid().v4();
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('trips')
        .doc(docId)
        .set({
      'imageUrl': downloadUrl,
      'country': _countryController.text,
      'city': _cityController.text,
      'place': _placeController.text,
      'memo': _memoController.text,
      'color': _selectedColor?.value,
      'timestamp': Timestamp.now(),
      if (widget.groupId != null) 'groupId': widget.groupId,
      if (geoPoint != null) 'location': geoPoint,
    });

    setState(() => _isLoading = false);
    Navigator.pop(context);
  }

  Widget _buildColorCircles() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _extractedColors.map((color) {
        final isSelected = _selectedColor == color;
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedColor = color;
              _selectedColorName = getColorName(color);
            });
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
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

  String getColorName(Color color) {
    int r = color.red, g = color.green, b = color.blue;
    if (r > 180 && g < 100 && b < 100) return '빨간색';
    if (r > 200 && g > 180 && b < 100) return '주황색';
    if (r > 200 && g > 200 && b < 100) return '노란색';
    if (r < 100 && g > 180 && b < 100) return '초록색';
    if (r < 120 && g < 120 && b > 180) return '파란색';
    if (r > 150 && b > 150 && g < 100) return '자주색';
    if (r > 230 && g > 230 && b > 230) return '흰색';
    if (r < 60 && g < 60 && b < 60) return '검정색';
    return '기타';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('여행 기록 업로드')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(children: [
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              height: 200,
              width: double.infinity,
              color: Colors.grey[300],
              child: _image == null
                  ? const Center(child: Text('이미지를 선택하세요'))
                  : Image.file(_image!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 12),
          if (_extractedColors.isNotEmpty) _buildColorCircles(),
          if (_selectedColorName != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                '선택된 색상: $_selectedColorName',
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _countryController,
            decoration: const InputDecoration(labelText: '나라'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _cityController,
            decoration: const InputDecoration(labelText: '도시'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _placeController,
            decoration: const InputDecoration(labelText: '장소'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _memoController,
            decoration: const InputDecoration(labelText: '메모'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isLoading ? null : _upload,
            child: _isLoading ? const CircularProgressIndicator() : const Text('업로드'),
          )
        ]),
      ),
    );
  }
}
