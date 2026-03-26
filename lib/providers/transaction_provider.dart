import 'package:flutter/material.dart';
import '../models/transaction_model.dart';
import '../core/database/database_helper.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';
import 'item_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

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
      bool matchType = type == 'all' || tx.type == type;
      bool matchDelete = tx.isDeleted == 0;
      bool matchStatus = status == null || _normalizeStatus(tx.status) == _normalizeStatus(status);
      bool matchDate = true;
      if (range != null) {
        final start = DateTime(range.start.year, range.start.month, range.start.day);
        final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
        matchDate = tx.date.isAfter(start.subtract(const Duration(seconds: 1))) && 
                    tx.date.isBefore(end);
      }
      bool matchCategory = category == null || category == 'All' || tx.category == category;
      bool matchItem = itemName == null || itemName.isEmpty || tx.parsedItems.any((i) => 
          (i['name'] ?? '').toLowerCase().contains(itemName.toLowerCase()));

      return matchType && matchDelete && matchStatus && matchDate && matchCategory && matchItem;
    }).toList();
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
      
      // If completed, cancel reminders
      if (tx.status == 'completed' && tx.id != null) {
        await NotificationService().cancelOrderReminders(tx.id!);
      }

      await fetchTransactions();
      _syncSingleTransaction(tx);
    } catch (e) {
      debugPrint("Error updating transaction: $e");
    }
  }

  Future<void> softDeleteTransaction(int id, ItemProvider itemProvider) async {
    try {
      final tx = _allTransactions.firstWhere((t) => t.id == id);
      await DatabaseHelper.instance.softDeleteTransaction(id);
      await _applyStockEffect(tx, itemProvider, isAddingEffect: false);
      
      // Cancel notifications upon delete
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

  Future<void> _applyStockEffect(TransactionModel tx, ItemProvider itemProvider, {required bool isAddingEffect}) async {
    final items = tx.parsedItems;
    for (var itemMap in items) {
      try {
        final name = itemMap['name']!;
        final qty = double.tryParse(itemMap['qty'] ?? '0') ?? 0;
        final extraQty = double.tryParse(itemMap['extra_qty'] ?? '0') ?? 0;
        final totalQty = qty + extraQty;
        if (totalQty == 0) continue;

        int? targetId;
        try { targetId = itemProvider.items.firstWhere((i) => i.name == name).id; } catch (_) {}

        if (targetId != null) {
          bool shouldIncrease = (tx.type == 'sale') ? !isAddingEffect : isAddingEffect;
          await itemProvider.adjustStock(targetId, totalQty, shouldIncrease);
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
