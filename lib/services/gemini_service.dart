import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/foundation.dart';

class GeminiService {
  // Hardcoded key removed for security and because it was unused
  static GenerativeModel? _model;

  static Future<void> init(String apiKey) async {
    _model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);
  }

  static Future<String?> generateResponse(String prompt) async {
    if (_model == null) return null;
    try {
      final content = [Content.text(prompt)];
      final response = await _model!.generateContent(content);
      return response.text;
    } catch (e) {
      debugPrint("Gemini Error: $e");
      return null;
    }
  }
}
