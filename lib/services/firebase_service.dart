import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
import '../models/recipe_model.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference _collection(String name) {
    if (_uid == null) throw Exception("User not logged in");
    return _firestore.collection('users').doc(_uid).collection(name);
  }

  DocumentReference _profileDoc() {
    if (_uid == null) throw Exception("User not logged in");
    return _firestore.collection('users').doc(_uid).collection('profile').doc('business_info');
  }

  // --- High-Speed Batch Sync ---
  Future<void> syncBatch(String collectionName, List<Map<String, dynamic>> dataList) async {
    if (dataList.isEmpty) return;
    
    final col = _collection(collectionName);
    
    // Firestore batch limit is 500. We chunk it to 200 as requested for stability.
    for (var i = 0; i < dataList.length; i += 200) {
      final batch = _firestore.batch();
      final chunk = dataList.sublist(i, i + 200 > dataList.length ? dataList.length : i + 200);
      
      for (var data in chunk) {
        final id = data['id']?.toString();
        if (id != null) {
          batch.set(col.doc(id), data, SetOptions(merge: true));
        }
      }
      await batch.commit();
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
    await _profileDoc().set(profileData, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> fetchProfile() async {
    final doc = await _profileDoc().get();
    return doc.data() as Map<String, dynamic>?;
  }

  Future<bool> syncTransaction(TransactionModel tx) async {
    try {
      await _collection('transactions').doc(tx.id?.toString()).set(tx.toMap(), SetOptions(merge: true));
      return true;
    } catch (e) {
      return false;
    }
  }

  // --- Fetch Methods for masterRestoreFromCloud ---
  Future<List<CategoryModel>> fetchAllCategories() async {
    final snap = await _collection('categories').get();
    return snap.docs.map((d) => CategoryModel.fromMap(d.data() as Map<String, dynamic>)).toList();
  }

  Future<List<ItemModel>> fetchAllItems() async {
    try {
      final snap = await _collection('items').get();
      List<ItemModel> items = [];
      for (var doc in snap.docs) {
        try {
          items.add(ItemModel.fromMap(doc.data() as Map<String, dynamic>));
        } catch (e) {
          debugPrint("🔥 FIREBASE FETCH ERROR [Item ID: ${doc.id}]: $e");
        }
      }
      return items;
    } catch (e) {
      debugPrint("🔥 FIREBASE FATAL FETCH ERROR [Items]: $e");
      return [];
    }
  }

  Future<List<TransactionModel>> fetchAllTransactions() async {
    final snap = await _collection('transactions').get();
    return snap.docs.map((d) => TransactionModel.fromMap(d.data() as Map<String, dynamic>)).toList();
  }

  Future<List<StaffModel>> fetchAllStaff() async {
    final snap = await _collection('staff').get();
    return snap.docs.map((d) => StaffModel.fromMap(d.data() as Map<String, dynamic>)).toList();
  }

  Future<List<SupplierModel>> fetchAllSuppliers() async {
    final snap = await _collection('suppliers').get();
    return snap.docs.map((d) => SupplierModel.fromMap(d.data() as Map<String, dynamic>)).toList();
  }

  Future<List<PurchaseReminderModel>> fetchAllPurchaseReminders() async {
    final snap = await _collection('purchase_reminders').get();
    return snap.docs.map((d) => PurchaseReminderModel.fromMap(d.data() as Map<String, dynamic>)).toList();
  }

  Future<List<RecipeModel>> fetchAllRecipes() async {
    final snap = await _collection('recipes').get();
    return snap.docs.map((d) => RecipeModel.fromMap(d.data() as Map<String, dynamic>)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchAllUnits() async {
    final snap = await _collection('units').get();
    return snap.docs.map((d) => d.data() as Map<String, dynamic>).toList();
  }

  // --- Sync Single Methods ---
  Future<void> syncItem(ItemModel item) async => await _collection('items').doc(item.id?.toString()).set(item.toMap(), SetOptions(merge: true));
  Future<void> syncCategory(CategoryModel category) async => await _collection('categories').doc(category.id?.toString()).set(category.toMap(), SetOptions(merge: true));
  Future<void> syncStaffAdvance(StaffAdvanceModel advance) async => await _collection('staff_advance').doc(advance.id?.toString()).set(advance.toMap(), SetOptions(merge: true));
  Future<void> syncStaffLeave(StaffLeaveModel leave) async => await _collection('staff_leave').doc(leave.id?.toString()).set(leave.toMap(), SetOptions(merge: true));
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
    final results = await Future.wait([
      fetchAllTransactions(),
      fetchAllItems(),
      fetchAllCategories(),
      fetchAllStaff(),
      fetchAllSuppliers(),
      fetchAllUnits(),
      fetchAllPurchaseReminders(),
      fetchAllRecipes(),
      _collection('staff_advance').get(),
      _collection('staff_leave').get(),
      _profileDoc().get(),
    ]);

    return {
      'transactions': results[0],
      'items': results[1],
      'categories': results[2],
      'staff': results[3],
      'suppliers': results[4],
      'units': results[5],
      'purchase_reminders': results[6],
      'recipes': results[7],
      'staff_advances': (results[8] as QuerySnapshot).docs.map((d) => StaffAdvanceModel.fromMap(d.data() as Map<String, dynamic>)).toList(),
      'staff_leaves': (results[9] as QuerySnapshot).docs.map((d) => StaffLeaveModel.fromMap(d.data() as Map<String, dynamic>)).toList(),
      'profile': (results[10] as DocumentSnapshot).data(),
    };
  }

  // Compatibility
  Future<void> syncStaff(StaffModel staff) async => await _collection('staff').doc(staff.id?.toString()).set(staff.toMap());
}
