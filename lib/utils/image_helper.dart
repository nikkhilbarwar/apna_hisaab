import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../screens/items/icon_crop_screen.dart';

class ImageHelper {
  static Future<String?> pickAndCropItemIcon({
    required BuildContext context,
    required Color themeColor,
    bool isCircle = true,
  }) async {
    final ImagePicker picker = ImagePicker();
    
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );

    if (image == null) return null;

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

    if (croppedPath == null) return null;

    // Move from Temp to Permanent Directory
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'staff_${DateTime.now().millisecondsSinceEpoch}${path.extension(croppedPath)}';
      final savedImage = await File(croppedPath).copy('${appDir.path}/$fileName');
      return savedImage.path;
    } catch (e) {
      debugPrint("Error saving permanent image: $e");
      return croppedPath;
    }
  }
}
