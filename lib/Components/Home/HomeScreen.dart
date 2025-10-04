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

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  bool _loadingLocal = true;
  List<Map> _localDrafts = [];
  late AnimationController _fabController;

  @override
  void initState() {
    super.initState();
    _loadLocalDrafts();
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fabController.forward();
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Saved to gallery'),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Text('Download failed'),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Error: $e')),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _deletePost(Map post) async {
    final isLocal = post['isLocal'] == true;

    if (isLocal) {
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
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.delete_outline, color: Colors.white),
              SizedBox(width: 12),
              Text("Local draft deleted"),
            ],
          ),
          backgroundColor: Colors.orange.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      await _loadLocalDrafts();
      setState(() {});
    } else {
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(post['postId'])
          .delete();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.delete_outline, color: Colors.white),
              SizedBox(width: 12),
              Text("Post deleted"),
            ],
          ),
          backgroundColor: Colors.orange.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
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
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF6366F1).withOpacity(0.9),
                const Color(0xFF8B5CF6).withOpacity(0.9),
              ],
            ),
          ),
        ),
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, size: 28),
            SizedBox(width: 8),
            Text(
              "Meme Feed",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _manualRefresh,
              tooltip: 'Refresh',
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.logout_rounded),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                  );
                }
              },
              tooltip: 'Logout',
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF6366F1).withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: _loadingLocal
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF6366F1),
                  strokeWidth: 3,
                ),
              )
            : StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('posts')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  final firebasePosts =
                      snapshot.hasData ? snapshot.data!.docs : [];

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
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.image_not_supported_outlined,
                            size: 80,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "No memes yet!",
                            style: TextStyle(
                              fontSize: 20,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Create your first meme",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    color: const Color(0xFF6366F1),
                    onRefresh: _manualRefresh,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(top: 100, bottom: 100),
                      itemCount: combined.length,
                      itemBuilder: (context, index) {
                        final post = combined[index];
                        final isLocal = post['isLocal'] == true;

                        return Container(
                          margin: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white,
                                Colors.grey.shade50,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(20),
                                    ),
                                    child: isLocal
                                        ? Image.file(
                                            File(post['imagePath']),
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            height: 300,
                                          )
                                        : Image.network(
                                            post['imageUrl'],
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            height: 300,
                                            loadingBuilder: (context, child,
                                                loadingProgress) {
                                              if (loadingProgress == null)
                                                return child;
                                              return Container(
                                                height: 300,
                                                color: Colors.grey.shade200,
                                                child: const Center(
                                                  child: CircularProgressIndicator(
                                                    color: Color(0xFF6366F1),
                                                  ),
                                                ),
                                              );
                                            },
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    Container(
                                              height: 300,
                                              color: Colors.grey.shade300,
                                              child: const Center(
                                                child: Icon(
                                                  Icons.broken_image_outlined,
                                                  size: 60,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ),
                                          ),
                                  ),

                                  if (isLocal)
                                    Positioned(
                                      top: 16,
                                      left: 16,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.orange.shade400,
                                              Colors.orange.shade600,
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(20),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.orange.withOpacity(0.5),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.save_outlined,
                                                color: Colors.white, size: 16),
                                            SizedBox(width: 4),
                                            Text(
                                              "DRAFT",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                letterSpacing: 1,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                  Positioned(
                                    top: 16,
                                    right: 16,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.5),
                                        shape: BoxShape.circle,
                                      ),
                                      child: IconButton(
                                        icon: const Icon(Icons.delete_rounded,
                                            color: Colors.white, size: 22),
                                        onPressed: () => _deletePost(post),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              if ((post['text'] ?? '').isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    post['text'],
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF1F2937),
                                      height: 1.4,
                                    ),
                                  ),
                                ),

                              if (!isLocal)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: const BorderRadius.vertical(
                                      bottom: Radius.circular(20),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(12),
                                          onTap: () => _likePost(
                                              post['postId'], post['likes'] ?? 0),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.favorite_rounded,
                                                  color: Color(0xFFEF4444),
                                                  size: 24,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  "${post['likes']}",
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                    color: Color(0xFF1F2937),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(12),
                                          onTap: () => _saveImage(post['imageUrl']),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 8),
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Color(0xFF6366F1),
                                                  Color(0xFF8B5CF6),
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: const Row(
                                              children: [
                                                Icon(Icons.download_rounded,
                                                    color: Colors.white, size: 20),
                                                SizedBox(width: 6),
                                                Text(
                                                  "Save",
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
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
      ),
      floatingActionButton: ScaleTransition(
        scale: CurvedAnimation(
          parent: _fabController,
          curve: Curves.elasticOut,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFFEC4899),
                Color(0xFFF59E0B),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEC4899).withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: FloatingActionButton.extended(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const MemeEditorScreen()),
              );
            },
            backgroundColor: Colors.transparent,
            elevation: 0,
            icon: const Icon(Icons.add_photo_alternate_rounded, size: 28),
            label: const Text(
              "Create",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}