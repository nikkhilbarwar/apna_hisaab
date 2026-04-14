import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import '../models/item_model.dart';
import '../models/category_model.dart';
import '../core/database/database_helper.dart';
import '../services/firebase_service.dart';

class ItemProvider with ChangeNotifier {
  List<ItemModel> _items = [];
  List<CategoryModel> _categories = [];
  final FirebaseService _firebaseService = FirebaseService();
  bool _isSyncing = false;

  // Alert Tracking State (using string keys to support category groups)
  final Map<String, String> _dismissedKeysToday = {}; // key -> dateString
  final Map<String, DateTime> _snoozedKeys = {}; // key -> snoozeUntil
  final Map<String, double> _lastAlertStockLevel = {}; // key -> stockLevelWhenAlerted

  String _getAlertKey(ItemModel item) {
    CategoryModel? cat;
    try {
      cat = _categories.firstWhere((c) => c.name.trim().toLowerCase() == item.category.trim().toLowerCase());
    } catch (_) {}
    if (cat != null && cat.useCategoryStock == 1) {
      return "CAT_${cat.name.trim().toLowerCase()}";
    }
    return "ITEM_${item.id}";
  }

  double _getAlertCurrentValue(ItemModel item) {
    CategoryModel? cat;
    try {
      cat = _categories.firstWhere((c) => c.name.trim().toLowerCase() == item.category.trim().toLowerCase());
    } catch (_) {}
    if (cat != null && cat.useCategoryStock == 1) {
      return cat.stockQty;
    }
    return item.currentStock;
  }

  List<ItemModel> get allItems => _items;
  List<CategoryModel> get categories => _categories;

  List<ItemModel> get items {
    List<ItemModel> sorted = _items.where((i) => i.isDeleted == 0).toList();
    sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return sorted;
  }

  List<ItemModel> get deletedItems => _items.where((i) => i.isDeleted == 1).toList();

  bool isLowStock(ItemModel item) {
    if (item.isDeleted == 1 || item.lowStockAlert == 0) return false;

    CategoryModel? cat;
    try {
      cat = _categories.firstWhere((c) => c.name.trim().toLowerCase() == item.category.trim().toLowerCase());
    } catch (_) {}

    if (cat != null && cat.useCategoryStock == 1) {
      // Shared Category Stock Logic:
      // Alert triggers if Category alert is ON and stock <= category limit
      // Note: We already checked item.lowStockAlert above, which for shared items
      // is synced with the category alert status via toggleCategoryAlerts.
      return cat.stockQty <= cat.lowStockLimit;
    }

    return item.currentStock <= item.minStock;
  }

  List<ItemModel> get lowStockItems {
    return _items.where((item) => isLowStock(item)).toList();
  }

  // Items that actually need an alert popup right now based on business logic
  List<ItemModel> get pendingAlertItems {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final now = DateTime.now();
    Map<String, ItemModel> alerts = {};

    for (var item in lowStockItems) {
      String key = _getAlertKey(item);
      double currentVal = _getAlertCurrentValue(item);

      // 1. If stock level changed since last dismissal, show again
      if (_lastAlertStockLevel.containsKey(key) && _lastAlertStockLevel[key] != currentVal) {
        _dismissedKeysToday.remove(key);
        _snoozedKeys.remove(key);
      }

      // 2. Don't alert if dismissed today
      if (_dismissedKeysToday[key] == todayStr) continue;

      // 3. Don't alert if snoozed
      if (_snoozedKeys.containsKey(key) && now.isBefore(_snoozedKeys[key]!)) continue;

      // Store one representative item per alert key
      if (!alerts.containsKey(key)) {
        alerts[key] = item;
      }
    }
    return alerts.values.toList();
  }

  void dismissAlertForToday(ItemModel item) {
    String key = _getAlertKey(item);
    _dismissedKeysToday[key] = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _lastAlertStockLevel[key] = _getAlertCurrentValue(item);
    notifyListeners();
  }

  void snoozeAlert(ItemModel item, {int minutes = 60}) {
    String key = _getAlertKey(item);
    _snoozedKeys[key] = DateTime.now().add(Duration(minutes: minutes));
    _lastAlertStockLevel[key] = _getAlertCurrentValue(item);
    notifyListeners();
  }

  List<ItemModel> getItemsByCategory(String categoryName) {
    final cleanCategory = categoryName.trim().toLowerCase();
    if (cleanCategory == 'uncategorized') {
      final categoryNames = _categories.map((c) => c.name.trim().toLowerCase()).toSet();
      return _items.where((i) {
        final itemCat = i.category.trim().toLowerCase();
        return itemCat.isEmpty || !categoryNames.contains(itemCat);
      }).toList();
    }
    return _items.where((item) => item.category.trim().toLowerCase() == cleanCategory).toList();
  }

