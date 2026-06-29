class PurchaseReminderModel {
  int? id;
  int? itemId;
  String itemName;
  String category;
  double quantity;
  double? expectedPrice;
  String? note;
  String priority; // Low, Medium, High
  DateTime dueDate;
  String status; // pending, bought, skipped
  int isSynced;
  int isDeleted;
  DateTime? deletedAt;
  DateTime? updatedAt;
  String? licenseId;

  PurchaseReminderModel({
    this.id,
    this.itemId,
    required this.itemName,
    required this.category,
    required this.quantity,
    this.expectedPrice,
    this.note,
    this.priority = 'Medium',
    required this.dueDate,
    this.status = 'pending',
    this.isSynced = 0,
    this.isDeleted = 0,
    this.deletedAt,
    this.updatedAt,
    this.licenseId,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'item_id': itemId,
      'item_name': itemName,
      'category': category,
      'quantity': quantity,
      'expected_price': expectedPrice,
      'note': note,
      'priority': priority,
      'due_date': dueDate.toIso8601String(),
      'status': status,
      'is_synced': isSynced,
      'is_deleted': isDeleted,
      'deleted_at': deletedAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'license_id': licenseId ?? 'NONE',
    };
  }

  factory PurchaseReminderModel.fromMap(Map<String, dynamic> map) {
    return PurchaseReminderModel(
      id: (map['id'] as num?)?.toInt(),
      itemId: (map['item_id'] as num?)?.toInt(),
      itemName: map['item_name']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
      quantity: (map['quantity'] as num? ?? 0).toDouble(),
      expectedPrice: map['expected_price'] != null ? (map['expected_price'] as num).toDouble() : null,
      note: map['note']?.toString(),
      priority: map['priority']?.toString() ?? 'Medium',
      dueDate: map['due_date'] != null ? (DateTime.tryParse(map['due_date'].toString()) ?? DateTime.now()) : DateTime.now(),
      status: map['status']?.toString() ?? 'pending',
      isSynced: (map['is_synced'] as num? ?? 0).toInt(),
      isDeleted: (map['is_deleted'] as num? ?? 0).toInt(),
      deletedAt: map['deleted_at'] != null ? DateTime.tryParse(map['deleted_at'].toString()) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
      licenseId: map['license_id']?.toString(),
    );
  }
}
