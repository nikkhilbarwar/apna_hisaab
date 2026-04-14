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
  int isSynced; 
  int lowStockAlert; 
  String? icon; // Added for custom icon support
  int isDeleted;
  DateTime? deletedAt;

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
    this.isSynced = 0,
    this.lowStockAlert = 1,
    this.icon,
    this.isDeleted = 0,
    this.deletedAt,
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
      'is_synced': isSynced,
      'low_stock_alert': lowStockAlert,
      'icon': icon,
      'is_deleted': isDeleted,
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  factory ItemModel.fromMap(Map<String, dynamic> map) {
    return ItemModel(
      id: (map['id'] as num?)?.toInt(),
      name: map['name']?.toString() ?? '',
      category: map['category']?.toString() ?? 'General',
      unit: map['unit']?.toString() ?? 'pcs',
      minStock: (map['min_stock'] as num? ?? 0).toDouble(),
      currentStock: (map['current_stock'] as num? ?? 0).toDouble(),
      price: map['price'] != null ? (map['price'] as num).toDouble() : null,
      purchasePrice: map['purchase_price'] != null ? (map['purchase_price'] as num).toDouble() : null,
      transportCost: map['transport_cost'] != null ? (map['transport_cost'] as num).toDouble() : null,
      halfPrice: map['half_price'] != null ? (map['half_price'] as num).toDouble() : null,
      fullUnit: map['full_unit']?.toString(),
      halfUnit: map['half_unit']?.toString(),
      fullQty: map['full_qty'] != null ? (map['full_qty'] as num).toDouble() : null,
      halfQty: map['half_qty'] != null ? (map['half_qty'] as num).toDouble() : null,
      itemType: map['item_type']?.toString() ?? 'selling',
      isSynced: (map['is_synced'] as num? ?? 0).toInt(),
      lowStockAlert: (map['low_stock_alert'] as num? ?? 1).toInt(),
      icon: map['icon']?.toString(),
      isDeleted: (map['is_deleted'] as num? ?? 0).toInt(),
      deletedAt: map['deleted_at'] != null ? DateTime.tryParse(map['deleted_at'].toString()) : null,
    );
  }
}
