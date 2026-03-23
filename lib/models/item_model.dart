class ItemModel {
  int? id;
  String name;
  String category;
  String unit;
  double minStock;
  double currentStock;
  double? price; // Selling price for Full/Normal
  double? halfPrice; // Selling price for Half
  String? fullUnit; // e.g., '10 pc'
  String? halfUnit; // e.g., '5 pc'
  double? fullQty; // Numeric value for stock deduction (e.g., 10)
  double? halfQty; // Numeric value for stock deduction (e.g., 5)
  String itemType; // 'selling' or 'purchase'

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
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
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
    };
  }

  factory ItemModel.fromMap(Map<String, dynamic> map) {
    return ItemModel(
      id: map['id'],
      name: map['name'],
      category: map['category'],
      unit: map['unit'],
      minStock: (map['min_stock'] as num).toDouble(),
      currentStock: (map['current_stock'] as num).toDouble(),
      price: map['price'] != null ? (map['price'] as num).toDouble() : null,
      halfPrice: map['half_price'] != null ? (map['half_price'] as num).toDouble() : null,
      fullUnit: map['full_unit'],
      halfUnit: map['half_unit'],
      fullQty: map['full_qty'] != null ? (map['full_qty'] as num).toDouble() : null,
      halfQty: map['half_qty'] != null ? (map['half_qty'] as num).toDouble() : null,
      itemType: map['item_type'] ?? 'selling',
    );
  }
}
