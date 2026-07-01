import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../models/item_model.dart';
import '../models/transaction_model.dart';
import '../core/database/database_helper.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';
import 'item_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'dart:convert';
import '../models/category_model.dart';
import '../models/staff_model.dart';
import '../models/supplier_model.dart';
import '../models/purchase_reminder_model.dart';
import '../models/recipe_model.dart';
import '../main.dart'; // To access navigatorKey
import 'category_provider.dart';
import 'staff_provider.dart';
import 'supplier_provider.dart';
import 'unit_provider.dart';
import 'purchase_reminder_provider.dart';
import 'profile_provider.dart';
import 'package:provider/provider.dart';

class TransactionProvider with ChangeNotifier {
  List<TransactionModel> _allTransactions = [];
  final FirebaseService _firebaseService = FirebaseService();
  Timer? _syncTimer;
  bool _syncRequired = false;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;

  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncTime => _lastSyncTime;

  String _normalizeStatus(String? status) {
    if (status == null || status.isEmpty) return 'completed';
    return status.trim().toLowerCase();
  }

  List<TransactionModel> get transactions => _allTransactions.where((tx) {
    return tx.isDeleted == 0 && _normalizeStatus(tx.status) == 'completed';
  }).toList();

  List<TransactionModel> get pendingTransactions =>
      _allTransactions.where((tx) {
        final status = _normalizeStatus(tx.status);
        return tx.isDeleted == 0 && (status == 'pending' || status == 'draft');
      }).toList();

  List<TransactionModel> get deletedTransactions =>
      _allTransactions.where((tx) => tx.isDeleted == 1).toList();

  TransactionProvider() {
    _initializeData();
    _setupConnectivityListener();
    _startScheduledSync();
  }

  Future<void> _initializeData() async {
    await fetchTransactions();
    await syncAllUnsynced();
  }

