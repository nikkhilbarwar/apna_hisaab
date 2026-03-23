import 'package:flutter/material.dart';
import '../models/item_model.dart';
import '../core/database/database_helper.dart';
import '../services/firebase_service.dart';

class ItemProvider with ChangeNotifier {
  List<ItemModel> _items = [];
  final FirebaseService _firebaseService = FirebaseService();

  List<ItemModel> get items {
    List<ItemModel> sorted = List.from(_items);
    sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return sorted;
  }

  List<ItemModel> get lowStockItems =>
      _items.where((item) => item.currentStock <= item.minStock).toList();

  List<ItemModel> getItemsByCategory(String category) {
    return items.where((item) => item.category == category).toList();
  }

  Future<void> fetchItems() async {
    try {
      _items = await DatabaseHelper.instance.getAllItems();
      notifyListeners();
    } catch (e) {
      debugPrint("Error fetching items: $e");
    }
  }

  // Logic: Prevent duplicate item names
  bool isItemExists(String name, {int? excludeId}) {
    return _items.any((item) => 
      item.name.toLowerCase().trim() == name.toLowerCase().trim() && item.id != excludeId);
  }

  Future<bool> addItem(ItemModel item) async {
    if (isItemExists(item.name)) return false;
    
    try {
      int id = await DatabaseHelper.instance.insertItem(item);
      item.id = id;
      await fetchItems();
      _firebaseService.syncItem(item);
      return true;
    } catch (e) {
      debugPrint("Error adding item: $e");
      return false;
    }
  }

  Future<bool> updateItem(ItemModel item) async {
    if (isItemExists(item.name, excludeId: item.id)) return false;
    
    try {
      await DatabaseHelper.instance.updateItem(item);
      await fetchItems();
      _firebaseService.syncItem(item);
      return true;
    } catch (e) {
      debugPrint("Error updating item: $e");
      return false;
    }
  }

  Future<void> deleteItem(int id) async {
    try {
      await DatabaseHelper.instance.deleteItem(id);
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
      _firebaseService.syncItem(item).catchError((e) => debugPrint("Firebase Item Sync Error: $e"));
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
