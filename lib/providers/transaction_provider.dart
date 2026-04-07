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

class TransactionProvider with ChangeNotifier {
  List<TransactionModel> _allTransactions = [];
  final FirebaseService _firebaseService = FirebaseService();
  Timer? _syncTimer;
  bool _syncRequired = false;
  bool _isSyncing = false;

  bool get isSyncing => _isSyncing;

  String _normalizeStatus(String? status) {
    if (status == null || status.isEmpty) return 'completed';
    return status.trim().toLowerCase();
  }

  List<TransactionModel> get transactions => _allTransactions.where((tx) {
    return tx.isDeleted == 0 && _normalizeStatus(tx.status) == 'completed';
  }).toList();

  List<TransactionModel> get pendingTransactions => _allTransactions.where((tx) {
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
    if (_allTransactions.isEmpty) {
      debugPrint("Local data empty, triggering auto-restore...");
      await masterRestoreFromCloud();
    }
  }

  Future<void> masterRestoreFromCloud() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.any((result) => result != ConnectivityResult.none)) {
      _isSyncing = true;
      notifyListeners();
      try {
        debugPrint("🚀 STARTING MASTER RESTORE FROM CLOUD...");

        final cloudCategories = await _firebaseService.fetchAllCategories();
        for (var cat in cloudCategories) {
          final localCats = await DatabaseHelper.instance.getAllCategories();
          if (!localCats.any((c) => c.id == cat.id || c.name == cat.name)) {
            await DatabaseHelper.instance.insertCategory(cat);
          }
        }

        final cloudItems = await _firebaseService.fetchAllItems();
        for (var item in cloudItems) {
          final localItems = await DatabaseHelper.instance.getAllItems();
          if (!localItems.any((i) => i.id == item.id || i.name == item.name)) {
            item.isSynced = 1;
            await DatabaseHelper.instance.insertItem(item);
          }
        }

        final cloudTxs = await _firebaseService.fetchAllTransactions();
        if (cloudTxs.isNotEmpty) {
          final localTxs = await DatabaseHelper.instance.getAllTransactions();
          for (var tx in cloudTxs) {
            bool exists = localTxs.any((t) => t.id == tx.id || (t.date.isAtSameMomentAs(tx.date) && t.amount == tx.amount));
            if (!exists) {
              tx.isSynced = 1;
              await DatabaseHelper.instance.insertTransaction(tx);
            }
          }
        }

        final cloudStaff = await _firebaseService.fetchAllStaff();
        for (var s in cloudStaff) {
           final localStaff = await DatabaseHelper.instance.getAllStaff();
           if (!localStaff.any((ls) => ls.id == s.id)) {
             s.isSynced = 1;
             await DatabaseHelper.instance.insertStaff(s);
           }
        }

        final cloudSuppliers = await _firebaseService.fetchAllSuppliers();
        for (var sup in cloudSuppliers) {
           final localSuppliers = await DatabaseHelper.instance.getAllSuppliers();
           if (!localSuppliers.any((ls) => ls.id == sup.id)) {
             sup.isSynced = 1;
             await DatabaseHelper.instance.insertSupplier(sup);
           }
        }

        final cloudReminders = await _firebaseService.fetchAllPurchaseReminders();
        for (var rem in cloudReminders) {
           rem.isSynced = 1;
           await DatabaseHelper.instance.database.then((db) => db.insert('purchase_reminders', rem.toMap(), conflictAlgorithm: ConflictAlgorithm.replace));
        }

        final cloudUnits = await _firebaseService.fetchAllUnits();
        for (var unitData in cloudUnits) {
           String? name = unitData['name'];
           if (name != null) await DatabaseHelper.instance.insertUnit(name);
        }

        await fetchTransactions();
        debugPrint("✅ Master Restore Completed Successfully");
      } catch (e) {
        debugPrint("❌ Master Restore error: $e");
      } finally {
        _isSyncing = false;
        notifyListeners();
      }
    }
  }

  Future<void> restoreFromCloud() async => await masterRestoreFromCloud();

  void _setupConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
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
        if (connectivityResult.any((result) => result != ConnectivityResult.none)) {
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
      bool matchType = type == 'all' || tx.type == type || (type == 'purchase' && tx.type == 'expense');
      bool matchDelete = tx.isDeleted == 0;
      bool matchStatus = status == null || _normalizeStatus(tx.status) == _normalizeStatus(status);
      bool matchDate = true;
      if (range != null) {
        final start = DateTime(range.start.year, range.start.month, range.start.day);
        final endLimit = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
        matchDate = tx.date.isAtSameMomentAs(start) || (tx.date.isAfter(start) && tx.date.isBefore(endLimit));
      }

      bool matchCategory = category == null || category == 'All';
      if (!matchCategory && category != null) {
        bool txCategoryMatch = tx.category.toLowerCase() == category.toLowerCase();
        bool itemCategoryMatch = tx.parsedItems.any((i) => (i['category'] ?? '').toLowerCase() == category.toLowerCase());
        matchCategory = txCategoryMatch || itemCategoryMatch;
      }

      bool matchItem = itemName == null || itemName.isEmpty || tx.parsedItems.any((i) =>
          (i['name'] ?? '').toLowerCase().contains(itemName.toLowerCase()));

      return matchType && matchDelete && matchStatus && matchDate && matchCategory && matchItem;
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
    var sortedEntries = itemCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sortedEntries.take(5));
  }

  Future<void> addTransaction(TransactionModel tx, ItemProvider itemProvider) async {
    try {
      tx.status = _normalizeStatus(tx.status).isEmpty ? 'completed' : _normalizeStatus(tx.status);
      int id = await DatabaseHelper.instance.insertTransaction(tx);
      tx.id = id;
      await _applyStockEffect(tx, itemProvider, isAddingEffect: true);
      await fetchTransactions();
      _syncSingleTransaction(tx);
    } catch (e) {
      debugPrint("Error adding transaction: $e");
    }
  }

  Future<void> updateTransaction(TransactionModel tx, ItemProvider itemProvider, {TransactionModel? oldTx}) async {
    try {
      tx.status = _normalizeStatus(tx.status).isEmpty ? 'completed' : _normalizeStatus(tx.status);
      tx.isSynced = 0;
      if (oldTx != null) await _applyStockEffect(oldTx, itemProvider, isAddingEffect: false);
      await DatabaseHelper.instance.updateTransaction(tx);
      await _applyStockEffect(tx, itemProvider, isAddingEffect: true);

      if (tx.status == 'completed' && tx.id != null) {
        await NotificationService().cancelOrderReminders(tx.id!);
      }

      await fetchTransactions();
      _syncSingleTransaction(tx);
    } catch (e) {
      debugPrint("Error updating transaction: $e");
    }
  }

  Future<void> toggleItemCheck(int transactionId, String itemName, bool isChecked) async {
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
          item['checked'] = isChecked;
          break;
        }
      }

      tx.description = jsonEncode(items) + metadata;
      tx.isSynced = 0;
      await DatabaseHelper.instance.updateTransaction(tx);
      notifyListeners();
      _syncSingleTransaction(tx);
    } catch (e) {
      debugPrint("Error toggling item check: $e");
    }
  }

  Future<void> addPortionToPending(int transactionId, String itemName, bool isHalfOptionEnabled, bool isDecrement, ItemProvider itemProvider) async {
    try {
      final index = _allTransactions.indexWhere((t) => t.id == transactionId);
      if (index == -1) return;

      final originalTx = _allTransactions[index];
      final tx = TransactionModel.fromMap(originalTx.toMap());
      bool isSale = tx.type.toLowerCase() == 'sale' || tx.type.toLowerCase() == 'income';

      String cleanJson = tx.description;
      String metadata = "";
      if (tx.description.contains(' | ')) {
        cleanJson = tx.description.split(' | ').first;
        metadata = tx.description.substring(tx.description.indexOf(' | '));
      }

      final List<dynamic> itemsList = jsonDecode(cleanJson);
      int itemIndex = itemsList.indexWhere((i) => i['name'] == itemName);
      if (itemIndex == -1) return;

      double currentQty = double.tryParse(itemsList[itemIndex]['qty'].toString()) ?? 0;
      double step = isHalfOptionEnabled ? 0.5 : 1.0;
      double newQty = isDecrement ? (currentQty - step) : (currentQty + step);

      if (newQty <= 0) {
        itemsList.removeAt(itemIndex);
      } else {
        itemsList[itemIndex]['qty'] = newQty.toString();
        
        if (isSale) {
          try {
            final master = itemProvider.items.firstWhere((i) => i.name == itemName);
            itemsList[itemIndex]['full_price'] = (master.price ?? 0).toString();
            itemsList[itemIndex]['half_price'] = (master.halfPrice ?? 0).toString();
            
            if (newQty == 0.5 && master.halfPrice != null && master.halfPrice! > 0) {
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

      // Re-calculate raw items sum using accurate portion rules
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
        taxAmt = double.tryParse(metadata.split('Tax: ₹').last.split(' | ').first.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
      }
      if (metadata.contains('Discount: ₹')) {
        discAmt = double.tryParse(metadata.split('Discount: ₹').last.split(' | ').first.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
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

  Future<void> updatePendingItem(int transactionId, String itemName, {double? newQty, String? newVariant, bool isDelete = false, required ItemProvider itemProvider}) async {
    try {
      final index = _allTransactions.indexWhere((t) => t.id == transactionId);
      if (index == -1) return;

      final originalTx = _allTransactions[index];
      final tx = TransactionModel.fromMap(originalTx.toMap());
      bool isSale = tx.type.toLowerCase() == 'sale' || tx.type.toLowerCase() == 'income';

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
              final masterItem = itemProvider.items.firstWhere((i) => i.name == itemName);
              items[itemIndex]['price'] = (newVariant.toLowerCase() == 'half' ? (masterItem.halfPrice ?? 0) : (masterItem.price ?? 0)).toString();
              items[itemIndex]['full_price'] = (masterItem.price ?? 0).toString();
              items[itemIndex]['half_price'] = (masterItem.halfPrice ?? 0).toString();
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
        taxAmt = double.tryParse(metadata.split('Tax: ₹').last.split(' | ').first.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
      }
      if (metadata.contains('Discount: ₹')) {
        discAmt = double.tryParse(metadata.split('Discount: ₹').last.split(' | ').first.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
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
      final tx = _allTransactions.firstWhere((t) => t.id == id);
      await DatabaseHelper.instance.softDeleteTransaction(id);
      await _applyStockEffect(tx, itemProvider, isAddingEffect: false);
      await NotificationService().cancelOrderReminders(id);
      tx.isDeleted = 1;
      tx.deletedAt = DateTime.now();
      await fetchTransactions();
      _syncSingleTransaction(tx);
    } catch (e) {
      debugPrint("Error soft deleting transaction: $e");
    }
  }

  Future<void> restoreTransaction(int id, ItemProvider itemProvider) async {
    try {
      final tx = _allTransactions.firstWhere((t) => t.id == id);
      await DatabaseHelper.instance.restoreTransaction(id);
      await _applyStockEffect(tx, itemProvider, isAddingEffect: true);
      tx.isDeleted = 0;
      tx.deletedAt = null;
      await fetchTransactions();
      _syncSingleTransaction(tx);
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

  Future<void> _applyStockEffect(TransactionModel tx, ItemProvider itemProvider, {required bool isAddingEffect}) async {
    final items = tx.parsedItems;
    for (var itemMap in items) {
      try {
        final name = itemMap['name']!;
        int? targetId;
        ItemModel? masterItem;
        try {
          masterItem = itemProvider.items.firstWhere((i) => i.name == name);
          targetId = masterItem.id;
        } catch (_) {}

        if (targetId != null && masterItem != null) {
          final displayQty = double.tryParse(itemMap['qty'] ?? '0') ?? 0;
          final extraQty = double.tryParse(itemMap['extra_qty'] ?? '0') ?? 0;
          final totalDisplayQty = displayQty + extraQty;

          double piecesToAdjust = totalDisplayQty * (masterItem.fullQty ?? 1.0);
          
          if (piecesToAdjust == 0) continue;

          bool shouldIncrease = (tx.type == 'sale' || tx.type == 'income') ? !isAddingEffect : isAddingEffect;
          await itemProvider.adjustStock(targetId, piecesToAdjust, shouldIncrease);
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
        final unsynced = await DatabaseHelper.instance.getUnsyncedTransactions();
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
    return _getTransactionsInRange(range).where((tx) => tx.type == 'sale' || tx.type == 'income').fold(0.0, (sum, tx) => sum + tx.amount);
  }

  double getPurchasesForRange(DateTimeRange? range) {
    return _getTransactionsInRange(range).where((tx) => tx.type == 'purchase' || tx.type == 'expense').fold(0.0, (sum, tx) => sum + tx.amount);
  }

  double getCashSalesForRange(DateTimeRange? range) {
    return _getTransactionsInRange(range).where((tx) => (tx.type == 'sale' || tx.type == 'income') && (tx.paymentMode == 'Cash' || tx.paymentMode == 'Split')).fold(0.0, (sum, tx) => sum + (tx.paymentMode == 'Split' ? tx.cashAmount : tx.amount));
  }

  double getUpiSalesForRange(DateTimeRange? range) {
    return _getTransactionsInRange(range).where((tx) => (tx.type == 'sale' || tx.type == 'income') && (tx.paymentMode == 'UPI' || tx.paymentMode == 'Split')).fold(0.0, (sum, tx) => sum + (tx.paymentMode == 'Split' ? tx.upiAmount : tx.amount));
  }

  double getCreditSalesForRange(DateTimeRange? range) {
    return _getTransactionsInRange(range).where((tx) => (tx.type == 'sale' || tx.type == 'income') && tx.paymentMode == 'Credit').fold(0.0, (sum, tx) => sum + (tx.amount - tx.paidAmount));
  }

  double getAvgOrderValueForRange(DateTimeRange? range) {
    final txs = _getTransactionsInRange(range).where((tx) => tx.type == 'sale' || tx.type == 'income').toList();
    if (txs.isEmpty) return 0.0;
    return getSalesForRange(range) / txs.length;
  }

  double getProfitForRange(DateTimeRange? range) {
    return getSalesForRange(range) - getPurchasesForRange(range);
  }

  int getOrderCountForRange(DateTimeRange? range) {
    return _getTransactionsInRange(range).where((tx) => tx.type == 'sale' || tx.type == 'income').length;
  }

  double getSalesGrowthForRange(DateTimeRange? range) {
    double current = getSalesForRange(range);
    double prev = 0;

    if (range == null) {
      prev = yesterdaySales;
    } else {
      final duration = range.end.difference(range.start);
      final prevStart = range.start.subtract(duration).subtract(const Duration(days: 1));
      final prevEnd = range.start.subtract(const Duration(days: 1));
      prev = getSalesForRange(DateTimeRange(start: prevStart, end: prevEnd));
    }

    if (prev == 0) return current > 0 ? 100.0 : 0.0;
    return ((current - prev) / prev) * 100;
  }

  List<TransactionModel> _getTransactionsInRange(DateTimeRange? range) {
    return _allTransactions.where((tx) {
      bool matchStatus = tx.isDeleted == 0 && _normalizeStatus(tx.status) == 'completed';
      if (!matchStatus) return false;

      if (range == null) {
        final now = DateTime.now();
        return tx.date.year == now.year && tx.date.month == now.month && tx.date.day == now.day;
      } else {
        final start = DateTime(range.start.year, range.start.month, range.start.day);
        final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
        return tx.date.isAfter(start.subtract(const Duration(seconds: 1))) && tx.date.isBefore(end);
      }
    }).toList();
  }

  double get cashSalesToday => getCashSalesForRange(null);
  double get upiSalesToday => getUpiSalesForRange(null);
  double get creditSalesToday => getCreditSalesForRange(null);

  double get salesGrowth => getSalesGrowthForRange(null);

  double get avgOrderValue => getAvgOrderValueForRange(null);

  double get profitToday => getProfitForRange(null);

  List<TransactionModel> _activeDayTransactions(DateTime day) {
    return _allTransactions.where((tx) =>
      tx.isDeleted == 0 &&
      _normalizeStatus(tx.status) == 'completed' &&
      tx.date.year == day.year && tx.date.month == day.month && tx.date.day == day.day
    ).toList();
  }
}
