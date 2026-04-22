import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import '../core/database/database_helper.dart';
import '../models/item_model.dart';
import '../models/category_model.dart';
import '../models/recipe_model.dart';
import '../services/firebase_service.dart';

class ItemProvider with ChangeNotifier {
  List<ItemModel> _items = [];
  List<CategoryModel> _categories = [];
  Map<int, List<RecipeModel>> _recipes = {}; // productId -> List<RecipeModel>
  final FirebaseService _firebaseService = FirebaseService();
  bool _isSyncing = false;

  // Alert Tracking State (using string keys to support category groups)
  final Map<String, String> _dismissedKeysToday = {}; // key -> dateString
  final Map<String, DateTime> _snoozedKeys = {}; // key -> snoozeUntil
  final Map<String, double> _lastAlertStockLevel =
      {}; // key -> stockLevelWhenAlerted

  String getStockKey(ItemModel item) {
    // 1. Linked Item priority (Take first one for the key)
    if (item.linkedItemIds.isNotEmpty) return "ITEM_${item.linkedItemIds.first}";

    // 2. Linked Category priority
    if (item.linkedCategoryIds.isNotEmpty) {
      try {
        final cat =
            _categories.firstWhere((c) => c.id == item.linkedCategoryIds.first);
        return "CAT_${cat.name.trim().toLowerCase()}";
      } catch (_) {
        return "CAT_ID_${item.linkedCategoryIds.first}";
      }
    }

    // 3. Own Category Shared Stock
    CategoryModel? cat;
    try {
      cat = _categories.firstWhere(
        (c) =>
            c.name.trim().toLowerCase() == item.category.trim().toLowerCase(),
      );
    } catch (_) {}
    if (cat != null && cat.useCategoryStock == 1) {
      return "CAT_${cat.name.trim().toLowerCase()}";
    }

    // 4. Individual Item
    return "ITEM_${item.id}";
  }

