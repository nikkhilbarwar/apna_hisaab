import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/transaction_model.dart';
import '../models/staff_model.dart';
import '../models/item_model.dart';
import '../models/supplier_model.dart';
import '../models/category_model.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference _collection(String name) {
    if (_uid == null) throw Exception("User not logged in");
    return _firestore.collection('users').doc(_uid).collection(name);
  }

  // --- Transactions ---
  Future<void> syncTransaction(TransactionModel tx) async {
    try {
      await _collection('transactions').doc(tx.id?.toString()).set(tx.toMap());
    } catch (e) {
      print("Error syncing transaction: $e");
      rethrow;
    }
  }

  Future<void> deleteTransaction(int id) async {
    try {
      await _collection('transactions').doc(id.toString()).delete();
    } catch (e) {
      print("Error deleting transaction from Firebase: $e");
    }
  }

  Future<List<TransactionModel>> fetchAllTransactions() async {
    try {
      final snapshot = await _collection('transactions').get();
      return snapshot.docs.map((doc) => TransactionModel.fromMap(doc.data() as Map<String, dynamic>)).toList();
    } catch (e) {
      print("Error fetching transactions from Firebase: $e");
      return [];
    }
  }

  // --- Items ---
  Future<void> syncItem(ItemModel item) async {
    try {
      await _collection('items').doc(item.id?.toString()).set(item.toMap());
    } catch (e) {
      print("Error syncing item: $e");
    }
  }

  Future<void> deleteItem(int id) async {
    try {
      await _collection('items').doc(id.toString()).delete();
    } catch (e) {
      print("Error deleting item from Firebase: $e");
    }
  }

  Future<List<ItemModel>> fetchAllItems() async {
    try {
      final snapshot = await _collection('items').get();
      return snapshot.docs.map((doc) => ItemModel.fromMap(doc.data() as Map<String, dynamic>)).toList();
    } catch (e) {
      print("Error fetching items from Firebase: $e");
      return [];
    }
  }

  // --- Staff ---
  Future<void> syncStaff(StaffModel staff) async {
    try {
      await _collection('staff').doc(staff.id?.toString()).set(staff.toMap());
    } catch (e) {
      print("Error syncing staff: $e");
    }
  }

  Future<void> deleteStaff(int id) async {
    try {
      await _collection('staff').doc(id.toString()).delete();
    } catch (e) {
      print("Error deleting staff from Firebase: $e");
    }
  }

  Future<List<StaffModel>> fetchAllStaff() async {
    try {
      final snapshot = await _collection('staff').get();
      return snapshot.docs.map((doc) => StaffModel.fromMap(doc.data() as Map<String, dynamic>)).toList();
    } catch (e) {
      print("Error fetching staff from Firebase: $e");
      return [];
    }
  }

  // --- Suppliers ---
  Future<void> syncSupplier(SupplierModel supplier) async {
    try {
      await _collection('suppliers').doc(supplier.id?.toString()).set(supplier.toMap());
    } catch (e) {
      print("Error syncing supplier: $e");
    }
  }

  Future<void> deleteSupplier(int id) async {
    try {
      await _collection('suppliers').doc(id.toString()).delete();
    } catch (e) {
      print("Error deleting supplier from Firebase: $e");
    }
  }

  Future<List<SupplierModel>> fetchAllSuppliers() async {
    try {
      final snapshot = await _collection('suppliers').get();
      return snapshot.docs.map((doc) => SupplierModel.fromMap(doc.data() as Map<String, dynamic>)).toList();
    } catch (e) {
      print("Error fetching suppliers from Firebase: $e");
      return [];
    }
  }

  // --- Categories ---
  Future<void> syncCategory(CategoryModel category) async {
    try {
      await _collection('categories').doc(category.id?.toString()).set(category.toMap());
    } catch (e) {
      print("Error syncing category: $e");
    }
  }

  Future<void> deleteCategory(int id) async {
    try {
      await _collection('categories').doc(id.toString()).delete();
    } catch (e) {
      print("Error deleting category from Firebase: $e");
    }
  }

  Future<List<CategoryModel>> fetchAllCategories() async {
    try {
      final snapshot = await _collection('categories').get();
      return snapshot.docs.map((doc) => CategoryModel.fromMap(doc.data() as Map<String, dynamic>)).toList();
    } catch (e) {
      print("Error fetching categories from Firebase: $e");
      return [];
    }
  }

  // Batch sync for offline data
  Future<void> syncAllUnsynced(List<TransactionModel> unsynced) async {
    try {
      final batch = _firestore.batch();
      final userDoc = _firestore.collection('users').doc(_uid);
      for (var tx in unsynced) {
        final docRef = userDoc.collection('transactions').doc(tx.id?.toString());
        batch.set(docRef, tx.toMap());
      }
      await batch.commit();
    } catch (e) {
      print("Error in batch sync: $e");
    }
  }
}
