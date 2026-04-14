import 'package:flutter/material.dart';
import '../models/category_model.dart';
import '../core/database/database_helper.dart';
import '../services/firebase_service.dart';

class CategoryProvider with ChangeNotifier {
  List<CategoryModel> _categories = [];
  final FirebaseService _firebaseService = FirebaseService();
  
  List<CategoryModel> get categories {
    return _categories.where((c) => c.isDeleted == 0).toList();
  }

  List<CategoryModel> get deletedCategories => _categories.where((c) => c.isDeleted == 1).toList();

  Future<void> fetchCategories() async {
    _categories = await DatabaseHelper.instance.getAllCategories();
    
    // Always check for duplicates and required categories
    await _cleanupDuplicateCategories();
    
    if (_categories.isEmpty) {
      await _insertDefaultCategories();
    } else {
      notifyListeners();
    }
  }

  Future<void> _cleanupDuplicateCategories() async {
    bool changed = false;
    final Map<String, CategoryModel> seen = {};
    final List<CategoryModel> duplicates = [];

    // Force rename logic can be removed or kept for general cleanup
    // But since we want to allow deleting "General", we don't need to force it anymore.

    // Identify duplicates (Same Name and Same Type)
    for (var cat in _categories) {
      String key = "${cat.name.toLowerCase().trim()}_${cat.type}";
      if (seen.containsKey(key)) {
        duplicates.add(cat);
      } else {
        seen[key] = cat;
      }
    }

    if (duplicates.isNotEmpty) {
      final db = await DatabaseHelper.instance.database;
      for (var dup in duplicates) {
        String originalName = seen["${dup.name.toLowerCase().trim()}_${dup.type}"]!.name;
        // Move items and transactions to the original category
        await db.update('items', {'category': originalName}, where: 'category = ?', whereArgs: [dup.name]);
        await db.update('transactions', {'category': originalName}, where: 'category = ?', whereArgs: [dup.name]);
        
        await DatabaseHelper.instance.permanentDeleteCategory(dup.id!);
        _firebaseService.deleteCategory(dup.id!);
      }
      _categories = await DatabaseHelper.instance.getAllCategories();
      changed = true;
    }

    if (changed) notifyListeners();
  }

  Future<void> _insertDefaultCategories() async {
    List<CategoryModel> defaults = [
      CategoryModel(name: 'Sales', iconName: 'point_of_sale', type: 'selling', displayOrder: 0),
      CategoryModel(name: 'Raw Material', iconName: 'inventory_2', type: 'purchase', displayOrder: 1),
      CategoryModel(name: 'Utility', iconName: 'bolt', type: 'purchase', displayOrder: 2),
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
    category.name = category.name.trim();
    if (isCategoryExists(category.name)) return false;
    category.displayOrder = _categories.length;
    int id = await DatabaseHelper.instance.insertCategory(category);
    category.id = id;
    _categories.add(category);
    _firebaseService.syncCategory(category).catchError((e) => debugPrint("Category Sync Error: $e"));
    notifyListeners();
    return true;
  }

  Future<void> reorderCategories(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final CategoryModel item = _categories.removeAt(oldIndex);
    _categories.insert(newIndex, item);
    for (int i = 0; i < _categories.length; i++) {
      _categories[i].displayOrder = i;
      await DatabaseHelper.instance.updateCategory(_categories[i]);
      _firebaseService.syncCategory(_categories[i]);
    }
    notifyListeners();
  }

  Future<void> softDeleteCategory(int id, String name) async {
    final db = await DatabaseHelper.instance.database;
    
    // Find a fallback category (the first one that isn't the one being deleted)
    String fallbackCategory = 'Uncategorized';
    final otherCats = _categories.where((c) => c.id != id && c.isDeleted == 0).toList();
    if (otherCats.isNotEmpty) {
      fallbackCategory = otherCats.first.name;
    }

    await db.update('items', {'category': fallbackCategory}, where: 'category = ?', whereArgs: [name]);
    await db.update('transactions', {'category': fallbackCategory}, where: 'category = ?', whereArgs: [name]);

    await DatabaseHelper.instance.softDeleteCategory(id);
    int index = _categories.indexWhere((cat) => cat.id == id);
    if (index != -1) {
      _categories[index].isDeleted = 1;
      _categories[index].deletedAt = DateTime.now();
      _firebaseService.syncCategory(_categories[index]);
    }
    notifyListeners();
  }

  Future<void> restoreCategory(int id) async {
    try {
      await DatabaseHelper.instance.restoreCategory(id);
      int index = _categories.indexWhere((cat) => cat.id == id);
      if (index != -1) {
        _categories[index].isDeleted = 0;
        _categories[index].deletedAt = null;
        _firebaseService.syncCategory(_categories[index]);
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error restoring category: $e");
    }
  }

  Future<void> permanentDeleteCategory(int id) async {
    try {
      await DatabaseHelper.instance.permanentDeleteCategory(id);
      await _firebaseService.deleteCategory(id);
      _categories.removeWhere((cat) => cat.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint("Error permanent deleting category: $e");
    }
  }
  
  Future<bool> updateCategory(CategoryModel category, String oldName) async {
    category.name = category.name.trim();
    if (isCategoryExists(category.name, excludeId: category.id)) return false;
    final db = await DatabaseHelper.instance.database;
    await DatabaseHelper.instance.updateCategory(category);
    await db.update('items', {'category': category.name}, where: 'category = ?', whereArgs: [oldName]);
    await db.update('transactions', {'category': category.name}, where: 'category = ?', whereArgs: [oldName]);

    // Sync item stocks if shared stock is enabled
    if (category.useCategoryStock == 1) {
      await db.update(
        'items',
        {
          'current_stock': category.stockQty,
          'low_stock_alert': 1,
          'is_synced': 0
        },
        where: 'category = ?',
        whereArgs: [category.name],
      );
    }

    int index = _categories.indexWhere((c) => c.id == category.id);
    if (index != -1) {
      _categories[index] = category;
      _firebaseService.syncCategory(category);
    }
    notifyListeners();
    return true;
  }

  CategoryModel? getCategoryByName(String name) {
    try {
      return _categories.firstWhere((cat) => cat.name == name);
    } catch (_) {
      return null;
    }
  }
}