  double _getAlertCurrentValue(ItemModel item) {
    // 1. Linked Item takes highest priority for stock value
    if (item.linkedItemIds.isNotEmpty) {
      try {
        return _items.firstWhere((i) => i.id == item.linkedItemIds.first).currentStock;
      } catch (_) {}
    }

    // 2. Linked Category takes next priority
    if (item.linkedCategoryIds.isNotEmpty) {
      try {
        return _categories
            .firstWhere((c) => c.id == item.linkedCategoryIds.first)
            .stockQty;
      } catch (_) {}
    }

    // 3. Own Category Shared Stock
    CategoryModel? cat;
    try {
      cat = _categories.firstWhere(
        (c) =>
            c.name.trim().toLowerCase() == item.category.trim().toLowerCase(),
      );
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

  List<ItemModel> get deletedItems =>
      _items.where((i) => i.isDeleted == 1).toList();

  bool isLowStock(ItemModel item) {
    if (item.isDeleted == 1 || item.lowStockAlert == 0) return false;

    CategoryModel? cat;
    try {
      cat = _categories.firstWhere(
        (c) =>
            c.name.trim().toLowerCase() == item.category.trim().toLowerCase(),
      );
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
      String key = getStockKey(item);
      double currentVal = _getAlertCurrentValue(item);

      // 1. If stock level changed since last dismissal, show again
      if (_lastAlertStockLevel.containsKey(key) &&
          _lastAlertStockLevel[key] != currentVal) {
        _dismissedKeysToday.remove(key);
        _snoozedKeys.remove(key);
      }

      // 2. Don't alert if dismissed today
      if (_dismissedKeysToday[key] == todayStr) continue;

      // 3. Don't alert if snoozed
      if (_snoozedKeys.containsKey(key) && now.isBefore(_snoozedKeys[key]!))
        continue;

      // Store one representative item per alert key
      if (!alerts.containsKey(key)) {
        alerts[key] = item;
      }
    }
    return alerts.values.toList();
  }

  void dismissAlertForToday(ItemModel item) {
    String key = getStockKey(item);
    _dismissedKeysToday[key] = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _lastAlertStockLevel[key] = _getAlertCurrentValue(item);
    notifyListeners();
  }

  void snoozeAlert(ItemModel item, {int minutes = 60}) {
    String key = getStockKey(item);
    _snoozedKeys[key] = DateTime.now().add(Duration(minutes: minutes));
    _lastAlertStockLevel[key] = _getAlertCurrentValue(item);
    notifyListeners();
  }

  List<ItemModel> getItemsByCategory(String categoryName) {
    final cleanCategory = categoryName.trim().toLowerCase();
    if (cleanCategory == 'uncategorized') {
      final categoryNames = _categories
          .map((c) => c.name.trim().toLowerCase())
          .toSet();
      return _items.where((i) {
        if (i.isDeleted == 1) return false;
        final itemCat = i.category.trim().toLowerCase();
        return itemCat.isEmpty || !categoryNames.contains(itemCat);
      }).toList();
    }
    return _items
        .where(
          (item) =>
              item.isDeleted == 0 &&
              item.category.trim().toLowerCase() == cleanCategory,
        )
        .toList();
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
    Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        syncAllPendingItems();
      }
    });
  }

  Future<void> fetchItems() async {
    try {
      _items = await DatabaseHelper.instance.getAllItems();
      await _fetchRecipes();
      notifyListeners();
    } catch (e) {
      debugPrint("Error fetching items: $e");
    }
  }

  Future<void> _fetchRecipes() async {
    _recipes.clear();
    for (var item in _items) {
      if (item.id != null &&
          (item.itemType == 'selling' || item.itemType == 'readymade')) {
        final recipeMaps =
            await DatabaseHelper.instance.getRecipesByProduct(item.id!);
        if (recipeMaps.isNotEmpty) {
          _recipes[item.id!] =
              recipeMaps.map((m) => RecipeModel.fromMap(m)).toList();
        }
      }
    }
  }

  List<RecipeModel> getRecipe(int productId) => _recipes[productId] ?? [];

  Future<void> saveRecipe(int productId, List<RecipeModel> recipe) async {
    // 1. Delete from SQLite
    await DatabaseHelper.instance.deleteRecipesByProduct(productId);
    // 2. Delete from Firebase
    await _firebaseService.deleteRecipesByProductId(productId);

    for (var component in recipe) {
      final id = await DatabaseHelper.instance.insertRecipe(
        productId,
        component.materialId,
        component.quantity,
      );
      // Sync each recipe to Firebase immediately
      final newRecipe = RecipeModel(
        id: id,
        productId: productId,
        materialId: component.materialId,
        quantity: component.quantity,
      );
      await _firebaseService.syncRecipe(newRecipe);
      await DatabaseHelper.instance.updateSyncStatus('recipes', id, 1);
    }
    await _fetchRecipes();
    notifyListeners();
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

  bool isItemExists(String name, {int? excludeId, String? itemType}) {
    return _items.any(
      (item) =>
          item.name.toLowerCase().trim() == name.toLowerCase().trim() &&
          item.id != excludeId &&
          (itemType == null || item.itemType == itemType),
    );
  }

  Future<bool> addItem(ItemModel item) async {
    item.name = item.name.trim();
    item.category = item.category.trim();

    if (isItemExists(item.name, itemType: item.itemType)) return false;

    try {
      item.isSynced = 0;

      // Ensure the category exists in the categories table
      bool catExists = _categories.any(
        (c) => c.name.toLowerCase() == item.category.toLowerCase(),
      );
      if (!catExists && item.category.isNotEmpty) {
        final newCat = CategoryModel(
          name: item.category,
          type: item.itemType == 'purchase' ? 'purchase' : 'selling',
          iconName: item.itemType == 'purchase' ? 'inventory_2' : 'category',
          displayOrder: _categories.length,
        );
        await DatabaseHelper.instance.insertCategory(newCat);
        await fetchCategories(); // Refresh local category list
      }

      // Logic for Linked Stock or Shared Category Stock
      if (item.linkedItemIds.isNotEmpty) {
        try {
          item.currentStock = _items.firstWhere((i) => i.id == item.linkedItemIds.first).currentStock;
        } catch (_) {}
      } else if (item.linkedCategoryIds.isNotEmpty) {
        try {
          item.currentStock = _categories.firstWhere((c) => c.id == item.linkedCategoryIds.first).stockQty;
        } catch (_) {}
      } else {
        CategoryModel? cat;
        try {
          cat = _categories.firstWhere(
            (c) =>
                c.name.trim().toLowerCase() == item.category.trim().toLowerCase(),
          );
        } catch (_) {}
        if (cat != null && cat.useCategoryStock == 1) {
          item.currentStock = cat.stockQty;
          // Item should inherit alert setting if category alert is on
          item.lowStockAlert = 1;
          item.minStock = cat.lowStockLimit;
        }
      }

      int id = await DatabaseHelper.instance.insertItem(item);
      item.id = id;
      await fetchItems();

      _firebaseService
          .syncItem(item)
          .then((_) {
            DatabaseHelper.instance.updateSyncStatus('items', id, 1);
          })
          .catchError((e) {
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

    if (isItemExists(item.name, excludeId: item.id, itemType: item.itemType)) return false;

    try {
      item.isSynced = 0;

      // Sync stock if linked
      if (item.linkedItemIds.isNotEmpty) {
        try {
          item.currentStock = _items.firstWhere((i) => i.id == item.linkedItemIds.first).currentStock;
        } catch (_) {}
      } else if (item.linkedCategoryIds.isNotEmpty) {
        try {
          item.currentStock = _categories.firstWhere((c) => c.id == item.linkedCategoryIds.first).stockQty;
        } catch (_) {}
      } else {
        // If item moved to/is in a shared stock category, sync its stock
        CategoryModel? cat;
        try {
          cat = _categories.firstWhere(
            (c) =>
                c.name.trim().toLowerCase() == item.category.trim().toLowerCase(),
          );
        } catch (_) {}
        if (cat != null && cat.useCategoryStock == 1) {
          item.currentStock = cat.stockQty;
          // Sync alert settings too if it's a shared stock category
          if (cat.lowStockLimit != null) {
            item.minStock = cat.lowStockLimit;
          }
        }
      }

      await DatabaseHelper.instance.updateItem(item);
      await fetchItems();

      _firebaseService
          .syncItem(item)
          .then((_) {
            DatabaseHelper.instance.updateSyncStatus('items', item.id!, 1);
          })
          .catchError((e) {
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
      final categoryItems = _items
          .where((i) => i.category.trim().toLowerCase() == cleanCat)
          .toList();
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
      await DatabaseHelper.instance.deleteRecipesByProduct(id);
      await _firebaseService.deleteItem(id);
      await _firebaseService.deleteRecipesByProductId(id);
      _items.removeWhere((i) => i.id == id);
      _recipes.remove(id);
      notifyListeners();
    } catch (e) {
      debugPrint("Error permanent deleting item: $e");
    }
  }

  Future<void> adjustStock(int itemId, double quantity, bool isAdding) async {
    try {
      final item = _items.firstWhere((i) => i.id == itemId);
      
      // If this item is a CHILD (e.g. Burger linked to Bun), 
      // redirect the adjustment to the PARENT (Bun).
      if (item.linkedItemIds.isNotEmpty) {
        for (var parentId in item.linkedItemIds) {
          await adjustStock(parentId, quantity, isAdding);
        }
        return;
      }

      // If this item is part of a LINKED CATEGORY, redirect adjustment to the category pool
      // (This is handled inside updateStock, but we calculate based on category value here)
      
      double currentVal = _getAlertCurrentValue(item);
      double newStock = isAdding ? currentVal + quantity : currentVal - quantity;

      await updateStock(itemId, newStock);
    } catch (e) {
      debugPrint("Adjust Stock Error: $e");
    }
  }

  Future<void> updateStock(int id, double newStock) async {
    try {
      final item = _items.firstWhere((i) => i.id == id);

      // 1. UPDATE PRIMARY SOURCE (The record that actually holds the stock value)
      
      CategoryModel? cat;
      try {
        cat = _categories.firstWhere(
          (c) => c.name.trim().toLowerCase() == item.category.trim().toLowerCase(),
        );
      } catch (_) {}

      if (cat != null && cat.useCategoryStock == 1) {
        // A. Shared Category Logic
        await DatabaseHelper.instance.updateCategoryStock(cat.id!, newStock);
        await DatabaseHelper.instance.updateCategoryItemsStock(cat.name, newStock);
      } else if (item.linkedItemIds.isNotEmpty) {
        // B. Linked Items (Parents) Logic
        for (var parentId in item.linkedItemIds) {
          await DatabaseHelper.instance.updateItemStock(parentId, newStock);
          // If Parent belongs to a shared category, update that too
          try {
            final parent = _items.firstWhere((i) => i.id == parentId);
            final pCat = _categories.firstWhere((c) => c.name.trim().toLowerCase() == parent.category.trim().toLowerCase());
            if (pCat.useCategoryStock == 1) {
              await DatabaseHelper.instance.updateCategoryStock(pCat.id!, newStock);
              await DatabaseHelper.instance.updateCategoryItemsStock(pCat.name, newStock);
            }
          } catch (_) {}
        }
      } else {
        // C. Individual Item Stock
        await DatabaseHelper.instance.updateItemStock(id, newStock);
      }

      // 2. PROPAGATION TO LINKED CATEGORIES (Explicit links)
      if (item.linkedCategoryIds.isNotEmpty) {
        for (var catId in item.linkedCategoryIds) {
          await DatabaseHelper.instance.updateCategoryStock(catId, newStock);
          try {
            final lCat = _categories.firstWhere((c) => c.id == catId);
            await DatabaseHelper.instance.updateCategoryItemsStock(lCat.name, newStock);
          } catch (_) {}
        }
      }

      // 3. PROPAGATION TO CHILDREN (If this item is a Parent, update all its linked children)
      for (var i in _items) {
        if (i.linkedItemIds.contains(id)) {
          await DatabaseHelper.instance.updateItemStock(i.id!, newStock);
        }
      }

      // 4. SYNC UI & CLOUD
      await refreshData();
      syncAllPendingItems(); 
    } catch (e) {
      debugPrint("Deep Stock Update Error: $e");
    }
  }
}
