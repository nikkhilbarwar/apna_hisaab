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
  DateTime? updatedAt;
  String? licenseId;

  // New Staff Mode Fields
  bool isLoginEnabled;
  String staffCode;
  String loginPin;
  String permissions; // JSON string of permissions

  StaffModel({
    this.id,
    required this.name,
    this.role = 'Staff',
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
    this.updatedAt,
    this.licenseId,
    this.isLoginEnabled = false,
    this.staffCode = '',
    this.loginPin = '',
    this.permissions = '{"can_sale":true,"can_stock":false,"can_reports":false,"can_manage_staff":false}',
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
      'updated_at': updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'license_id': licenseId ?? 'NONE',
      'is_login_enabled': isLoginEnabled ? 1 : 0,
      'staff_code': staffCode,
      'login_pin': loginPin,
      'permissions': permissions,
    };
  }

  factory StaffModel.fromMap(Map<String, dynamic> map) {
    // Helper to safely parse int from various types
    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    // Helper to safely parse double from various types
    double parseDouble(dynamic value, double defaultValue) {
      if (value == null) return defaultValue;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? defaultValue;
    }

    return StaffModel(
      id: parseInt(map['id']),
      name: map['name']?.toString() ?? 'Unknown',
      role: map['role']?.toString() ?? 'Staff',
      monthlySalary: parseDouble(map['monthly_salary'], 0.0),
      joinDate: map['join_date'] != null
          ? DateTime.tryParse(map['join_date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      contact: map['contact']?.toString() ?? '',
      totalLeaves: parseDouble(map['total_leaves'], 0.0),
      imagePath: map['image_path']?.toString(),
      imageUrl: map['image_url']?.toString(),
      isSynced: parseInt(map['is_synced'] ?? 0) ?? 0,
      advance: 0,
      isDeleted: parseInt(map['is_deleted'] ?? 0) ?? 0,
      deletedAt: map['deleted_at'] != null ? DateTime.tryParse(map['deleted_at'].toString()) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
      licenseId: map['license_id']?.toString(),
      isLoginEnabled: (parseInt(map['is_login_enabled'] ?? 0) ?? 0) == 1,
      staffCode: map['staff_code']?.toString() ?? '',
      loginPin: map['login_pin']?.toString() ?? '',
      permissions: map['permissions']?.toString() ?? '{"can_sale":true,"can_stock":false,"can_reports":false,"can_manage_staff":false}',
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
  String status; // 'pending' or 'settled'
  int isSynced;
  DateTime? updatedAt;
  String? licenseId;

  StaffAdvanceModel({
    this.id,
    required this.staffId,
    required this.amount,
    required this.date,
    this.status = 'pending',
    this.isSynced = 0,
    this.updatedAt,
    this.licenseId,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'staff_id': staffId, // Map to staff_id in DB
      'amount': amount,
      'date': date.toIso8601String(),
      'status': status,
      'is_synced': isSynced,
      'updated_at': updatedAt?.toIso8601String() ?? date.toIso8601String(),
      'license_id': licenseId ?? 'NONE',
    };
  }

  factory StaffAdvanceModel.fromMap(Map<String, dynamic> map) {
    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    return StaffAdvanceModel(
      id: parseInt(map['id']),
      staffId: parseInt(map['staff_id']) ?? 0,
      amount: (map['amount'] as num? ?? 0).toDouble(),
      date: map['date'] != null
          ? DateTime.tryParse(map['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      status: map['status']?.toString() ?? 'pending',
      isSynced: parseInt(map['is_synced'] ?? 0) ?? 0,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
      licenseId: map['license_id']?.toString(),
    );
  }
}

class StaffLeaveModel {
  int? id;
  int staffId;
  DateTime date;
  double type; // 1.0 for full, 0.5 for half
  int isSynced;
  DateTime? updatedAt;
  String? licenseId;

  StaffLeaveModel({
    this.id,
    required this.staffId,
    required this.date,
    required this.type,
    this.isSynced = 0,
    this.updatedAt,
    this.licenseId,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'staff_id': staffId,
      'date': DateTime(date.year, date.month, date.day).toIso8601String(),
      'type': type,
      'is_synced': isSynced,
      'updated_at': updatedAt?.toIso8601String() ?? date.toIso8601String(),
      'license_id': licenseId ?? 'NONE',
    };
  }

  factory StaffLeaveModel.fromMap(Map<String, dynamic> map) {
    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    return StaffLeaveModel(
      id: parseInt(map['id']),
      staffId: parseInt(map['staff_id']) ?? 0,
      date: map['date'] != null
          ? DateTime.tryParse(map['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      type: (map['type'] as num? ?? 0).toDouble(),
      isSynced: parseInt(map['is_synced'] ?? 0) ?? 0,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
      licenseId: map['license_id']?.toString(),
    );
  }
}
