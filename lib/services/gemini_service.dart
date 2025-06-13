import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GeminiService {
  static final String? _apiKey = dotenv.env['GEMINI_API_KEY'];

  static Future<String> getRecommendation(
    String userPrompt, {
    List<String> visitedLocations = const [],
    bool excludeVisited = false,
  }) async {
    if (_apiKey == null) {
      throw Exception('GEMINI_API_KEY is not set in .env file');
    }

    final model = GenerativeModel(
      model: 'gemini-2.0-flash',
      apiKey: _apiKey!,
      systemInstruction: Content.text(
        "당신은 한국인을 위한 친근하고 유용한 여행지 추천 전문가입니다. "
        "굵은 글씨나 별표, 마크다운 형식을 사용하지 마세요. "
        "자연스럽고 따뜻한 한국어 문체로 답변해주세요. "
        "과장된 표현 없이도 장소의 매력을 상세하게 설명해주세요. "
        "답변 길이는 자유롭게 작성하세요."
        "여행장소 특별시 광역시 시도군 기타등등을 절때 강조하지마세요."
      ),
    );

    String fullPrompt = "사용자의 여행 스타일: $userPrompt";
    if (excludeVisited && visitedLocations.isNotEmpty) {
      fullPrompt += "\\n제외할 지역: ${visitedLocations.join(', ')}";
    }

    final response = await model.generateContent([
      Content.text(fullPrompt),
    ]);

    return response.text ?? '추천 결과가 없습니다.';
  }
}
