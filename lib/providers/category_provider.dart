import 'package:flutter/material.dart';
import '../models/category_model.dart';
import '../core/database/database_helper.dart';

class CategoryProvider with ChangeNotifier {
  List<CategoryModel> _categories = [];
  
  List<CategoryModel> get categories {
    // Logic: Selling first, then Purchase.
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
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query('categories');
    
    if (maps.isEmpty) {
      await _insertDefaultCategories();
    } else {
      _categories = maps.map((item) => CategoryModel.fromMap(item)).toList();
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

  // Logic: Prevent duplicate category names
  bool isCategoryExists(String name, {int? excludeId}) {
    return _categories.any((cat) => 
      cat.name.toLowerCase().trim() == name.toLowerCase().trim() && cat.id != excludeId);
  }

  Future<bool> addCategory(CategoryModel category) async {
    if (isCategoryExists(category.name)) return false;

    final db = await DatabaseHelper.instance.database;
    int id = await db.insert('categories', category.toMap());
    category.id = id;
    _categories.add(category);
    notifyListeners();
    return true;
  }

  Future<void> deleteCategory(int id, String name) async {
    final db = await DatabaseHelper.instance.database;
    if (name == 'General') return;

    await db.update('items', {'category': 'General'}, where: 'category = ?', whereArgs: [name]);
    await db.update('transactions', {'category': 'General'}, where: 'category = ?', whereArgs: [name]);

    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
    _categories.removeWhere((cat) => cat.id == id);
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
      notifyListeners();
    }
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
