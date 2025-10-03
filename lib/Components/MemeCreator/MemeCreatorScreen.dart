import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MemeCreatorScreen extends StatefulWidget {
  const MemeCreatorScreen({super.key});

  @override
  State<MemeCreatorScreen> createState() => _MemeCreatorScreenState();
}

class _MemeCreatorScreenState extends State<MemeCreatorScreen> {
  File? _selectedImage;
  final _picker = ImagePicker();
  final _textController = TextEditingController();
  bool _isUploading = false;

  // 🔹 Replace with your Cloudinary details
  final String cloudName = "dxcqu9b5s";
  final String uploadPreset = "meme_preset";

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked != null) {
      setState(() {
        _selectedImage = File(picked.path);
      });
    }
  }

  Future<void> _uploadMeme() async {
    if (_selectedImage == null) return;

    setState(() => _isUploading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;

      // 🔹 Upload to Cloudinary
      String uploadUrl =
          "https://api.cloudinary.com/v1_1/$cloudName/image/upload";

      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(_selectedImage!.path),
        "upload_preset": uploadPreset, // unsigned preset
      });

      final response = await Dio().post(uploadUrl, data: formData);

      if (response.statusCode == 200) {
        final imageUrl = response.data["secure_url"];

        // 🔹 Save metadata in Firestore
        await FirebaseFirestore.instance.collection("posts").add({
          "imageUrl": imageUrl,
          "likes": 0,
          "text": _textController.text.trim(),
          "user": user?.email ?? "anonymous",
          "timestamp": FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Meme uploaded successfully!"),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } else {
        throw Exception("Upload failed: ${response.statusMessage}");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.orange),
      );
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create Meme")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_selectedImage != null)
              Expanded(
                child: Stack(
                  children: [
                    Image.file(_selectedImage!, fit: BoxFit.contain),
                    if (_textController.text.isNotEmpty)
                      Positioned(
                        bottom: 20,
                        left: 20,
                        right: 20,
                        child: Text(
                          _textController.text,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            backgroundColor: Colors.black54,
                          ),
                        ),
                      ),
                  ],
                ),
              )
            else
              const Expanded(
                child: Center(child: Text("Pick an image to start")),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              decoration: const InputDecoration(
                labelText: "Meme Text (optional)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text("Camera"),
                ),
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text("Gallery"),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isUploading ? null : _uploadMeme,
              child: _isUploading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Upload Meme"),
            ),
          ],
        ),
      ),
    );
  }
}
