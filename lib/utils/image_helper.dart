import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../screens/items/icon_crop_screen.dart';

class ImageHelper {
  static Future<String?> pickAndCropItemIcon({
    required BuildContext context,
    required Color themeColor,
    bool isCircle = true,
  }) async {
    final ImagePicker picker = ImagePicker();
    
    // 1. Pick Image
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );

    if (image == null) return null;

    // 2. Open Custom Crop Screen (Pure Flutter, handles Safe Area)
    if (!context.mounted) return image.path;
    
    final String? croppedPath = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IconCropScreen(
          imageFile: File(image.path), 
          themeColor: themeColor,
          isCircle: isCircle,
        ),
      ),
    );

    return croppedPath; // Sirf cropped path return karega, cancel hone par null aayega
  }
}
