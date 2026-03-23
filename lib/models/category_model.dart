class CategoryModel {
  int? id;
  String name;
  String iconName;
  String type; // 'selling' or 'purchase'

  CategoryModel({
    this.id,
    required this.name,
    this.iconName = 'category',
    this.type = 'selling',
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'icon_name': iconName,
      'type': type,
    };
  }

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      iconName: map['icon_name'] as String? ?? 'category',
      type: map['type'] as String? ?? 'selling',
    );
  }
}
