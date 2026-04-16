import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
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

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference _collection(String name) {
    if (_uid == null) throw Exception("User not logged in");
    return _firestore.collection('users').doc(_uid).collection(name);
  }

  DocumentReference _profileDoc() {
    if (_uid == null) throw Exception("User not logged in");
    return _firestore.collection('users').doc(_uid).collection('profile').doc('business_info');
  }

  // --- Helper: Compress Image ---
  Future<Uint8List?> _compressImage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return bytes; // Return original if decoding fails

      // Aggressive resize for staff photos to stay well within 1MB Firestore limit
      if (image.width > 400 || image.height > 400) {
        image = img.copyResize(image, width: 400, height: 400, interpolation: img.Interpolation.average);
      }

      // Compress to JPEG with 60% quality - Businessman: saves cost, Developer: stays under 1MB
      final compressed = Uint8List.fromList(img.encodeJpg(image, quality: 60));
      return compressed.isEmpty ? bytes : compressed;
    } catch (e) {
      debugPrint("Compression error, using original: $e");
      try { return await file.readAsBytes(); } catch(_) { return null; }
    }
  }

  // --- Image Storage (Updated to Base64 for FREE Users) ---
  Future<String?> uploadStaffImage(File imageFile, String staffId) async {
    try {
      if (_uid == null) return null;
      
      final compressedBytes = await _compressImage(imageFile);
      if (compressedBytes == null) return null;

      // Convert to Base64 string instead of uploading to Storage
      String base64Image = base64Encode(compressedBytes);
      return "base64:$base64Image"; 
    } catch (e) {
      debugPrint("Error converting staff image to base64: $e");
      return null;
    }
  }

  Future<String?> uploadBusinessLogo(File imageFile) async {
    try {
      if (_uid == null) return null;
      final compressedBytes = await _compressImage(imageFile);
      if (compressedBytes == null) return null;

      String base64Image = base64Encode(compressedBytes);
      return "base64:$base64Image";
    } catch (e) {
      debugPrint("Error converting logo to base64: $e");
      return null;
    }
  }

  Future<void> downloadFile(String url, File localFile) async {
    try {
      final ref = _storage.refFromURL(url);
      await ref.writeToFile(localFile);
    } catch (e) {
      debugPrint("Error downloading file: $e");
    }
  }

  // --- Profile ---
  Future<void> syncProfile(Map<String, dynamic> profileData) async {
    try {
      await _profileDoc().set(profileData, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error syncing profile: $e");
    }
  }

  Future<Map<String, dynamic>?> fetchProfile() async {
    try {
      final doc = await _profileDoc().get();
      return doc.data() as Map<String, dynamic>?;
    } catch (e) {
      debugPrint("Error fetching profile: $e");
      return null;
    }
  }

  // --- Transactions ---
  Future<bool> syncTransaction(TransactionModel tx) async {
    try {
      if (_uid == null) return false;
      await _collection('transactions').doc(tx.id?.toString()).set(tx.toMap(), SetOptions(merge: true));
      debugPrint("✅ Sync Success: Transaction ${tx.id}");
      return true;
    } catch (e) {
      debugPrint("⚠️ Sync Failed: Transaction ${tx.id} - $e");
      return false;
    }
  }

  Future<void> deleteTransaction(int id) async {
    try {
      await _collection('transactions').doc(id.toString()).delete();
    } catch (e) {
      debugPrint("Error deleting transaction from Firebase: $e");
    }
  }

  Future<List<TransactionModel>> fetchAllTransactions() async {
    try {
      final snapshot = await _collection('transactions').get();
      List<TransactionModel> txs = [];
      for (var doc in snapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;
          txs.add(TransactionModel.fromMap(data));
        } catch (e) {
          debugPrint("Skipping a corrupt transaction doc: ${doc.id}, Error: $e");
        }
      }
      debugPrint("FirebaseService: Fetched ${txs.length} transactions from cloud.");
      return txs;
    } catch (e) {
      debugPrint("Error fetching transactions from Firebase: $e");
      return [];
    }
  }

  Future<void> cleanupOldTransactions() async {
    try {
      final cutoffDate = DateTime.now().subtract(const Duration(days: 365));
      final oldDocs = await _collection('transactions')
          .where('date', isLessThan: cutoffDate.toIso8601String())
          .get();

      if (oldDocs.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (var doc in oldDocs.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        debugPrint("Cleaned up ${oldDocs.docs.length} old transactions.");
      }
    } catch (e) {
      debugPrint("Error cleaning up old transactions: $e");
    }
  }

  // --- Items ---
  Future<void> syncItem(ItemModel item) async {
    try {
      await _collection('items').doc(item.id?.toString()).set(item.toMap());
    } catch (e) {
      debugPrint("Error syncing item: $e");
    }
  }

  Future<void> deleteItem(int id) async {
    try {
      await _collection('items').doc(id.toString()).delete();
    } catch (e) {
      debugPrint("Error deleting item from Firebase: $e");
    }
  }

  Future<List<ItemModel>> fetchAllItems() async {
    try {
      final snapshot = await _collection('items').get();
      List<ItemModel> items = [];
      for (var doc in snapshot.docs) {
        try {
          items.add(ItemModel.fromMap(doc.data() as Map<String, dynamic>));
        } catch (e) {
          debugPrint("Skipping corrupt item: ${doc.id}, Error: $e");
        }
      }
      return items;
    } catch (e) {
      debugPrint("Error fetching items from Firebase: $e");
      return [];
    }
  }

  // --- Staff ---
  Future<void> syncStaff(StaffModel staff) async {
    try {
      await _collection('staff').doc(staff.id?.toString()).set(staff.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error syncing staff: $e");
    }
  }

  Future<void> syncStaffLeave(StaffLeaveModel leave) async {
    try {
      await _collection('staff_leave').doc(leave.id?.toString()).set(leave.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error syncing staff leave: $e");
    }
  }

  Future<void> syncStaffAdvance(StaffAdvanceModel advance) async {
    try {
      await _collection('staff_advance').doc(advance.id?.toString()).set(advance.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error syncing staff advance: $e");
    }
  }

  Future<void> deleteStaffLeave(int id) async {
    try {
      await _collection('staff_leave').doc(id.toString()).delete();
    } catch (e) {
      debugPrint("Error deleting staff leave from Firebase: $e");
    }
  }

  Future<List<StaffLeaveModel>> fetchAllStaffLeaves() async {
    try {
      final snapshot = await _collection('staff_leave').get();
      List<StaffLeaveModel> leaves = [];
      for (var doc in snapshot.docs) {
        try {
          leaves.add(StaffLeaveModel.fromMap(doc.data() as Map<String, dynamic>));
        } catch (e) {
          debugPrint("Skipping corrupted staff_leave: ${doc.id}, Error: $e");
        }
      }
      return leaves;
    } catch (e) {
      debugPrint("Error fetching staff leaves from Firebase: $e");
      return [];
    }
  }

  Future<void> deleteStaffAdvance(int id) async {
    try {
      await _collection('staff_advance').doc(id.toString()).delete();
    } catch (e) {
      debugPrint("Error deleting staff advance from Firebase: $e");
    }
  }

  Future<void> deleteStaffAdvancesByStaffId(int staffId) async {
    try {
      final snapshot = await _collection('staff_advance').where('staff_id', isEqualTo: staffId).get();
      for (var doc in snapshot.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint("Error deleting staff advances by staff_id from Firebase: $e");
    }
  }

  Future<void> deleteStaffLeavesByStaffId(int staffId) async {
    try {
      final snapshot = await _collection('staff_leave').where('staff_id', isEqualTo: staffId).get();
      for (var doc in snapshot.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint("Error deleting staff leaves by staff_id from Firebase: $e");
    }
  }

  Future<void> deleteStaff(int id) async {
    try {
      // 1. Delete Firestore Document
      await _collection('staff').doc(id.toString()).delete();

      // 2. Delete Staff Advances & Leaves
      final advances = await _collection('staff_advance').where('staff_id', isEqualTo: id).get();
      for (var doc in advances.docs) {
        await doc.reference.delete();
      }
      
      final leaves = await _collection('staff_leave').where('staff_id', isEqualTo: id).get();
      for (var doc in leaves.docs) {
        await doc.reference.delete();
      }

      // 3. Delete Image from Storage (To save Free Space)
      try {
        final ref = _storage.ref().child('users/$_uid/staff_images/$id.jpg');
        await ref.delete();
        debugPrint("Staff image deleted from storage to save space.");
      } catch (e) {
        debugPrint("No image found in storage to delete or error: $e");
      }
    } catch (e) {
      debugPrint("Error deleting staff from Firebase: $e");
    }
  }

  Future<List<StaffAdvanceModel>> fetchAllStaffAdvances() async {
    try {
      final snapshot = await _collection('staff_advance').get();
      List<StaffAdvanceModel> advances = [];
      for (var doc in snapshot.docs) {
        try {
          advances.add(StaffAdvanceModel.fromMap(doc.data() as Map<String, dynamic>));
        } catch (e) {
          debugPrint("Skipping corrupted staff_advance: ${doc.id}, Error: $e");
        }
      }
      return advances;
    } catch (e) {
      debugPrint("Error fetching staff advances from Firebase: $e");
      return [];
    }
  }

  Future<List<StaffModel>> fetchAllStaff() async {
    try {
      final snapshot = await _collection('staff').get();
      List<StaffModel> staff = [];
      for (var doc in snapshot.docs) {
        try {
          staff.add(StaffModel.fromMap(doc.data() as Map<String, dynamic>));
        } catch (e) {
          debugPrint("Skipping corrupted staff doc: ${doc.id}, Error: $e");
        }
      }
      return staff;
    } catch (e) {
      debugPrint("Error fetching staff from Firebase: $e");
      return [];
    }
  }

  // --- Suppliers ---
  Future<void> syncSupplier(SupplierModel supplier) async {
    try {
      await _collection('suppliers').doc(supplier.id?.toString()).set(supplier.toMap());
    } catch (e) {
      debugPrint("Error syncing supplier: $e");
    }
  }

  Future<void> deleteSupplier(int id) async {
    try {
      await _collection('suppliers').doc(id.toString()).delete();
    } catch (e) {
      debugPrint("Error deleting supplier from Firebase: $e");
    }
  }

  Future<List<SupplierModel>> fetchAllSuppliers() async {
    try {
      final snapshot = await _collection('suppliers').get();
      List<SupplierModel> suppliers = [];
      for (var doc in snapshot.docs) {
        try {
          suppliers.add(SupplierModel.fromMap(doc.data() as Map<String, dynamic>));
        } catch (e) {
          debugPrint("Skipping corrupt supplier: ${doc.id}, Error: $e");
        }
      }
      return suppliers;
    } catch (e) {
      debugPrint("Error fetching suppliers from Firebase: $e");
      return [];
    }
  }

  // --- Categories ---
  Future<void> syncCategory(CategoryModel category) async {
    try {
      await _collection('categories').doc(category.id?.toString()).set(category.toMap());
    } catch (e) {
      debugPrint("Error syncing category: $e");
    }
  }

  Future<void> deleteCategory(int id) async {
    try {
      await _collection('categories').doc(id.toString()).delete();
    } catch (e) {
      debugPrint("Error deleting category from Firebase: $e");
    }
  }

  Future<List<CategoryModel>> fetchAllCategories() async {
    try {
      final snapshot = await _collection('categories').get();
      List<CategoryModel> categories = [];
      for (var doc in snapshot.docs) {
        try {
          categories.add(CategoryModel.fromMap(doc.data() as Map<String, dynamic>));
        } catch (e) {
          debugPrint("Skipping corrupt category: ${doc.id}, Error: $e");
        }
      }
      return categories;
    } catch (e) {
      debugPrint("Error fetching categories from Firebase: $e");
      return [];
    }
  }

  // --- Units ---
  Future<void> syncUnit(Map<String, dynamic> unit) async {
    try {
      await _collection('units').doc(unit['id'].toString()).set(unit);
    } catch (e) {
      debugPrint("Error syncing unit: $e");
    }
  }

  Future<List<Map<String, dynamic>>> fetchAllUnits() async {
    try {
      final snapshot = await _collection('units').get();
      return snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint("Error fetching units from Firebase: $e");
      return [];
    }
  }

  // --- Purchase Reminders ---
  Future<void> syncPurchaseReminder(PurchaseReminderModel reminder) async {
    try {
      await _collection('purchase_reminders').doc(reminder.id?.toString()).set(reminder.toMap());
    } catch (e) {
      debugPrint("Error syncing purchase reminder: $e");
    }
  }

  Future<List<PurchaseReminderModel>> fetchAllPurchaseReminders() async {
    try {
      final snapshot = await _collection('purchase_reminders').get();
      List<PurchaseReminderModel> reminders = [];
      for (var doc in snapshot.docs) {
        try {
          reminders.add(PurchaseReminderModel.fromMap(doc.data() as Map<String, dynamic>));
        } catch (e) {
          debugPrint("Skipping corrupt reminder: ${doc.id}, Error: $e");
        }
      }
      return reminders;
    } catch (e) {
      debugPrint("Error fetching purchase reminders from Firebase: $e");
      return [];
    }
  }

  // --- Master Restore Function with Error Handling ---
  Future<Map<String, dynamic>> fetchAllUserData() async {
    final Map<String, dynamic> result = {
      'transactions': <TransactionModel>[],
      'items': <ItemModel>[],
      'categories': <CategoryModel>[],
      'staff': <StaffModel>[],
      'suppliers': <SupplierModel>[],
      'units': <Map<String, dynamic>>[],
      'purchase_reminders': <PurchaseReminderModel>[],
      'staff_advances': <StaffAdvanceModel>[],
      'staff_leaves': <StaffLeaveModel>[],
      'profile': null,
    };

    try {
      // Fetch each collection individually with its own try-catch
      // This prevents one corrupt collection from breaking the entire restore
      try {
        result['transactions'] = await fetchAllTransactions();
      } catch (e) {
        debugPrint("Master Restore: Transactions fetch failed: $e");
      }

      try {
        result['items'] = await fetchAllItems();
      } catch (e) {
        debugPrint("Master Restore: Items fetch failed: $e");
      }

      try {
        result['categories'] = await fetchAllCategories();
      } catch (e) {
        debugPrint("Master Restore: Categories fetch failed: $e");
      }

      try {
        result['staff'] = await fetchAllStaff();
      } catch (e) {
        debugPrint("Master Restore: Staff fetch failed: $e");
      }

      try {
        result['suppliers'] = await fetchAllSuppliers();
      } catch (e) {
        debugPrint("Master Restore: Suppliers fetch failed: $e");
      }

      try {
        result['units'] = await fetchAllUnits();
      } catch (e) {
        debugPrint("Master Restore: Units fetch failed: $e");
      }

      try {
        result['purchase_reminders'] = await fetchAllPurchaseReminders();
      } catch (e) {
        debugPrint("Master Restore: Reminders fetch failed: $e");
      }

      try {
        result['staff_advances'] = await fetchAllStaffAdvances();
      } catch (e) {
        debugPrint("Master Restore: Advances fetch failed: $e");
      }

      try {
        result['staff_leaves'] = await fetchAllStaffLeaves();
      } catch (e) {
        debugPrint("Master Restore: Leaves fetch failed: $e");
      }

      try {
        result['profile'] = await fetchProfile();
      } catch (e) {
        debugPrint("Master Restore: Profile fetch failed: $e");
      }

      return result;
    } catch (e) {
      debugPrint("Critical Master Restore Fetch error: $e");
      return result; // Return partial data if possible
    }
  }
}
