import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  DateTime? _lastSyncTimestamp;

  bool get isSyncing => _isSyncing;
  double get syncProgress => _syncProgress;
  String get syncStatus => _syncStatus;
  DateTime? get lastSyncTimestamp => _lastSyncTimestamp;

  SyncProvider() {
    _loadLastSyncTime();
    _startAutoSync();
  }

  Future<void> _loadLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    final timeStr = prefs.getString('last_sync_timestamp_$uid');
    if (timeStr != null) {
      _lastSyncTimestamp = DateTime.tryParse(timeStr);
    }
  }

  Future<void> _saveLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    _lastSyncTimestamp = DateTime.now();
    await prefs.setString('last_sync_timestamp_$uid', _lastSyncTimestamp!.toIso8601String());
  }

  void _startAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.any((result) => result != ConnectivityResult.none)) {
        // Run background delta push and pull
        await syncAllToCloudSilently();
        await syncCloudToLocalSilently();
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
      
      // 1. Items
      final unsyncedItems = await db.getUnsyncedData('items');
      if (unsyncedItems.isNotEmpty) {
        await _firebaseService.syncBatch('items', unsyncedItems);
        for (var map in unsyncedItems) await db.updateSyncStatus('items', map['id'], 1);
      }

      // 2. Categories
      final unsyncedCats = await db.getUnsyncedData('categories');
      if (unsyncedCats.isNotEmpty) {
        await _firebaseService.syncBatch('categories', unsyncedCats);
        for (var map in unsyncedCats) await db.updateSyncStatus('categories', map['id'], 1);
      }

      // 3. Recipes
      final unsyncedRecipes = await db.getUnsyncedData('recipes');
      if (unsyncedRecipes.isNotEmpty) {
        await _firebaseService.syncBatch('recipes', unsyncedRecipes);
        for (var map in unsyncedRecipes) await db.updateSyncStatus('recipes', map['id'], 1);
      }

      // 4. Staff
      final unsyncedStaff = await db.getUnsyncedData('staff');
      if (unsyncedStaff.isNotEmpty) {
        await _firebaseService.syncBatch('staff', unsyncedStaff);
        for (var map in unsyncedStaff) await db.updateSyncStatus('staff', map['id'], 1);
      }

      // 5. Staff Advances & Leaves
      final unsyncedAdvances = await db.getUnsyncedData('staff_advance');
      if (unsyncedAdvances.isNotEmpty) {
        await _firebaseService.syncBatch('staff_advance', unsyncedAdvances);
        for (var map in unsyncedAdvances) await db.updateSyncStatus('staff_advance', map['id'], 1);
      }

      final unsyncedLeaves = await db.getUnsyncedData('staff_leave');
      if (unsyncedLeaves.isNotEmpty) {
        await _firebaseService.syncBatch('staff_leave', unsyncedLeaves);
        for (var map in unsyncedLeaves) await db.updateSyncStatus('staff_leave', map['id'], 1);
      }

      // 6. Transactions
      final unsyncedTxs = await db.getUnsyncedTransactions();
      if (unsyncedTxs.isNotEmpty) {
        // Individual sync for transactions to handle larger objects and safety
        for (var tx in unsyncedTxs) {
          final success = await _firebaseService.syncTransaction(tx);
          if (success) await db.updateTransactionSyncStatus(tx.id!, 1);
        }
      }

      // 7. Suppliers & Reminders
      final unsyncedSuppliers = await db.getUnsyncedData('suppliers');
      if (unsyncedSuppliers.isNotEmpty) {
        await _firebaseService.syncBatch('suppliers', unsyncedSuppliers);
        for (var map in unsyncedSuppliers) await db.updateSyncStatus('suppliers', map['id'], 1);
      }

      final unsyncedReminders = await db.getUnsyncedData('purchase_reminders');
      if (unsyncedReminders.isNotEmpty) {
        await _firebaseService.syncBatch('purchase_reminders', unsyncedReminders);
        for (var map in unsyncedReminders) await db.updateSyncStatus('purchase_reminders', map['id'], 1);
      }
      
      debugPrint("Auto-sync (Push) completed at ${DateTime.now()}");
    } catch (e) {
      debugPrint("Silent Sync Push Error: $e");
    }
  }

  Future<void> syncCloudToLocalSilently({BuildContext? context}) async {
    if (_isSyncing) return;
    try {
      final db = DatabaseHelper.instance;
      bool hasUpdates = false;
      
      // 1. Items
      final cloudItems = await _firebaseService.fetchAllItems(since: _lastSyncTimestamp);
      if (cloudItems.isNotEmpty) {
        await db.smartMerge('items', cloudItems.map((i) => (i..isSynced = 1).toMap()).toList());
        hasUpdates = true;
      }

      // 2. Transactions
      final cloudTxs = await _firebaseService.fetchAllTransactions(since: _lastSyncTimestamp);
      if (cloudTxs.isNotEmpty) {
        await db.smartMerge('transactions', cloudTxs.map((t) => (t..isSynced = 1).toMap()).toList());
        hasUpdates = true;
      }

      // 3. Categories
      final cloudCats = await _firebaseService.fetchAllCategories(since: _lastSyncTimestamp);
      if (cloudCats.isNotEmpty) {
        await db.smartMerge('categories', cloudCats.map((c) => (c..isSynced = 1).toMap()).toList());
        hasUpdates = true;
      }

      // 4. Staff & Related
      final cloudStaff = await _firebaseService.fetchAllStaff(since: _lastSyncTimestamp);
      if (cloudStaff.isNotEmpty) {
        await db.smartMerge('staff', cloudStaff.map((s) => (s..isSynced = 1).toMap()).toList());
        hasUpdates = true;
      }

      final cloudAdvances = await _firebaseService.fetchAllStaffAdvances(since: _lastSyncTimestamp);
      if (cloudAdvances.isNotEmpty) {
        await db.smartMerge('staff_advance', cloudAdvances.map((a) => (a..isSynced = 1).toMap()).toList());
        hasUpdates = true;
      }

      final cloudLeaves = await _firebaseService.fetchAllStaffLeaves(since: _lastSyncTimestamp);
      if (cloudLeaves.isNotEmpty) {
        await db.smartMerge('staff_leave', cloudLeaves.map((l) => (l..isSynced = 1).toMap()).toList());
        hasUpdates = true;
      }

      // 5. Recipes
      final cloudRecipes = await _firebaseService.fetchAllRecipes(since: _lastSyncTimestamp);
      if (cloudRecipes.isNotEmpty) {
        await db.smartMerge('recipes', cloudRecipes.map((r) => (r..isSynced = 1).toMap()).toList());
        hasUpdates = true;
      }

      // 6. Suppliers & Reminders
      final cloudSuppliers = await _firebaseService.fetchAllSuppliers(since: _lastSyncTimestamp);
      if (cloudSuppliers.isNotEmpty) {
        await db.smartMerge('suppliers', cloudSuppliers.map((s) => (s..isSynced = 1).toMap()).toList());
        hasUpdates = true;
      }

      final cloudReminders = await _firebaseService.fetchAllPurchaseReminders(since: _lastSyncTimestamp);
      if (cloudReminders.isNotEmpty) {
        await db.smartMerge('purchase_reminders', cloudReminders.map((r) => (r..isSynced = 1).toMap()).toList());
        hasUpdates = true;
      }

      if (hasUpdates && context != null && context.mounted) {
        _refreshProviders(context);
      }

      await _saveLastSyncTime();
      debugPrint("Cloud-to-Local delta sync (Pull) completed at ${DateTime.now()}");
    } catch (e) {
      debugPrint("Delta Sync Pull Error: $e");
    }
  }

  void _refreshProviders(BuildContext context) {
    Provider.of<ItemProvider>(context, listen: false).refreshData();
    Provider.of<CategoryProvider>(context, listen: false).fetchCategories();
    Provider.of<TransactionProvider>(context, listen: false).fetchTransactions();
    Provider.of<StaffProvider>(context, listen: false).fetchStaff();
    Provider.of<SupplierProvider>(context, listen: false).fetchSuppliers();
    Provider.of<UnitProvider>(context, listen: false).fetchUnits();
    Provider.of<PurchaseReminderProvider>(context, listen: false).fetchReminders();
    Provider.of<ProfileProvider>(context, listen: false).loadProfile();
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
      await _saveLastSyncTime(); // Update timestamp on manual sync success
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
