class SupplierModel {
  int? id;
  String name;
  String contact;
  String itemsSupplied;
  String notes;
  int isSynced;
  int isDeleted;
  DateTime? deletedAt;
  DateTime? updatedAt;

  SupplierModel({
    this.id,
    required this.name,
    this.contact = '',
    this.itemsSupplied = '',
    this.notes = '',
    this.isSynced = 0,
    this.isDeleted = 0,
    this.deletedAt,
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
      'is_deleted': isDeleted,
      'deleted_at': deletedAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
    };
  }

  factory SupplierModel.fromMap(Map<String, dynamic> map) {
    return SupplierModel(
      id: (map['id'] as num?)?.toInt(),
      name: map['name']?.toString() ?? 'Unknown',
      contact: map['contact']?.toString() ?? '',
      itemsSupplied: map['items_supplied']?.toString() ?? '',
      notes: map['notes']?.toString() ?? '',
      isSynced: (map['is_synced'] as num? ?? 0).toInt(),
      isDeleted: (map['is_deleted'] as num? ?? 0).toInt(),
      deletedAt: map['deleted_at'] != null ? DateTime.tryParse(map['deleted_at'].toString()) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
    );
  }
}
