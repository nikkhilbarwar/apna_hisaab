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
    };
  }

  factory PurchaseReminderModel.fromMap(Map<String, dynamic> map) {
    return PurchaseReminderModel(
      id: map['id'],
      itemId: map['item_id'],
      itemName: map['item_name'] ?? '',
      category: map['category'] ?? '',
      quantity: (map['quantity'] as num? ?? 0).toDouble(),
      expectedPrice: map['expected_price'] != null ? (map['expected_price'] as num).toDouble() : null,
      note: map['note'],
      priority: map['priority'] ?? 'Medium',
      dueDate: map['due_date'] != null ? DateTime.parse(map['due_date']) : DateTime.now(),
      status: map['status'] ?? 'pending',
      isSynced: map['is_synced'] ?? 0,
    );
  }
}
