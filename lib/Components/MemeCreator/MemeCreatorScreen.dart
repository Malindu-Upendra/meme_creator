import 'dart:io';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';
import 'package:screenshot/screenshot.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MemeEditorScreen extends StatefulWidget {
  const MemeEditorScreen({super.key});
  @override
  State<MemeEditorScreen> createState() => _MemeEditorScreenState();
}

class _MemeEditorScreenState extends State<MemeEditorScreen> {
  File? _baseImage;
  final _picker = ImagePicker();
  final ScreenshotController _screenshotController = ScreenshotController();

  final GlobalKey _editorKey = GlobalKey();

  List<_TextInfo> texts = [];
  List<_EmojiInfo> emojis = [];

  bool _isDrawing = false;
  List<Offset> drawingPoints = [];
  Color drawingColor = Colors.red;
  double drawingStroke = 4.0;

  Offset _gestureStartFocalLocal = Offset.zero;
  Offset _gestureStartOffset = Offset.zero;
  double _gestureStartScale = 1.0;
  double _gestureStartRotation = 0.0;
  int _gestureActiveIndex = -1;
  bool _gestureIsTextItem = true;

  bool _isUploading = false;

  final String cloudName = "dxcqu9b5s";
  final String uploadPreset = "meme_preset";

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 90);
    if (picked != null) {
      setState(() {
        _baseImage = File(picked.path);
      });
    }
  }

  void _addNewText() {
    setState(() {
      texts.add(
        _TextInfo(
          text: "New Text",
          color: Colors.white,
          fontSize: 28,
          fontFamily: 'Roboto',
          offset: const Offset(80, 80),
          scale: 1.0,
          rotation: 0.0,
        ),
      );
    });
  }

  void _addEmoji(String emoji) {
    setState(() {
      emojis.add(
        _EmojiInfo(
          emoji: emoji,
          offset: const Offset(120, 120),
          size: 48,
          scale: 1.0,
          rotation: 0.0,
        ),
      );
    });
  }

  void _startDrawing(DragStartDetails details) {
    if (!_isDrawing) return;
    final box = _editorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    setState(() => drawingPoints.add(local));
  }

  void _updateDrawing(DragUpdateDetails details) {
    if (!_isDrawing) return;
    final box = _editorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    setState(() => drawingPoints.add(local));
  }

  void _endDrawing(DragEndDetails details) {
    if (!_isDrawing) return;
    setState(() => drawingPoints.add(Offset.zero));
  }

  void _onScaleStart(ScaleStartDetails details, bool isText, int index) {
    final box = _editorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    _gestureStartFocalLocal = box.globalToLocal(details.focalPoint);
    _gestureActiveIndex = index;
    _gestureIsTextItem = isText;
    if (isText) {
      final item = texts[index];
      _gestureStartOffset = item.offset;
      _gestureStartScale = item.scale;
      _gestureStartRotation = item.rotation;
    } else {
      final item = emojis[index];
      _gestureStartOffset = item.offset;
      _gestureStartScale = item.scale;
      _gestureStartRotation = item.rotation;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_gestureActiveIndex == -1) return;
    final box = _editorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final focalLocal = box.globalToLocal(details.focalPoint);
    final delta = focalLocal - _gestureStartFocalLocal;

    if (_gestureIsTextItem) {
      final item = texts[_gestureActiveIndex];
      setState(() {
        item.offset = _gestureStartOffset + delta;
        item.scale = (_gestureStartScale * details.scale).clamp(0.3, 6.0);
        item.rotation = _gestureStartRotation + details.rotation;
      });
    } else {
      final item = emojis[_gestureActiveIndex];
      setState(() {
        item.offset = _gestureStartOffset + delta;
        item.scale = (_gestureStartScale * details.scale).clamp(0.3, 6.0);
        item.rotation = _gestureStartRotation + details.rotation;
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _gestureActiveIndex = -1;
  }

  void _editTextDialog(int index) {
    final textInfo = texts[index];
    final controller = TextEditingController(text: textInfo.text);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit text"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: controller),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text("Font size"),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    min: 8,
                    max: 72,
                    value: textInfo.fontSize,
                    onChanged: (v) => setState(() => textInfo.fontSize = v),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Text("Color"),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickTextColor(index);
                  },
                  child: Container(
                    width: 24,
                    height: 24,
                    color: textInfo.color,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => textInfo.text = controller.text);
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _pickTextColor(int index) {
    Color pick = texts[index].color;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Pick color"),
        content: BlockPicker(
          pickerColor: pick,
          onColorChanged: (color) => pick = color,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => texts[index].color = pick);
              Navigator.pop(c);
            },
            child: const Text("Set"),
          ),
        ],
      ),
    );
  }

  void _deleteTextAt(int index) {
    setState(() {
      if (index >= 0 && index < texts.length) texts.removeAt(index);
    });
  }

  void _deleteEmojiAt(int index) {
    setState(() {
      if (index >= 0 && index < emojis.length) emojis.removeAt(index);
    });
  }

  Future<bool> _hasInternetConnection() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity == ConnectivityResult.none) return false;

    // Extra verification for real connectivity
    try {
      final result = await Dio().get(
        'https://www.google.com',
        options: Options(
          receiveTimeout: const Duration(seconds: 3),
          sendTimeout: const Duration(seconds: 3),
        ),
      );
      return result.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _uploadMeme() async {
    setState(() => _isUploading = true);
    _showUploadingDialog();

    try {
      // Capture current meme as image bytes
      Uint8List? captured = await _screenshotController.captureFromWidget(
        RepaintBoundary(key: GlobalKey(), child: _buildEditorForCapture()),
        delay: const Duration(milliseconds: 100),
      );

      final dir = await getTemporaryDirectory();
      final filePath =
          '${dir.path}/meme_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(filePath)..writeAsBytesSync(captured);

      if (await _hasInternetConnection()) {
        // ✅ Upload to Cloudinary if connected
        final uploadUrl =
            "https://api.cloudinary.com/v1_1/$cloudName/image/upload";
        final formData = FormData.fromMap({
          "file": await MultipartFile.fromFile(file.path),
          "upload_preset": uploadPreset,
        });

        final response = await Dio().post(uploadUrl, data: formData);

        if (response.statusCode == 200) {
          final imageUrl = response.data["secure_url"];
          final user = FirebaseAuth.instance.currentUser;

          await FirebaseFirestore.instance.collection("posts").add({
            "imageUrl": imageUrl,
            "likes": 0,
            "timestamp": FieldValue.serverTimestamp(),
            "user": user?.email ?? "anonymous",
          });

          if (mounted) {
            _hideUploadingDialog();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("✅ Meme uploaded successfully!")),
            );
            Navigator.pop(context);
          }
        } else {
          throw Exception("Upload failed: ${response.statusMessage}");
        }
      } else {
        // 🚫 No internet — save locally as draft
        final appDir = await getApplicationDocumentsDirectory();
        final localPath =
            '${appDir.path}/offline_meme_${DateTime.now().millisecondsSinceEpoch}.png';
        await file.copy(localPath);

        // Save draft in Hive local box
        final box = await Hive.openBox('outbox');
        await box.add({
          'localPath': localPath,
          'text': texts.isNotEmpty ? texts.map((t) => t.text).join(' ') : '',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'uploaded': false,
          'isDraft': true,
        });

        _hideUploadingDialog();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "📦 Saved offline as draft — will upload when online",
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Upload error: $e");
      _hideUploadingDialog();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("❌ Upload failed: $e")));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  void _showUploadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                "Uploading Meme...",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _hideUploadingDialog() {
    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  Widget _buildEditorForCapture() {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        color: Colors.transparent,
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        child: Stack(
          children: [
            if (_baseImage != null)
              Positioned.fill(
                child: Image.file(_baseImage!, fit: BoxFit.contain),
              ),
            CustomPaint(
              painter: _DrawingPainterSimple(
                points: drawingPoints,
                color: drawingColor,
                stroke: drawingStroke,
              ),
            ),
            for (var t in texts)
              Positioned(
                left: t.offset.dx,
                top: t.offset.dy,
                child: Transform(
                  transform: Matrix4.identity()
                    ..scale(t.scale)
                    ..rotateZ(t.rotation),
                  alignment: Alignment.center,
                  child: Text(
                    t.text,
                    style: GoogleFonts.getFont(
                      t.fontFamily,
                      fontSize: t.fontSize,
                      color: t.color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            for (var e in emojis)
              Positioned(
                left: e.offset.dx,
                top: e.offset.dy,
                child: Transform(
                  transform: Matrix4.identity()
                    ..scale(e.scale)
                    ..rotateZ(e.rotation),
                  alignment: Alignment.center,
                  child: Text(e.emoji, style: TextStyle(fontSize: e.size)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Meme Editor")),
      body: Column(
        children: [
          Expanded(
            child: _baseImage == null
                ? const Center(child: Text("Pick an image"))
                : Screenshot(
                    controller: _screenshotController,
                    child: Container(
                      key: _editorKey,
                      color: Colors.black,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: FittedBox(
                              fit: BoxFit.contain,
                              alignment: Alignment.center,
                              child: Image.file(_baseImage!),
                            ),
                          ),

                          if (_isDrawing)
                            Positioned.fill(
                              child: GestureDetector(
                                onPanStart: _startDrawing,
                                onPanUpdate: _updateDrawing,
                                onPanEnd: _endDrawing,
                                child: CustomPaint(
                                  painter: _DrawingPainterSimple(
                                    points: drawingPoints,
                                    color: drawingColor,
                                    stroke: drawingStroke,
                                  ),
                                ),
                              ),
                            )
                          else
                            Positioned.fill(
                              child: IgnorePointer(
                                ignoring: true,
                                child: CustomPaint(
                                  painter: _DrawingPainterSimple(
                                    points: drawingPoints,
                                    color: drawingColor,
                                    stroke: drawingStroke,
                                  ),
                                ),
                              ),
                            ),

                          for (int i = 0; i < texts.length; i++)
                            _buildTextSticker(i),

                          for (int i = 0; i < emojis.length; i++)
                            _buildEmojiSticker(i),
                        ],
                      ),
                    ),
                  ),
          ),

          if (_baseImage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isUploading ? null : _addNewText,
                    icon: const Icon(Icons.text_fields),
                    label: const Text("Text"),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (texts.isEmpty) {
                        _addNewText();
                      }
                      if (texts.isNotEmpty) {
                        final idx = texts.length - 1;
                        _pickTextColor(idx);
                      }
                    },
                    icon: const Icon(Icons.color_lens),
                    label: const Text("Color"),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _isUploading
                        ? null
                        : setState(() => _isDrawing = !_isDrawing),
                    icon: const Icon(Icons.brush),
                    label: Text(_isDrawing ? "Stop Draw" : "Draw"),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      _isUploading
                          ? null
                          : showModalBottomSheet(
                              context: context,
                              builder: (_) => EmojiPicker(
                                onEmojiSelected: (cat, emoji) {
                                  Navigator.pop(context);
                                  _addEmoji(emoji.emoji);
                                },
                              ),
                            );
                    },
                    icon: const Icon(Icons.emoji_emotions),
                    label: const Text("Emoji"),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isUploading ? null : _uploadMeme,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text("Upload"),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: () =>
                    _isUploading ? null : _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text("Camera"),
              ),
              ElevatedButton.icon(
                onPressed: () =>
                    _isUploading ? null : _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text("Gallery"),
              ),
            ],
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildTextSticker(int i) {
    final t = texts[i];
    return Positioned(
      left: t.offset.dx,
      top: t.offset.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onScaleStart: (details) => _onScaleStart(details, true, i),
        onScaleUpdate: (details) => _onScaleUpdate(details),
        onScaleEnd: (details) => _onScaleEnd(details),
        onDoubleTap: () => _editTextDialog(i),
        onLongPress: () => _deleteTextAt(i),
        child: Transform(
          transform: Matrix4.identity()
            ..scale(t.scale)
            ..rotateZ(t.rotation),
          alignment: Alignment.center,
          child: Container(
            color: Colors.transparent,
            child: Text(
              t.text,
              style: GoogleFonts.getFont(
                t.fontFamily,
                fontSize: t.fontSize,
                color: t.color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmojiSticker(int i) {
    final e = emojis[i];
    return Positioned(
      left: e.offset.dx,
      top: e.offset.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onScaleStart: (details) => _onScaleStart(details, false, i),
        onScaleUpdate: (details) => _onScaleUpdate(details),
        onScaleEnd: (details) => _onScaleEnd(details),
        onDoubleTap: () => _deleteEmojiAt(i),
        child: Transform(
          transform: Matrix4.identity()
            ..scale(e.scale)
            ..rotateZ(e.rotation),
          alignment: Alignment.center,
          child: Container(
            color: Colors.transparent,
            child: Text(e.emoji, style: TextStyle(fontSize: e.size)),
          ),
        ),
      ),
    );
  }
}

class _TextInfo {
  String text;
  Color color;
  double fontSize;
  String fontFamily;
  Offset offset;
  double scale;
  double rotation;

  _TextInfo({
    required this.text,
    required this.color,
    required this.fontSize,
    required this.fontFamily,
    required this.offset,
    required this.scale,
    required this.rotation,
  });
}

class _EmojiInfo {
  String emoji;
  Offset offset;
  double size;
  double scale;
  double rotation;

  _EmojiInfo({
    required this.emoji,
    required this.offset,
    required this.size,
    required this.scale,
    required this.rotation,
  });
}

class _DrawingPainterSimple extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final double stroke;
  _DrawingPainterSimple({
    required this.points,
    required this.color,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] == Offset.zero || points[i + 1] == Offset.zero) continue;
      canvas.drawLine(points[i], points[i + 1], paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingPainterSimple oldDelegate) => true;
}
