class CategoryModel {
  int? id;
  String name;
  String iconName;
  String type; // 'selling' or 'purchase'
  int displayOrder;
  int useCategoryStock;
  double stockQty;
  double lowStockLimit;
  int isSynced;
  int isDeleted;
  DateTime? deletedAt;

  CategoryModel({
    this.id,
    required this.name,
    this.iconName = 'category',
    this.type = 'selling',
    this.displayOrder = 0,
    this.useCategoryStock = 0,
    this.stockQty = 0,
    this.lowStockLimit = 10,
    this.isSynced = 0,
    this.isDeleted = 0,
    this.deletedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'icon_name': iconName,
      'type': type,
      'display_order': displayOrder,
      'use_category_stock': useCategoryStock,
      'stock_qty': stockQty,
      'low_stock_limit': lowStockLimit,
      'is_synced': isSynced,
      'is_deleted': isDeleted,
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: (map['id'] as num?)?.toInt(),
      name: map['name']?.toString() ?? 'General',
      iconName: map['icon_name']?.toString() ?? 'category',
      type: map['type']?.toString() ?? 'selling',
      displayOrder: (map['display_order'] as num? ?? 0).toInt(),
      useCategoryStock: (map['use_category_stock'] as num? ?? 0).toInt(),
      stockQty: (map['stock_qty'] as num? ?? 0).toDouble(),
      lowStockLimit: (map['low_stock_limit'] as num? ?? 10).toDouble(),
      isSynced: (map['is_synced'] as num? ?? 0).toInt(),
      isDeleted: (map['is_deleted'] as num? ?? 0).toInt(),
      deletedAt: map['deleted_at'] != null ? DateTime.tryParse(map['deleted_at'].toString()) : null,
    );
  }

  CategoryModel copyWith({
    int? id,
    String? name,
    String? iconName,
    String? type,
    int? displayOrder,
    int? useCategoryStock,
    double? stockQty,
    double? lowStockLimit,
    int? isSynced,
    int? isDeleted,
    DateTime? deletedAt,
  }) {
    return CategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      type: type ?? this.type,
      displayOrder: displayOrder ?? this.displayOrder,
      useCategoryStock: useCategoryStock ?? this.useCategoryStock,
      stockQty: stockQty ?? this.stockQty,
      lowStockLimit: lowStockLimit ?? this.lowStockLimit,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
