import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
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

  final _placeController = TextEditingController();
  final _memoController = TextEditingController();

  String? _selectedSido; // 선택된 시/도
  String? _selectedSigungu; // 선택된 시/군/구

  List<String> _sidoNames = []; // 모든 시도 이름 리스트
  Map<String, List<String>> _sigunguNamesMap = {}; // 시도별 시군구 이름 맵
  Map<String, String> _sidoCodeMap = {}; // 시도 이름으로 코드 찾기 (시군구 필터링용)

  @override
  void initState() {
    super.initState();
    _loadGeoJsonData(); // GeoJSON 데이터 로드
  }

  @override
  void dispose() {
    _placeController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  // GeoJSON 파일을 로드하고 시도/시군구 목록을 파싱하는 함수
  Future<void> _loadGeoJsonData() async {
    try {
      setState(() {
        _isLoading = true; // 데이터 로드 시작
      });

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

      // 2. 시군구 GeoJSON 로드 (세종시 외 일반 시군구)
      final sigunguData = await rootBundle.loadString(
        'assets/geo/skorea_municipalities_2018_geo.json', // .json 확장자 수정됨
      );
      final sigunguGeoJson = json.decode(sigunguData);
      Map<String, List<String>> tempSigunguNamesMap = {};

      for (var feature in sigunguGeoJson['features']) {
        final props = feature['properties'];
        final name = props['name'] as String; // 시군구 이름 (예: "동구", "수원시")
        final code = props['code'].toString();

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

      // 3. 세종특별자치시 GeoJSON 로드 및 읍면동 추가
      try {
        final sejongData = await rootBundle.loadString('assets/geo/sejong.geojson');
        final sejongGeoJson = json.decode(sejongData);
        List<String> sejongSubRegions = [];
        for (var feature in sejongGeoJson['features']) {
          final props = feature['properties'];
          final String subRegionName = props['adm_nm'] as String? ?? props['name'] as String? ?? '알 수 없는 세종 읍면동';
          sejongSubRegions.add(subRegionName);
        }
        tempSigunguNamesMap['세종특별자치시'] = sejongSubRegions;
      } catch (e) {
        debugPrint("세종 GeoJSON 로드 중 오류 발생: $e");
      }

      // --- **추가된 로직: 각 시/도 이름을 시/군/구 목록의 맨 앞에 포함** ---
      tempSidoNames.forEach((sidoName) {
        if (!tempSigunguNamesMap.containsKey(sidoName)) {
          tempSigunguNamesMap[sidoName] = [];
        }
        // 각 시/도 목록의 맨 앞에 해당 시/도 이름을 추가 (중복 방지)
        if (!tempSigunguNamesMap[sidoName]!.contains(sidoName)) {
            tempSigunguNamesMap[sidoName]!.insert(0, sidoName);
        }
      });
      // --- **추가된 로직 끝** ---

      // 시군구 목록 정렬 (선택 사항)
      tempSigunguNamesMap.forEach((key, value) {
        // 시도 이름이 맨 앞에 이미 추가되어 있으므로, 나머지 시군구만 정렬
        if (value.length > 1) {
          final sidoName = value[0]; // 시도 이름은 그대로 유지
          final subList = value.sublist(1)..sort(); // 나머지 시군구만 정렬
          value
            ..clear()
            ..add(sidoName)
            ..addAll(subList);
        }
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

  // GeoPoint는 선택된 시/도, 시/군/구, 장소 정보를 기반으로 생성
  Future<GeoPoint?> _getLatLngFromAddress(String sido, String? sigungu, String place) async {
    try {
      String address = sido;
      if (sigungu != null && sigungu.isNotEmpty) {
        address += ' $sigungu';
      }
      if (place.isNotEmpty) {
        address += ' $place';
      }

      final locations = await locationFromAddress(address);
      if (locations.isEmpty) {
        final sidoLocations = await locationFromAddress(sido);
        if (sidoLocations.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('세부 주소로는 위치를 찾을 수 없어 "$sido"의 중심 좌표로 저장됩니다.')),
          );
          return GeoPoint(sidoLocations.first.latitude, sidoLocations.first.longitude);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('주소를 기반으로 한 위치를 찾을 수 없습니다.')),
        );
        return null;
      }
final location = locations.first;
return GeoPoint(location.latitude, location.longitude); // ✅ 수정 완료

    } catch (e) {
      debugPrint('주소 좌표 변환 실패: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('주소 좌표 변환 중 오류 발생: ${e.toString()}')),
      );
      return null;
    }
  }

  Future<void> _upload() async {
    if (_image == null ||
        _selectedSido == null ||
        _placeController.text.isEmpty ||
        _selectedColor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미지, 지역 (시/도), 장소, 색상을 모두 선택해주세요.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final geoPoint = await _getLatLngFromAddress(
      _selectedSido!,
      _selectedSigungu, // 드롭다운으로 선택된 세부 지역 값
      _placeController.text,
    );

    final fileName = path.basename(_image!.path);
    final ref = FirebaseStorage.instance.ref().child('uploads/${widget.uid}/$fileName');
    try {
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
        'country': '대한민국',
        'city': _selectedSido!, // 시/도 이름 저장 (전국 지도 색칠에 사용)
        'sigungu': _selectedSigungu, // 드롭다운으로 선택된 세부 지역 이름 저장
        'place': _placeController.text,
        'memo': _memoController.text,
        'color': _selectedColor?.value,
        'timestamp': Timestamp.now(),
        if (widget.groupId != null) 'groupId': widget.groupId,
        if (geoPoint != null) 'location': geoPoint,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('여행 기록이 성공적으로 업로드되었습니다!')),
      );

      _resetForm();
      if (widget.onUploadComplete != null) {
        widget.onUploadComplete!();
      }
    } catch (e) {
      debugPrint('업로드 실패: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('업로드에 실패했습니다: ${e.toString()}')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _resetForm() {
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
    double brightness = (0.2126 * r + 0.7152 * g + 0.0722 * b);
    double maxVal = [r, g, b].reduce((a, b) => a > b ? a : b).toDouble();
    double minVal = [r, g, b].reduce((a, b) => a < b ? a : b).toDouble();
    double saturation = (maxVal - minVal) / maxVal;
    if (maxVal == 0) saturation = 0;

    if (brightness > 220 && saturation < 0.2) return '흰색';
    if (brightness < 30) return '검정색';
    if (saturation < 0.2) return '회색';

    if (r > g && r > b) {
      if (g > b) return '주황색';
      return '빨간색';
    }
    if (g > r && g > b) {
      if (r > b) return '연두색';
      return '초록색';
    }
    if (b > r && b > g) {
      if (r > g) return '보라색';
      return '파란색';
    }
    
    if (r > 200 && g > 200 && b < 100) return '노란색';
    if (r > 150 && b > 150) return '자주색';

    return '기타';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _sidoNames.isEmpty) {
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

          // 시/도 선택 드롭다운 (필수)
          DropdownButtonFormField<String>(
            value: _selectedSido,
            hint: const Text('지역 (시/도) 선택 *'),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: '지역 (시/도) *',
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
                _selectedSigungu = null; // 시도가 바뀌면 세부 지역 초기화
              });
            },
          ),
          const SizedBox(height: 8),

          // 세부 지역 드롭다운 (선택된 시도에 따라 필터링, 시도 이름 포함)
DropdownButtonFormField<String>(
  value: _selectedSigungu,
  hint: const Text('세부 지역 (시/군/구/읍/면/동) 선택'),
  decoration: const InputDecoration(
    border: OutlineInputBorder(),
    labelText: '세부 지역 (시/군/구/읍/면/동)',
  ),
  items: _selectedSido != null
      ? (_sigunguNamesMap[_selectedSido!] ?? []).map((String sigungu) {
          return DropdownMenuItem<String>(
            value: sigungu,
            child: Text(sigungu),
          );
        }).toList()
      : [],
  onChanged: _selectedSido != null
      ? (String? newValue) {
          setState(() {
            _selectedSigungu = newValue;
          });
        }
      : null, // 시도가 선택되지 않으면 비활성화
  isExpanded: true,
  menuMaxHeight: 300,
),

          const SizedBox(height: 8),

          TextField(
            controller: _placeController,
            decoration: const InputDecoration(labelText: '세부 장소 (예: 특정 건물, 공원 이름) *'),
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