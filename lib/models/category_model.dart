class CategoryModel {
  int? id;
  String name;
  String iconName;
  String type; // 'selling' or 'purchase'
  int displayOrder;

  CategoryModel({
    this.id,
    required this.name,
    this.iconName = 'category',
    this.type = 'selling',
    this.displayOrder = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'icon_name': iconName,
      'type': type,
      'display_order': displayOrder,
    };
  }

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      iconName: map['icon_name'] as String? ?? 'category',
      type: map['type'] as String? ?? 'selling',
      displayOrder: map['display_order'] as int? ?? 0,
    );
  }

  CategoryModel copyWith({
    int? id,
    String? name,
    String? iconName,
    String? type,
    int? displayOrder,
  }) {
    return CategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      type: type ?? this.type,
      displayOrder: displayOrder ?? this.displayOrder,
    );
  }
}
