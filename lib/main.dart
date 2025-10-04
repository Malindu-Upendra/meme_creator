import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'firebase_options.dart';

import 'Components/Login/LoginScreen.dart';
import 'Components/Home/HomeScreen.dart';
import 'Utils/SyncService.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  await Hive.openBox('outbox'); 
  await Hive.openBox('user');  

  await MediaStore.ensureInitialized();
  MediaStore.appFolder = "MemeCreator";

  final connectivity = await Connectivity().checkConnectivity();
  final bool hasConnection = connectivity != ConnectivityResult.none;

  if (hasConnection) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  SyncService().start();

  runApp(MyApp(hasConnection: hasConnection));
}

class MyApp extends StatelessWidget {
  final bool hasConnection;
  const MyApp({super.key, required this.hasConnection});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meme Creator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: AuthWrapper(hasConnection: hasConnection),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  final bool hasConnection;
  const AuthWrapper({super.key, required this.hasConnection});

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

  @override
  Widget build(BuildContext context) {
    // 🚫 If offline, go directly to HomeScreen (offline mode)
    return FutureBuilder<bool>(
      future: _hasInternetConnection(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.data!) {
          return const HomeScreen();
        }

        // ✅ Otherwise, use Firebase Auth
        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, authSnapshot) {
            if (authSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            } else if (authSnapshot.hasData) {
              return const HomeScreen();
            } else {
              return const LoginPage();
            }
          },
        );
      },
    );
  }
}
