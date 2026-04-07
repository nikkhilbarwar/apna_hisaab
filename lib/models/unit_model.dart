class UnitModel {
  int? id;
  String name;
  int isSynced;

  UnitModel({
    this.id,
    required this.name,
    this.isSynced = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'is_synced': isSynced,
    };
  }

  factory UnitModel.fromMap(Map<String, dynamic> map) {
    return UnitModel(
      id: (map['id'] as num?)?.toInt(),
      name: map['name']?.toString() ?? '',
      isSynced: (map['is_synced'] as num? ?? 0).toInt(),
    );
  }
}
