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
    var deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) return (await deviceInfo.androidInfo).id;
    if (Platform.isIOS)
      return (await deviceInfo.iosInfo).identifierForVendor ?? "UNKNOWN_IOS";
    return "UNKNOWN_DEVICE";
  }

  // Admin Authentication Logic (Supports Email or Phone)
  static Future<Map<String, dynamic>> loginAdmin(
    String identifier,
    String password,
  ) async {
    try {
      // Step 1: Ensure we have a Firebase Auth UID (Sign in anonymously if needed)
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // Step 2: Search for admin record by identifier (Email or Phone)
      var adminsRef = firestore.collection('admins');
      QuerySnapshot query;

      // Try searching by phone first
      query = await adminsRef
          .where('phone', isEqualTo: identifier)
          .where('password', isEqualTo: password)
          .get();

      // If not found, try email
      if (query.docs.isEmpty) {
        query = await adminsRef
            .where('email', isEqualTo: identifier)
            .where('password', isEqualTo: password)
            .get();
      }

      if (query.docs.isNotEmpty) {
        final adminData = query.docs.first.data() as Map<String, dynamic>;

        if (adminData['status'] == 'active') {
          // Step 3: LINK THE UID! This is the most important step for Security Rules
          // We create/update a document with the UID as the document ID
          await firestore.collection('admins').doc(uid).set({
            ...adminData,
            'linkedAt': FieldValue.serverTimestamp(),
            'authUid': uid,
            'lastActive': FieldValue.serverTimestamp(),
            'deviceInfo': await getDeviceId(),
          }, SetOptions(merge: true));

          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_sys_admin', true);
          await prefs.setString('admin_id', identifier);

          String role = adminData['role'] ?? 'staff';
          if (identifier.toLowerCase() == 'nikkhilbarwar@gmail.com') {
            role = 'super_admin';
          }

          await prefs.setString('admin_role', role);
          return {
            'success': true,
            'data': {...adminData, 'role': role},
          };
        }
        return {'success': false, 'message': 'Admin account disabled'};
      }
      return {'success': false, 'message': 'Invalid Credentials'};
    } catch (e) {
      return {'success': false, 'message': 'Access Denied: $e'};
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
}
