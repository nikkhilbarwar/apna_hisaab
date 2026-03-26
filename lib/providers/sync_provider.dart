import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/firebase_service.dart';
import '../core/database/database_helper.dart';
import 'transaction_provider.dart';
import 'item_provider.dart';
import 'category_provider.dart';
import 'staff_provider.dart';
import 'supplier_provider.dart';
import '../models/item_model.dart';
import '../models/staff_model.dart';
import '../models/category_model.dart';
import '../models/supplier_model.dart';
import 'dart:async';
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
    // 5 minutes auto sync as requested
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
      
      // 1. Sync Categories
      final unsyncedCats = await db.getUnsyncedData('categories');
      for (var map in unsyncedCats) {
        final cat = CategoryModel.fromMap(map);
        await _firebaseService.syncCategory(cat);
        await db.updateSyncStatus('categories', cat.id!, 1);
      }

      // 2. Sync Items (Inventory)
      final unsyncedItems = await db.getUnsyncedData('items');
      for (var map in unsyncedItems) {
        final item = ItemModel.fromMap(map);
        await _firebaseService.syncItem(item);
        await db.updateSyncStatus('items', item.id!, 1);
      }

      // 3. Sync Staff & Salaries
      final unsyncedStaff = await db.getUnsyncedData('staff');
      for (var map in unsyncedStaff) {
        final staff = StaffModel.fromMap(map);
        await _firebaseService.syncStaff(staff);
        await db.updateSyncStatus('staff', staff.id!, 1);
      }

      // 4. Sync Suppliers
      final unsyncedSuppliers = await db.getUnsyncedData('suppliers');
      for (var map in unsyncedSuppliers) {
        final supplier = SupplierModel.fromMap(map);
        await _firebaseService.syncSupplier(supplier);
        await db.updateSyncStatus('suppliers', supplier.id!, 1);
      }

      // 5. Sync Transactions
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

  Future<bool> fullRestoreFromServer(BuildContext context) async {
    if (_isSyncing) return false;
    
    _isSyncing = true;
    _syncProgress = 0.1;
    _syncStatus = "Connecting to cloud...";
    notifyListeners();

    try {
      // 1. Fetch all data from Firebase
      final cloudData = await _firebaseService.fetchAllUserData();
      
      _syncStatus = "Clearing local database...";
      _syncProgress = 0.3;
      notifyListeners();

      // 2. Clear Local DB
      await DatabaseHelper.instance.clearAllData();

      // 3. Insert Categories
      _syncStatus = "Restoring Categories...";
      final categories = cloudData['categories'] ?? [];
      for (var cat in categories) {
        await DatabaseHelper.instance.insertCategory(cat);
      }
      _syncProgress = 0.5;
      notifyListeners();

      // 4. Insert Items (Stock/Inventory)
      _syncStatus = "Restoring Inventory...";
      final items = cloudData['items'] ?? [];
      for (var item in items) {
        await DatabaseHelper.instance.insertItem(item);
      }
      _syncProgress = 0.7;
      notifyListeners();

      // 5. Insert Staff & Salary info
      _syncStatus = "Restoring Staff details...";
      final staff = cloudData['staff'] ?? [];
      for (var s in staff) {
        await DatabaseHelper.instance.insertStaff(s);
      }

      // 6. Insert Suppliers
      _syncStatus = "Restoring Suppliers...";
      final suppliers = cloudData['suppliers'] ?? [];
      for (var sup in suppliers) {
        await DatabaseHelper.instance.insertSupplier(sup);
      }
      
      // 7. Insert Transactions
      _syncStatus = "Restoring Transactions...";
      final transactions = cloudData['transactions'] ?? [];
      for (var tx in transactions) {
        await DatabaseHelper.instance.insertTransaction(tx);
      }
      
      _syncProgress = 1.0;
      _syncStatus = "Sync Complete!";
      notifyListeners();

      // 8. Refresh all Providers to show new data on UI
      if (context.mounted) {
        Provider.of<CategoryProvider>(context, listen: false).fetchCategories();
        Provider.of<ItemProvider>(context, listen: false).fetchItems();
        Provider.of<TransactionProvider>(context, listen: false).fetchTransactions();
        Provider.of<StaffProvider>(context, listen: false).fetchStaff();
        Provider.of<SupplierProvider>(context, listen: false).fetchSuppliers();
      }

      return true;
    } catch (e) {
      _syncStatus = "Restore Failed: $e";
      debugPrint("Full Restore Error: $e");
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }
}
