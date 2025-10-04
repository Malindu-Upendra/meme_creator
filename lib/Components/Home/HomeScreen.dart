import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:meme_creator/Components/MemeCreator/MemeCreatorScreen.dart';
import '../Login/LoginScreen.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loadingLocal = true;
  List<Map> _localDrafts = [];

  @override
  void initState() {
    super.initState();
    _loadLocalDrafts();
  }

  /// Load locally saved (uploaded == false) memes from Hive
  Future<void> _loadLocalDrafts() async {
    await Hive.initFlutter();
    final box = await Hive.openBox('outbox');
    final drafts = box.values
        .where((d) => d['uploaded'] == false)
        .map((d) => Map<String, dynamic>.from(d))
        .toList();
    setState(() {
      _localDrafts = drafts;
      _loadingLocal = false;
    });
  }

  Future<void> _likePost(String postId, int currentLikes) async {
    await FirebaseFirestore.instance.collection('posts').doc(postId).update({
      'likes': currentLikes + 1,
    });
  }

  Future<void> _saveImage(String url) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempPath =
          '${tempDir.path}/meme_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final response = await Dio().download(url, tempPath);
      if (response.statusCode == 200) {
        final mediaStore = MediaStore();
        await mediaStore.saveFile(
          relativePath: '',
          dirName: DirName.download,
          tempFilePath: tempPath,
          dirType: DirType.download,
        );
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('✅ Saved to gallery')));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('❌ Download failed')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('❌ Error: $e')));
    }
  }

  Future<void> _deletePost(Map post) async {
    final isLocal = post['isLocal'] == true;

    if (isLocal) {
      // Delete from Hive + file system
      final box = await Hive.openBox('outbox');
      final drafts = box.values.toList();
      final index = drafts.indexWhere(
          (d) => d['localPath'] == post['imagePath'] && d['uploaded'] == false);
      if (index != -1) {
        await box.deleteAt(index);
      }
      final file = File(post['imagePath']);
      if (file.existsSync()) await file.delete();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("🗑️ Local draft deleted")),
      );
      await _loadLocalDrafts();
      setState(() {});
    } else {
      // Delete from Firestore
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(post['postId'])
          .delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("🗑️ Post deleted")),
      );
    }
  }

  Future<void> _manualRefresh() async {
    await Future.delayed(const Duration(milliseconds: 800));
    await _loadLocalDrafts();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Meme Creator Feed"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _manualRefresh,
          ),
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
      body: _loadingLocal
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                final firebasePosts =
                    snapshot.hasData ? snapshot.data!.docs : [];

                // Combine Firestore + local drafts
                final combined = [
                  ..._localDrafts.map((d) => {
                        'isLocal': true,
                        'imagePath': d['localPath'],
                        'text': d['text'] ?? '',
                        'timestamp': d['timestamp'],
                      }),
                  ...firebasePosts.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return {
                      'isLocal': false,
                      'postId': doc.id,
                      'imageUrl': data['imageUrl'],
                      'text': data['text'] ?? '',
                      'likes': data['likes'] ?? 0,
                      'timestamp':
                          (data['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ??
                              0,
                    };
                  }),
                ];

                combined.sort((a, b) =>
                    (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));

                if (combined.isEmpty) {
                  return const Center(child: Text("No memes yet!"));
                }

                return RefreshIndicator(
                  color: Colors.blue,
                  onRefresh: _manualRefresh,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: combined.length,
                    itemBuilder: (context, index) {
                      final post = combined[index];
                      final isLocal = post['isLocal'] == true;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 8),
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Stack(
                              children: [
                                // Image
                                ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(12),
                                  ),
                                  child: isLocal
                                      ? Image.file(
                                          File(post['imagePath']),
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          height: 250,
                                        )
                                      : Image.network(
                                          post['imageUrl'],
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          height: 250,
                                          loadingBuilder: (context, child,
                                              loadingProgress) {
                                            if (loadingProgress == null)
                                              return child;
                                            return const Center(
                                                child:
                                                    CircularProgressIndicator());
                                          },
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  const Center(
                                                      child: Text(
                                                          "Image failed to load")),
                                        ),
                                ),

                                // DRAFT Tag
                                if (isLocal)
                                  Positioned(
                                    top: 10,
                                    left: 10,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.9),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        "DRAFT",
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),

                                // Delete Button
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  child: IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.white),
                                    style: ButtonStyle(
                                        backgroundColor:
                                            WidgetStateProperty.all(
                                                Colors.black38)),
                                    onPressed: () => _deletePost(post),
                                  ),
                                ),
                              ],
                            ),

                            // Text content
                            if ((post['text'] ?? '').isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  post['text'],
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500),
                                ),
                              ),

                            // Action buttons (only uploaded)
                            if (!isLocal)
                              Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.favorite_border,
                                            color: Colors.red,
                                          ),
                                          onPressed: () => _likePost(
                                              post['postId'],
                                              post['likes'] ?? 0),
                                        ),
                                        Text("${post['likes']} likes"),
                                      ],
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.download,
                                        color: Colors.blue,
                                      ),
                                      onPressed: () =>
                                          _saveImage(post['imageUrl']),
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
            MaterialPageRoute(builder: (context) => const MemeEditorScreen()),
          );
        },
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }
}
