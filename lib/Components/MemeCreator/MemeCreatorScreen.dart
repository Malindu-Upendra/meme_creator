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
import 'package:image_cropper/image_cropper.dart';

class MemeEditorScreen extends StatefulWidget {
  const MemeEditorScreen({super.key});
  @override
  State<MemeEditorScreen> createState() => _MemeEditorScreenState();
}

class _MemeEditorScreenState extends State<MemeEditorScreen>
    with TickerProviderStateMixin {
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

  late AnimationController _toolbarController;

  final String cloudName = "dxcqu9b5s";
  final String uploadPreset = "meme_preset";

  @override
  void initState() {
    super.initState();
    _toolbarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _toolbarController.forward();
  }

  @override
  void dispose() {
    _toolbarController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 90);

    if (picked != null) {
      final croppedImage = await _cropImage(File(picked.path));

      if (croppedImage != null) {
        setState(() {
          _baseImage = croppedImage;
          texts.clear();
          emojis.clear();
          drawingPoints.clear();
        });
      }
    }
  }

  Future<File?> _cropImage(File imageFile) async {
    final androidColor = const Color(0xFFF59E0B);

    CroppedFile? croppedFile = await ImageCropper().cropImage(
      sourcePath: imageFile.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Your Meme',
          toolbarColor: androidColor,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
        IOSUiSettings(
          title: 'Crop Your Meme',
          doneButtonTitle: 'Done',
          cancelButtonTitle: 'Cancel',
          minimumAspectRatio: 1.0,
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
      ],
    );

    if (croppedFile != null) {
      return File(croppedFile.path);
    }
    return null;
  }

  Future<void> _triggerCrop() async {
    if (_baseImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select an image first.")),
      );
      return;
    }

    final croppedImage = await _cropImage(_baseImage!);

    if (croppedImage != null) {
      setState(() {
        _baseImage = croppedImage;

        texts.clear();
        emojis.clear();
        drawingPoints.clear();
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Edit Text",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Enter text',
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.format_size, color: Color(0xFF6366F1)),
                const SizedBox(width: 12),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF6366F1),
                      inactiveTrackColor: Colors.grey.shade300,
                      thumbColor: const Color(0xFF6366F1),
                      overlayColor: const Color(0xFF6366F1).withOpacity(0.2),
                    ),
                    child: Slider(
                      min: 8,
                      max: 72,
                      value: textInfo.fontSize,
                      onChanged: (v) => setState(() => textInfo.fontSize = v),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () {
                Navigator.of(context).pop();
                _pickTextColor(index);
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.palette, color: Color(0xFF6366F1)),
                    const SizedBox(width: 12),
                    const Text(
                      "Change Color",
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: textInfo.color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ElevatedButton(
              onPressed: () {
                setState(() => textInfo.text = controller.text);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "Save",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Pick Color",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: BlockPicker(
          pickerColor: pick,
          onColorChanged: (color) => pick = color,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ElevatedButton(
              onPressed: () {
                setState(() => texts[index].color = pick);
                Navigator.pop(c);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "Set",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
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
      Uint8List? captured = await _screenshotController.captureFromWidget(
        RepaintBoundary(key: GlobalKey(), child: _buildEditorForCapture()),
        delay: const Duration(milliseconds: 100),
      );

      final dir = await getTemporaryDirectory();
      final filePath =
          '${dir.path}/meme_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(filePath)..writeAsBytesSync(captured);

      if (await _hasInternetConnection()) {
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
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 12),
                    Text("Meme uploaded successfully!"),
                  ],
                ),
                backgroundColor: Colors.green.shade600,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                margin: const EdgeInsets.all(16),
              ),
            );
            Navigator.pop(context);
          }
        } else {
          throw Exception("Upload failed: ${response.statusMessage}");
        }
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        final localPath =
            '${appDir.path}/offline_meme_${DateTime.now().millisecondsSinceEpoch}.png';
        await file.copy(localPath);

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
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.cloud_off, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Saved offline as draft — will upload when online",
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.orange.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Upload error: $e");
      _hideUploadingDialog();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text("Upload failed: $e")),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      setState(() => _isUploading = false);
    }
  }

  void _showUploadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF6366F1)),
            const SizedBox(width: 20),
            const Expanded(
              child: Text(
                "Uploading Meme...",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFEC4899).withOpacity(0.9),
                const Color(0xFFF59E0B).withOpacity(0.9),
              ],
            ),
          ),
        ),
        title: const Row(
          children: [
            Icon(Icons.auto_fix_high, size: 24),
            SizedBox(width: 8),
            Text("Meme Editor", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _baseImage == null
                ? Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFFEC4899).withOpacity(0.1),
                          Colors.white,
                        ],
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(30),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFFEC4899).withOpacity(0.2),
                                  const Color(0xFFF59E0B).withOpacity(0.2),
                                ],
                              ),
                            ),
                            child: Icon(
                              Icons.image_outlined,
                              size: 80,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            "Pick an image to get started",
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
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

          SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: _toolbarController,
                    curve: Curves.easeOut,
                  ),
                ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  if (_baseImage != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12.0,
                        horizontal: 8,
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _buildToolButton(
                            icon: Icons.crop_rotate,
                            label: "Crop",
                            gradient: const LinearGradient(
                              colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                            ),
                            onPressed: _isUploading || _baseImage == null
                                ? null
                                : _triggerCrop,
                          ),
                          _buildToolButton(
                            icon: Icons.text_fields,
                            label: "Text",
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                            ),
                            onPressed: _isUploading ? null : _addNewText,
                          ),
                          _buildToolButton(
                            icon: Icons.color_lens,
                            label: "Color",
                            gradient: const LinearGradient(
                              colors: [Color(0xFFEC4899), Color(0xFFF472B6)],
                            ),
                            onPressed: () {
                              if (texts.isEmpty) {
                                _addNewText();
                              }
                              if (texts.isNotEmpty) {
                                final idx = texts.length - 1;
                                _pickTextColor(idx);
                              }
                            },
                          ),
                          _buildToolButton(
                            icon: _isDrawing
                                ? Icons.brush_outlined
                                : Icons.brush,
                            label: _isDrawing ? "Stop" : "Draw",
                            gradient: LinearGradient(
                              colors: [
                                _isDrawing
                                    ? Colors.red.shade400
                                    : const Color(0xFFF59E0B),
                                _isDrawing
                                    ? Colors.red.shade600
                                    : const Color(0xFFFBBF24),
                              ],
                            ),
                            onPressed: _isUploading
                                ? null
                                : () =>
                                      setState(() => _isDrawing = !_isDrawing),
                          ),
                          _buildToolButton(
                            icon: Icons.emoji_emotions,
                            label: "Emoji",
                            gradient: const LinearGradient(
                              colors: [Color(0xFF10B981), Color(0xFF34D399)],
                            ),
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
                          ),
                          _buildToolButton(
                            icon: Icons.cloud_upload,
                            label: "Upload",
                            gradient: const LinearGradient(
                              colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
                            ),
                            onPressed: _isUploading ? null : _uploadMeme,
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 8,
                      right: 8,
                      bottom: 20,
                      top: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildImageSourceButton(
                            icon: Icons.camera_alt,
                            label: "Camera",
                            onPressed: () => _isUploading
                                ? null
                                : _pickImage(ImageSource.camera),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildImageSourceButton(
                            icon: Icons.photo_library,
                            label: "Gallery",
                            onPressed: () => _isUploading
                                ? null
                                : _pickImage(ImageSource.gallery),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required Gradient gradient,
    VoidCallback? onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.first.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildImageSourceButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF6366F1), width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF6366F1),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
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
