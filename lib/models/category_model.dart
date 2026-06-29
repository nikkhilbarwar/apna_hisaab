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
  DateTime? updatedAt;
  String? licenseId;

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
    this.updatedAt,
    this.licenseId,
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
      'updated_at': updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'license_id': licenseId ?? 'NONE',
    };
  }

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    // Helper to safely parse int from various types
    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    // Helper to safely parse double from various types
    double parseDouble(dynamic value, double defaultValue) {
      if (value == null) return defaultValue;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? defaultValue;
    }

    return CategoryModel(
      id: parseInt(map['id']),
      name: map['name']?.toString() ?? 'General',
      iconName: map['icon_name']?.toString() ?? 'category',
      type: map['type']?.toString() ?? 'selling',
      displayOrder: parseInt(map['display_order'] ?? 0) ?? 0,
      useCategoryStock: parseInt(map['use_category_stock'] ?? 0) ?? 0,
      stockQty: parseDouble(map['stock_qty'], 0.0),
      lowStockLimit: parseDouble(map['low_stock_limit'], 10.0),
      isSynced: parseInt(map['is_synced'] ?? 0) ?? 0,
      isDeleted: parseInt(map['is_deleted'] ?? 0) ?? 0,
      deletedAt: map['deleted_at'] != null ? DateTime.tryParse(map['deleted_at'].toString()) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
      licenseId: map['license_id']?.toString(),
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
    DateTime? updatedAt,
    String? licenseId,
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
      updatedAt: updatedAt ?? this.updatedAt,
      licenseId: licenseId ?? this.licenseId,
    );
  }
}
