import 'package:flutter/material.dart';
import '../models/transaction_model.dart';
import '../core/database/database_helper.dart';
import '../services/firebase_service.dart';
import 'item_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

class TransactionProvider with ChangeNotifier {
  List<TransactionModel> _allTransactions = [];
  final FirebaseService _firebaseService = FirebaseService();
  Timer? _syncTimer;
  bool _syncRequired = false;

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

  bool get hasPendingTransactions => pendingTransactions.isNotEmpty;

  List<TransactionModel> get deletedTransactions =>
      _allTransactions.where((tx) => tx.isDeleted == 1).toList();

  List<TransactionModel> get allRecentTransactions =>
      _allTransactions.where((tx) => tx.isDeleted == 0).toList();

  TransactionProvider() {
    fetchTransactions();
    _setupConnectivityListener();
    _startScheduledSync();
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

  Future<void> addTransaction(TransactionModel tx, ItemProvider itemProvider) async {
    try {
      tx.status = _normalizeStatus(tx.status).isEmpty ? 'completed' : _normalizeStatus(tx.status);
      
      int id = await DatabaseHelper.instance.insertTransaction(tx);
      tx.id = id;

      // Logic: Deduct stock even if pending (as per user request)
      await _applyStockEffect(tx, itemProvider, isAddingEffect: true);

      await fetchTransactions();
      await _syncSingleTransaction(tx);
    } catch (e) {
      debugPrint("Error adding transaction: $e");
    }
  }

  Future<void> updateTransaction(TransactionModel tx, ItemProvider itemProvider, {TransactionModel? oldTx}) async {
    try {
      tx.status = _normalizeStatus(tx.status).isEmpty ? 'completed' : _normalizeStatus(tx.status);
      tx.isSynced = 0;

      // Revert old stock effect if updating
      if (oldTx != null) {
        await _applyStockEffect(oldTx, itemProvider, isAddingEffect: false);
      }

      await DatabaseHelper.instance.updateTransaction(tx);
      
      // Apply new stock effect
      await _applyStockEffect(tx, itemProvider, isAddingEffect: true);

      await fetchTransactions();
      await _syncSingleTransaction(tx);
    } catch (e) {
      debugPrint("Error updating transaction: $e");
    }
  }

  Future<void> softDeleteTransaction(int id, ItemProvider itemProvider) async {
    try {
      final tx = _allTransactions.firstWhere((t) => t.id == id);
      await DatabaseHelper.instance.softDeleteTransaction(id);

      // Restore stock when deleted
      await _applyStockEffect(tx, itemProvider, isAddingEffect: false);

      await fetchTransactions();
      await _syncSingleTransaction(tx);
    } catch (e) {
      debugPrint("Error soft deleting transaction: $e");
    }
  }

  Future<void> restoreTransaction(int id, ItemProvider itemProvider) async {
    try {
      final tx = _allTransactions.firstWhere((t) => t.id == id);
      await DatabaseHelper.instance.restoreTransaction(id);

      // Re-deduct stock when restored
      await _applyStockEffect(tx, itemProvider, isAddingEffect: true);

      await fetchTransactions();
      await _syncSingleTransaction(tx);
    } catch (e) {
      debugPrint("Error restoring transaction: $e");
    }
  }

  Future<void> _applyStockEffect(TransactionModel tx, ItemProvider itemProvider, {required bool isAddingEffect}) async {
    final items = tx.parsedItems;
    for (var itemMap in items) {
      try {
        final itemIdStr = itemMap['id'];
        final name = itemMap['name']!;
        final qty = double.tryParse(itemMap['qty'] ?? '0') ?? 0;
        final extraQty = double.tryParse(itemMap['extra_qty'] ?? '0') ?? 0;
        final totalQty = qty + extraQty;

        if (totalQty == 0) continue;

        int? targetId = int.tryParse(itemIdStr ?? '');
        
        // If ID not found, try finding by name (fallback)
        if (targetId == null || targetId == -1) {
          try {
            targetId = itemProvider.items.firstWhere((i) => i.name == name).id;
          } catch (_) {}
        }

        if (targetId != null) {
          bool shouldIncrease;
          if (tx.type == 'sale') {
            // Sale normally decreases stock. If we are "Adding the effect", we decrease. If we are "Removing/Reverting", we increase.
            shouldIncrease = !isAddingEffect;
          } else {
            // Purchase/Expense normally increases stock.
            shouldIncrease = isAddingEffect;
          }
          await itemProvider.adjustStock(targetId, totalQty, shouldIncrease);
        }
      } catch (e) {
        debugPrint("Stock adjustment failed for item: ${itemMap['name']}, error: $e");
      }
    }
  }

  Future<void> settleCredit(int txId, double amountPaidNow) async {
    try {
      final tx = _allTransactions.firstWhere((t) => t.id == txId);
      tx.paidAmount += amountPaidNow;
      tx.isSynced = 0;
      await DatabaseHelper.instance.updateTransaction(tx);
      await fetchTransactions();
      await _syncSingleTransaction(tx);
    } catch (e) {
      debugPrint("Settle Credit Error: $e");
    }
  }

  Map<String, dynamic> getRangeStats(DateTimeRange range, double monthlyStaffSalary) {
    final filtered = _allTransactions.where((tx) {
      return tx.isDeleted == 0 &&
          _normalizeStatus(tx.status) == 'completed' &&
          tx.date.isAfter(range.start.subtract(const Duration(seconds: 1))) &&
          tx.date.isBefore(range.end.add(const Duration(days: 1)));
    }).toList();

    double sales =
    filtered.where((tx) => tx.type == 'sale').fold(0, (sum, tx) => sum + tx.amount);
    double expenses = filtered
        .where((tx) => tx.type == 'expense' || tx.type == 'purchase')
        .fold(0, (sum, tx) => sum + tx.amount);

    int days = range.duration.inDays + 1;
    double staffCost = (monthlyStaffSalary / 30) * days;
    double profit = sales - (expenses + staffCost);

    return {
      'sales': sales,
      'expenses': expenses,
      'staffCost': staffCost,
      'profit': profit,
      'transactions': filtered,
    };
  }

  Future<void> deletePermanently(int id) async {
    try {
      await DatabaseHelper.instance.deleteTransactionPermanently(id);
      await _firebaseService.deleteTransaction(id);
      await fetchTransactions();
    } catch (e) {
      debugPrint("Error permanent deleting transaction: $e");
    }
  }

  Future<void> _syncSingleTransaction(TransactionModel tx) async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.any((result) => result != ConnectivityResult.none)) {
      try {
        await _firebaseService.syncTransaction(tx);
        await DatabaseHelper.instance.updateTransactionSyncStatus(tx.id!, 1);
        await fetchTransactions();
      } catch (e) {
        debugPrint("Sync failed: $e");
      }
    }
  }

  Future<void> syncAllUnsynced() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.any((result) => result != ConnectivityResult.none)) {
      try {
        final unsynced = await DatabaseHelper.instance.getUnsyncedTransactions();
        if (unsynced.isEmpty) return;

        for (var tx in unsynced) {
          try {
            await _firebaseService.syncTransaction(tx);
            await DatabaseHelper.instance.updateTransactionSyncStatus(tx.id!, 1);
          } catch (e) {
            debugPrint("Failed to sync transaction ${tx.id}: $e");
          }
        }
        await fetchTransactions();
      } catch (e) {
        debugPrint("Error during batch sync: $e");
      }
    }
  }

  double get todaySales => _activeTodayTransactions
      .where((tx) => tx.type == 'sale' && _normalizeStatus(tx.status) == 'completed')
      .fold(0.0, (sum, tx) => sum + tx.amount);

  double get yesterdaySales {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return _allTransactions.where((tx) {
      return tx.isDeleted == 0 &&
          tx.type == 'sale' &&
          _normalizeStatus(tx.status) == 'completed' &&
          tx.date.year == yesterday.year &&
          tx.date.month == yesterday.month &&
          tx.date.day == yesterday.day;
    }).fold(0.0, (sum, tx) => sum + tx.amount);
  }

  double get salesGrowth =>
      yesterdaySales == 0 ? (todaySales > 0 ? 100 : 0) : ((todaySales - yesterdaySales) / yesterdaySales) * 100;

  double get avgOrderValue {
    final sales = _activeTodayTransactions
        .where((tx) => tx.type == 'sale' && _normalizeStatus(tx.status) == 'completed')
        .toList();
    return sales.isEmpty ? 0 : todaySales / sales.length;
  }

  double get todayExpenses => _activeTodayTransactions
      .where((tx) =>
  (tx.type == 'expense' || tx.type == 'purchase') &&
      _normalizeStatus(tx.status) == 'completed')
      .fold(0.0, (sum, tx) => sum + tx.amount);

  double get profitToday => todaySales - todayExpenses;

  double get cashSalesToday {
    double total = 0;
    for (var tx in _activeTodayTransactions.where(
          (t) => t.type == 'sale' && _normalizeStatus(t.status) == 'completed',
    )) {
      if (tx.paymentMode == 'Cash') total += tx.amount;
      else if (tx.paymentMode == 'Split') total += tx.cashAmount;
    }
    return total;
  }

  double get upiSalesToday {
    double total = 0;
    for (var tx in _activeTodayTransactions.where(
          (t) => t.type == 'sale' && _normalizeStatus(t.status) == 'completed',
    )) {
      if (tx.paymentMode == 'UPI') total += tx.amount;
      else if (tx.paymentMode == 'Split') total += tx.upiAmount;
    }
    return total;
  }

  double get creditSalesToday => _activeTodayTransactions
      .where((tx) =>
  tx.type == 'sale' &&
      tx.paymentMode == 'Credit' &&
      _normalizeStatus(tx.status) == 'completed')
      .fold(0.0, (sum, tx) => sum + tx.amount);

  List<TransactionModel> get _activeTodayTransactions {
    final now = DateTime.now();
    return _allTransactions.where((tx) {
      return tx.isDeleted == 0 &&
          tx.date.year == now.year &&
          tx.date.month == now.month &&
          tx.date.day == now.day;
    }).toList();
  }
}
