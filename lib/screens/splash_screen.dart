import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/profile_provider.dart';
import 'auth/auth_wrapper.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    // 1. Request permissions (Optional - won't block the user anymore)
    try {
      await [
        Permission.storage,
        Permission.camera,
        Permission.notification,
      ].request();
    } catch (e) {
      debugPrint("Permission request error: $e");
    }
    
    // 2. Wait for 2 seconds to show the branding
    await Future.delayed(const Duration(seconds: 2));
    
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AuthWrapper()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4E3E91), Color(0xFF7541B5)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            Container(
              width: 160,
              height: 160,
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: profile.logoPath.isNotEmpty && File(profile.logoPath).existsSync()
                    ? Image.file(File(profile.logoPath), width: 150, height: 150, fit: BoxFit.cover)
                    : Image.asset('assets/icon/app_icon.png', width: 150, height: 150, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              profile.businessName.toUpperCase(),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5),
            ),
            const Text('Professional Management', style: TextStyle(fontSize: 16, color: Colors.white70)),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 50),
              child: LinearProgressIndicator(
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD600)),
              ),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}
