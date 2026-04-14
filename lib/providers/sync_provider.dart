import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/purchase_reminder_model.dart';
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

      final unsyncedAdvances = await db.getUnsyncedData('staff_advance');
      for (var map in unsyncedAdvances) {
        final advance = StaffAdvanceModel.fromMap(map);
        await _firebaseService.syncStaffAdvance(advance);
        await db.updateSyncStatus('staff_advance', advance.id!, 1);
      }

      final unsyncedLeaves = await db.getUnsyncedData('staff_leave');
      for (var map in unsyncedLeaves) {
        final leave = StaffLeaveModel.fromMap(map);
        await _firebaseService.syncStaffLeave(leave);
        await db.updateSyncStatus('staff_leave', leave.id!, 1);
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
      _syncProgress = 0.05;
      if (context.mounted) notifyListeners();

      // 1.1 Sync Purchase Reminders
      _syncStatus = "Uploading reminders...";
      final allRemindersRaw = await (await db.database).query('purchase_reminders');
      for (var map in allRemindersRaw) {
        final reminder = PurchaseReminderModel.fromMap(map);
        await _firebaseService.syncPurchaseReminder(reminder);
        await db.updateSyncStatus('purchase_reminders', reminder.id!, 1);
      }
      _syncProgress = 0.1;
      notifyListeners();

      // 2. Categories
      _syncStatus = "Uploading categories...";
      final allCats = await db.getAllCategories();
      for (int i = 0; i < allCats.length; i++) {
        await _firebaseService.syncCategory(allCats[i]);
        await db.updateSyncStatus('categories', allCats[i].id!, 1);
        if (i % 5 == 0 || i == allCats.length - 1) {
          _progress(0.1 + (0.15 * (i + 1) / (allCats.isEmpty ? 1 : allCats.length)), "Uploading categories...");
        }
      }

      // 3. Items
      _syncStatus = "Uploading items...";
      final allItems = await db.getAllItems();
      for (int i = 0; i < allItems.length; i++) {
        await _firebaseService.syncItem(allItems[i]);
        await db.updateSyncStatus('items', allItems[i].id!, 1);
        if (i % 10 == 0 || i == allItems.length - 1) {
          _progress(0.25 + (0.2 * (i + 1) / (allItems.isEmpty ? 1 : allItems.length)), "Uploading items...");
        }
      }

      // 4. Staff
      _syncStatus = "Uploading staff...";
      final allStaff = await db.getAllStaff();
      for (int i = 0; i < allStaff.length; i++) {
        final staff = allStaff[i];
        // Upload image to Firebase Storage if exists locally
        if (staff.imagePath != null && staff.imagePath!.isNotEmpty) {
          final file = File(staff.imagePath!);
          if (await file.exists()) {
            _syncStatus = "Uploading image for ${staff.name}...";
            notifyListeners();
            final imageUrl = await _firebaseService.uploadStaffImage(file, staff.id.toString());
            if (imageUrl != null) {
              staff.imageUrl = imageUrl;
            }
          }
        }
        await _firebaseService.syncStaff(staff);
        await db.updateSyncStatus('staff', staff.id!, 1);
        _syncProgress = 0.45 + (0.1 * (i + 1) / (allStaff.isEmpty ? 1 : allStaff.length));
        notifyListeners();
      }

      // 5. Staff Advances
      _syncStatus = "Uploading advances...";
      final allAdvancesRaw = await db.database.then((d) => d.query('staff_advance'));
      for (int i = 0; i < allAdvancesRaw.length; i++) {
        final adv = StaffAdvanceModel.fromMap(allAdvancesRaw[i]);
        await _firebaseService.syncStaffAdvance(adv);
        await db.updateSyncStatus('staff_advance', adv.id!, 1);
      }
      _syncProgress = 0.52;
      notifyListeners();

      // 5.1 Staff Leaves
      _syncStatus = "Uploading leaves...";
      final allLeavesRaw = await db.database.then((d) => d.query('staff_leave'));
      for (int i = 0; i < allLeavesRaw.length; i++) {
        final leave = StaffLeaveModel.fromMap(allLeavesRaw[i]);
        await _firebaseService.syncStaffLeave(leave);
        await db.updateSyncStatus('staff_leave', leave.id!, 1);
      }
      _syncProgress = 0.55;
      notifyListeners();

      // 6. Suppliers
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
        if (i % 10 == 0 || i == allTxs.length - 1) {
          _progress(0.65 + (0.35 * (i + 1) / (allTxs.isEmpty ? 1 : allTxs.length)), "Uploading transactions...");
        }
      }

      _syncStatus = "Sync Complete!";
      _syncProgress = 1.0;
      notifyListeners();
      return true;
    } catch (e) {
      _syncStatus = "Sync Failed: $e";
      debugPrint("Sync Failed: $e");
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
      
      // Safety Check: Verify if cloud data is actually present
      final List<TransactionModel> transactions = cloudData['transactions'] ?? [];
      final List<ItemModel> items = cloudData['items'] ?? [];
      final List<CategoryModel> categories = cloudData['categories'] ?? [];
      
      if (transactions.isEmpty && items.isEmpty && categories.isEmpty) {
        _progress(0.0, "Restore Aborted: Cloud backup is empty.");
        debugPrint("SyncProvider: Restore aborted because cloud data is empty.");
        return false;
      }

      _syncProgress = 0.1;
      _syncStatus = "Cleaning local database...";
      notifyListeners();
      await DatabaseHelper.instance.clearAllData();

      // 1. Profile
      _syncStatus = "Restoring profile...";
      if (cloudData['profile'] != null && context.mounted) {
        final profile = Provider.of<ProfileProvider>(context, listen: false);
        await profile.loadFromMap(cloudData['profile']);
      }
      _syncProgress = 0.2;
      notifyListeners();

      // 2. Categories
      _syncStatus = "Restoring categories...";
      // Removed redeclaration of 'categories'
      for (var cat in categories) {
        // Sanitize category name
        cat.name = cat.name.trim();
        await DatabaseHelper.instance.insertCategory(cat);
      }
      _syncProgress = 0.35;
      notifyListeners();

      // 3. Items
      _syncStatus = "Restoring items...";
      // Removed redeclaration of 'items'
      debugPrint("SyncProvider: Found ${items.length} items on cloud.");
      for (var item in items) {
        try {
          item.isSynced = 1;
          item.name = item.name.trim();
          if (item.category.isNotEmpty) {
            item.category = item.category.trim();
          }
          await DatabaseHelper.instance.insertItem(item);
        } catch (e) {
          debugPrint("Error restoring item ${item.name}: $e");
        }
      }
      _syncProgress = 0.5;
      notifyListeners();

      // 5. Staff
      _syncStatus = "Restoring staff...";
      final staffList = cloudData['staff'] as List<StaffModel>? ?? [];
      final appDir = await getApplicationDocumentsDirectory();
      
      for (var s in staffList) {
        s.isSynced = 1;
        // If there's a cloud image, handle it (Base64 or URL)
        if (s.imageUrl != null && s.imageUrl!.isNotEmpty) {
          final fileName = 'staff_${s.id}.png';
          final localPath = p.join(appDir.path, fileName);
          final localFile = File(localPath);
          
          if (!(await localFile.exists())) {
             _syncStatus = "Restoring image for ${s.name}...";
             notifyListeners();
             
             if (s.imageUrl!.startsWith('base64:')) {
               try {
                 final base64String = s.imageUrl!.replaceFirst('base64:', '');
                 await localFile.writeAsBytes(base64Decode(base64String));
                 s.imagePath = localPath;
               } catch (e) {
                 debugPrint("Error decoding base64 image: $e");
               }
             } else {
               try {
                 await _firebaseService.downloadFile(s.imageUrl!, localFile);
                 s.imagePath = localPath;
               } catch (e) {
                 debugPrint("Error downloading file: $e");
               }
             }
          }
        }
        await DatabaseHelper.instance.insertStaff(s);
      }
      _syncProgress = 0.6;
      notifyListeners();

      // 5.1 Staff Advances
      _syncStatus = "Restoring advances...";
      final advances = cloudData['staff_advances'] as List<StaffAdvanceModel>? ?? [];
      for (var adv in advances) {
        adv.isSynced = 1;
        final db = await DatabaseHelper.instance.database;
        await db.insert('staff_advance', adv.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      _syncProgress = 0.63;
      notifyListeners();

      // 5.2 Staff Leaves
      _syncStatus = "Restoring leaves...";
      final leaves = cloudData['staff_leaves'] as List<StaffLeaveModel>? ?? [];
      for (var leave in leaves) {
        leave.isSynced = 1;
        final db = await DatabaseHelper.instance.database;
        await db.insert('staff_leave', leave.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      _syncProgress = 0.65;
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
      // Removed redeclaration of 'transactions'
      debugPrint("SyncProvider: Found ${transactions.length} transactions on cloud.");
      
      final db = await DatabaseHelper.instance.database;
      for (int i = 0; i < transactions.length; i++) {
        final tx = transactions[i];
        try {
          tx.isSynced = 1;
          await db.insert(
            'transactions', 
            tx.toMap(), 
            conflictAlgorithm: ConflictAlgorithm.replace
          );
        } catch (e) {
          debugPrint("Error restoring transaction ${tx.id}: $e");
        }
        if (i % 10 == 0 || i == transactions.length - 1) {
          _progress(0.8 + (0.2 * (i + 1) / (transactions.isEmpty ? 1 : transactions.length)), "Restoring transactions...");
        }
      }
      
      _progress(1.0, "Restore Complete!");

      // CRITICAL: Refresh ALL providers to show new data immediately
      if (context.mounted) {
        final t = Provider.of<TransactionProvider>(context, listen: false);
        final i = Provider.of<ItemProvider>(context, listen: false);
        final c = Provider.of<CategoryProvider>(context, listen: false);
        final s = Provider.of<StaffProvider>(context, listen: false);
        final sup = Provider.of<SupplierProvider>(context, listen: false);
        final u = Provider.of<UnitProvider>(context, listen: false);
        final r = Provider.of<PurchaseReminderProvider>(context, listen: false);
        final p = Provider.of<ProfileProvider>(context, listen: false);

        await Future.wait([
          c.fetchCategories(), // Fetch categories first to ensure items link correctly
          t.fetchTransactions(),
          i.refreshData(),
          s.fetchStaff(),
          sup.fetchSuppliers(),
          u.fetchUnits(),
          r.fetchReminders(),
          p.loadProfile(),
        ]);
        
        debugPrint("SyncProvider: All Providers refreshed with restored data.");
      }

      return true;
    } catch (e) {
      _progress(0.0, "Restore Failed: $e");
      debugPrint("SyncProvider Error: $e");
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
}
