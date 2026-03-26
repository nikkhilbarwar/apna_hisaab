import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/item_model.dart';
import '../core/database/database_helper.dart';
import '../services/firebase_service.dart';

class ItemProvider with ChangeNotifier {
  List<ItemModel> _items = [];
  final FirebaseService _firebaseService = FirebaseService();
  bool _isSyncing = false;

  List<ItemModel> get items {
    List<ItemModel> sorted = List.from(_items);
    sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return sorted;
  }

  List<ItemModel> get lowStockItems =>
      _items.where((item) => item.lowStockAlert == 1 && item.currentStock <= item.minStock).toList();

  List<ItemModel> getItemsByCategory(String category) {
    return items.where((item) => item.category == category).toList();
  }

  ItemProvider() {
    fetchItems();
    _setupConnectivityListener();
  }

  void _setupConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        syncAllPendingItems();
      }
    });
  }

  Future<void> fetchItems() async {
    try {
      _items = await DatabaseHelper.instance.getAllItems();
      notifyListeners();
    } catch (e) {
      debugPrint("Error fetching items: $e");
    }
  }

  Future<void> syncAllPendingItems() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final unsynced = await DatabaseHelper.instance.getUnsyncedData('items');
      for (var map in unsynced) {
        final item = ItemModel.fromMap(map);
        await _firebaseService.syncItem(item);
        await DatabaseHelper.instance.updateSyncStatus('items', item.id!, 1);
      }
      await fetchItems();
    } catch (e) {
      debugPrint("Background Item Sync Error: $e");
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  bool isItemExists(String name, {int? excludeId}) {
    return _items.any((item) => 
      item.name.toLowerCase().trim() == name.toLowerCase().trim() && item.id != excludeId);
  }

  Future<bool> addItem(ItemModel item) async {
    if (isItemExists(item.name)) return false;
    
    try {
      item.isSynced = 0;
      int id = await DatabaseHelper.instance.insertItem(item);
      item.id = id;
      await fetchItems();
      
      _firebaseService.syncItem(item).then((_) {
        DatabaseHelper.instance.updateSyncStatus('items', id, 1);
      }).catchError((e) {
        debugPrint("Immediate Item Sync Error: $e");
        return null;
      });
      
      return true;
    } catch (e) {
      debugPrint("Error adding item: $e");
      return false;
    }
  }

  Future<bool> updateItem(ItemModel item) async {
    if (isItemExists(item.name, excludeId: item.id)) return false;
    
    try {
      item.isSynced = 0;
      await DatabaseHelper.instance.updateItem(item);
      await fetchItems();
      
      _firebaseService.syncItem(item).then((_) {
        DatabaseHelper.instance.updateSyncStatus('items', item.id!, 1);
      }).catchError((e) {
        debugPrint("Update Item Sync Error: $e");
        return null;
      });
      
      return true;
    } catch (e) {
      debugPrint("Error updating item: $e");
      return false;
    }
  }

  Future<void> toggleLowStockAlert(int id, bool value) async {
    try {
      final item = _items.firstWhere((i) => i.id == id);
      item.lowStockAlert = value ? 1 : 0;
      await updateItem(item);
    } catch (e) {
      debugPrint("Error toggling alert: $e");
    }
  }

  Future<void> toggleCategoryAlerts(String category, bool value) async {
    try {
      final categoryItems = _items.where((i) => i.category == category).toList();
      for (var item in categoryItems) {
        item.lowStockAlert = value ? 1 : 0;
        await DatabaseHelper.instance.updateItem(item);
      }
      await fetchItems();
    } catch (e) {
      debugPrint("Error toggling category alerts: $e");
    }
  }

  Future<void> deleteItem(int id) async {
    try {
      await DatabaseHelper.instance.deleteItem(id);
      await _firebaseService.deleteItem(id);
      await fetchItems();
    } catch (e) {
      debugPrint("Error deleting item: $e");
    }
  }

  Future<void> updateStock(int id, double newStock) async {
    try {
      await DatabaseHelper.instance.updateItemStock(id, newStock);
      await fetchItems();
      final item = _items.firstWhere((i) => i.id == id);
      _firebaseService.syncItem(item).then((_) {
        DatabaseHelper.instance.updateSyncStatus('items', id, 1);
      });
    } catch (e) {
      debugPrint("Local Stock Update Error: $e");
    }
  }

  Future<void> adjustStock(int itemId, double quantity, bool isAdding) async {
    try {
      final item = _items.firstWhere((i) => i.id == itemId);
      double newStock = isAdding 
          ? item.currentStock + quantity 
          : item.currentStock - quantity;
      
      await updateStock(itemId, newStock);
    } catch (e) {
      debugPrint("Adjust Stock Error: $e");
    }
  }
}
