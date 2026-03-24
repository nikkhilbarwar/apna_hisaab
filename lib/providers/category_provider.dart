import 'package:flutter/material.dart';
import '../models/category_model.dart';
import '../models/item_model.dart';
import '../models/transaction_model.dart';
import '../models/staff_model.dart';
import '../core/database/database_helper.dart';
import '../services/firebase_service.dart';

class CategoryProvider with ChangeNotifier {
  List<CategoryModel> _categories = [];
  final FirebaseService _firebaseService = FirebaseService();
  
  List<CategoryModel> get categories {
    List<CategoryModel> sorted = List.from(_categories);
    sorted.sort((a, b) {
      if (a.type == b.type) {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return a.type == 'selling' ? -1 : 1;
    });
    return sorted;
  }

  Future<void> fetchCategories() async {
    _categories = await DatabaseHelper.instance.getAllCategories();
    
    if (_categories.isEmpty) {
      await _insertDefaultCategories();
    } else {
      notifyListeners();
    }
  }

  Future<void> _insertDefaultCategories() async {
    List<CategoryModel> defaults = [
      CategoryModel(name: 'Sales', iconName: 'point_of_sale', type: 'selling'),
      CategoryModel(name: 'Raw Material', iconName: 'inventory_2', type: 'purchase'),
      CategoryModel(name: 'Utility', iconName: 'bolt', type: 'purchase'),
      CategoryModel(name: 'General', iconName: 'category', type: 'selling'),
    ];

    for (var cat in defaults) {
      await addCategory(cat);
    }
  }

  bool isCategoryExists(String name, {int? excludeId}) {
    return _categories.any((cat) => 
      cat.name.toLowerCase().trim() == name.toLowerCase().trim() && cat.id != excludeId);
  }

  Future<bool> addCategory(CategoryModel category) async {
    if (isCategoryExists(category.name)) return false;

    int id = await DatabaseHelper.instance.insertCategory(category);
    category.id = id;
    _categories.add(category);
    
    // Sync to Firebase
    _firebaseService.syncCategory(category).catchError((e) => debugPrint("Category Sync Error: $e"));
    
    notifyListeners();
    return true;
  }

  Future<void> deleteCategory(int id, String name) async {
    if (name == 'General') return;

    // Update related items and transactions locally
    final db = await DatabaseHelper.instance.database;
    await db.update('items', {'category': 'General'}, where: 'category = ?', whereArgs: [name]);
    await db.update('transactions', {'category': 'General'}, where: 'category = ?', whereArgs: [name]);

    await DatabaseHelper.instance.deleteCategory(id);
    _categories.removeWhere((cat) => cat.id == id);
    
    // Delete from Firebase
    _firebaseService.deleteCategory(id);
    
    notifyListeners();
  }
  
  Future<bool> updateCategory(CategoryModel category, String oldName) async {
    if (isCategoryExists(category.name, excludeId: category.id)) return false;

    final db = await DatabaseHelper.instance.database;
    await db.update('categories', category.toMap(), where: 'id = ?', whereArgs: [category.id]);
    
    await db.update('items', {'category': category.name}, where: 'category = ?', whereArgs: [oldName]);
    await db.update('transactions', {'category': category.name}, where: 'category = ?', whereArgs: [oldName]);
    
    int index = _categories.indexWhere((c) => c.id == category.id);
    if (index != -1) {
      _categories[index] = category;
      _firebaseService.syncCategory(category);
    }
    notifyListeners();
    return true;
  }

  // --- Restore Logic ---
  Future<void> restoreFromCloud() async {
    try {
      final cloudData = await _firebaseService.fetchAllUserData();
      
      // Clear Local DB
      await DatabaseHelper.instance.clearAllData();
      
      // Insert Items
      final items = cloudData['items'] as List<ItemModel>;
      for (var item in items) {
        await DatabaseHelper.instance.insertItem(item);
      }
      
      // Insert Categories
      final categories = cloudData['categories'] as List<CategoryModel>;
      for (var cat in categories) {
        await DatabaseHelper.instance.insertCategory(cat);
      }

      // Insert Transactions
      final txs = cloudData['transactions'] as List<TransactionModel>;
      for (var tx in txs) {
        await DatabaseHelper.instance.insertTransaction(tx);
      }
      
      // Insert Staff
      final staffList = cloudData['staff'] as List<StaffModel>;
      for (var s in staffList) {
        await DatabaseHelper.instance.insertStaff(s);
      }
      
      // Refresh local state
      await fetchCategories();
    } catch (e) {
      debugPrint("Full Restore Error: $e");
      rethrow;
    }
  }

  CategoryModel? getCategoryByName(String name) {
    try {
      return _categories.firstWhere((cat) => cat.name == name);
    } catch (_) {
      return null;
    }
  }
}
