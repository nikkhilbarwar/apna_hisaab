import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../providers/profile_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/transaction_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/license_service.dart';
import '../main_navigation.dart';
import 'login_screen.dart';
import 'activation_screen.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isCurrentlyRestoring = false;
  bool _hasCheckedRestore = false; // Flag to prevent infinite loop

  Future<void> _checkAndRestoreData(BuildContext context) async {
    // Only run if not already running and not already checked
    if (_isCurrentlyRestoring || _hasCheckedRestore) return;

    try {
      final txProvider = Provider.of<TransactionProvider>(context, listen: false);
      final syncProvider = Provider.of<SyncProvider>(context, listen: false);
      
      // Use a small delay to let the initial fetch finish
      await Future.delayed(const Duration(milliseconds: 500));
      await txProvider.fetchTransactions();
      
      if (txProvider.transactions.isEmpty) {
        if (mounted) {
          setState(() => _isCurrentlyRestoring = true);
          debugPrint("AuthWrapper: Local DB empty, starting cloud restore...");
          
          bool success = await syncProvider.fullRestoreFromServer(context);
          
          if (success) {
            debugPrint("AuthWrapper: Restore Success. Refreshing UI...");
            await txProvider.fetchTransactions();
          }
          
          if (mounted) {
            setState(() {
              _isCurrentlyRestoring = false;
              _hasCheckedRestore = true; // Mark as done even if no data found on cloud
            });
          }
        }
      } else {
        // If data is already there, no need to restore ever again in this session
        if (mounted) {
          setState(() {
            _hasCheckedRestore = true;
          });
        }
      }
    } catch (e) {
      debugPrint("AuthWrapper Restore Check Error: $e");
      if (mounted) {
        setState(() {
          _isCurrentlyRestoring = false;
          _hasCheckedRestore = true;
        });
      }
    }
  }

  Future<void> _checkAnnouncement(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final doc = await LicenseService.firestore.collection('admin_settings').doc('announcement').get();
      
      if (doc.exists) {
        final data = doc.data()!;
        final String message = data['message'] ?? "";
        final String lastSeen = prefs.getString('last_announcement') ?? "";

        if (message.isNotEmpty && message != lastSeen) {
          if (mounted) {
            _showAnnouncementDialog(context, message);
            await prefs.setString('last_announcement', message);
          }
        }
      }
    } catch (e) {
      debugPrint("Announcement Check Error: $e");
    }
  }

  void _showAnnouncementDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.campaign, color: Colors.orange),
            SizedBox(width: 10),
            Text("ANNOUNCEMENT", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK, GOT IT", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _updateUserHeartbeat(ProfileProvider profile) async {
    if (profile.isActivated && profile.licenseKey.isNotEmpty) {
      try {
        await LicenseService.verifyLicense(profile.licenseKey);
        debugPrint("User heartbeat updated: ${profile.licenseKey}");
      } catch (e) {
        debugPrint("Heartbeat Update Error: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen(message: 'Authenticating...');
        }
        
        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          
          // If we are in the middle of a restore, show the restore screen
          if (_isCurrentlyRestoring) {
            return Consumer<SyncProvider>(
              builder: (context, sync, child) => _LoadingScreen(
                message: 'Restoring your data...',
                subMessage: sync.syncStatus,
                progress: sync.syncProgress,
              ),
            );
          }

          return Consumer<ProfileProvider>(
            builder: (context, profile, child) {
              if (profile.isLoading) {
                return const _LoadingScreen(message: 'Loading Profile...');
              }

              bool isAdmin = user.email == "nikkhilbarwar@gmail.com" || 
                             user.email == "anitamishra1714@gmail.com" ||
                             user.email == "missadvocate06@gmail.com";
              
              if (isAdmin || profile.isActivated) {
                // Trigger checks ONCE after login
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  if (isAdmin) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('admin_id', user.email ?? "Super Admin");
                    await prefs.setBool('is_sys_admin', true);
                  }
                  _checkAndRestoreData(context);
                  _checkAnnouncement(context);
                  _updateUserHeartbeat(profile);
                });
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

class _LoadingScreen extends StatelessWidget {
  final String message;
  final String? subMessage;
  final double? progress;

  const _LoadingScreen({
    required this.message, 
    this.subMessage, 
    this.progress
  });

  Future<void> _updateUserHeartbeat(ProfileProvider profile) async {
    if (profile.isActivated && profile.licenseKey.isNotEmpty) {
      try {
        await LicenseService.verifyLicense(profile.licenseKey);
        debugPrint("User heartbeat updated: ${profile.licenseKey}");
      } catch (e) {
        debugPrint("Heartbeat Update Error: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (progress != null) 
                CircularProgressIndicator(value: progress)
              else
                const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(message, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              if (subMessage != null) ...[
                const SizedBox(height: 8),
                Text(subMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
