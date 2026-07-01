import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/database/database_helper.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential?> registerWithEmail(String email, String password) async {
    try {
      return await _auth.createUserWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      debugPrint("Registration Error: $e");
      rethrow;
    }
  }

  Future<UserCredential?> loginWithEmail(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      debugPrint("Login Error: $e");
      rethrow;
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      debugPrint("Password Reset Error: $e");
      rethrow;
    }
  }

  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Logic: Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        debugPrint("Google Sign-In: User cancelled the flow.");
        return null;
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create a new credential
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Once signed in, return the UserCredential
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      return userCredential;
    } catch (e) {
      debugPrint("❌ GOOGLE LOGIN CRITICAL ERROR: $e");
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      // 1. Reset Database instances (closes old DB and resets currentUserId)
      DatabaseHelper.resetDatabase();
      
      // 2. Clear all local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      
      // 3. Sign out from Firebase and Google
      await _googleSignIn.signOut();
      await _auth.signOut();
      
      debugPrint("✅ Full Sign-out and data cleanup complete.");
    } catch (e) {
      debugPrint("Sign-Out Error: $e");
    }
  }

  Future<void> deleteAccount() async {
    try {
      User? user = _auth.currentUser;
      if (user != null) {
        final uid = user.uid;
        final firestore = FirebaseFirestore.instance;

        // Get user profile first to find license key
        final userDoc = await firestore.collection('users').doc(uid).get();
        final userData = userDoc.data();
        final licenseKey = userData?['license_key'] ?? userData?['licenseKey'];

        // 1. Reset License if exists
        if (licenseKey != null && licenseKey.toString().isNotEmpty) {
          await firestore.collection('licenses').doc(licenseKey).update({
            'activated': false,
            'activeDeviceId': null,
            'activatedAt': null,
          }).catchError((e) => debugPrint("License Reset Skip: $e"));
        }

        // 2. Delete all user data from various collections
        final collections = [
          'items', 'categories', 'transactions', 'staff', 
          'suppliers', 'units', 'reminders', 'support_tickets'
        ];

        for (var collection in collections) {
          try {
            final snapshots = await firestore.collection(collection)
                .where('createdBy', isEqualTo: uid).get();
            
            // Delete in batches to avoid permission/timeout issues
            final batch = firestore.batch();
            for (var doc in snapshots.docs) {
              batch.delete(doc.reference);
            }
            await batch.commit();
          } catch (e) {
            debugPrint("Error cleaning $collection: $e");
          }
        }

        // 3. Delete the main user doc
        await firestore.collection('users').doc(uid).delete().catchError((e) => debugPrint("User Doc Delete Skip: $e"));

        // 4. Sign out from Google first if applicable
        await _googleSignIn.signOut();
        
        // 5. Delete the Auth User (This requires recent login)
        await user.delete();
      }
    } catch (e) {
      debugPrint("Delete Account Error: $e");
      rethrow;
    }
  }

  /// Silently sign in the user if they were previously signed in with Google.
  /// This helps in session persistence across app restarts.
  Future<void> handleSilentSignIn() async {
    try {
      // 1. Check if user is already in Firebase (Standard Persistence)
      if (_auth.currentUser != null) return;

      // 2. If not in Firebase, check if Google has a session
      final GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();
      if (googleUser != null) {
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await _auth.signInWithCredential(credential);
        debugPrint("Silent Login Success: Firebase session restored via Google");
      }
    } catch (e) {
      debugPrint("Silent Sign-In Error: $e");
    }
  }
}