  Future<bool> masterRestoreFromCloud() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.any((result) => result != ConnectivityResult.none)) {
      if (_isSyncing) return false; 
      
      _isSyncing = true;
      notifyListeners();

      try {
        debugPrint("🚀 STARTING FAST MASTER RESTORE...");

        final results = await Future.wait([
          _firebaseService.fetchAllCategories(),
          _firebaseService.fetchAllItems(),
          _firebaseService.fetchAllTransactions(),
          _firebaseService.fetchAllStaff(),
          _firebaseService.fetchAllSuppliers(),
          _firebaseService.fetchAllPurchaseReminders(),
          _firebaseService.fetchAllUnits(),
          _firebaseService.fetchAllRecipes(),
        ]);

        final cloudCategories = results[0] as List<CategoryModel>;
        final cloudItems = results[1] as List<ItemModel>;
        final cloudTxs = results[2] as List<TransactionModel>;
        final cloudStaff = results[3] as List<StaffModel>;
        final cloudSuppliers = results[4] as List<SupplierModel>;
        final cloudReminders = results[5] as List<PurchaseReminderModel>;
        final cloudUnits = results[6] as List<Map<String, dynamic>>;
        final cloudRecipes = results[7] as List<RecipeModel>;

        final db = DatabaseHelper.instance;
        await db.clearAllData();

        if (cloudCategories.isNotEmpty) {
          await db.batchInsert(
            'categories',
            cloudCategories.map((c) => (c..isSynced = 1).toMap()).toList(),
          );
        }

        if (cloudItems.isNotEmpty) {
          await db.batchInsert(
            'items',
            cloudItems.map((i) => (i..isSynced = 1).toMap()).toList(),
          );
        }

        if (cloudTxs.isNotEmpty) {
          await db.batchInsert(
            'transactions',
            cloudTxs.map((t) => (t..isSynced = 1).toMap()).toList(),
          );
        }

        if (cloudStaff.isNotEmpty) {
          await db.batchInsert(
            'staff',
            cloudStaff.map((s) => (s..isSynced = 1).toMap()).toList(),
          );
        }
        
        if (cloudSuppliers.isNotEmpty) {
          await db.batchInsert(
            'suppliers',
            cloudSuppliers.map((s) => (s..isSynced = 1).toMap()).toList(),
          );
        }

        if (cloudReminders.isNotEmpty) {
          await db.batchInsert(
            'purchase_reminders',
            cloudReminders.map((r) => (r..isSynced = 1).toMap()).toList(),
          );
        }

        if (cloudUnits.isNotEmpty) {
          for (var unitData in cloudUnits) {
            String? name = unitData['name'];
            if (name != null) await db.insertUnit(name, isSynced: 1);
          }
        }

        if (cloudRecipes.isNotEmpty) {
          await db.batchInsert(
            'recipes',
            cloudRecipes.map((r) => (r..isSynced = 1).toMap()).toList(),
          );
        }

        // Refresh all providers after restore
        if (navigatorKey.currentContext != null) {
          final context = navigatorKey.currentContext!;
          await Future.wait([
            Provider.of<ItemProvider>(context, listen: false).refreshData(),
            Provider.of<CategoryProvider>(context, listen: false).fetchCategories(),
            Provider.of<StaffProvider>(context, listen: false).fetchStaff(),
            Provider.of<SupplierProvider>(context, listen: false).fetchSuppliers(),
            Provider.of<UnitProvider>(context, listen: false).fetchUnits(),
            Provider.of<PurchaseReminderProvider>(context, listen: false).fetchReminders(),
            Provider.of<ProfileProvider>(context, listen: false).loadProfile(),
          ]);
        }

        await fetchTransactions();
        _lastSyncTime = DateTime.now();
        debugPrint("✅ Fast Master Restore Completed!");
        return true;
      } catch (e) {
        debugPrint("❌ Master Restore error: $e");
        return false;
      } finally {
        _isSyncing = false;
        notifyListeners();
      }
    }
    return false;
  }

  Future<void> restoreFromCloud() async => await masterRestoreFromCloud();

  void _setupConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        if (_syncRequired) {
          syncAllUnsynced();
          _syncRequired = false;
        }
      }
    });
  }

  void _startScheduledSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 30), (timer) async {
      final now = DateTime.now();
      if (now.hour == 0) _syncRequired = true;
      if (now.hour >= 1 && _syncRequired) {
        final connectivityResult = await Connectivity().checkConnectivity();
        if (connectivityResult.any(
          (result) => result != ConnectivityResult.none,
        )) {
          await syncAllUnsynced();
          _syncRequired = false;
        }
      }
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchTransactions() async {
    try {
      _allTransactions = await DatabaseHelper.instance.getAllTransactions();
      notifyListeners();
    } catch (e) {
      debugPrint("Error fetching transactions: $e");
    }
  }

  List<TransactionModel> getFilteredTransactions({
    required String type,
    DateTimeRange? range,
    String? category,
    String? itemName,
    String? status,
  }) {
    return _allTransactions.where((tx) {
      bool matchType =
          type == 'all' ||
          tx.type == type ||
          (type == 'purchase' && tx.type == 'expense');
      bool matchDelete = tx.isDeleted == 0;
      bool matchStatus =
          status == null ||
          _normalizeStatus(tx.status) == _normalizeStatus(status);
      bool matchDate = true;
      if (range != null) {
        final start = DateTime(
          range.start.year,
          range.start.month,
          range.start.day,
        );
        final endLimit = DateTime(
          range.end.year,
          range.end.month,
          range.end.day,
          23,
          59,
          59,
        );
        matchDate =
            tx.date.isAtSameMomentAs(start) ||
            (tx.date.isAfter(start) && tx.date.isBefore(endLimit));
      }

      bool matchCategory = category == null || category == 'All';
      if (!matchCategory) {
        bool txCategoryMatch =
            tx.category.toLowerCase() == category.toLowerCase();
        bool itemCategoryMatch = tx.parsedItems.any(
          (i) => (i['category'] ?? '').toLowerCase() == category.toLowerCase(),
        );
        matchCategory = txCategoryMatch || itemCategoryMatch;
      }

      bool matchItem =
          itemName == null ||
          itemName.isEmpty ||
          tx.parsedItems.any(
            (i) => (i['name'] ?? '').toLowerCase().contains(
              itemName.toLowerCase(),
            ),
          );

      return matchType &&
          matchDelete &&
          matchStatus &&
          matchDate &&
          matchCategory &&
          matchItem;
    }).toList();
  }

  Map<String, double> getPaymentSplit(List<TransactionModel> txs) {
    double cash = 0, upi = 0, credit = 0;
    for (var tx in txs) {
      if (tx.paymentMode == 'Split') {
        cash += tx.cashAmount;
        upi += tx.upiAmount;
      } else if (tx.paymentMode == 'Cash') {
        cash += tx.amount;
      } else if (tx.paymentMode == 'UPI') {
        upi += tx.amount;
      } else if (tx.paymentMode == 'Credit') {
        credit += (tx.amount - tx.paidAmount);
        cash += tx.paidAmount;
      }
    }
    return {'Cash': cash, 'UPI': upi, 'Credit': credit};
  }

  Map<String, int> getTopItems(List<TransactionModel> txs) {
    Map<String, int> itemCounts = {};
    for (var tx in txs) {
      for (var item in tx.parsedItems) {
        String name = item['name'] ?? 'Unknown';
        double qty = double.tryParse(item['qty'] ?? '1') ?? 1;
        itemCounts[name] = (itemCounts[name] ?? 0) + qty.toInt();
      }
    }
    var sortedEntries = itemCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sortedEntries.take(5));
  }

  Future<int> _getNextTokenNumber() async {
    final now = DateTime.now();
    final todayStart = DateTime(
      now.year,
      now.month,
      now.day,
      0,
      0,
      0,
    ).toIso8601String();

    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM transactions WHERE date >= ? AND is_deleted = 0",
      [todayStart],
    );

    int count = Sqflite.firstIntValue(result) ?? 0;
    return count + 1;
  }

  String _extractToken(String desc) {
    if (!desc.contains("Token: ")) return "";
    try {
      return desc.split("Token: ").last.split(" | ").first.trim();
    } catch (_) {
      return "";
    }
  }

  Future<void> _ensureToken(
    TransactionModel tx, {
    TransactionModel? oldTx,
  }) async {
    if (tx.category == 'Salary' || tx.type == 'expense') return;

    if (oldTx != null) {
      String oldToken = _extractToken(oldTx.description);
      if (oldToken.isNotEmpty && !_extractToken(tx.description).isNotEmpty) {
        _injectToken(tx, oldToken);
        return;
      }
    }

    if (_extractToken(tx.description).isEmpty) {
      int token = await _getNextTokenNumber();
      _injectToken(tx, token.toString());
    }
  }

  void _injectToken(TransactionModel tx, String token) {
    if (tx.description.contains("Token: ")) return;

    List<String> parts = tx.description.split(" | ");
    String jsonPart = parts.first;
    List<String> metadata = parts.length > 1 ? parts.sublist(1) : [];

    metadata.insert(0, "Token: $token");
    tx.description = "$jsonPart | ${metadata.join(' | ')}";
  }

  Future<TransactionModel?> addTransaction(
    TransactionModel tx,
    ItemProvider itemProvider,
    {ProfileProvider? profile} // Add profile check
  ) async {
    // BLOCK SALE IF ADMIN BLOCKED IT
    if (profile != null && tx.type == 'sale' && profile.saleBlocked) {
      debugPrint("❌ SALE BLOCKED BY ADMIN");
      return null;
    }

    try {
      tx.status = _normalizeStatus(tx.status).isEmpty
          ? 'completed'
          : _normalizeStatus(tx.status);
      tx.category = tx.category.trim();

      await _ensureToken(tx);

      int id = await DatabaseHelper.instance.insertTransaction(tx);
      tx.id = id;

      _allTransactions.insert(0, tx);
      notifyListeners(); 

      await _applyStockEffect(tx, itemProvider, isAddingEffect: true);

      _syncSingleTransaction(tx);
      return tx;
    } catch (e) {
      debugPrint("Error adding transaction: $e");
      return null;
    }
  }

  Future<TransactionModel?> updateTransaction(
    TransactionModel tx,
    ItemProvider itemProvider, {
    TransactionModel? oldTx,
    ProfileProvider? profile,
  }) async {
    if (profile != null && tx.type == 'sale' && profile.saleBlocked) {
      debugPrint("❌ SALE BLOCKED BY ADMIN");
      return null;
    }

    try {
      tx.status = _normalizeStatus(tx.status).isEmpty
          ? 'completed'
          : _normalizeStatus(tx.status);
      tx.category = tx.category.trim();
      tx.isSynced = 0;

      await _ensureToken(tx, oldTx: oldTx);

      if (oldTx != null)
        await _applyStockEffect(oldTx, itemProvider, isAddingEffect: false);
      await DatabaseHelper.instance.updateTransaction(tx);

      final index = _allTransactions.indexWhere((t) => t.id == tx.id);
      if (index != -1) {
        _allTransactions[index] = tx;
        notifyListeners();
      }

      await _applyStockEffect(tx, itemProvider, isAddingEffect: true);

      if (tx.status == 'completed' && tx.id != null) {
        await NotificationService().cancelOrderReminders(tx.id!);
      }

      _syncSingleTransaction(tx);
      return tx;
    } catch (e) {
      debugPrint("Error updating transaction: $e");
      return null;
    }
  }

  Future<void> toggleItemCheck(
    int transactionId,
    String itemName,
    double itemQty,
    bool isChecked,
  ) async {
    try {
      final index = _allTransactions.indexWhere((t) => t.id == transactionId);
      if (index == -1) return;

      final tx = _allTransactions[index];

      String cleanJson = tx.description;
      String metadata = "";
      if (tx.description.contains(' | ')) {
        cleanJson = tx.description.split(' | ').first;
        metadata = tx.description.substring(tx.description.indexOf(' | '));
      }

      final List<dynamic> items = jsonDecode(cleanJson);
      for (var item in items) {
        if (item is Map && item['name'] == itemName) {
          final double storedQty =
              double.tryParse(item['qty']?.toString() ?? '1') ?? 1.0;
          if ((storedQty - itemQty).abs() < 0.01) {
            item['checked'] = isChecked;
            break;
          }
        }
      }

      tx.description = jsonEncode(items) + metadata;
      tx.isSynced = 0;

      _allTransactions[index] = tx;
      notifyListeners();

      await DatabaseHelper.instance.updateTransaction(tx);
      _syncSingleTransaction(tx);
    } catch (e) {
      debugPrint("Error toggling item check: $e");
    }
  }

  Future<void> addPortionToPending(
    int transactionId,
    String itemName,
    bool isHalfOptionEnabled,
    bool isDecrement,
    ItemProvider itemProvider,
  ) async {
    try {
      final index = _allTransactions.indexWhere((t) => t.id == transactionId);
      if (index == -1) return;

      final originalTx = _allTransactions[index];
      final tx = TransactionModel.fromMap(originalTx.toMap());
      bool isSale =
          tx.type.toLowerCase() == 'sale' || tx.type.toLowerCase() == 'income';

      String cleanJson = tx.description;
      String metadata = "";
      if (tx.description.contains(' | ')) {
        cleanJson = tx.description.split(' | ').first;
        metadata = tx.description.substring(tx.description.indexOf(' | '));
      }

      final List<dynamic> itemsList = jsonDecode(cleanJson);
      int itemIndex = itemsList.indexWhere((i) => i['name'] == itemName);
      if (itemIndex == -1) return;

      double currentQty =
          double.tryParse(itemsList[itemIndex]['qty'].toString()) ?? 0;
      double step = isHalfOptionEnabled ? 0.5 : 1.0;
      double newQty = isDecrement ? (currentQty - step) : (currentQty + step);

      if (newQty <= 0) {
        itemsList.removeAt(itemIndex);
      } else {
        itemsList[itemIndex]['qty'] = newQty.toString();

        if (isSale) {
          try {
            final master = itemProvider.items.firstWhere(
              (i) => i.name == itemName,
            );
            itemsList[itemIndex]['full_price'] = (master.price ?? 0).toString();
            itemsList[itemIndex]['half_price'] = (master.halfPrice ?? 0)
                .toString();

            if (newQty == 0.5 &&
                master.halfPrice != null &&
                master.halfPrice! > 0) {
              itemsList[itemIndex]['variant'] = 'Half';
              itemsList[itemIndex]['price'] = master.halfPrice.toString();
            } else {
              itemsList[itemIndex]['variant'] = 'Full';
              itemsList[itemIndex]['price'] = (master.price ?? 0).toString();
            }
          } catch (_) {}
        }
      }

      if (itemsList.isEmpty) {
        await softDeleteTransaction(transactionId, itemProvider);
        return;
      }

      double newRawSum = 0;
      for (var it in itemsList) {
        double q = double.tryParse(it['qty'].toString()) ?? 0;
        double p = double.tryParse(it['price'].toString()) ?? 0;
        double fP = double.tryParse(it['full_price']?.toString() ?? '0') ?? 0;
        double hP = double.tryParse(it['half_price']?.toString() ?? '0') ?? 0;
        double exQ = double.tryParse(it['extra_qty']?.toString() ?? '0') ?? 0;
        double exP = double.tryParse(it['extra_price']?.toString() ?? '0') ?? 0;

        double base;
        if (fP > 0 && hP > 0) {
          int fullPortions = q.floor();
          double remainder = q - fullPortions;
          base = (fullPortions * fP) + (remainder > 0 ? hP : 0);
        } else {
          base = q * p;
        }

        double totalExtra = exQ > 0 ? (exQ * exP) : exP;
        newRawSum += base + totalExtra;
      }

      double taxAmt = 0;
      double discAmt = 0;
      if (metadata.contains('Tax: ₹')) {
        taxAmt =
            double.tryParse(
              metadata
                  .split('Tax: ₹')
                  .last
                  .split(' | ')
                  .first
                  .replaceAll(RegExp(r'[^0-9.]'), ''),
            ) ??
            0;
      }
      if (metadata.contains('Discount: ₹')) {
        discAmt =
            double.tryParse(
              metadata
                  .split('Discount: ₹')
                  .last
                  .split(' | ')
                  .first
                  .replaceAll(RegExp(r'[^0-9.]'), ''),
            ) ??
            0;
      }

      tx.description = jsonEncode(itemsList) + metadata;
      tx.amount = (newRawSum + taxAmt - discAmt);
      if (tx.amount < 0) tx.amount = 0;
      tx.isSynced = 0;

      await updateTransaction(tx, itemProvider, oldTx: originalTx);
    } catch (e) {
      debugPrint("Error updating portion: $e");
    }
  }

  Future<void> updatePendingItem(
    int transactionId,
    String itemName, {
    double? newQty,
    String? newVariant,
    bool isDelete = false,
    required ItemProvider itemProvider,
  }) async {
    try {
      final index = _allTransactions.indexWhere((t) => t.id == transactionId);
      if (index == -1) return;

      final originalTx = _allTransactions[index];
      final tx = TransactionModel.fromMap(originalTx.toMap());
      bool isSale =
          tx.type.toLowerCase() == 'sale' || tx.type.toLowerCase() == 'income';

      String cleanJson = tx.description;
      String metadata = "";
      if (tx.description.contains(' | ')) {
        cleanJson = tx.description.split(' | ').first;
        metadata = tx.description.substring(tx.description.indexOf(' | '));
      }

      final List<dynamic> items = jsonDecode(cleanJson);
      int itemIndex = items.indexWhere((i) => i['name'] == itemName);
      if (itemIndex == -1) return;

      if (isDelete) {
        items.removeAt(itemIndex);
      } else {
        if (newQty != null) items[itemIndex]['qty'] = newQty.toString();
        if (newVariant != null) {
          items[itemIndex]['variant'] = newVariant;
          if (isSale) {
            try {
              final masterItem = itemProvider.items.firstWhere(
                (i) => i.name == itemName,
              );
              items[itemIndex]['price'] =
                  (newVariant.toLowerCase() == 'half'
                          ? (masterItem.halfPrice ?? 0)
                          : (masterItem.price ?? 0))
                      .toString();
              items[itemIndex]['full_price'] = (masterItem.price ?? 0)
                  .toString();
              items[itemIndex]['half_price'] = (masterItem.halfPrice ?? 0)
                  .toString();
            } catch (_) {}
          }
        }
      }

      if (items.isEmpty) {
        await softDeleteTransaction(transactionId, itemProvider);
        return;
      }

      double newRawSum = 0;
      for (var it in items) {
        double q = double.tryParse(it['qty'].toString()) ?? 0;
        double p = double.tryParse(it['price'].toString()) ?? 0;
        double fP = double.tryParse(it['full_price']?.toString() ?? '0') ?? 0;
        double hP = double.tryParse(it['half_price']?.toString() ?? '0') ?? 0;
        double exQ = double.tryParse(it['extra_qty']?.toString() ?? '0') ?? 0;
        double exP = double.tryParse(it['extra_price']?.toString() ?? '0') ?? 0;

        double base;
        if (fP > 0 && hP > 0) {
          int fullPortions = q.floor();
          double remainder = q - fullPortions;
          base = (fullPortions * fP) + (remainder > 0 ? hP : 0);
        } else {
          base = q * p;
        }

        double totalExtra = exQ > 0 ? (exQ * exP) : exP;
        newRawSum += base + totalExtra;
      }

      double taxAmt = 0;
      double discAmt = 0;
      if (metadata.contains('Tax: ₹')) {
        taxAmt =
            double.tryParse(
              metadata
                  .split('Tax: ₹')
                  .last
                  .split(' | ')
                  .first
                  .replaceAll(RegExp(r'[^0-9.]'), ''),
            ) ??
            0;
      }
      if (metadata.contains('Discount: ₹')) {
        discAmt =
            double.tryParse(
              metadata
                  .split('Discount: ₹')
                  .last
                  .split(' | ')
                  .first
                  .replaceAll(RegExp(r'[^0-9.]'), ''),
            ) ??
            0;
      }

      tx.description = jsonEncode(items) + metadata;
      tx.amount = (newRawSum + taxAmt - discAmt);
      if (tx.amount < 0) tx.amount = 0;
      tx.isSynced = 0;

      await updateTransaction(tx, itemProvider, oldTx: originalTx);
    } catch (e) {
      debugPrint("Error updating pending item: $e");
    }
  }

  Future<void> softDeleteTransaction(int id, ItemProvider itemProvider) async {
    try {
      final index = _allTransactions.indexWhere((t) => t.id == id);
      if (index == -1) return;

      final tx = _allTransactions[index];

      final now = DateTime.now();
      tx.isDeleted = 1;
      tx.deletedAt = now;
      tx.updatedAt = now;
      tx.isSynced = 0;
      notifyListeners();

      await DatabaseHelper.instance.softDeleteTransaction(id);
      await _applyStockEffect(tx, itemProvider, isAddingEffect: false);
      await NotificationService().cancelOrderReminders(id);

      await _syncSingleTransaction(tx);
    } catch (e) {
      debugPrint("Error soft deleting transaction: $e");
    }
  }

  Future<void> restoreTransaction(int id, ItemProvider itemProvider) async {
    try {
      final index = _allTransactions.indexWhere((t) => t.id == id);
      if (index == -1) return;

      final tx = _allTransactions[index];

      final now = DateTime.now();
      tx.isDeleted = 0;
      tx.deletedAt = null;
      tx.updatedAt = now;
      tx.isSynced = 0;
      notifyListeners();

      await DatabaseHelper.instance.restoreTransaction(id);
      await _applyStockEffect(tx, itemProvider, isAddingEffect: true);

      // Force immediate sync for restored transaction
      await _syncSingleTransaction(tx);
    } catch (e) {
      debugPrint("Error restoring transaction: $e");
    }
  }

  Future<void> permanentDeleteTransaction(int id) async {
    try {
      await DatabaseHelper.instance.permanentDeleteTransaction(id);
      _allTransactions.removeWhere((t) => t.id == id);
      notifyListeners();
      await _firebaseService.deleteTransaction(id);
    } catch (e) {
      debugPrint("Error permanent deleting transaction: $e");
    }
  }

  Future<void> _applyStockEffect(
    TransactionModel tx,
    ItemProvider itemProvider, {
    required bool isAddingEffect,
  }) async {
    final items = tx.parsedItems;
    bool isSaleType = tx.type == 'sale' || tx.type == 'income';
    bool isPurchaseType = tx.type == 'purchase';

    for (var itemMap in items) {
      try {
        final name = itemMap['name']!.toString().trim().toLowerCase();
        
        final masterItem = itemProvider.items.firstWhere(
          (i) => i.name.trim().toLowerCase() == name,
          orElse: () => ItemModel(name: 'Unknown', category: '', unit: '', minStock: 0, currentStock: 0)
        );

        if (masterItem.id == null) continue;

        final displayQty = (double.tryParse(itemMap['qty']?.toString() ?? '0') ?? 0).toDouble();
        final extraQty = (double.tryParse(itemMap['extra_qty']?.toString() ?? '0') ?? 0).toDouble();

        // Multiplier Logic for Packets/Plates to Pieces conversion
        double multiplier = 1.0;
        final variant = itemMap['variant']?.toString() ?? 'Full';
        
        if (variant.toLowerCase() == 'half' && isSaleType) {
          multiplier = (masterItem.halfQty != null && masterItem.halfQty! > 0) 
              ? masterItem.halfQty! 
              : 0.5;
        } else {
          // For 'Full', 'None', or Purchases (treating Qty as Packet count)
          multiplier = (masterItem.fullQty != null && masterItem.fullQty! > 0) 
              ? masterItem.fullQty! 
              : 1.0;
        }

        // Calculation: (Quantity entered * multiplier) + extra pieces
        double piecesToAdjust = (displayQty * multiplier) + extraQty;

        // 1. ADJUST MAIN ITEM STOCK
        if (piecesToAdjust > 0) {
          bool shouldIncrease = isPurchaseType ? isAddingEffect : !isAddingEffect;
          await itemProvider.adjustStock(masterItem.id!, piecesToAdjust, shouldIncrease);
        }

        // 2. RECIPE CONSUMPTION
        if ((masterItem.itemType == 'selling' || masterItem.itemType == 'readymade') && isSaleType) {
          final recipe = itemProvider.getRecipe(masterItem.id!);
          final masterStockKey = itemProvider.getStockKey(masterItem);

          for (var component in recipe) {
            final componentItem = itemProvider.items.firstWhere(
              (i) => i.id == component.materialId,
              orElse: () => ItemModel(name: 'Unknown', category: '', unit: '', minStock: 0, currentStock: 0)
            );

            if (componentItem.id == null) continue;

            final String materialStockKey = itemProvider.getStockKey(componentItem);
            if (materialStockKey == masterStockKey) {
              continue;
            }

            // Recipe consumption is typically per "Serving Unit" (the unit sold).
            // So if you sell 1 "Plate", you consume the recipe defined for 1 plate.
            // We use displayQty + (extraQty / multiplier) to get the 'serving units' sold.
            double servingUnitsSold = displayQty + (extraQty / multiplier);
            final double materialQtyToAdjust = servingUnitsSold * component.quantity;

            await itemProvider.adjustStock(component.materialId, materialQtyToAdjust, !isAddingEffect);
          }
        }
      } catch (e) {
        debugPrint("Stock adjustment failed: $e");
      }
    }
  }

  Future<void> syncAllUnsynced() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.any((result) => result != ConnectivityResult.none)) {
      _isSyncing = true;
      notifyListeners();
      try {
        final unsynced = await DatabaseHelper.instance
            .getUnsyncedTransactions();
        for (var tx in unsynced) {
          await _firebaseService.syncTransaction(tx);
          await DatabaseHelper.instance.updateTransactionSyncStatus(tx.id!, 1);
        }
        await fetchTransactions();
      } catch (e) {
        debugPrint("Batch sync error: $e");
      } finally {
        _isSyncing = false;
        notifyListeners();
      }
    }
  }

  Future<void> _syncSingleTransaction(TransactionModel tx) async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.any((result) => result != ConnectivityResult.none)) {
      _isSyncing = true;
      notifyListeners();
      try {
        await _firebaseService.syncTransaction(tx);
        await DatabaseHelper.instance.updateTransactionSyncStatus(tx.id!, 1);
      } catch (e) {
        debugPrint("Single sync failed: $e");
      } finally {
        _isSyncing = false;
        notifyListeners();
      }
    }
  }

  double get todaySales => getSalesForRange(null);
  double get todayPurchases => getPurchasesForRange(null);
  double get yesterdaySales {
    final start = DateTime.now().subtract(const Duration(days: 1));
    final range = DateTimeRange(start: start, end: start);
    return getSalesForRange(range);
  }

  double getSalesForRange(DateTimeRange? range) {
    return _getTransactionsInRange(range)
        .where((tx) => tx.type == 'sale' || tx.type == 'income')
        .fold(0.0, (sum, tx) => sum + tx.amount);
  }

  double getPurchasesForRange(DateTimeRange? range) {
    return _getTransactionsInRange(range)
        .where((tx) => tx.type == 'purchase' || tx.type == 'expense')
        .fold(0.0, (sum, tx) => sum + tx.amount);
  }

  double getCashSalesForRange(DateTimeRange? range) {
    return _getTransactionsInRange(range)
        .where(
          (tx) =>
              (tx.type == 'sale' || tx.type == 'income') &&
              (tx.paymentMode == 'Cash' || tx.paymentMode == 'Split'),
        )
        .fold(
          0.0,
          (sum, tx) =>
              sum + (tx.paymentMode == 'Split' ? tx.cashAmount : tx.amount),
        );
  }

  double getUpiSalesForRange(DateTimeRange? range) {
    return _getTransactionsInRange(range)
        .where(
          (tx) =>
              (tx.type == 'sale' || tx.type == 'income') &&
              (tx.paymentMode == 'UPI' || tx.paymentMode == 'Split'),
        )
        .fold(
          0.0,
          (sum, tx) =>
              sum + (tx.paymentMode == 'Split' ? tx.upiAmount : tx.amount),
        );
  }

  double getCreditSalesForRange(DateTimeRange? range) {
    return _getTransactionsInRange(range)
        .where(
          (tx) =>
              (tx.type == 'sale' || tx.type == 'income') &&
              tx.paymentMode == 'Credit',
        )
        .fold(0.0, (sum, tx) => sum + (tx.amount - tx.paidAmount));
  }

  double getAvgOrderValueForRange(DateTimeRange? range) {
    final txs = _getTransactionsInRange(
      range,
    ).where((tx) => tx.type == 'sale' || tx.type == 'income').toList();
    if (txs.isEmpty) return 0.0;
    return getSalesForRange(range) / txs.length;
  }

  double getProfitForRange(DateTimeRange? range) {
    return getSalesForRange(range) - getPurchasesForRange(range);
  }

  int getOrderCountForRange(DateTimeRange? range) {
    return _getTransactionsInRange(
      range,
    ).where((tx) => tx.type == 'sale' || tx.type == 'income').length;
  }

  double getSalesGrowthForRange(DateTimeRange? range) {
    double current = getSalesForRange(range);
    double prev = 0;

    if (range == null) {
      prev = yesterdaySales;
    } else {
      final duration = range.end.difference(range.start);
      final prevStart = range.start
          .subtract(duration)
          .subtract(const Duration(days: 1));
      final prevEnd = range.start.subtract(const Duration(days: 1));
      prev = getSalesForRange(DateTimeRange(start: prevStart, end: prevEnd));
    }

    if (prev == 0) return current > 0 ? 100.0 : 0.0;
    return ((current - prev) / prev) * 100;
  }

  List<TransactionModel> _getTransactionsInRange(DateTimeRange? range) {
    return _allTransactions.where((tx) {
      bool matchStatus =
          tx.isDeleted == 0 && _normalizeStatus(tx.status) == 'completed';
      if (!matchStatus) return false;

      if (range == null) {
        final now = DateTime.now();
        return tx.date.year == now.year &&
            tx.date.month == now.month &&
            tx.date.day == now.day;
      } else {
        final start = DateTime(
          range.start.year,
          range.start.month,
          range.start.day,
        );
        final end = DateTime(
          range.end.year,
          range.end.month,
          range.end.day,
          23,
          59,
          59,
        );
        return tx.date.isAfter(start.subtract(const Duration(seconds: 1))) &&
            tx.date.isBefore(end);
      }
    }).toList();
  }

  double get cashSalesToday => getCashSalesForRange(null);
  double get upiSalesToday => getUpiSalesForRange(null);
  double get creditSalesToday => getCreditSalesForRange(null);

  double get salesGrowth => getSalesGrowthForRange(null);

  double get avgOrderValue => getAvgOrderValueForRange(null);

  double get profitToday => getProfitForRange(null);

  Future<void> updateTransactionSnapshots(
    int? txId,
    List<TransactionItemSnapshot> updatedSnapshots,
  ) async {
    if (txId == null) return;
    try {
      final index = _allTransactions.indexWhere((t) => t.id == txId);
      if (index == -1) return;

      final originalTx = _allTransactions[index];
      final tx = TransactionModel.fromMap(originalTx.toMap());

      String metadata = "";
      if (tx.description.contains(' | ')) {
        metadata = tx.description.substring(tx.description.indexOf(' | '));
      }

      final List<Map<String, dynamic>> jsonList = updatedSnapshots.map((s) {
        return {
          'id': s.id,
          'name': s.name,
          'category': s.category,
          'qty': s.qty,
          'unit': s.unit,
          'variant': s.variant,
          'price': s.price,
          'purchase_price': s.purchasePrice,
          'transport_cost': s.transportCost,
          'full_price': s.fullPrice,
          'half_price': s.halfPrice,
          'extra_qty': s.extraQty,
          'extra_price': s.extraPrice,
          'serving_method': s.servingMethod,
          'table_number': s.tableNumber,
          'checked': s.checked,
          'item_type': s.itemType,
        };
      }).toList();

      tx.description = jsonEncode(jsonList) + metadata;
      tx.isSynced = 0;

      await DatabaseHelper.instance.updateTransaction(tx);
      _allTransactions[index] = tx;
      notifyListeners();

      _syncSingleTransaction(tx);
    } catch (e) {
      debugPrint("Error updating transaction snapshots: $e");
    }
  }
}
