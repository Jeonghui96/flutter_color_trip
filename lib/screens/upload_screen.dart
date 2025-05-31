import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle; // rootBundle 추가
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:flutter_exif_rotation/flutter_exif_rotation.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:geocoding/geocoding.dart';

class UploadScreen extends StatefulWidget {
  final String uid;
  final String? groupId;
  final VoidCallback? onUploadComplete;

  const UploadScreen({
    super.key,
    required this.uid,
    this.groupId,
    this.onUploadComplete,
  });

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? _image;
  bool _isLoading = false;
  List<Color> _extractedColors = [];
  Color? _selectedColor;
  String? _selectedColorName;

  // 기존 텍스트 컨트롤러는 장소, 메모만 남음
  final _placeController = TextEditingController();
  final _memoController = TextEditingController();

  // 드롭다운을 위한 변수
  String? _selectedSido; // 선택된 시/도
  String? _selectedSigungu; // 선택된 시/군/구

  // GeoJSON 데이터 파싱을 위한 맵
  List<String> _sidoNames = []; // 모든 시도 이름 리스트
  Map<String, List<String>> _sigunguNamesMap = {}; // 시도별 시군구 이름 맵
  Map<String, String> _sidoCodeMap = {}; // 시도 이름으로 코드 찾기 (시군구 필터링용)

  @override
  void initState() {
    super.initState();
    _loadGeoJsonData(); // GeoJSON 데이터 로드
  }

