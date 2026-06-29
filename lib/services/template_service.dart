import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart';
import '../models/item_model.dart';
import '../models/category_model.dart';
import '../core/database/database_helper.dart';
import '../providers/item_provider.dart';
import '../providers/category_provider.dart';
import 'package:flutter/material.dart';

class TemplateService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 1. Fetch all available Starter Packs (for Setup Wizard)
  static Future<List<Map<String, dynamic>>> fetchStarterPacks() async {
    try {
      final snap = await _firestore.collection('starter_packs').get();
      return snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
    } catch (e) {
      debugPrint("Error fetching packs: $e");
      return [];
    }
  }

  // 2. Add/Update a Starter Pack (for Admin Panel)
  static Future<void> saveStarterPack(String name, List<CategoryModel> categories, List<ItemModel> items) async {
    await _firestore.collection('starter_packs').doc(name).set({
      'packName': name,
      'updatedAt': FieldValue.serverTimestamp(),
      'categories': categories.map((c) => c.toMap()).toList(),
      'items': items.map((i) => i.toMap()).toList(),
    });
  }

  // 3. Inject Selected Items into User's Local DB
  static Future<bool> injectTemplate({
    required String licenseId,
    required List<ItemModel> selectedItems,
    required List<CategoryModel> selectedCategories,
    required ItemProvider itemProvider,
    required CategoryProvider catProvider,
  }) async {
    final db = DatabaseHelper.instance;
    try {
      // Use a transaction for atomic injection
      final database = await db.database;
      await database.transaction((txn) async {
        // 1. Insert Categories
        for (var cat in selectedCategories) {
          cat.licenseId = licenseId;
          cat.isSynced = 0;
          await txn.insert('categories', cat.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
        }

        // 2. Insert Items
        for (var item in selectedItems) {
          item.licenseId = licenseId;
          item.isSynced = 0;
          // Ensure prices are set as per template
          await txn.insert('items', item.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      });

      // Refresh providers to show new data
      await itemProvider.refreshData();
      await catProvider.fetchCategories();
      return true;
    } catch (e) {
      debugPrint("Injection Error: $e");
      return false;
    }
  }
}
