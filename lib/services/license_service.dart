import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';

class LicenseService {
  static FirebaseApp? _licenseApp;
  static FirebaseFirestore? _licenseFirestore;

  static Future<void> init() async {
    if (_licenseFirestore != null) return;
    try {
      _licenseApp = await Firebase.initializeApp(
        name: 'TheGrillerZone',
        options: const FirebaseOptions(
          apiKey: "AIzaSyCa-EEAFEujhHqEuWz1vAeiYROgdQRxtBU",
          authDomain: "the-griller-zone-pos.firebaseapp.com",
          projectId: "the-griller-zone-pos",
          storageBucket: "the-griller-zone-pos.firebasestorage.app",
          messagingSenderId: "49958796947",
          appId: "1:49958796947:web:3a34af44934689523f5766",
        ),
      );
      _licenseFirestore = FirebaseFirestore.instanceFor(app: _licenseApp!);
    } catch (e) {
      try {
        _licenseApp = Firebase.app('TheGrillerZone');
        _licenseFirestore = FirebaseFirestore.instanceFor(app: _licenseApp!);
      } catch (_) {}
    }
  }

  static FirebaseFirestore get firestore {
    if (_licenseFirestore == null) throw "License System Offline";
    return _licenseFirestore!;
  }

  static Future<String> getDeviceId() async {
    var deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) return (await deviceInfo.androidInfo).id;
    if (Platform.isIOS) return (await deviceInfo.iosInfo).identifierForVendor ?? "UNKNOWN_IOS";
    return "UNKNOWN_DEVICE";
  }

  // Admin Authentication Logic (Supports Email or Phone)
  static Future<Map<String, dynamic>> loginAdmin(String identifier, String password) async {
    try {
      await init();
      // Check for email OR phone
      final emailSnapshot = await firestore.collection('admins')
          .where('email', isEqualTo: identifier)
          .where('password', isEqualTo: password)
          .get();

      final phoneSnapshot = await firestore.collection('admins')
          .where('phone', isEqualTo: identifier)
          .where('password', isEqualTo: password)
          .get();

      final docs = emailSnapshot.docs.isNotEmpty ? emailSnapshot.docs : phoneSnapshot.docs;

      if (docs.isNotEmpty) {
        final data = docs.first.data();
        if (data['status'] == 'active') {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_sys_admin', true);
          await prefs.setString('admin_id', identifier);
          return {'success': true, 'data': data};
        }
        return {'success': false, 'message': 'Admin account disabled'};
      }
      return {'success': false, 'message': 'Invalid Credentials'};
    } catch (e) {
      return {'success': false, 'message': 'Connection Error: $e'};
    }
  }

  static Future<Map<String, dynamic>> verifyLicense(String key) async {
    try {
      await init();
      final doc = await firestore.collection('licenses').doc(key).get();
      if (!doc.exists) return {'success': false, 'message': 'Invalid License Key'};

      final data = doc.data()!;
      final deviceId = await getDeviceId();
      
      if (data['status'] != 'active') return {'success': false, 'message': 'License disabled'};
      
      if (data['activated'] == true && data['activeDeviceId'] != null && data['activeDeviceId'] != deviceId) {
        return {'success': false, 'message': 'Key already registered on another device'};
      }

      DateTime? expiry;
      if (data['isLifetime'] != true && data['validTill'] != null) {
        expiry = DateTime.tryParse(data['validTill']);
        if (expiry != null && expiry.isBefore(DateTime.now())) {
          return {'success': false, 'message': 'License Expired', 'isExpired': true};
        }
      }

      if (data['activated'] != true) {
        final version = await getAppVersion();
        await firestore.collection('licenses').doc(key).update({
          'activated': true,
          'activeDeviceId': deviceId,
          'activatedAt': FieldValue.serverTimestamp(),
          'lastUsedAt': FieldValue.serverTimestamp(),
          'appVersion': version,
        });
      } else {
        // Update last used and version even if already activated
        final version = await getAppVersion();
        await firestore.collection('licenses').doc(key).update({
          'lastUsedAt': FieldValue.serverTimestamp(),
          'appVersion': version,
        });
      }
      return {
        'success': true, 
        'isLifetime': data['isLifetime'] ?? false, 
        'expiryDate': expiry,
        'message': 'Success'
      };
    } catch (e) {
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  static Future<String> getAppVersion() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version;
    } catch (_) {
      return "1.0.0";
    }
  }

  static Future<void> resetDevice(String licenseKey, String adminIdentifier) async {
    await firestore.collection('licenses').doc(licenseKey).update({
      'activated': false,
      'activeDeviceId': null,
    });
    await logAdminAction(adminIdentifier, "RESET_DEVICE", "Reset device for $licenseKey");
  }

  static Future<void> logAdminAction(String adminId, String action, String details) async {
    await firestore.collection('admin_logs').add({
      'adminId': adminId,
      'action': action,
      'details': details,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
