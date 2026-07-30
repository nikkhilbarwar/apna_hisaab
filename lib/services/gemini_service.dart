import 'dart:convert';
import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/foundation.dart';

class GeminiService {
  static const String _apiKey = 'AIzaSy...'; // Put your hardcoded Gemini API key here

  /// Helper to extract JSON block from potentially messy AI response
  static String? _cleanJsonResponse(String text, {required bool isArray}) {
    try {
      final startChar = isArray ? '[' : '{';
      final endChar = isArray ? ']' : '}';
      
      int startIndex = text.indexOf(startChar);
      int endIndex = text.lastIndexOf(endChar);
      
      if (startIndex == -1 || endIndex == -1 || endIndex <= startIndex) {
        return null;
      }
      
      return text.substring(startIndex, endIndex + 1);
    } catch (e) {
      return null;
    }
  }
}
