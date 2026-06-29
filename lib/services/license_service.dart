import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';

class LicenseService {
  // Simplified: No need for secondary FirebaseApp since we use Single Project now.
  static Future<void> init() async {
    // The default app is already initialized in main.dart
  }

  // Uses the default Firestore instance
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;

  static Future<String> getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? storedId = prefs.getString('active_device_id');
      if (storedId != null && storedId.isNotEmpty) return storedId;

      var deviceInfo = DeviceInfoPlugin();
      String id = "UNKNOWN_DEVICE";
      if (Platform.isAndroid) {
        id = (await deviceInfo.androidInfo).id;
      } else if (Platform.isIOS) {
        id = (await deviceInfo.iosInfo).identifierForVendor ?? "UNKNOWN_IOS";
      }

      if (id != "UNKNOWN_DEVICE") {
        await prefs.setString('active_device_id', id);
      }
      return id;
    } catch (e) {
      debugPrint("Error getting device ID: $e");
      return "UNKNOWN_DEVICE";
    }
  }

  static Future<Map<String, dynamic>> verifyLicense(String key) async {
    try {
      final doc = await firestore.collection('licenses').doc(key).get();
      if (!doc.exists)
        return {'success': false, 'message': 'Invalid License Key'};

      final data = doc.data()!;
      final deviceId = await getDeviceId();

      if (data['status'] != 'active')
        return {'success': false, 'message': 'License disabled'};

      if (data['activated'] == true &&
          data['activeDeviceId'] != null &&
          data['activeDeviceId'] != deviceId) {
        return {
          'success': false,
          'message': 'Key already registered on another device',
        };
      }

      DateTime? expiry;
      if (data['isLifetime'] != true && data['validTill'] != null) {
        expiry = DateTime.tryParse(data['validTill']);
        if (expiry != null && expiry.isBefore(DateTime.now())) {
          return {
            'success': false,
            'message': 'License Expired',
            'isExpired': true,
          };
        }
      }

      final version = await getAppVersion();
      final uid = FirebaseAuth.instance.currentUser?.uid;

      if (data['activated'] != true) {
        await firestore.collection('licenses').doc(key).update({
          'activated': true,
          'activeDeviceId': deviceId,
          'activatedBy': uid, // Link UID here
          'activatedAt': FieldValue.serverTimestamp(),
          'lastUsedAt': FieldValue.serverTimestamp(),
          'appVersion': version,
        });
      } else {
        await firestore.collection('licenses').doc(key).update({
          'lastUsedAt': FieldValue.serverTimestamp(),
          'activatedBy': uid, // Ensure UID is present even if already activated
          'appVersion': version,
        });
      }

      // Persist license key and device ID globally in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_device_id', deviceId);
      await prefs.setString('license_key', key);

      return {
        'success': true,
        'isLifetime': data['isLifetime'] ?? false,
        'expiryDate': expiry,
        'message': 'Success',
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

  static Future<void> resetDevice(
    String licenseKey,
    String adminIdentifier,
  ) async {
    await firestore.collection('licenses').doc(licenseKey).update({
      'activated': false,
      'activeDeviceId': null,
    });
    await logAdminAction(
      adminIdentifier,
      "RESET_DEVICE",
      "Reset device for $licenseKey",
    );
  }

  static Future<void> logAdminAction(
    String adminId,
    String action,
    String details,
  ) async {
    await firestore.collection('admin_logs').add({
      'adminId': adminId,
      'action': action,
      'details': details,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // --- Support Ticket System ---

  static Future<void> ensureAuth() async {
    if (FirebaseAuth.instance.currentUser == null) {
      try {
        await FirebaseAuth.instance.signInAnonymously();
      } catch (e) {
        debugPrint("Error signing in anonymously: $e");
      }
    }
  }

  static Future<void> createTicket({
    required String licenseKey,
    required String restaurantName,
    required String phone,
    required String subject,
    required String message,
  }) async {
    await ensureAuth();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final trimmedKey = licenseKey.trim();

    if (trimmedKey.isEmpty) {
      debugPrint("Warning: Creating ticket with empty license key");
    }

    await firestore.collection('support_tickets').add({
      'licenseKey': trimmedKey,
      'restaurantName': restaurantName,
      'phone': phone,
      'subject': subject,
      'message': message,
      'status': 'open',
      'createdBy': uid, // For security rules
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
    final now = DateTime.now();
    await firestore.collection('support_tickets').doc(ticketId).update({
      'replies': FieldValue.arrayUnion([
        {
          'id': now.millisecondsSinceEpoch.toString(),
          'message': message,
          'senderRole': senderRole,
          'senderName': senderName,
          'timestamp': now.toIso8601String(),
        },
      ]),
      'lastUpdate': FieldValue.serverTimestamp(),
      'status': senderRole == 'admin' ? 'answered' : 'open',
      'hasUnreadReply': senderRole == 'admin', // Add this flag
    });

    try {
      final doc = await firestore
          .collection('support_tickets')
          .doc(ticketId)
          .get();
      if (!doc.exists) return;
      final data = doc.data()!;

      if (senderRole == 'admin') {
        // --- NOTIFY USER ---
        final licenseKey = data['licenseKey'];
        if (licenseKey != null) {
          final userQuery = await firestore
              .collection('users')
              .where('license_key', isEqualTo: licenseKey)
              .limit(1)
              .get();
          if (userQuery.docs.isNotEmpty) {
            final fcmToken = userQuery.docs.first.data()['fcmToken'];
            if (fcmToken != null) {
              await firestore.collection('notifications_queue').add({
                'token': fcmToken,
                'title': 'Support Update',
                'body': '$senderName: $message',
                'data': {'type': 'support_reply', 'ticketId': ticketId},
                'createdAt': FieldValue.serverTimestamp(),
                'status': 'pending',
              });
            }
          }
        }
      } else {
        // --- NOTIFY ADMIN ---
        await firestore.collection('notifications_queue').add({
          'topic': 'admin_support',
          'title': 'New Support Reply',
          'body': '${data['restaurantName'] ?? 'Customer'}: $message',
          'data': {'type': 'support_reply', 'ticketId': ticketId},
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'pending',
        });
      }
    } catch (e) {
      debugPrint("Error queuing notification: $e");
    }
  }

  static Future<void> deleteTicketReply(String ticketId, String replyId) async {
    final docRef = firestore.collection('support_tickets').doc(ticketId);
    final doc = await docRef.get();
    if (!doc.exists) return;

    final replies = List.from(doc.data()?['replies'] ?? []);
    replies.removeWhere((r) => r['id'] == replyId.toString());

    await docRef.update({
      'replies': replies,
      'lastUpdate': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteTicket(String ticketId) async {
    try {
      // असल में डिलीट करने के बजाय हम स्टेटस 'deleted' कर देंगे
      // क्योंकि यूजर के पास अपडेट की परमिशन है पर डिलीट की नहीं।
      await firestore.collection('support_tickets').doc(ticketId).update({
        'status': 'deleted',
        'lastUpdate': FieldValue.serverTimestamp(),
      });
      debugPrint("Ticket $ticketId marked as deleted (Soft Delete)");
    } catch (e) {
      debugPrint("Error marking ticket as deleted: $e");
      rethrow;
    }
  }

  static Future<void> resolveTicket(String ticketId) async {
    await firestore.collection('support_tickets').doc(ticketId).update({
      'status': 'resolved',
      'lastUpdate': FieldValue.serverTimestamp(),
    });
  }

  static Stream<QuerySnapshot> getTickets(String licenseKey) {
    if (licenseKey.trim().isEmpty) {
      return firestore
          .collection('support_tickets')
          .where('licenseKey', isEqualTo: 'NON_EXISTENT')
          .snapshots();
    }

    // Query by licenseKey to ensure history is visible across device re-installs.
    // This works if your Security Rules allow reading by 'isSignedIn()'
    return firestore
        .collection('support_tickets')
        .where('licenseKey', isEqualTo: licenseKey.trim())
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

  static Future<void> queueAnnouncementNotification(
    String title,
    String body,
  ) async {
    await firestore.collection('notifications_queue').add({
      'title': title,
      'body': body,
      'topic': 'announcements',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<Map<String, dynamic>> loginAdmin(String phone, String password) async {
    try {
      final snap = await firestore
          .collection('admins')
          .where('phone', isEqualTo: phone)
          .where('password', isEqualTo: password)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        return {'success': false, 'message': 'Invalid Admin Credentials'};
      }

      final adminData = snap.docs.first.data();
      if (adminData['status'] != 'active') {
        return {'success': false, 'message': 'Account disabled by system'};
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('admin_session_id', snap.docs.first.id);
      await prefs.setString('admin_role', adminData['role'] ?? 'staff');

      return {'success': true, 'message': 'Login successful'};
    } catch (e) {
      return {'success': false, 'message': 'Login Error: $e'};
    }
  }
}
