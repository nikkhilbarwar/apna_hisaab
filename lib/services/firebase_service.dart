import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/transaction_model.dart';
import '../models/staff_model.dart';
import '../models/item_model.dart';
import '../models/supplier_model.dart';
import '../models/category_model.dart';
import '../models/purchase_reminder_model.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference _collection(String name) {
    if (_uid == null) throw Exception("User not logged in");
    return _firestore.collection('users').doc(_uid).collection(name);
  }

  DocumentReference _profileDoc() {
    if (_uid == null) throw Exception("User not logged in");
    return _firestore.collection('users').doc(_uid).collection('profile').doc('business_info');
  }

  // --- Profile ---
  Future<void> syncProfile(Map<String, dynamic> profileData) async {
    try {
      await _profileDoc().set(profileData, SetOptions(merge: true));
    } catch (e) {
      print("Error syncing profile: $e");
    }
  }

  Future<Map<String, dynamic>?> fetchProfile() async {
    try {
      final doc = await _profileDoc().get();
      return doc.data() as Map<String, dynamic>?;
    } catch (e) {
      print("Error fetching profile: $e");
      return null;
    }
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
      List<TransactionModel> txs = [];
      for (var doc in snapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;
          txs.add(TransactionModel.fromMap(data));
        } catch (e) {
          print("Skipping a corrupt transaction doc: ${doc.id}, Error: $e");
        }
      }
      return txs;
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

  // --- Units ---
  Future<void> syncUnit(Map<String, dynamic> unit) async {
    try {
      await _collection('units').doc(unit['id'].toString()).set(unit);
    } catch (e) {
      print("Error syncing unit: $e");
    }
  }

  Future<List<Map<String, dynamic>>> fetchAllUnits() async {
    try {
      final snapshot = await _collection('units').get();
      return snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
    } catch (e) {
      print("Error fetching units from Firebase: $e");
      return [];
    }
  }

  // --- Purchase Reminders ---
  Future<void> syncPurchaseReminder(PurchaseReminderModel reminder) async {
    try {
      await _collection('purchase_reminders').doc(reminder.id?.toString()).set(reminder.toMap());
    } catch (e) {
      print("Error syncing purchase reminder: $e");
    }
  }

  Future<List<PurchaseReminderModel>> fetchAllPurchaseReminders() async {
    try {
      final snapshot = await _collection('purchase_reminders').get();
      return snapshot.docs.map((doc) => PurchaseReminderModel.fromMap(doc.data() as Map<String, dynamic>)).toList();
    } catch (e) {
      print("Error fetching purchase reminders from Firebase: $e");
      return [];
    }
  }

  // --- Master Restore Function ---
  Future<Map<String, dynamic>> fetchAllUserData() async {
    try {
      final results = await Future.wait([
        fetchAllTransactions(),
        fetchAllItems(),
        fetchAllCategories(),
        fetchAllStaff(),
        fetchAllSuppliers(),
        fetchAllUnits(),
        fetchAllPurchaseReminders(),
        fetchProfile(),
      ]);

      return {
        'transactions': results[0],
        'items': results[1],
        'categories': results[2],
        'staff': results[3],
        'suppliers': results[4],
        'units': results[5],
        'purchase_reminders': results[6],
        'profile': results[7],
      };
    } catch (e) {
      print("Restore fetch error: $e");
      rethrow;
    }
  }
}
