// lib/services/gemini_service.dart
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GeminiService {
  static final String? _apiKey = dotenv.env['GEMINI_API_KEY'];

  static Future<String> getRecommendation(
    String userPrompt, {
    List<String> visitedLocations = const [], // 현재 사용되지 않음
    bool excludeVisited = false, // 현재 사용되지 않음
    List<String> excludeLocations = const [], // <-- 새로 추가된 매개변수
  }) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('GEMINI_API_KEY is not set in .env file or is empty. Please check your .env file and pubspec.yaml assets.');
    }

    final model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _apiKey!,
      systemInstruction: Content.text(
        "당신은 한국인을 위한 친근하고 유용한 여행지 추천 전문가입니다. "
        "굵은 글씨나 별표, 마크다운 형식(예: #, *, -, `)을 사용하지 마세요. "
        "자연스럽고 따뜻한 한국어 문체로 답변해주세요. "
        "과장된 표현 없이도 장소의 매력을 상세하게 설명해주세요. "
        "답변 길이는 자유롭게 작성하세요."
        "여행장소 특별시 광역시 시도군 기타등등을 절때 강조하지마세요."
      ),
    );

    String fullPrompt = userPrompt;

    // excludeLocations가 비어있지 않으면 프롬프트에 추가합니다.
    if (excludeLocations.isNotEmpty) {
      fullPrompt += "\n\n이전에 추천했거나 언급된 다음 장소/맛집은 제외하고 새로운 곳을 추천해주세요: ${excludeLocations.join(', ')}";
    }

    try {
      final response = await model.generateContent([
        Content.text(fullPrompt),
      ]);
      return response.text ?? '추천 결과가 없습니다.';
    } on GenerativeAIException catch (e) {
      print("Gemini API Error: ${e.message}");
      return "AI 응답 생성 중 오류가 발생했습니다: ${e.message}";
    } catch (e) {
      print("Error generating content: $e");
      return "알 수 없는 오류로 AI 응답 생성에 실패했습니다: $e";
    }
  }
}