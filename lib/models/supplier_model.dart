class SupplierModel {
  int? id;
  String name;
  String contact;
  String itemsSupplied;
  String notes;
  int isSynced;
  DateTime? updatedAt;

  SupplierModel({
    this.id,
    required this.name,
    this.contact = '',
    this.itemsSupplied = '',
    this.notes = '',
    this.isSynced = 0,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'contact': contact,
      'items_supplied': itemsSupplied,
      'notes': notes,
      'is_synced': isSynced,
      'updated_at': updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
    };
  }

  factory SupplierModel.fromMap(Map<String, dynamic> map) {
    return SupplierModel(
      id: map['id'],
      name: map['name'],
      contact: map['contact'] ?? '',
      itemsSupplied: map['items_supplied'] ?? '',
      notes: map['notes'] ?? '',
      isSynced: map['is_synced'] ?? 0,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
    );
  }
}
