import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../providers/profile_provider.dart';
import '../main_navigation.dart';
import 'login_screen.dart';
import 'activation_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().authStateChanges,
      builder: (context, snapshot) {
        // 1. Handle the initial waiting state during session restoration
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }
        
        // 2. If we have a user, check their activation/admin status
        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          
          return Consumer<ProfileProvider>(
            builder: (context, profile, child) {
              // logic: Admin Bypass - Nikkhil's both emails are always activated
              bool isAdmin = user.email == "nikkhilbarwar@gmail.com" || 
                             user.email == "anitamishra1714@gmail.com" ||
                             user.email == "missadvocate06@gmail.com";
              
              // Ensure profile is loaded for this specific user
              // Note: ProfileProvider.loadProfile() is triggered inside main/init
              
              if (isAdmin || profile.isActivated) {
                return const MainNavigation();
              } else {
                // If not activated, double check if profile is still loading
                if (profile.businessName == 'My Business' && !isAdmin) {
                   // Brief loading state if profile hasn't synced yet
                   return const _LoadingScreen();
                }
                return const ActivationScreen();
              }
            },
          );
        }

        // 3. No active session found, go to Login
        return const LoginScreen();
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Restoring Session...', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
