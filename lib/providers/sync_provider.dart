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
      
      // Silent sync logic (No UI update needed for progress here typically)
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

  Future<bool> fullRestoreFromServer(BuildContext context) async {
    if (_isSyncing) return false;
    
    _isSyncing = true;
    _syncProgress = 0.0;
    _syncStatus = "Connecting to secure cloud...";
    _estimatedSecondsRemaining = 25; // Initial estimate
    notifyListeners();

    // Start a dummy countdown timer for the estimated time
    Timer? countdown;
    countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_estimatedSecondsRemaining > 2) {
        _estimatedSecondsRemaining--;
        notifyListeners();
      } else {
        countdown?.cancel();
      }
    });

    try {
      // 1. Fetch data
      _syncProgress = 0.1;
      notifyListeners();
      final cloudData = await _firebaseService.fetchAllUserData();
      
      _syncProgress = 0.25;
      _syncStatus = "Cleaning local database for fresh restore...";
      notifyListeners();
      await DatabaseHelper.instance.clearAllData();

      // 3. Categories
      _syncProgress = 0.35;
      _syncStatus = "Restoring Product Categories...";
      notifyListeners();
      final categories = cloudData['categories'] ?? [];
      for (var cat in categories) {
        await DatabaseHelper.instance.insertCategory(cat);
      }

      // 4. Items
      _syncProgress = 0.55;
      _syncStatus = "Downloading Inventory Stock...";
      notifyListeners();
      final items = cloudData['items'] ?? [];
      for (var item in items) {
        await DatabaseHelper.instance.insertItem(item);
      }

      // 5. Staff & Salaries
      _syncProgress = 0.70;
      _syncStatus = "Restoring Staff and Salary data...";
      notifyListeners();
      final staff = cloudData['staff'] ?? [];
      for (var s in staff) {
        await DatabaseHelper.instance.insertStaff(s);
      }

      // 6. Suppliers
      _syncStatus = "Updating Supplier information...";
      final suppliers = cloudData['suppliers'] ?? [];
      for (var sup in suppliers) {
        await DatabaseHelper.instance.insertSupplier(sup);
      }
      
      // 7. Transactions
      _syncProgress = 0.85;
      _syncStatus = "Finalizing Transaction History...";
      notifyListeners();
      final transactions = cloudData['transactions'] ?? [];
      for (var tx in transactions) {
        await DatabaseHelper.instance.insertTransaction(tx);
      }
      
      _syncProgress = 1.0;
      _estimatedSecondsRemaining = 0;
      _syncStatus = "Data successfully restored!";
      notifyListeners();
      countdown.cancel();

      // Refresh providers
      if (context.mounted) {
        Provider.of<CategoryProvider>(context, listen: false).fetchCategories();
        Provider.of<ItemProvider>(context, listen: false).fetchItems();
        Provider.of<TransactionProvider>(context, listen: false).fetchTransactions();
        Provider.of<StaffProvider>(context, listen: false).fetchStaff();
        Provider.of<SupplierProvider>(context, listen: false).fetchSuppliers();
      }

      return true;
    } catch (e) {
      _syncStatus = "Restore Failed: Check internet connection";
      debugPrint("Full Restore Error: $e");
      countdown.cancel();
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }
}
