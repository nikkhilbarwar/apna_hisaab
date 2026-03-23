import 'package:flutter/services.dart';

class AppFormatter {
  /// Logic: Capitalize first letter of each word
  static String capitalizeEachWord(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  /// Formatter for TextFields to auto-capitalize each word while typing
  static final TextInputFormatter capitalizeWordsFormatter = 
      TextInputFormatter.withFunction((oldValue, newValue) {
    String newText = capitalizeEachWord(newValue.text);
    return newValue.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  });
}
