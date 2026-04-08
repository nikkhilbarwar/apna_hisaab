import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

enum CropMode { circle, square, portrait, landscape }

class IconCropScreen extends StatefulWidget {
  final File imageFile;
  final Color themeColor;
  final bool isCircle;

  const IconCropScreen({
    super.key, 
    required this.imageFile, 
    required this.themeColor,
    this.isCircle = true,
  });

  @override
  State<IconCropScreen> createState() => _IconCropScreenState();
}

class _IconCropScreenState extends State<IconCropScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _isProcessing = false;
  late CropMode _currentMode;

  @override
  void initState() {
    super.initState();
    _currentMode = widget.isCircle ? CropMode.circle : CropMode.square;
  }

  Future<void> _captureAndCrop() async {
    setState(() => _isProcessing = true);
    try {
      // 1. Pure viewer ka screenshot lo
      RenderRepaintBoundary? boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      ui.Image fullImage = await boundary.toImage(pixelRatio: 3.0);
      
      final size = boundary.size;
      final double pixelScale = fullImage.width / size.width;

      // 2. Box ki dimensions nikalon jo screen par dikh rahi hain
      double boxW, boxH;
      if (_currentMode == CropMode.landscape) {
        boxW = size.width * 0.9;
        boxH = boxW * (3/4);
      } else if (_currentMode == CropMode.portrait) {
        boxH = size.height * 0.7;
        boxW = boxH * (3/4);
        if (boxW > size.width * 0.9) {
          boxW = size.width * 0.9;
          boxH = boxW * (4/3);
        }
      } else {
        boxW = size.width * 0.85;
        boxH = boxW;
      }

      // 3. Crop coordinates (Center point se calculation)
      final double left = (size.width - boxW) / 2 * pixelScale;
      final double top = (size.height - boxH) / 2 * pixelScale;
      final double width = boxW * pixelScale;
      final double height = boxH * pixelScale;

      // 4. Sirf box wala area draw karo
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      canvas.drawImageRect(
        fullImage,
        Rect.fromLTWH(left, top, width, height),
        Rect.fromLTWH(0, 0, width, height),
        Paint(),
      );

      final img = await recorder.endRecording().toImage(width.toInt(), height.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final String fileName = 'cropped_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = await File('${tempDir.path}/$fileName').create();
      await file.writeAsBytes(bytes);

      if (mounted) Navigator.pop(context, file.path);
    } catch (e) {
      debugPrint("Crop Error: $e");
      if (mounted) Navigator.pop(context, widget.imageFile.path);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // RepaintBoundary ab InteractiveViewer ke upar hai taaki zoom capture ho sake
                  RepaintBoundary(
                    key: _boundaryKey,
                    child: Container(
                      color: Colors.black,
                      child: InteractiveViewer(
                        boundaryMargin: const EdgeInsets.all(double.infinity),
                        minScale: 0.1,
                        maxScale: 10.0,
                        child: Center(child: Image.file(widget.imageFile)),
                      ),
                    ),
                  ),
                  
                  // Overlay (Notch aur Box visualization)
                  _buildOverlay(),
                ],
              ),
            ),
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
          const Text("Crop Image", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          _isProcessing 
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : IconButton(
                icon: Icon(Icons.check, color: widget.themeColor, size: 28),
                onPressed: _captureAndCrop,
              ),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          double w, h;
          if (_currentMode == CropMode.landscape) {
            w = constraints.maxWidth * 0.9;
            h = w * (3/4);
          } else if (_currentMode == CropMode.portrait) {
            h = constraints.maxHeight * 0.7;
            w = h * (3/4);
            if (w > constraints.maxWidth * 0.9) {
              w = constraints.maxWidth * 0.9;
              h = w * (4/3);
            }
          } else {
            w = constraints.maxWidth * 0.85;
            h = w;
          }

          return Stack(
            children: [
              // Dark Background with Hole
              ColorFiltered(
                colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.7), BlendMode.srcOut),
                child: Stack(
                  children: [
                    Container(decoration: const BoxDecoration(color: Colors.black, backgroundBlendMode: BlendMode.dstOut)),
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        width: w, height: h,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: _currentMode == CropMode.circle ? BoxShape.circle : BoxShape.rectangle,
                          borderRadius: _currentMode == CropMode.circle ? null : BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Visible Border
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: w, height: h,
                  decoration: BoxDecoration(
                    border: Border.all(color: widget.themeColor.withOpacity(0.5), width: 2),
                    shape: _currentMode == CropMode.circle ? BoxShape.circle : BoxShape.rectangle,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      color: Colors.black,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _modeButton(CropMode.circle, Icons.circle_outlined, "Circle"),
              _modeButton(CropMode.square, Icons.crop_square, "1:1"),
              _modeButton(CropMode.portrait, Icons.crop_portrait, "3:4"),
              _modeButton(CropMode.landscape, Icons.crop_landscape, "4:3"),
            ],
          ),
          const SizedBox(height: 16),
          const Text("Drag & Zoom photo inside the box", style: TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _modeButton(CropMode mode, IconData icon, String label) {
    bool isSelected = _currentMode == mode;
    return InkWell(
      onTap: () => setState(() => _currentMode = mode),
      child: Column(
        children: [
          Icon(icon, color: isSelected ? widget.themeColor : Colors.white54, size: 24),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: isSelected ? widget.themeColor : Colors.white54, fontSize: 10)),
        ],
      ),
    );
  }
}
