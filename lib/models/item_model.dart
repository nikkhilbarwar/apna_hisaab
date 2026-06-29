
import 'package:flutter/cupertino.dart';

class ItemModel {
  int? id;
  String name;
  String category;
  String unit;
  double minStock;
  double currentStock;
  double? price; 
  double? purchasePrice; // Added for profit calculation
  double? transportCost; // "Rent" or transportation cost for getting the item
  double? halfPrice; 
  String? fullUnit; 
  String? halfUnit; 
  double? fullQty; 
  double? halfQty; 
  String itemType; // 'selling' (prepared), 'purchase' (raw), 'readymade' (both)
  List<int> linkedItemIds; // Links to specific selling items
  List<int> linkedCategoryIds; // Links to selling categories (for Shared Stock)
  int isSynced;
  int lowStockAlert; 
  String? icon; // Added for custom icon support
  int isDeleted;
  DateTime? deletedAt;
  DateTime? updatedAt;
  String? licenseId;

  ItemModel({
    this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.minStock,
    required this.currentStock,
    this.price,
    this.purchasePrice,
    this.transportCost,
    this.halfPrice,
    this.fullUnit,
    this.halfUnit,
    this.fullQty,
    this.halfQty,
    this.itemType = 'selling',
    this.linkedItemIds = const [],
    this.linkedCategoryIds = const [],
    this.isSynced = 0,
    this.lowStockAlert = 1,
    this.icon,
    this.isDeleted = 0,
    this.deletedAt,
    this.updatedAt,
    this.licenseId,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'category': category,
      'unit': unit,
      'min_stock': minStock,
      'current_stock': currentStock,
      'price': price,
      'purchase_price': purchasePrice,
      'transport_cost': transportCost,
      'half_price': halfPrice,
      'full_unit': fullUnit,
      'half_unit': halfUnit,
      'full_qty': fullQty,
      'half_qty': halfQty,
      'item_type': itemType,
      'linked_item_ids': linkedItemIds.join(','),
      'linked_category_ids': linkedCategoryIds.join(','),
      'is_synced': isSynced,
      'low_stock_alert': lowStockAlert,
      'icon': icon,
      'is_deleted': isDeleted,
      'deleted_at': deletedAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'license_id': licenseId ?? 'NONE',
    };
  }

  factory ItemModel.fromMap(Map<String, dynamic> map) {
    // Validate critical fields
    if (map['name'] == null) {
      throw Exception("Missing required field: 'name'. Data: $map");
    }

    try {
      // Helper to safely parse int from various types (String, num, null)
      int? parseInt(dynamic value) {
        if (value == null) return null;
        if (value is num) return value.toInt();
        return int.tryParse(value.toString());
      }

      // Helper to safely parse double from various types
      double? parseDouble(dynamic value) {
        if (value == null) return null;
        if (value is num) return value.toDouble();
        return double.tryParse(value.toString());
      }

      // Helper to safely parse list of IDs (handles String "1,2,3", List [1,2,3], or String "[1,2,3]")
      List<int> parseIdList(dynamic value) {
        if (value == null) return [];
        if (value is List) {
          return value.map((e) => int.tryParse(e.toString())).whereType<int>().toList();
        }
        final stringValue = value.toString().trim();
        if (stringValue.isEmpty) return [];
        
        // Remove brackets if present
        final cleanString = stringValue.replaceAll('[', '').replaceAll(']', '');
        return cleanString
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .map((s) => int.tryParse(s))
            .whereType<int>()
            .toList();
      }

      return ItemModel(
        id: parseInt(map['id']),
        name: map['name'].toString(),
        category: map['category']?.toString() ?? 'General',
        unit: map['unit']?.toString() ?? 'pcs',
        minStock: parseDouble(map['min_stock']) ?? 0.0,
        currentStock: parseDouble(map['current_stock']) ?? 0.0,
        price: parseDouble(map['price']),
        purchasePrice: parseDouble(map['purchase_price']),
        transportCost: parseDouble(map['transport_cost']),
        halfPrice: parseDouble(map['half_price']),
        fullUnit: map['full_unit']?.toString(),
        halfUnit: map['half_unit']?.toString(),
        fullQty: parseDouble(map['full_qty']),
        halfQty: parseDouble(map['half_qty']),
        itemType: map['item_type']?.toString() ?? 'selling',
        linkedItemIds: parseIdList(map['linked_item_ids']),
        linkedCategoryIds: parseIdList(map['linked_category_ids']),
        isSynced: parseInt(map['is_synced'] ?? 0) ?? 0,
        lowStockAlert: parseInt(map['low_stock_alert'] ?? 1) ?? 1,
        icon: map['icon']?.toString(),
        isDeleted: parseInt(map['is_deleted'] ?? 0) ?? 0,
        deletedAt: map['deleted_at'] != null ? DateTime.tryParse(map['deleted_at'].toString()) : null,
        updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
        licenseId: map['license_id']?.toString(),
      );
    } catch (e) {
      debugPrint("🔥 ITEM PARSING ERROR: $e | DATA: $map");
      throw Exception("Parsing error: $e. Data: $map");
    }
  }

  ItemModel copyWith({
    int? id,
    String? name,
    String? category,
    String? unit,
    double? minStock,
    double? currentStock,
    double? price,
    double? purchasePrice,
    double? transportCost,
    double? halfPrice,
    String? fullUnit,
    String? halfUnit,
    double? fullQty,
    double? halfQty,
    String? itemType,
    List<int>? linkedItemIds,
    List<int>? linkedCategoryIds,
    int? isSynced,
    int? lowStockAlert,
    String? icon,
    int? isDeleted,
    DateTime? deletedAt,
    DateTime? updatedAt,
    String? licenseId,
  }) {
    return ItemModel(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      minStock: minStock ?? this.minStock,
      currentStock: currentStock ?? this.currentStock,
      price: price ?? this.price,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      transportCost: transportCost ?? this.transportCost,
      halfPrice: halfPrice ?? this.halfPrice,
      fullUnit: fullUnit ?? this.fullUnit,
      halfUnit: halfUnit ?? this.halfUnit,
      fullQty: fullQty ?? this.fullQty,
      halfQty: halfQty ?? this.halfQty,
      itemType: itemType ?? this.itemType,
      linkedItemIds: linkedItemIds ?? this.linkedItemIds,
      linkedCategoryIds: linkedCategoryIds ?? this.linkedCategoryIds,
      isSynced: isSynced ?? this.isSynced,
      lowStockAlert: lowStockAlert ?? this.lowStockAlert,
      icon: icon ?? this.icon,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      licenseId: licenseId ?? this.licenseId,
    );
  }
}
