import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';

class LicenseService {
  // Simplified: No need for secondary FirebaseApp since we use Single Project now.
  static Future<void> init() async {
    // The default app is already initialized in main.dart
  }

  // Uses the default Firestore instance
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;

  static Future<String> getDeviceId() async {
    var deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) return (await deviceInfo.androidInfo).id;
    if (Platform.isIOS) return (await deviceInfo.iosInfo).identifierForVendor ?? "UNKNOWN_IOS";
    return "UNKNOWN_DEVICE";
  }

  // Admin Authentication Logic (Supports Email or Phone)
  static Future<Map<String, dynamic>> loginAdmin(String identifier, String password) async {
    try {
      // Check for BOTH Email or Phone
      var query = firestore.collection('admins')
          .where('password', isEqualTo: password);
      
      var docs = await query.where('phone', isEqualTo: identifier).get().then((s) => s.docs);
      
      if (docs.isEmpty) {
        docs = await query.where('email', isEqualTo: identifier).get().then((s) => s.docs);
      }

      if (docs.isNotEmpty) {
        final data = docs.first.data();
        if (data['status'] == 'active') {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_sys_admin', true);
          await prefs.setString('admin_id', identifier);
          
          // Force nikkhilbarwar@gmail.com as super_admin always
          String role = data['role'] ?? 'staff';
          if (identifier.toLowerCase() == 'nikkhilbarwar@gmail.com') {
            role = 'super_admin';
          }
          
          await prefs.setString('admin_role', role);
          return {'success': true, 'data': {...data, 'role': role}};
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

  // --- Support Ticket System ---

  static Future<void> createTicket({
    required String licenseKey,
    required String restaurantName,
    required String phone,
    required String subject,
    required String message,
  }) async {
    await firestore.collection('support_tickets').add({
      'licenseKey': licenseKey,
      'restaurantName': restaurantName,
      'phone': phone,
      'subject': subject,
      'message': message,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'lastUpdate': FieldValue.serverTimestamp(),
      'replies': [],
    });
  }

  static Future<void> addTicketReply({
    required String ticketId,
    required String message,
    required String senderRole,
    required String senderName,
  }) async {
    await firestore.collection('support_tickets').doc(ticketId).update({
      'replies': FieldValue.arrayUnion([{
        'message': message,
        'senderRole': senderRole,
        'senderName': senderName,
        'timestamp': DateTime.now().toIso8601String(),
      }]),
      'lastUpdate': FieldValue.serverTimestamp(),
      if (senderRole == 'admin') 'status': 'answered',
    });
  }

  static Future<void> resolveTicket(String ticketId) async {
    await firestore.collection('support_tickets').doc(ticketId).update({
      'status': 'resolved',
      'lastUpdate': FieldValue.serverTimestamp(),
    });
  }

  static Stream<QuerySnapshot> getTickets(String licenseKey) {
    return firestore.collection('support_tickets')
        .where('licenseKey', isEqualTo: licenseKey)
        .orderBy('lastUpdate', descending: true)
        .snapshots();
  }

  static Stream<DocumentSnapshot> getTicketStream(String ticketId) {
    return firestore.collection('support_tickets').doc(ticketId).snapshots();
  }

  // --- Staff / Admin Management ---

  static Stream<QuerySnapshot> getAdminStream() {
    return firestore.collection('admins').snapshots();
  }

  static Future<void> updateAdmin({
    required String id,
    required String email,
    required String password,
    required String role,
    required String status,
  }) async {
    await firestore.collection('admins').doc(id).set({
      'email': email,
      'password': password,
      'role': role,
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> deleteAdmin(String id) async {
    await firestore.collection('admins').doc(id).delete();
  }

  static Future<void> queueAnnouncementNotification(String title, String body) async {
    await firestore.collection('notifications_queue').add({
      'title': title,
      'body': body,
      'topic': 'announcements',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
