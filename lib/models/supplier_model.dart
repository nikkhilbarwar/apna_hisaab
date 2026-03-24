class SupplierModel {
  int? id;
  String name;
  String contact;
  String itemsSupplied;
  String notes;
  int isSynced;

  SupplierModel({
    this.id,
    required this.name,
    this.contact = '',
    this.itemsSupplied = '',
    this.notes = '',
    this.isSynced = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'contact': contact,
      'items_supplied': itemsSupplied,
      'notes': notes,
      'is_synced': isSynced,
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
    );
  }
}
