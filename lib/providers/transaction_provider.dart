import 'package:flutter/material.dart';
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
    return (status ?? '').trim().toLowerCase();
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
      await restoreFromCloud();
    }
  }

  Future<void> restoreFromCloud() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.any((result) => result != ConnectivityResult.none)) {
      _isSyncing = true;
      notifyListeners();
      try {
        final cloudData = await _firebaseService.fetchAllTransactions();
        if (cloudData.isNotEmpty) {
          for (var tx in cloudData) {
            bool exists = await _checkIfTransactionExistsLocally(tx.id!);
            if (!exists) {
              await DatabaseHelper.instance.insertTransaction(tx);
            }
          }
          await fetchTransactions();
        }
      } catch (e) {
        debugPrint("Restore error: $e");
      } finally {
        _isSyncing = false;
        notifyListeners();
      }
    }
  }

  Future<bool> _checkIfTransactionExistsLocally(int id) async {
    return _allTransactions.any((t) => t.id == id);
  }

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
        final endLimit = DateTime(range.end.year, range.end.month, range.end.day).add(const Duration(days: 1));
        matchDate = tx.date.isAtSameMomentAs(start) || (tx.date.isAfter(start) && tx.date.isBefore(endLimit));
      }
      bool matchCategory = category == null || category == 'All' || tx.category.toLowerCase() == category.toLowerCase();
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
      final List<dynamic> items = jsonDecode(tx.description);
      for (var item in items) {
        if (item is Map && item['name'] == itemName) {
          item['checked'] = isChecked;
          break;
        }
      }

      tx.description = jsonEncode(items);
      tx.isSynced = 0;
      await DatabaseHelper.instance.updateTransaction(tx);
      notifyListeners();
      _syncSingleTransaction(tx);
    } catch (e) {
      debugPrint("Error toggling item check: $e");
    }
  }

  // Babu ji: Smart Portion logic for clean UI (1, 2, 3 plates) and accurate prices (Cheese Ball Fix)
  Future<void> addPortionToPending(int transactionId, String itemName, bool isHalfOptionEnabled, bool isDecrement, ItemProvider itemProvider) async {
    try {
      final index = _allTransactions.indexWhere((t) => t.id == transactionId);
      if (index == -1) return;

      final originalTx = _allTransactions[index];
      final tx = TransactionModel.fromMap(originalTx.toMap());
      
      final List<dynamic> items = jsonDecode(tx.description);
      int itemIndex = items.indexWhere((i) => i['name'] == itemName);
      if (itemIndex == -1) return;

      final masterItem = itemProvider.items.firstWhere((i) => i.name == itemName);
      
      // Babu Ji Logic: Agar item mein Half option hai, toh qty 0.5 se badhegi
      double qtyChange = isHalfOptionEnabled ? 0.5 : 1.0;
      double currentQty = double.tryParse(items[itemIndex]['qty'].toString()) ?? 0;

      if (isDecrement) {
        if (currentQty <= qtyChange) {
          items.removeAt(itemIndex);
        } else {
          items[itemIndex]['qty'] = (currentQty - qtyChange).toString();
        }
      } else {
        items[itemIndex]['qty'] = (currentQty + qtyChange).toString();
      }

      if (items.isEmpty) {
        await softDeleteTransaction(transactionId, itemProvider);
        return;
      }

      // Master Pricing Recalculation (Cheese Ball 120/70 Logic)
      double newTotal = 0;
      for (var it in items) {
        String name = it['name'] ?? '';
        double q = double.tryParse(it['qty'].toString()) ?? 0;
        
        ItemModel? master;
        try { master = itemProvider.items.firstWhere((i) => i.name == name); } catch (_) {}

        if (master != null && master.halfPrice != null && master.halfPrice! > 0) {
          // Calculation: (Full Plates * Full Price) + (If 0.5 exists * Half Price)
          int fullPlatesCount = q.floor();
          double remainderHalf = q - fullPlatesCount;
          
          double itemPriceSum = (fullPlatesCount * (master.price ?? 0)) + (remainderHalf > 0 ? master.halfPrice! : 0);
          newTotal += itemPriceSum;
          
          // JSON description price update for display consistency
          it['price'] = (q == 0.5 ? master.halfPrice! : master.price!).toString();
        } else {
          double p = double.tryParse(it['price'].toString()) ?? 0;
          newTotal += (q * p);
        }
      }

      tx.description = jsonEncode(items);
      tx.amount = newTotal < 0 ? 0 : newTotal;
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
      
      final List<dynamic> items = jsonDecode(tx.description);
      int itemIndex = items.indexWhere((i) => i['name'] == itemName);
      if (itemIndex == -1) return;

      if (isDelete) {
        items.removeAt(itemIndex);
      } else {
        if (newQty != null) items[itemIndex]['qty'] = newQty.toString();
        if (newVariant != null) {
          items[itemIndex]['variant'] = newVariant;
          try {
            final masterItem = itemProvider.items.firstWhere((i) => i.name == itemName);
            items[itemIndex]['price'] = (newVariant == 'Half' ? masterItem.halfPrice : masterItem.price).toString();
          } catch (_) {}
        }
      }

      if (items.isEmpty) {
        await softDeleteTransaction(transactionId, itemProvider);
        return;
      }

      tx.description = jsonEncode(items);
      
      double newTotal = 0;
      for (var it in items) {
        double q = double.tryParse(it['qty'].toString()) ?? 0;
        double p = double.tryParse(it['price'].toString()) ?? 0;
        newTotal += (q * p);
      }
      tx.amount = newTotal;

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
          // Babu Ji: Stock piece-wise minus hona chahiye, Plate-wise nahi
          final displayQty = double.tryParse(itemMap['qty'] ?? '0') ?? 0;
          final extraQty = double.tryParse(itemMap['extra_qty'] ?? '0') ?? 0;
          final totalDisplayQty = displayQty + extraQty;
          
          double piecesToAdjust = totalDisplayQty * (masterItem.fullQty ?? 1.0);
          
          if (piecesToAdjust == 0) continue;

          bool shouldIncrease = (tx.type == 'sale') ? !isAddingEffect : isAddingEffect;
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

  double get todaySales => _activeDayTransactions(DateTime.now()).where((tx) => tx.type == 'sale').fold(0.0, (sum, tx) => sum + tx.amount);
  double get todayPurchases => _activeDayTransactions(DateTime.now()).where((tx) => tx.type == 'purchase' || tx.type == 'expense').fold(0.0, (sum, tx) => sum + tx.amount);
  double get yesterdaySales => _activeDayTransactions(DateTime.now().subtract(const Duration(days: 1))).where((tx) => tx.type == 'sale').fold(0.0, (sum, tx) => sum + tx.amount);
  
  double get cashSalesToday => _activeDayTransactions(DateTime.now()).where((tx) => tx.type == 'sale' && (tx.paymentMode == 'Cash' || tx.paymentMode == 'Split')).fold(0.0, (sum, tx) => sum + (tx.paymentMode == 'Split' ? tx.cashAmount : tx.amount));
  double get upiSalesToday => _activeDayTransactions(DateTime.now()).where((tx) => tx.type == 'sale' && (tx.paymentMode == 'UPI' || tx.paymentMode == 'Split')).fold(0.0, (sum, tx) => sum + (tx.paymentMode == 'Split' ? tx.upiAmount : tx.amount));
  double get creditSalesToday => _activeDayTransactions(DateTime.now()).where((tx) => tx.type == 'sale' && tx.paymentMode == 'Credit').fold(0.0, (sum, tx) => sum + (tx.amount - tx.paidAmount));

  double get salesGrowth {
    if (yesterdaySales == 0) return todaySales > 0 ? 100.0 : 0.0;
    return ((todaySales - yesterdaySales) / yesterdaySales) * 100;
  }

  double get avgOrderValue {
    final todayTxs = _activeDayTransactions(DateTime.now()).where((tx) => tx.type == 'sale').toList();
    if (todayTxs.isEmpty) return 0.0;
    return todaySales / todayTxs.length;
  }

  double get profitToday => todaySales - todayPurchases;

  List<TransactionModel> _activeDayTransactions(DateTime day) {
    return _allTransactions.where((tx) => 
      tx.isDeleted == 0 && 
      _normalizeStatus(tx.status) == 'completed' &&
      tx.date.year == day.year && tx.date.month == day.month && tx.date.day == day.day
    ).toList();
  }
}
