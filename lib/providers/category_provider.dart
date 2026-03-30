import 'package:flutter/material.dart';
import '../models/category_model.dart';
import '../core/database/database_helper.dart';
import '../services/firebase_service.dart';

class CategoryProvider with ChangeNotifier {
  List<CategoryModel> _categories = [];
  final FirebaseService _firebaseService = FirebaseService();
  
  List<CategoryModel> get categories {
    return _categories;
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
      CategoryModel(name: 'Sales', iconName: 'point_of_sale', type: 'selling', displayOrder: 0),
      CategoryModel(name: 'Raw Material', iconName: 'inventory_2', type: 'purchase', displayOrder: 1),
      CategoryModel(name: 'Utility', iconName: 'bolt', type: 'purchase', displayOrder: 2),
      CategoryModel(name: 'General', iconName: 'category', type: 'selling', displayOrder: 3),
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

  Future<void> deleteCategory(int id, String name) async {
    if (name == 'General') return;
    final db = await DatabaseHelper.instance.database;
    await db.update('items', {'category': 'General'}, where: 'category = ?', whereArgs: [name]);
    await db.update('transactions', {'category': 'General'}, where: 'category = ?', whereArgs: [name]);
    await DatabaseHelper.instance.deleteCategory(id);
    _categories.removeWhere((cat) => cat.id == id);
    _firebaseService.deleteCategory(id);
    notifyListeners();
  }
  
  Future<bool> updateCategory(CategoryModel category, String oldName) async {
    if (isCategoryExists(category.name, excludeId: category.id)) return false;
    final db = await DatabaseHelper.instance.database;
    await DatabaseHelper.instance.updateCategory(category);
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

  CategoryModel? getCategoryByName(String name) {
    try {
      return _categories.firstWhere((cat) => cat.name == name);
    } catch (_) {
      return null;
    }
  }
}
