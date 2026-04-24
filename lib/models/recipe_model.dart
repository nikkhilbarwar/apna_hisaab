class RecipeModel {
  final int? id;
  final int productId; // Item being sold
  final int materialId; // Raw material being consumed
  final double quantity; // Quantity of material per unit of product
  int isSynced;
  DateTime? updatedAt;

  RecipeModel({
    this.id,
    required this.productId,
    required this.materialId,
    required this.quantity,
    this.isSynced = 0,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'product_id': productId,
      'material_id': materialId,
      'quantity': quantity,
      'is_synced': isSynced,
      'updated_at': updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
    };
  }

  factory RecipeModel.fromMap(Map<String, dynamic> map) {
    return RecipeModel(
      id: map['id'] as int?,
      productId: map['product_id'] as int,
      materialId: map['material_id'] as int,
      quantity: (map['quantity'] as num).toDouble(),
      isSynced: map['is_synced'] as int? ?? 0,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
    );
  }
}
