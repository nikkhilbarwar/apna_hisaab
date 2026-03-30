class CategoryModel {
  int? id;
  String name;
  String iconName;
  String type; // 'selling' or 'purchase'
  int displayOrder;
  int useCategoryStock;
  double stockQty;
  double lowStockLimit;

  CategoryModel({
    this.id,
    required this.name,
    this.iconName = 'category',
    this.type = 'selling',
    this.displayOrder = 0,
    this.useCategoryStock = 0,
    this.stockQty = 0,
    this.lowStockLimit = 10,
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
    };
  }

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      iconName: map['icon_name'] as String? ?? 'category',
      type: map['type'] as String? ?? 'selling',
      displayOrder: map['display_order'] as int? ?? 0,
      useCategoryStock: map['use_category_stock'] as int? ?? 0,
      stockQty: (map['stock_qty'] as num? ?? 0).toDouble(),
      lowStockLimit: (map['low_stock_limit'] as num? ?? 10).toDouble(),
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
    );
  }
}
