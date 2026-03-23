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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        
        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          
          return Consumer<ProfileProvider>(
            builder: (context, profile, child) {
              // logic: Admin Bypass - Nikkhil's both emails are always activated
              bool isAdmin = user.email == "nikkhilbarwar@gmail.com" || 
                             user.email == "anitamishra1714@gmail.com" ||
                             user.email == "missadvocate06@gmail.com";
              
              if (isAdmin || profile.isActivated) {
                return const MainNavigation();
              } else {
                return const ActivationScreen();
              }
            },
          );
        }

        return const LoginScreen();
      },
    );
  }
}
