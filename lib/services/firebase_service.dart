import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:image/image.dart' as img;
import '../models/transaction_model.dart';
import '../models/staff_model.dart';
import '../models/item_model.dart';
import '../models/supplier_model.dart';
import '../models/category_model.dart';
import '../models/purchase_reminder_model.dart';
import '../models/recipe_model.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static String? activeLicenseKey;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference _collection(String name) {
    if (activeLicenseKey != null && activeLicenseKey != 'NONE') {
      return _firestore.collection('licenses').doc(activeLicenseKey).collection(name);
    }
    if (_uid == null) throw Exception("User not logged in");
    return _firestore.collection('users').doc(_uid).collection(name);
  }

  DocumentReference _profileDoc() {
    if (activeLicenseKey != null && activeLicenseKey != 'NONE') {
      return _firestore.collection('licenses').doc(activeLicenseKey).collection('profile').doc('business_info');
    }
    if (_uid == null) throw Exception("User not logged in");
    return _firestore.collection('users').doc(_uid).collection('profile').doc('business_info');
  }

  // --- High-Speed Batch Sync with Compression ---
  Future<void> syncBatch(String collectionName, List<Map<String, dynamic>> dataList) async {
    if (dataList.isEmpty) return;
    
    final col = _collection(collectionName);

    // 1. Compression: Convert list to Base64 GZip
    final String compressedData = _compressData(dataList);

    // 2. We push in batches of 500 to optimize Firestore writes
    for (var i = 0; i < dataList.length; i += 500) {
      final batch = _firestore.batch();
      final chunk = dataList.sublist(i, i + 500 > dataList.length ? dataList.length : i + 500);
      
      for (var data in chunk) {
        final id = data['id']?.toString();
        if (id != null) {
          batch.set(col.doc(id), data, SetOptions(merge: true));
        }
      }
      await batch.commit();
    }
  }

  String _compressData(List<dynamic> data) {
    try {
      final jsonString = jsonEncode(data);
      final compressed = GZipCodec().encode(utf8.encode(jsonString));
      return base64Encode(compressed);
    } catch (e) {
      return jsonEncode(data); // Fallback
    }
  }

  // --- Image Compression ---
  Future<Uint8List?> _compressImage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return bytes;
      if (image.width > 400 || image.height > 400) {
        image = img.copyResize(image, width: 400, height: 400, interpolation: img.Interpolation.average);
      }
      return Uint8List.fromList(img.encodeJpg(image, quality: 60));
    } catch (e) {
      return null;
    }
  }

  Future<String?> uploadStaffImage(File imageFile, String staffId) async {
    try {
      final compressedBytes = await _compressImage(imageFile);
      if (compressedBytes == null) return null;
      return "base64:${base64Encode(compressedBytes)}";
    } catch (e) {
      return null;
    }
  }

  Future<String?> uploadBusinessLogo(File file) async {
     try {
      final compressedBytes = await _compressImage(file);
      if (compressedBytes == null) return null;
      return "base64:${base64Encode(compressedBytes)}"; 
    } catch (e) {
      return null;
    }
  }

  Future<void> syncProfile(Map<String, dynamic> profileData) async {
    // 1. Save to the active path (License or User)
    await _profileDoc().set(profileData, SetOptions(merge: true));

    // 2. DISCOVERY FIX: Always save a copy to the User path if we are in License mode
    // This allows a fresh install to find the license key via fetchProfileFromUserPath()
    if (activeLicenseKey != null && activeLicenseKey != 'NONE' && _uid != null) {
      await _firestore.collection('users').doc(_uid).collection('profile').doc('business_info').set({
        'license_key': activeLicenseKey,
        'updated_at': FieldValue.serverTimestamp(),
        'email': profileData['email'],
        'business_name': profileData['business_name'],
      }, SetOptions(merge: true));
      debugPrint("☁️ FIREBASE: Discovery profile updated for License: $activeLicenseKey");
    }
  }

  Future<Map<String, dynamic>?> fetchProfile() async {
    final doc = await _profileDoc().get();
    return doc.data() as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>?> fetchProfileFromUserPath() async {
    if (_uid == null) return null;
    final doc = await _firestore.collection('users').doc(_uid).collection('profile').doc('business_info').get();
    return doc.data();
  }

  Future<bool> syncTransaction(TransactionModel tx) async {
    try {
      if (activeLicenseKey != null && activeLicenseKey != 'NONE') {
        final licenseRef = _firestore.collection('licenses').doc(activeLicenseKey);
        final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final statsRef = licenseRef.collection('daily_stats').doc(today);

        await _firestore.runTransaction((transaction) async {
          // 1. Sync the transaction document
          transaction.set(
            licenseRef.collection('transactions').doc(tx.id?.toString()),
            tx.toMap(),
            SetOptions(merge: true),
          );

          // 2. Increment transaction count in the license metadata
          transaction.update(licenseRef, {
            'tx_count': FieldValue.increment(1),
            'last_activity': FieldValue.serverTimestamp(),
          });

          // 3. Increment daily stats
          transaction.set(statsRef, {
            'count': FieldValue.increment(1),
            'date': today,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        });
      } else {
        await _collection('transactions').doc(tx.id?.toString()).set(
          tx.toMap(),
          SetOptions(merge: true),
        );
      }
      return true;
    } catch (e) {
      debugPrint("Transaction Sync/Increment Error: $e");
      return false;
    }
  }

  // --- Fetch Methods for masterRestoreFromCloud ---
  Future<List<CategoryModel>> fetchAllCategories({DateTime? since}) async {
    final col = _collection('categories');
    debugPrint("☁️ FIREBASE: Fetching categories from ${col.path}...");
    Query query = col;
    if (since != null) {
      query = query.where('updated_at', isGreaterThan: since.toIso8601String());
    }
    final snap = await query.get();
    debugPrint("☁️ FIREBASE: Found ${snap.docs.length} documents in 'categories' collection.");
    return snap.docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      if (data['id'] == null) data['id'] = int.tryParse(d.id) ?? d.id.hashCode;
      return CategoryModel.fromMap(data);
    }).toList();
  }

  Future<List<ItemModel>> fetchAllItems({DateTime? since}) async {
    try {
      debugPrint("☁️ FIREBASE: Running Deep Scan for items...");
      List<QuerySnapshot> snapshots = [];

      // Attempt A: License Path
      if (activeLicenseKey != null && activeLicenseKey != 'NONE') {
        snapshots.add(await _firestore.collection('licenses').doc(activeLicenseKey).collection('items').get());
      }

      // Attempt B: User Path (Most likely location for your data)
      if (_uid != null) {
        snapshots.add(await _firestore.collection('users').doc(_uid).collection('items').get());
      }

      // Attempt C: Legacy Root Path
      snapshots.add(await _firestore.collection('items').get());

      List<ItemModel> items = [];
      for (var snap in snapshots) {
        if (snap.docs.isNotEmpty) {
          debugPrint("✅ FIREBASE: Found ${snap.docs.length} items in path: ${snap.docs.first.reference.path}");
          for (var doc in snap.docs) {
            try {
              final data = doc.data() as Map<String, dynamic>;
              if (data['id'] == null) {
                data['id'] = int.tryParse(doc.id) ?? doc.id.hashCode;
              }
              items.add(ItemModel.fromMap(data));
            } catch (e) {
              debugPrint("🔥 Item Parse Error [ID: ${doc.id}]: $e");
            }
          }
          // We found items, we return them here
          return items;
        }
      }

      debugPrint("❌ FIREBASE: Total Items Found: 0 in all paths.");
      return [];
    } catch (e) {
      debugPrint("🔥 FIREBASE FATAL FETCH ERROR [Items]: $e");
      return [];
    }
  }

  Future<List<TransactionModel>> fetchAllTransactions({DateTime? since}) async {
    final col = _collection('transactions');
    debugPrint("☁️ FIREBASE: Fetching transactions from ${col.path}...");
    Query query = col;
    if (since != null) {
      query = query.where('updated_at', isGreaterThan: since.toIso8601String());
    }
    final snap = await query.get();
    return snap.docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      if (data['id'] == null) data['id'] = int.tryParse(d.id) ?? d.id.hashCode;
      return TransactionModel.fromMap(data);
    }).toList();
  }

  Future<List<StaffModel>> fetchAllStaff({DateTime? since}) async {
    final col = _collection('staff');
    Query query = col;
    if (since != null) {
      query = query.where('updated_at', isGreaterThan: since.toIso8601String());
    }
    final snap = await query.get();
    return snap.docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      if (data['id'] == null) data['id'] = int.tryParse(d.id) ?? d.id.hashCode;
      return StaffModel.fromMap(data);
    }).toList();
  }

  Future<List<SupplierModel>> fetchAllSuppliers({DateTime? since}) async {
    final col = _collection('suppliers');
    Query query = col;
    if (since != null) {
      query = query.where('updated_at', isGreaterThan: since.toIso8601String());
    }
    final snap = await query.get();
    return snap.docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      if (data['id'] == null) data['id'] = int.tryParse(d.id) ?? d.id.hashCode;
      return SupplierModel.fromMap(data);
    }).toList();
  }

  Future<List<PurchaseReminderModel>> fetchAllPurchaseReminders({DateTime? since}) async {
    final col = _collection('purchase_reminders');
    Query query = col;
    if (since != null) {
      query = query.where('updated_at', isGreaterThan: since.toIso8601String());
    }
    final snap = await query.get();
    return snap.docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      if (data['id'] == null) data['id'] = int.tryParse(d.id) ?? d.id.hashCode;
      return PurchaseReminderModel.fromMap(data);
    }).toList();
  }

  Future<List<RecipeModel>> fetchAllRecipes({DateTime? since}) async {
    final col = _collection('recipes');
    Query query = col;
    if (since != null) {
      query = query.where('updated_at', isGreaterThan: since.toIso8601String());
    }
    final snap = await query.get();
    return snap.docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      if (data['id'] == null) data['id'] = int.tryParse(d.id) ?? d.id.hashCode;
      return RecipeModel.fromMap(data);
    }).toList();
  }

  Future<List<Map<String, dynamic>>> fetchAllUnits({DateTime? since}) async {
    Query query = _collection('units');
    if (since != null) {
      query = query.where('updated_at', isGreaterThan: since.toIso8601String());
    }
    final snap = await query.get();
    return snap.docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      if (data['id'] == null) data['id'] = int.tryParse(d.id) ?? d.id.hashCode;
      return data;
    }).toList();
  }

  // --- Sync Single Methods ---
  Future<void> syncItem(ItemModel item) async => await _collection('items').doc(item.id?.toString()).set(item.toMap(), SetOptions(merge: true));
  Future<void> syncCategory(CategoryModel category) async => await _collection('categories').doc(category.id?.toString()).set(category.toMap(), SetOptions(merge: true));
  Future<void> syncStaffAdvance(StaffAdvanceModel advance) async => await _collection('staff_advance').doc(advance.id?.toString()).set(advance.toMap(), SetOptions(merge: true));
  Future<void> syncStaffLeave(StaffLeaveModel leave) async => await _collection('staff_leave').doc(leave.id?.toString()).set(leave.toMap(), SetOptions(merge: true));

  Future<List<StaffAdvanceModel>> fetchAllStaffAdvances({DateTime? since}) async {
    Query query = _collection('staff_advance');
    if (since != null) {
      query = query.where('updated_at', isGreaterThan: since.toIso8601String());
    }
    final snap = await query.get();
    return snap.docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      if (data['id'] == null) data['id'] = int.tryParse(d.id) ?? d.id.hashCode;
      return StaffAdvanceModel.fromMap(data);
    }).toList();
  }

  Future<List<StaffLeaveModel>> fetchAllStaffLeaves({DateTime? since}) async {
    Query query = _collection('staff_leave');
    if (since != null) {
      query = query.where('updated_at', isGreaterThan: since.toIso8601String());
    }
    final snap = await query.get();
    return snap.docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      if (data['id'] == null) data['id'] = int.tryParse(d.id) ?? d.id.hashCode;
      return StaffLeaveModel.fromMap(data);
    }).toList();
  }
  Future<void> syncSupplier(SupplierModel supplier) async => await _collection('suppliers').doc(supplier.id?.toString()).set(supplier.toMap(), SetOptions(merge: true));
  Future<void> syncPurchaseReminder(PurchaseReminderModel reminder) async => await _collection('purchase_reminders').doc(reminder.id?.toString()).set(reminder.toMap(), SetOptions(merge: true));
  Future<void> syncRecipe(RecipeModel recipe) async => await _collection('recipes').doc(recipe.id?.toString()).set(recipe.toMap(), SetOptions(merge: true));
  Future<void> syncUnit(Map<String, dynamic> unit) async => await _collection('units').doc(unit['id']?.toString() ?? unit['name']).set(unit, SetOptions(merge: true));

  // --- Delete Methods ---
  Future<void> deleteTransaction(int id) async => await _collection('transactions').doc(id.toString()).delete();
  Future<void> deleteItem(int id) async => await _collection('items').doc(id.toString()).delete();
  Future<void> deleteCategory(int id) async => await _collection('categories').doc(id.toString()).delete();
  Future<void> deleteStaff(int id) async => await _collection('staff').doc(id.toString()).delete();
  Future<void> deleteStaffAdvance(int id) async => await _collection('staff_advance').doc(id.toString()).delete();
  Future<void> deleteStaffLeave(int id) async => await _collection('staff_leave').doc(id.toString()).delete();
  Future<void> deleteSupplier(int id) async => await _collection('suppliers').doc(id.toString()).delete();
  Future<void> deletePurchaseReminder(int id) async => await _collection('purchase_reminders').doc(id.toString()).delete();
  Future<void> deleteRecipe(int id) async => await _collection('recipes').doc(id.toString()).delete();

  Future<void> deleteRecipesByProductId(int productId) async {
    final snap = await _collection('recipes').where('product_id', isEqualTo: productId).get();
    final batch = _firestore.batch();
    for (var doc in snap.docs) batch.delete(doc.reference);
    await batch.commit();
  }

  Future<void> deleteStaffAdvancesByStaffId(int staffId) async {
    final snap = await _collection('staff_advance').where('staff_id', isEqualTo: staffId).get();
    final batch = _firestore.batch();
    for (var doc in snap.docs) batch.delete(doc.reference);
    await batch.commit();
  }

  Future<void> deleteStaffLeavesByStaffId(int staffId) async {
    final snap = await _collection('staff_leave').where('staff_id', isEqualTo: staffId).get();
    final batch = _firestore.batch();
    for (var doc in snap.docs) batch.delete(doc.reference);
    await batch.commit();
  }

  // --- Fetch All Data for SyncProvider Restore ---
  Future<Map<String, dynamic>> fetchAllUserData() async {
    final String currentLicense = activeLicenseKey ?? 'NONE';
    debugPrint("☁️ FIREBASE: Starting full data fetch. Active License: $currentLicense");

    // Helper to safely execute a fetch future
    Future<T> safeFetch<T>(Future<T> future, String label, T defaultValue) async {
      try {
        final result = await future;
        return result;
      } catch (e) {
        debugPrint("🔥 FIREBASE ERROR [Fetching $label]: $e");
        return defaultValue;
      }
    }

    // Try fetching items from current path
    List<ItemModel> items = await safeFetch(fetchAllItems(), "items", <ItemModel>[]);
    
    // FALLBACK: If items are empty and we have a license, try fetching from the User's private path
    if (items.isEmpty && currentLicense != 'NONE' && _uid != null) {
      debugPrint("⚠️ FIREBASE: No items in License path. Trying fallback User path...");
      try {
        final fallbackSnap = await _firestore.collection('users').doc(_uid).collection('items').get();
        items = fallbackSnap.docs.map((d) {
          final data = d.data();
          if (data['id'] == null) data['id'] = int.tryParse(d.id) ?? d.id.hashCode;
          return ItemModel.fromMap(data);
        }).toList();
        debugPrint("✅ FIREBASE: Found ${items.length} items in fallback path.");
      } catch (e) {
        debugPrint("🔥 FIREBASE: Fallback fetch failed: $e");
      }
    }

    final results = await Future.wait([
      safeFetch(fetchAllTransactions(), "transactions", <TransactionModel>[]),
      safeFetch(fetchAllCategories(), "categories", <CategoryModel>[]),
      safeFetch(fetchAllStaff(), "staff", <StaffModel>[]),
      safeFetch(fetchAllSuppliers(), "suppliers", <SupplierModel>[]),
      safeFetch(fetchAllUnits(), "units", <Map<String, dynamic>>[]),
      safeFetch(fetchAllPurchaseReminders(), "purchase_reminders", <PurchaseReminderModel>[]),
      safeFetch(fetchAllRecipes(), "recipes", <RecipeModel>[]),
      safeFetch(_collection('staff_advance').get(), "staff_advances", null),
      safeFetch(_collection('staff_leave').get(), "staff_leaves", null),
      safeFetch(_profileDoc().get(), "profile", null),
    ]);

    return {
      'transactions': results[0],
      'items': items,
      'categories': results[1],
      'staff': results[2],
      'suppliers': results[3],
      'units': results[4],
      'purchase_reminders': results[5],
      'recipes': results[6],
      'staff_advances': results[7] != null
          ? (results[7] as QuerySnapshot).docs.map((d) {
              final data = d.data() as Map<String, dynamic>;
              if (data['id'] == null) data['id'] = int.tryParse(d.id) ?? d.id.hashCode;
              return StaffAdvanceModel.fromMap(data);
            }).toList()
          : <StaffAdvanceModel>[],
      'staff_leaves': results[8] != null
          ? (results[8] as QuerySnapshot).docs.map((d) {
              final data = d.data() as Map<String, dynamic>;
              if (data['id'] == null) data['id'] = int.tryParse(d.id) ?? d.id.hashCode;
              return StaffLeaveModel.fromMap(data);
            }).toList()
          : <StaffLeaveModel>[],
      'profile': results[9] != null ? (results[9] as DocumentSnapshot).data() : null,
    };
  }

  // Compatibility
  Future<void> syncStaff(StaffModel staff) async => await _collection('staff').doc(staff.id?.toString()).set(staff.toMap());

  // --- Analytics for Admin ---
  Future<Map<String, int>> getLicenseStats(String licenseKey) async {
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final weekAgo = now.subtract(const Duration(days: 7));
    final monthAgo = now.subtract(const Duration(days: 30));

    final statsSnap = await _firestore
        .collection('licenses')
        .doc(licenseKey)
        .collection('daily_stats')
        .get();

    int today = 0;
    int week = 0;
    int month = 0;

    for (var doc in statsSnap.docs) {
      final dateStr = doc.id;
      final data = doc.data();
      final count = (data['count'] ?? 0) as int;

      try {
        final date = DateFormat('yyyy-MM-dd').parse(dateStr);
        if (dateStr == todayStr) today = count;
        if (date.isAfter(weekAgo) || dateStr == todayStr) week += count;
        if (date.isAfter(monthAgo) || dateStr == todayStr) month += count;
      } catch (e) {
        debugPrint("Date parse error: $e");
      }
    }

    // Also fetch the grand total from the license doc itself
    final licenseDoc = await _firestore.collection('licenses').doc(licenseKey).get();
    int total = (licenseDoc.data()?['tx_count'] ?? 0) as int;

    return {
      'today': today,
      'week': week,
      'month': month,
      'total': total,
    };
  }

  // --- Fix: Recalculate stats from actual transaction documents ---
  Future<int> recalculateLicenseStats(String licenseKeyOrId) async {
    debugPrint("Recalc: Starting for $licenseKeyOrId");

    DocumentReference? licenseRef;

    // 1. Find the correct License Document Reference
    final docById = await _firestore.collection('licenses').doc(licenseKeyOrId).get();
    if (docById.exists) {
      licenseRef = docById.reference;
    } else {
      final query = await _firestore.collection('licenses').where('licenseKey', isEqualTo: licenseKeyOrId).limit(1).get();
      if (query.docs.isNotEmpty) {
        licenseRef = query.docs.first.reference;
      }
    }

    if (licenseRef == null) {
      debugPrint("Recalc: License doc not found for $licenseKeyOrId");
      return 0;
    }

    final realId = licenseRef.id;

    // 2. Fetch Transactions from multiple possible locations
    // Location A: licenses/{id}/transactions (Preferred)
    var txSnap = await licenseRef.collection('transactions').get();
    debugPrint("Recalc: Path A (licenses/$realId/transactions) found ${txSnap.docs.length}");

    // Location B: users/{uid}/transactions (Legacy/Fallback)
    if (txSnap.docs.isEmpty) {
      final licDoc = await licenseRef.get();
      final licData = licDoc.data() as Map<String, dynamic>?;
      final uid = licData?['uid'] ?? licData?['owner_id'] ?? licData?['activatedBy'] ?? licData?['activated_by'];

      if (uid != null) {
        debugPrint("Recalc: Trying Fallback Path for UID: $uid");
        txSnap = await _firestore.collection('users').doc(uid).collection('transactions').get();
        debugPrint("Recalc: Path B (users/$uid/transactions) found ${txSnap.docs.length}");
      }
    }

    int totalCount = txSnap.docs.length;
    if (totalCount == 0) return 0;

    // 3. Aggregate stats by date
    Map<String, int> dailyCounts = {};
    for (var doc in txSnap.docs) {
      final data = doc.data();
      String? dateStr;

      final d = data['date'] ?? data['created_at'] ?? data['updated_at'];
      if (d is Timestamp) {
        dateStr = DateFormat('yyyy-MM-dd').format(d.toDate());
      } else if (d != null) {
        // Handle ISO strings or simple date strings
        dateStr = d.toString().split('T')[0].split(' ')[0];
      }

      if (dateStr != null && dateStr.length >= 10) {
        final key = dateStr.substring(0, 10);
        dailyCounts[key] = (dailyCounts[key] ?? 0) + 1;
      }
    }

    // 4. Update Firestore in a Batch
    final batch = _firestore.batch();

    // Update main license document
    batch.update(licenseRef, {
      'tx_count': totalCount,
      'last_recalc_at': FieldValue.serverTimestamp(),
    });

    // Update daily stats breakdown
    for (var entry in dailyCounts.entries) {
      final statsRef = licenseRef.collection('daily_stats').doc(entry.key);
      batch.set(statsRef, {
        'count': entry.value,
        'date': entry.key,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
    debugPrint("Recalc: Successfully updated stats for $totalCount transactions.");
    return totalCount;
  }
}
