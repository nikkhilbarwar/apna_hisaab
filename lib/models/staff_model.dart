class StaffModel {
  int? id;
  String name;
  double monthlySalary;
  double advance;
  DateTime joinDate;
  String contact;
  int totalLeaves;
  int isSynced;

  StaffModel({
    this.id,
    required this.name,
    required this.monthlySalary,
    this.advance = 0,
    required this.joinDate,
    this.contact = '',
    this.totalLeaves = 0,
    this.isSynced = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'monthly_salary': monthlySalary,
      'advance': advance,
      'join_date': joinDate.toIso8601String(),
      'contact': contact,
      'total_leaves': totalLeaves,
      'is_synced': isSynced,
    };
  }

  factory StaffModel.fromMap(Map<String, dynamic> map) {
    return StaffModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      monthlySalary: (map['monthly_salary'] as num).toDouble(),
      advance: (map['advance'] as num? ?? 0).toDouble(),
      joinDate: DateTime.parse(map['join_date'] as String),
      contact: map['contact'] as String? ?? '',
      totalLeaves: map['total_leaves'] as int? ?? 0,
      isSynced: map['is_synced'] as int? ?? 0,
    );
  }

  double calculateCurrentPayable() {
    double perDaySalary = monthlySalary / 30;
    double leaveDeduction = perDaySalary * totalLeaves;
    return monthlySalary - leaveDeduction - advance;
  }
}