  ItemProvider() {
    refreshData();
    _setupConnectivityListener();
  }

  Future<void> refreshData() async {
    await fetchItems();
    await fetchCategories();
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

  Future<void> fetchCategories() async {
    try {
      _categories = await DatabaseHelper.instance.getAllCategories();
      notifyListeners();
    } catch (e) {
      debugPrint("Error fetching categories: $e");
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
    item.name = item.name.trim();
    item.category = item.category.trim();
    
    if (isItemExists(item.name)) return false;
    
    try {
      item.isSynced = 0;

      // If item is in a shared stock category, force it to use category stock
      CategoryModel? cat;
      try {
        cat = _categories.firstWhere((c) => c.name.trim().toLowerCase() == item.category.trim().toLowerCase());
      } catch (_) {}
      if (cat != null && cat.useCategoryStock == 1) {
        item.currentStock = cat.stockQty;
        item.lowStockAlert = 1; // Always on for shared
      }

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
    item.name = item.name.trim();
    item.category = item.category.trim();

    if (isItemExists(item.name, excludeId: item.id)) return false;
    
    try {
      item.isSynced = 0;

      // If item moved to/is in a shared stock category, sync its stock
      CategoryModel? cat;
      try {
        cat = _categories.firstWhere((c) => c.name.trim().toLowerCase() == item.category.trim().toLowerCase());
      } catch (_) {}
      if (cat != null && cat.useCategoryStock == 1) {
        item.currentStock = cat.stockQty;
      }

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
      final cleanCat = category.trim().toLowerCase();
      final categoryItems = _items.where((i) => i.category.trim().toLowerCase() == cleanCat).toList();
      for (var item in categoryItems) {
        item.lowStockAlert = value ? 1 : 0;
        await DatabaseHelper.instance.updateItem(item);
      }
      await fetchItems();
    } catch (e) {
      debugPrint("Error toggling category alerts: $e");
    }
  }

  Future<void> softDeleteItem(int id) async {
    try {
      await DatabaseHelper.instance.softDeleteItem(id);
      final index = _items.indexWhere((i) => i.id == id);
      if (index != -1) {
        _items[index].isDeleted = 1;
        _items[index].deletedAt = DateTime.now();
        _items[index].isSynced = 0;
        _firebaseService.syncItem(_items[index]);
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error soft deleting item: $e");
    }
  }

  Future<void> restoreItem(int id) async {
    try {
      await DatabaseHelper.instance.restoreItem(id);
      final index = _items.indexWhere((i) => i.id == id);
      if (index != -1) {
        _items[index].isDeleted = 0;
        _items[index].deletedAt = null;
        _items[index].isSynced = 0;
        _firebaseService.syncItem(_items[index]);
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error restoring item: $e");
    }
  }

  Future<void> permanentDeleteItem(int id) async {
    try {
      await DatabaseHelper.instance.permanentDeleteItem(id);
      await _firebaseService.deleteItem(id);
      _items.removeWhere((i) => i.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint("Error permanent deleting item: $e");
    }
  }

  Future<void> updateStock(int id, double newStock) async {
    try {
      final item = _items.firstWhere((i) => i.id == id);
      
      CategoryModel? cat;
      try {
        cat = _categories.firstWhere((c) => c.name.trim().toLowerCase() == item.category.trim().toLowerCase());
      } catch (_) {}

      if (cat != null && cat.useCategoryStock == 1) {
        // Shared Category Stock Logic:
        // Use the newStock as the NEW absolute pool value
        double newCatStock = newStock;
        
        // 1. Update Category Stock in DB
        await DatabaseHelper.instance.updateCategoryStock(cat.id!, newCatStock);

        // 2. Update ALL items in this category to have the same stock level in DB
        await DatabaseHelper.instance.updateCategoryItemsStock(cat.name, newCatStock);

        // 3. Sync all affected items to Firebase before refreshing local state
        // to ensure the local state reflects the synced status accurately if needed
        final affectedItems = _items.where((i) => i.category.trim().toLowerCase() == cat!.name.trim().toLowerCase()).toList();
        for (var ai in affectedItems) {
           _firebaseService.syncItem(ai).then((_) {
             DatabaseHelper.instance.updateSyncStatus('items', ai.id!, 1);
           });
        }

        // 4. Refresh local state (this will re-fetch everything from DB)
        await refreshData();
      } else {
        // Normal individual stock update
        await DatabaseHelper.instance.updateItemStock(id, newStock);
        await fetchItems();
        final updatedItem = _items.firstWhere((i) => i.id == id);
        _firebaseService.syncItem(updatedItem).then((_) {
          DatabaseHelper.instance.updateSyncStatus('items', id, 1);
        });
      }
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
