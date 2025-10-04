import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// A background sync service that uploads locally saved memes
/// (when the app is offline) once an internet connection is restored.
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  StreamSubscription? _subscription;
  bool _isSyncing = false;

  final String cloudName = "dxcqu9b5s";
  final String uploadPreset = "meme_preset";

  void start() {
    _subscription ??= Connectivity()
        .onConnectivityChanged
        .listen((dynamic result) async {
      ConnectivityResult? connection;

      if (result is List<ConnectivityResult> && result.isNotEmpty) {
        connection = result.first;
      } else if (result is ConnectivityResult) {
        connection = result;
      }

      if (connection != null && connection != ConnectivityResult.none) {
        await _syncDrafts();
      }
    });
  }

  Future<void> _syncDrafts() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final outbox = await Hive.openBox('outbox');
      final drafts = outbox.values.where((d) => d['uploaded'] == false).toList();

      if (drafts.isEmpty) {
        print("🟢 No drafts to sync");
        _isSyncing = false;
        return;
      }

      print("🔄 Syncing ${drafts.length} draft(s)...");

      for (final draft in drafts) {
        final localPath = draft['localPath'];
        final text = draft['text'] ?? '';
        final file = File(localPath);

        if (!file.existsSync()) {
          print("⚠️ File not found: $localPath — skipping");
          continue;
        }

        try {
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
              "text": text,
              "likes": 0,
              "timestamp": FieldValue.serverTimestamp(),
              "user": user?.email ?? "anonymous",
            });

            final index = outbox.values.toList().indexOf(draft);
            await outbox.putAt(index, {
              ...draft,
              "uploaded": true,
              "isDraft": false,
            });

            print("✅ Uploaded draft from $localPath");
          } else {
            print("❌ Upload failed for draft at $localPath");
          }
        } catch (e) {
          print("⚠️ Error uploading draft: $e");
        }
      }

      print("✅ Sync complete!");
    } catch (e) {
      print("❌ SyncService error: $e");
    } finally {
      _isSyncing = false;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
