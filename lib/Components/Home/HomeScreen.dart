import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:meme_creator/Components/MemeCreator/MemeCreatorScreen.dart';
import '../Login/LoginScreen.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _likePost(String postId, int currentLikes) async {
    await FirebaseFirestore.instance.collection('posts').doc(postId).update({
      'likes': currentLikes + 1,
    });
  }

  Future<void> _saveImage(String url) async {
    try {
      // 1. Download image to a temporary file
      final tempDir = await getTemporaryDirectory();
      final tempPath =
          '${tempDir.path}/meme_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final response = await Dio().download(url, tempPath);

      if (response.statusCode == 200) {
        // 2. Save file to MediaStore (Gallery)
        final mediaStore = MediaStore();
        final result = await mediaStore.saveFile(
          relativePath: '', // or specify a subfolder like 'Memes'
          dirName: DirName.download,
          tempFilePath: tempPath,
          dirType: DirType.download,
        );
        debugPrint("✅ Image saved: $result");
      } else {
        debugPrint("❌ Failed to download image");
      }
    } catch (e) {
      debugPrint("❌ Error saving image: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Meme Creator Feed"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                );
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('posts')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final posts = snapshot.data!.docs;

          if (posts.isEmpty) {
            return const Center(child: Text("No memes uploaded yet!"));
          }

          return RefreshIndicator(
            color: Colors.blue,
            onRefresh: () async {
              // Manually trigger refresh (Firestore streams auto-update,
              // but we mimic refresh for better UX)
              await Future.delayed(const Duration(seconds: 1));
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                final postId = post.id;
                final data = post.data() as Map<String, dynamic>;
                final imageUrl = data['imageUrl'];
                final likes = data['likes'] ?? 0;

                return Card(
                  margin: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 8,
                  ),
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Image
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 250,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Text("Image failed to load"),
                            );
                          },
                        ),
                      ),

                      // Action buttons
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Like button
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.favorite_border,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _likePost(postId, likes),
                                ),
                                Text("$likes likes"),
                              ],
                            ),

                            // Save button
                            IconButton(
                              icon: const Icon(
                                Icons.download,
                                color: Colors.blue,
                              ),
                              onPressed: () => _saveImage(imageUrl),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => MemeEditorScreen()),
          );
        },
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }
}
