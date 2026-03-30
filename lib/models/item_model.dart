class ItemModel {
  int? id;
  String name;
  String category;
  String unit;
  double minStock;
  double currentStock;
  double? price; 
  double? halfPrice; 
  String? fullUnit; 
  String? halfUnit; 
  double? fullQty; 
  double? halfQty; 
  String itemType; 
  int isSynced; 
  int lowStockAlert; 
  String? icon; // Added for custom icon support

  ItemModel({
    this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.minStock,
    required this.currentStock,
    this.price,
    this.halfPrice,
    this.fullUnit,
    this.halfUnit,
    this.fullQty,
    this.halfQty,
    this.itemType = 'selling',
    this.isSynced = 0,
    this.lowStockAlert = 1,
    this.icon,
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
      'half_price': halfPrice,
      'full_unit': fullUnit,
      'half_unit': halfUnit,
      'full_qty': fullQty,
      'half_qty': halfQty,
      'item_type': itemType,
      'is_synced': isSynced,
      'low_stock_alert': lowStockAlert,
      'icon': icon,
    };
  }

  factory ItemModel.fromMap(Map<String, dynamic> map) {
    return ItemModel(
      id: map['id'],
      name: map['name'] ?? '',
      category: map['category'] ?? 'General',
      unit: map['unit'] ?? 'pcs',
      minStock: (map['min_stock'] as num? ?? 0).toDouble(),
      currentStock: (map['current_stock'] as num? ?? 0).toDouble(),
      price: map['price'] != null ? (map['price'] as num).toDouble() : null,
      halfPrice: map['half_price'] != null ? (map['half_price'] as num).toDouble() : null,
      fullUnit: map['full_unit'],
      halfUnit: map['half_unit'],
      fullQty: map['full_qty'] != null ? (map['full_qty'] as num).toDouble() : null,
      halfQty: map['half_qty'] != null ? (map['half_qty'] as num).toDouble() : null,
      itemType: map['item_type'] ?? 'selling',
      isSynced: map['is_synced'] ?? 0,
      lowStockAlert: map['low_stock_alert'] ?? 1,
      icon: map['icon'],
    );
  }
}