  // GeoJSON 파일을 로드하고 시도/시군구 목록을 파싱하는 함수
  Future<void> _loadGeoJsonData() async {
    try {
      // 1. 시도 GeoJSON 로드
      final sidoData = await rootBundle.loadString(
        'assets/geo/skorea_provinces_2018_geo.json',
      );
      final sidoGeoJson = json.decode(sidoData);
      List<String> tempSidoNames = [];
      Map<String, String> tempSidoCodeMap = {};

      for (var feature in sidoGeoJson['features']) {
        final props = feature['properties'];
        final name = props['name'] as String;
        final code = props['code'].toString(); // 시도 코드
        tempSidoNames.add(name);
        tempSidoCodeMap[name] = code;
      }

      // 2. 시군구 GeoJSON 로드 (세종시 포함)
      final sigunguData = await rootBundle.loadString(
        'assets/geo/skorea_municipalities_2018_geo.json',
      );
      final sigunguGeoJson = json.decode(sigunguData);
      Map<String, List<String>> tempSigunguNamesMap = {};

      // 세종시를 위해 별도로 로드
      final sejongData = await rootBundle.loadString('assets/geo/sejong.geojson');
      final sejongGeoJson = json.decode(sejongData);
      // 세종시는 "세종특별자치시" 하나의 이름으로 처리
      tempSigunguNamesMap['세종특별자치시'] = [(sejongGeoJson['features'][0]['properties']['name'] as String? ?? '세종특별자치시')];


      for (var feature in sigunguGeoJson['features']) {
        final props = feature['properties'];
        final name = props['name'] as String;
        final code = props['code'].toString();
        
        // 시도 코드 접두사를 이용하여 어떤 시도에 속하는 시군구인지 판단
        String? parentSidoName;
        for (var entry in tempSidoCodeMap.entries) {
          if (code.startsWith(entry.value)) {
            parentSidoName = entry.key;
            break;
          }
        }

        if (parentSidoName != null) {
          if (!tempSigunguNamesMap.containsKey(parentSidoName)) {
            tempSigunguNamesMap[parentSidoName] = [];
          }
          tempSigunguNamesMap[parentSidoName]!.add(name);
        }
      }

      // 시군구 목록 정렬 (선택 사항)
      tempSigunguNamesMap.forEach((key, value) {
        value.sort();
      });

      setState(() {
        _sidoNames = tempSidoNames..sort(); // 시도 이름 정렬
        _sigunguNamesMap = tempSigunguNamesMap;
        _sidoCodeMap = tempSidoCodeMap;
        _isLoading = false; // 데이터 로드 완료
      });
    } catch (e) {
      debugPrint('GeoJSON 데이터 로드 오류: $e');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지역 정보 로드에 실패했습니다. GeoJSON 파일이 올바른지 확인해주세요.')),
      );
    }
  }


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

  // GeoPoint는 선택된 시/도와 시/군/구를 기반으로 생성
  Future<GeoPoint?> _getLatLngFromAddress(String sido, String? sigungu, String place) async {
    try {
      String address = sido;
      if (sigungu != null && sigungu.isNotEmpty && sigungu != sido) { // 시군구가 시도와 같지 않을 때만 추가 (세종시 같은 경우)
        address += ' $sigungu';
      }
      address += ' $place'; // 장소 정보도 포함하여 더 정확한 좌표

      final locations = await locationFromAddress(address);
      if (locations.isEmpty) {
        // 시군구와 장소를 제외하고 시도만으로 다시 시도
        final sidoLocations = await locationFromAddress(sido);
        if(sidoLocations.isNotEmpty) return GeoPoint(sidoLocations.first.latitude, sidoLocations.first.longitude);
        return null;
      }
      final location = locations.first;
      return GeoPoint(location.latitude, location.longitude);
    } catch (e) {
      debugPrint('주소 좌표 변환 실패: $e');
      return null;
    }
  }

  Future<void> _upload() async {
    if (_image == null ||
        _selectedSido == null ||
        _placeController.text.isEmpty ||
        _selectedColor == null) { // 색상도 필수 조건에 추가
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미지, 지역, 장소, 색상을 모두 선택해주세요.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final geoPoint = await _getLatLngFromAddress(
      _selectedSido!,
      _selectedSigungu,
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
      'country': '대한민국', // 고정값으로 설정
      'city': _selectedSido!, // 시도 이름 저장
      'sigungu': _selectedSigungu, // 시군구 이름 저장
      'place': _placeController.text,
      'memo': _memoController.text,
      'color': _selectedColor?.value,
      'timestamp': Timestamp.now(),
      if (widget.groupId != null) 'groupId': widget.groupId,
      if (geoPoint != null) 'location': geoPoint,
    });

    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('여행 기록이 성공적으로 업로드되었습니다!')),
    );

    // 입력 필드 초기화 및 상태 초기화
    setState(() {
      _image = null;
      _selectedSido = null;
      _selectedSigungu = null;
      _placeController.clear();
      _memoController.clear();
      _extractedColors.clear();
      _selectedColor = null;
      _selectedColorName = null;
    });

    // 업로드 완료 콜백 함수 호출
    if (widget.onUploadComplete != null) {
      widget.onUploadComplete!();
    }
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
    if (_isLoading && _sidoNames.isEmpty) { // 초기 GeoJSON 로딩 중
      return Scaffold(
        appBar: AppBar(title: const Text('여행 기록 업로드')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

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

          // 시/도 선택 드롭다운
          DropdownButtonFormField<String>(
            value: _selectedSido,
            hint: const Text('지역 (시/도) 선택'),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: '지역 (시/도)',
            ),
            items: _sidoNames.map((String sido) {
              return DropdownMenuItem<String>(
                value: sido,
                child: Text(sido),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                _selectedSido = newValue;
                _selectedSigungu = null; // 시도가 바뀌면 시군구 초기화
              });
            },
          ),
          const SizedBox(height: 8),

          // 시/군/구 선택 드롭다운 (선택된 시도에 따라 필터링)
          DropdownButtonFormField<String>(
            value: _selectedSigungu,
            hint: const Text('세부 지역 (시/군/구) 선택'),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: '세부 지역 (시/군/구)',
            ),
            // 선택된 시도가 있을 때만 아이템을 보여줌
            items: _selectedSido != null
                ? (_sigunguNamesMap[_selectedSido!] ?? []).map((String sigungu) {
                    return DropdownMenuItem<String>(
                      value: sigungu,
                      child: Text(sigungu),
                    );
                  }).toList()
                : [], // 시도가 선택되지 않으면 빈 리스트
            onChanged: (String? newValue) {
              setState(() {
                _selectedSigungu = newValue;
              });
            },
            // 시도가 선택되지 않으면 비활성화
            isExpanded: true,
            menuMaxHeight: 300, // 드롭다운 메뉴 높이 제한
          ),
          const SizedBox(height: 8),

          TextField(
            controller: _placeController,
            decoration: const InputDecoration(labelText: '세부 장소 (선택 사항)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _memoController,
            decoration: const InputDecoration(labelText: '메모 (선택 사항)'),
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