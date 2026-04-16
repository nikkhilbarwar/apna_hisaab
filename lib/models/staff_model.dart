class StaffModel {
  int? id;
  String name;
  String role; // Added role field
  double monthlySalary;
  DateTime joinDate;
  String contact;
  double totalLeaves;
  String? imagePath;
  String? imageUrl; // Added for cloud sync
  int isSynced;
  double advance; // Kept as a runtime-only property
  double runtimeDeduction = 0.0; // Transient field for accurate calculation
  int isDeleted;
  DateTime? deletedAt;

  StaffModel({
    this.id,
    required this.name,
    this.role = 'Staff', // Default role
    required this.monthlySalary,
    required this.joinDate,
    this.contact = '',
    this.totalLeaves = 0,
    this.imagePath,
    this.imageUrl,
    this.isSynced = 0,
    this.advance = 0,
    this.isDeleted = 0,
    this.deletedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'role': role,
      'monthly_salary': monthlySalary,
      'join_date': joinDate.toIso8601String(),
      'contact': contact,
      'total_leaves': totalLeaves,
      'image_path': imagePath,
      'image_url': imageUrl,
      'is_synced': isSynced,
      'is_deleted': isDeleted,
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  factory StaffModel.fromMap(Map<String, dynamic> map) {
    return StaffModel(
      id: (map['id'] as num?)?.toInt(),
      name: map['name']?.toString() ?? 'Unknown',
      role: map['role']?.toString() ?? 'Staff',
      monthlySalary: (map['monthly_salary'] as num? ?? 0).toDouble(),
      joinDate: map['join_date'] != null 
          ? DateTime.tryParse(map['join_date'].toString()) ?? DateTime.now() 
          : DateTime.now(),
      contact: map['contact']?.toString() ?? '',
      totalLeaves: (map['total_leaves'] as num? ?? 0).toDouble(),
      imagePath: map['image_path']?.toString(),
      imageUrl: map['image_url']?.toString(),
      isSynced: (map['is_synced'] as num? ?? 0).toInt(),
      advance: 0,
      isDeleted: (map['is_deleted'] as num? ?? 0).toInt(),
      deletedAt: map['deleted_at'] != null ? DateTime.tryParse(map['deleted_at'].toString()) : null,
    );
  }

  double calculateCurrentPayable(double leaveDeduction) {
    if (monthlySalary <= 0) return 0.0;
    
    // deductions = calculated leave deduction + advance
    double net = monthlySalary - leaveDeduction - advance;
    return net < 0 ? 0.0 : net;
  }
}

class StaffAdvanceModel {
  int? id;
  int staffId; // Using staffId (CamelCase)
  double amount;
  DateTime date;
  int isSynced;

  StaffAdvanceModel({
    this.id,
    required this.staffId,
    required this.amount,
    required this.date,
    this.isSynced = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'staff_id': staffId, // Map to staff_id in DB
      'amount': amount,
      'date': date.toIso8601String(),
      'is_synced': isSynced,
    };
  }

  factory StaffAdvanceModel.fromMap(Map<String, dynamic> map) {
    return StaffAdvanceModel(
      id: (map['id'] as num?)?.toInt(),
      staffId: (map['staff_id'] as num? ?? 0).toInt(),
      amount: (map['amount'] as num? ?? 0).toDouble(),
      date: map['date'] != null 
          ? DateTime.tryParse(map['date'].toString()) ?? DateTime.now() 
          : DateTime.now(),
      isSynced: (map['is_synced'] as num? ?? 0).toInt(),
    );
  }
}

class StaffLeaveModel {
  int? id;
  int staffId;
  DateTime date;
  double type; // 1.0 for full, 0.5 for half
  int isSynced;

  StaffLeaveModel({
    this.id,
    required this.staffId,
    required this.date,
    required this.type,
    this.isSynced = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'staff_id': staffId,
      'date': DateTime(date.year, date.month, date.day).toIso8601String(),
      'type': type,
      'is_synced': isSynced,
    };
  }

  factory StaffLeaveModel.fromMap(Map<String, dynamic> map) {
    return StaffLeaveModel(
      id: (map['id'] as num?)?.toInt(),
      staffId: (map['staff_id'] as num? ?? 0).toInt(),
      date: map['date'] != null 
          ? DateTime.tryParse(map['date'].toString()) ?? DateTime.now() 
          : DateTime.now(),
      type: (map['type'] as num? ?? 0).toDouble(),
      isSynced: (map['is_synced'] as num? ?? 0).toInt(),
    );
  }
}
