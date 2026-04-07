import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
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
import '../models/staff_model.dart';
import '../models/category_model.dart';
import '../models/supplier_model.dart';
import '../models/transaction_model.dart';
import 'profile_provider.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class SyncProvider with ChangeNotifier {
  final FirebaseService _firebaseService = FirebaseService();
  bool _isSyncing = false;
  double _syncProgress = 0.0;
  String _syncStatus = "";
  int _estimatedSecondsRemaining = 0;
  Timer? _autoSyncTimer;

  bool get isSyncing => _isSyncing;
  double get syncProgress => _syncProgress;
  String get syncStatus => _syncStatus;
  int get estimatedSecondsRemaining => _estimatedSecondsRemaining;

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

  Future<void> syncAllToCloudSilently() async {
    if (_isSyncing) return;
    try {
      final db = DatabaseHelper.instance;
      
      final unsyncedCats = await db.getUnsyncedData('categories');
      for (var map in unsyncedCats) {
        final cat = CategoryModel.fromMap(map);
        await _firebaseService.syncCategory(cat);
        await db.updateSyncStatus('categories', cat.id!, 1);
      }

      final unsyncedItems = await db.getUnsyncedData('items');
      for (var map in unsyncedItems) {
        final item = ItemModel.fromMap(map);
        await _firebaseService.syncItem(item);
        await db.updateSyncStatus('items', item.id!, 1);
      }

      final unsyncedStaff = await db.getUnsyncedData('staff');
      for (var map in unsyncedStaff) {
        final staff = StaffModel.fromMap(map);
        await _firebaseService.syncStaff(staff);
        await db.updateSyncStatus('staff', staff.id!, 1);
      }

      final unsyncedSuppliers = await db.getUnsyncedData('suppliers');
      for (var map in unsyncedSuppliers) {
        final supplier = SupplierModel.fromMap(map);
        await _firebaseService.syncSupplier(supplier);
        await db.updateSyncStatus('suppliers', supplier.id!, 1);
      }

      final unsyncedTxs = await db.getUnsyncedTransactions();
      for (var tx in unsyncedTxs) {
        await _firebaseService.syncTransaction(tx);
        await db.updateTransactionSyncStatus(tx.id!, 1);
      }
      
      debugPrint("Auto-sync completed successfully at ${DateTime.now()}");
    } catch (e) {
      debugPrint("Silent Sync Error: $e");
    }
  }

  Future<bool> manualSyncToCloud(BuildContext context) async {
    if (_isSyncing) return false;
    
    _isSyncing = true;
    _syncProgress = 0.0;
    _syncStatus = "Preparing data...";
    notifyListeners();

    try {
      final db = DatabaseHelper.instance;
      final profile = Provider.of<ProfileProvider>(context, listen: false);

      // 1. Sync Profile
      _syncStatus = "Uploading profile...";
      await _firebaseService.syncProfile(profile.getProfileMap());
      _syncProgress = 0.1;
      notifyListeners();

      // 2. Categories
      _syncStatus = "Uploading categories...";
      final allCats = await db.getAllCategories();
      for (int i = 0; i < allCats.length; i++) {
        await _firebaseService.syncCategory(allCats[i]);
        await db.updateSyncStatus('categories', allCats[i].id!, 1);
        _syncProgress = 0.1 + (0.15 * (i + 1) / (allCats.isEmpty ? 1 : allCats.length));
        notifyListeners();
      }

      // 3. Items
      _syncStatus = "Uploading items...";
      final allItems = await db.getAllItems();
      for (int i = 0; i < allItems.length; i++) {
        await _firebaseService.syncItem(allItems[i]);
        await db.updateSyncStatus('items', allItems[i].id!, 1);
        _syncProgress = 0.25 + (0.2 * (i + 1) / (allItems.isEmpty ? 1 : allItems.length));
        notifyListeners();
      }

      // 4. Staff
      _syncStatus = "Uploading staff...";
      final allStaff = await db.getAllStaff();
      for (int i = 0; i < allStaff.length; i++) {
        await _firebaseService.syncStaff(allStaff[i]);
        await db.updateSyncStatus('staff', allStaff[i].id!, 1);
        _syncProgress = 0.45 + (0.1 * (i + 1) / (allStaff.isEmpty ? 1 : allStaff.length));
        notifyListeners();
      }

      // 5. Suppliers
      _syncStatus = "Uploading suppliers...";
      final allSuppliers = await db.getAllSuppliers();
      for (int i = 0; i < allSuppliers.length; i++) {
        await _firebaseService.syncSupplier(allSuppliers[i]);
        await db.updateSyncStatus('suppliers', allSuppliers[i].id!, 1);
        _syncProgress = 0.55 + (0.05 * (i + 1) / (allSuppliers.isEmpty ? 1 : allSuppliers.length));
        notifyListeners();
      }

      // 6. Units
      _syncStatus = "Uploading units...";
      final allUnits = await db.getAllUnits();
      for (var unit in allUnits) {
        await _firebaseService.syncUnit(unit);
      }
      _syncProgress = 0.65;
      notifyListeners();

      // 7. Transactions
      _syncStatus = "Uploading transactions...";
      final allTxs = await db.getAllTransactions();
      for (int i = 0; i < allTxs.length; i++) {
        await _firebaseService.syncTransaction(allTxs[i]);
        await db.updateTransactionSyncStatus(allTxs[i].id!, 1);
        _syncProgress = 0.65 + (0.35 * (i + 1) / (allTxs.isEmpty ? 1 : allTxs.length));
        notifyListeners();
      }

      _syncStatus = "Sync Complete!";
      _syncProgress = 1.0;
      notifyListeners();
      return true;
    } catch (e) {
      _syncStatus = "Sync Failed: $e";
      notifyListeners();
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<bool> fullRestoreFromServer(BuildContext context) async {
    if (_isSyncing) return false;
    
    _isSyncing = true;
    _syncProgress = 0.0;
    _syncStatus = "Connecting to secure cloud...";
    notifyListeners();

    try {
      final cloudData = await _firebaseService.fetchAllUserData();
      
      _syncProgress = 0.1;
      _syncStatus = "Cleaning local database...";
      notifyListeners();
      await DatabaseHelper.instance.clearAllData();

      // 1. Profile
      _syncStatus = "Restoring profile...";
      if (cloudData['profile'] != null) {
        final profile = Provider.of<ProfileProvider>(context, listen: false);
        await profile.loadFromMap(cloudData['profile']);
      }
      _syncProgress = 0.2;
      notifyListeners();

      // 2. Categories
      _syncStatus = "Restoring categories...";
      final categories = cloudData['categories'] ?? [];
      for (var cat in categories) {
        // Mark as synced before insert
        await DatabaseHelper.instance.insertCategory(cat);
      }
      _syncProgress = 0.35;
      notifyListeners();

      // 3. Items
      _syncStatus = "Restoring items...";
      final items = cloudData['items'] ?? [];
      for (var item in items) {
        item.isSynced = 1;
        await DatabaseHelper.instance.insertItem(item);
      }
      _syncProgress = 0.5;
      notifyListeners();

      // 4. Staff
      _syncStatus = "Restoring staff...";
      final staff = cloudData['staff'] ?? [];
      for (var s in staff) {
        s.isSynced = 1;
        await DatabaseHelper.instance.insertStaff(s);
      }
      _syncProgress = 0.6;
      notifyListeners();

      // 5. Suppliers
      _syncStatus = "Restoring suppliers...";
      final suppliers = cloudData['suppliers'] ?? [];
      for (var sup in suppliers) {
        sup.isSynced = 1;
        await DatabaseHelper.instance.insertSupplier(sup);
      }
      _syncProgress = 0.7;
      notifyListeners();

      // 6. Units
      _syncStatus = "Restoring units...";
      final units = cloudData['units'] ?? [];
      for (var unit in units) {
        await DatabaseHelper.instance.insertUnit(unit['name']);
      }
      _syncProgress = 0.75;
      notifyListeners();

      // 7. Purchase Reminders
      _syncStatus = "Restoring reminders...";
      final reminders = cloudData['purchase_reminders'] ?? [];
      for (var r in reminders) {
        r.isSynced = 1;
        final db = await DatabaseHelper.instance.database;
        await db.insert('purchase_reminders', r.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      _syncProgress = 0.8;
      notifyListeners();

      // 8. Transactions
      _syncStatus = "Restoring transactions...";
      final List<TransactionModel> transactions = cloudData['transactions'] ?? [];
      for (int i = 0; i < transactions.length; i++) {
        final tx = transactions[i];
        tx.isSynced = 1;
        await DatabaseHelper.instance.insertTransaction(tx);
        _syncProgress = 0.8 + (0.2 * (i + 1) / (transactions.isEmpty ? 1 : transactions.length));
        notifyListeners();
      }
      
      _syncProgress = 1.0;
      _syncStatus = "Restore Complete!";
      notifyListeners();

      // Refresh providers
      if (context.mounted) {
        Provider.of<CategoryProvider>(context, listen: false).fetchCategories();
        Provider.of<ItemProvider>(context, listen: false).fetchItems();
        Provider.of<TransactionProvider>(context, listen: false).fetchTransactions();
        Provider.of<StaffProvider>(context, listen: false).fetchStaff();
        Provider.of<SupplierProvider>(context, listen: false).fetchSuppliers();
        Provider.of<UnitProvider>(context, listen: false).fetchUnits();
        Provider.of<PurchaseReminderProvider>(context, listen: false).fetchReminders();
      }

      return true;
    } catch (e) {
      _syncStatus = "Restore Failed: $e";
      notifyListeners();
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }
}
