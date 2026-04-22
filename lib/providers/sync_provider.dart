import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/purchase_reminder_model.dart';
import '../models/staff_model.dart'; // Added missing imports
import '../models/recipe_model.dart'; // Added missing imports
import '../services/firebase_service.dart';
import '../core/database/database_helper.dart';
import 'transaction_provider.dart';
import 'item_provider.dart';
import 'category_provider.dart';
import 'staff_provider.dart';
import 'supplier_provider.dart';
import 'unit_provider.dart';
import 'purchase_reminder_provider.dart';
import '../models/item_model.dart';
import '../models/category_model.dart';
import '../models/supplier_model.dart';
import '../models/transaction_model.dart';
import 'profile_provider.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:connectivity_plus/connectivity_plus.dart';

class SyncProvider with ChangeNotifier {
  final FirebaseService _firebaseService = FirebaseService();
  bool _isSyncing = false;
  double _syncProgress = 0.0;
  String _syncStatus = "";
  Timer? _autoSyncTimer;

  bool get isSyncing => _isSyncing;
  double get syncProgress => _syncProgress;
  String get syncStatus => _syncStatus;

  SyncProvider() {
    _startAutoSync();
  }

  void _startAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.any((result) => result != ConnectivityResult.none)) {
        await syncAllToCloudSilently();
      }
    });
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  void resetSync() {
    _isSyncing = false;
    _syncProgress = 0.0;
    _syncStatus = "Sync reset. You can try again.";
    notifyListeners();
  }

  Future<void> syncAllToCloudSilently() async {
    if (_isSyncing) return;
    try {
      final db = DatabaseHelper.instance;
      
      // Batch sync for efficiency
      final unsyncedItems = await db.getUnsyncedData('items');
      if (unsyncedItems.isNotEmpty) {
        await _firebaseService.syncBatch('items', unsyncedItems);
        for (var map in unsyncedItems) {
          await db.updateSyncStatus('items', map['id'], 1);
        }
      }

      final unsyncedRecipes = await db.getUnsyncedData('recipes');
      if (unsyncedRecipes.isNotEmpty) {
        await _firebaseService.syncBatch('recipes', unsyncedRecipes);
        for (var map in unsyncedRecipes) {
          await db.updateSyncStatus('recipes', map['id'], 1);
        }
      }

      final unsyncedTxs = await db.getUnsyncedTransactions();
      if (unsyncedTxs.isNotEmpty) {
        for (var tx in unsyncedTxs) {
          await _firebaseService.syncTransaction(tx);
          await db.updateTransactionSyncStatus(tx.id!, 1);
        }
      }
      
      debugPrint("Auto-sync completed at ${DateTime.now()}");
    } catch (e) {
      debugPrint("Silent Sync Error: $e");
    }
  }

  Future<bool> manualSyncToCloud(BuildContext context) async {
    if (_isSyncing) return false;
    
    _isSyncing = true;
    _syncProgress = 0.0;
    _syncStatus = "Preparing high-speed sync...";
    notifyListeners();

    try {
      final db = DatabaseHelper.instance;
      final profile = Provider.of<ProfileProvider>(context, listen: false);

      // 1. Profile
      _progress(0.05, "Uploading business profile...");
      await _firebaseService.syncProfile(profile.getProfileMap());

      // 2. Categories
      _progress(0.15, "Uploading categories...");
      final allCats = await db.getAllCategories();
      await _firebaseService.syncBatch('categories', allCats.map((e) => e.toMap()).toList());
      for (var c in allCats) await db.updateSyncStatus('categories', c.id!, 1);

      // 3. Items
      _progress(0.35, "Uploading all items...");
      final allItems = await db.getAllItems();
      await _firebaseService.syncBatch('items', allItems.map((e) => e.toMap()).toList());
      for (var i in allItems) await db.updateSyncStatus('items', i.id!, 1);

      // 3.1 Recipes
      _progress(0.40, "Uploading recipes...");
      final unsyncedRecipes = await db.getUnsyncedData('recipes');
      if (unsyncedRecipes.isNotEmpty) {
        await _firebaseService.syncBatch('recipes', unsyncedRecipes);
        for (var r in unsyncedRecipes) {
          await db.updateSyncStatus('recipes', r['id'], 1);
        }
      }

      // 4. Staff & Images
      _progress(0.50, "Uploading staff details...");
      final allStaff = await db.getAllStaff();
      for (var staff in allStaff) {
        if (staff.imagePath != null && staff.imagePath!.isNotEmpty) {
          final file = File(staff.imagePath!);
          if (await file.exists()) {
            final imageUrl = await _firebaseService.uploadStaffImage(file, staff.id.toString());
            if (imageUrl != null) staff.imageUrl = imageUrl;
          }
        }
        await _firebaseService.syncStaff(staff);
        await db.updateSyncStatus('staff', staff.id!, 1);
      }

      // 5. Transactions (Batching these might be too large, doing individual but fast)
      _progress(0.70, "Uploading transactions...");
      final allTxs = await db.getAllTransactions();
      for (int i = 0; i < allTxs.length; i++) {
        await _firebaseService.syncTransaction(allTxs[i]);
        await db.updateTransactionSyncStatus(allTxs[i].id!, 1);
        if (i % 20 == 0) {
           _progress(0.70 + (0.30 * (i / allTxs.length)), "Uploading transactions (${i}/${allTxs.length})...");
        }
      }

      _progress(1.0, "All data synced successfully!");
      return true;
    } catch (e) {
      _progress(0.0, "Sync Error: $e");
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<bool> fullRestoreFromServer(BuildContext context) async {
    if (_isSyncing) return false;
    
    _isSyncing = true;
    _progress(0.0, "Connecting to cloud backup...");

    try {
      final cloudData = await _firebaseService.fetchAllUserData();
      
      _progress(0.1, "Securing local database...");
      await DatabaseHelper.instance.clearAllData();

      // Restore Profile
      if (cloudData['profile'] != null) {
        final profile = Provider.of<ProfileProvider>(context, listen: false);
        await profile.loadFromMap(cloudData['profile']);
      }

      final db = DatabaseHelper.instance;

      // Restore Categories (MUST BE FIRST)
      _progress(0.2, "Restoring categories...");
      final categories = cloudData['categories'] as List<CategoryModel>;
      if (categories.isNotEmpty) {
        await db.batchInsert('categories', categories.map((c) => (c..isSynced = 1).toMap()).toList());
      }

      // Restore Items
      _progress(0.3, "Restoring items...");
      final items = cloudData['items'] as List<ItemModel>;
      if (items.isNotEmpty) {
        await db.batchInsert('items', items.map((i) => (i..isSynced = 1).toMap()).toList());
      }

      // Restore Staff
      _progress(0.4, "Restoring staff & photos...");
      final staffList = cloudData['staff'] as List<StaffModel>;
      if (staffList.isNotEmpty) {
        // Process staff images if any
        for (var staff in staffList) {
          if (staff.imageUrl != null && staff.imageUrl!.startsWith('base64:')) {
            final path = await _saveBase64ToFile(staff.imageUrl!, "staff_${staff.id}");
            if (path != null) staff.imagePath = path;
          }
          staff.isSynced = 1;
        }
        await db.batchInsert('staff', staffList.map((s) => s.toMap()).toList());
      }

      // Restore Staff Advances
      final advances = cloudData['staff_advances'] as List<StaffAdvanceModel>;
      if (advances.isNotEmpty) {
        await db.batchInsert('staff_advance', advances.map((a) => (a..isSynced = 1).toMap()).toList());
      }

      // Restore Staff Leaves
      final leaves = cloudData['staff_leaves'] as List<StaffLeaveModel>;
      if (leaves.isNotEmpty) {
        await db.batchInsert('staff_leave', leaves.map((l) => (l..isSynced = 1).toMap()).toList());
      }

      // Restore Suppliers
      _progress(0.5, "Restoring suppliers...");
      final suppliers = cloudData['suppliers'] as List<SupplierModel>;
      if (suppliers.isNotEmpty) {
        await db.batchInsert('suppliers', suppliers.map((s) => s.toMap()).toList());
      }

      // Restore Units
      final units = cloudData['units'] as List<Map<String, dynamic>>;
      if (units.isNotEmpty) {
        for (var unit in units) {
          await db.insertUnit(unit['name'] ?? "", id: unit['id'], isSynced: 1);
        }
      }

      // Restore Purchase Reminders
      _progress(0.6, "Restoring reminders...");
      final reminders = cloudData['purchase_reminders'] as List<PurchaseReminderModel>;
      if (reminders.isNotEmpty) {
        await db.batchInsert('purchase_reminders', reminders.map((r) => (r..isSynced = 1).toMap()).toList());
      }

      // Restore Recipes
      _progress(0.7, "Restoring recipes...");
      final recipes = cloudData['recipes'] as List<RecipeModel>;
      if (recipes.isNotEmpty) {
        await db.batchInsert('recipes', recipes.map((r) => (r..isSynced = 1).toMap()).toList());
      }

      // Restore Transactions
      _progress(0.8, "Restoring transactions...");
      final txs = cloudData['transactions'] as List<TransactionModel>;
      if (txs.isNotEmpty) {
        // Transactions can be many, but batchInsert handles it
        await db.batchInsert('transactions', txs.map((t) => (t..isSynced = 1).toMap()).toList());
      }

      // Refresh UI
      if (context.mounted) {
        _progress(0.95, "Refreshing app data...");
        await Future.wait([
          Provider.of<ItemProvider>(context, listen: false).refreshData(),
          Provider.of<CategoryProvider>(context, listen: false).fetchCategories(),
          Provider.of<TransactionProvider>(context, listen: false).fetchTransactions(),
          Provider.of<StaffProvider>(context, listen: false).fetchStaff(),
          Provider.of<SupplierProvider>(context, listen: false).fetchSuppliers(),
          Provider.of<UnitProvider>(context, listen: false).fetchUnits(),
          Provider.of<PurchaseReminderProvider>(context, listen: false).fetchReminders(),
          Provider.of<ProfileProvider>(context, listen: false).loadProfile(),
        ]);
      }

      _progress(1.0, "Restore completed successfully!");
      return true;
    } catch (e) {
      debugPrint("Restore Error: $e");
      _progress(0.0, "Restore failed: $e");
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  void _progress(double p, String s) {
    _syncProgress = p;
    _syncStatus = s;
    notifyListeners();
  }

  Future<String?> _saveBase64ToFile(String base64Data, String fileName) async {
    try {
      final String pureBase64 = base64Data.replaceFirst('base64:', '');
      final bytes = base64Decode(pureBase64);
      final directory = await getApplicationDocumentsDirectory();
      final String filePath = p.join(directory.path, '${fileName}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      return filePath;
    } catch (e) {
      debugPrint("Error saving base64 image: $e");
      return null;
    }
  }
}
