import 'dart:io';

import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/staff_model.dart';
import '../core/database/database_helper.dart';
import '../services/firebase_service.dart';

class StaffProvider with ChangeNotifier {
  List<StaffModel> _staffList = [];
  final FirebaseService _firebaseService = FirebaseService();
  bool _isSyncing = false;

  List<StaffModel> get staffList => _staffList.where((s) => s.isDeleted == 0).toList();
  List<StaffModel> get deletedStaff => _staffList.where((s) => s.isDeleted == 1).toList();
  List<StaffModel> get allStaff => _staffList;
  bool get isSyncing => _isSyncing;

  StaffProvider() {
    fetchStaff();
    _setupConnectivityListener();
  }

  void _setupConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        syncAllPendingStaff();
      }
    });
  }

  Future<void> fetchStaff() async {
    try {
      _staffList = await DatabaseHelper.instance.getAllStaff();
      // Also fetch advances and leaves for each staff to keep the totals updated
      for (var staff in _staffList) {
        final advances = await getStaffAdvances(staff.id!);
        staff.advance = advances.fold(0.0, (sum, item) => sum + item.amount);
        
        final leaves = await getStaffLeaves(staff.id!);
        staff.totalLeaves = leaves.fold(0.0, (sum, item) => sum + item.type);
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error fetching staff: $e");
    }
  }

  Future<List<StaffLeaveModel>> getStaffLeaves(int staffId) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.query('staff_leave', where: 'staff_id = ?', whereArgs: [staffId]);
    return result.map((json) => StaffLeaveModel.fromMap(json)).toList();
  }

  Future<void> toggleLeave(int staffId, DateTime date) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final dateStr = DateTime(date.year, date.month, date.day).toIso8601String();
      
      final existing = await db.query('staff_leave', 
        where: 'staff_id = ? AND date = ?', 
        whereArgs: [staffId, dateStr]
      );

      if (existing.isEmpty) {
        // Add Full Leave (1.0)
        final leave = StaffLeaveModel(staffId: staffId, date: date, type: 1.0);
        int id = await db.insert('staff_leave', leave.toMap());
        try {
          await _firebaseService.syncStaffLeave(leave..id = id);
          await DatabaseHelper.instance.updateSyncStatus('staff_leave', id, 1);
        } catch (e) {
          debugPrint("Leave Sync Error: $e");
        }
      } else {
        final currentType = (existing.first['type'] as num).toDouble();
        final leaveId = existing.first['id'] as int;
        
        if (currentType == 1.0) {
          // Switch to Half Day (0.5)
          await db.update('staff_leave', {'type': 0.5, 'is_synced': 0}, where: 'id = ?', whereArgs: [leaveId]);
          final updatedLeave = StaffLeaveModel.fromMap({...existing.first, 'type': 0.5});
          try {
            await _firebaseService.syncStaffLeave(updatedLeave);
            await DatabaseHelper.instance.updateSyncStatus('staff_leave', leaveId, 1);
          } catch (e) {
            debugPrint("Leave Update Sync Error: $e");
          }
        } else {
          // Remove Leave (Work Day)
          await db.delete('staff_leave', where: 'id = ?', whereArgs: [leaveId]);
          await _firebaseService.deleteStaffLeave(leaveId);
        }
      }
      await fetchStaff();
    } catch (e) {
      debugPrint("Error toggling leave: $e");
    }
  }

  Future<List<StaffAdvanceModel>> getStaffAdvances(int staffId) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.query('staff_advance', where: 'staff_id = ?', whereArgs: [staffId], orderBy: 'date DESC');
    return result.map((json) => StaffAdvanceModel.fromMap(json)).toList();
  }

  Future<void> addAdvance(int staffId, double amount) async {
    try {
      final advance = StaffAdvanceModel(
        staffId: staffId,
        amount: amount,
        date: DateTime.now(),
      );
      
      final db = await DatabaseHelper.instance.database;
      int id = await db.insert('staff_advance', advance.toMap());
      advance.id = id;
      
      // Update the main staff record's cached advance sum
      await fetchStaff();
      
      // Sync to Firebase
      try {
        await _firebaseService.syncStaffAdvance(advance);
        await DatabaseHelper.instance.updateSyncStatus('staff_advance', id, 1);
      } catch (e) {
        debugPrint("Advance Sync Error: $e");
      }
    } catch (e) {
      debugPrint("Error adding advance: $e");
    }
  }

  Future<void> syncAllPendingStaff() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      // Sync staff members
      final unsyncedStaff = await DatabaseHelper.instance.getUnsyncedData('staff');
      for (var map in unsyncedStaff) {
        final staff = StaffModel.fromMap(map);
        await _firebaseService.syncStaff(staff);
        await DatabaseHelper.instance.updateSyncStatus('staff', staff.id!, 1);
      }
      
      // Sync staff advances
      final unsyncedAdvances = await DatabaseHelper.instance.getUnsyncedData('staff_advance');
      for (var map in unsyncedAdvances) {
        final advance = StaffAdvanceModel.fromMap(map);
        await _firebaseService.syncStaffAdvance(advance);
        await DatabaseHelper.instance.updateSyncStatus('staff_advance', advance.id!, 1);
      }

      // Sync staff leaves
      final unsyncedLeaves = await DatabaseHelper.instance.getUnsyncedData('staff_leave');
      for (var map in unsyncedLeaves) {
        final leave = StaffLeaveModel.fromMap(map);
        await _firebaseService.syncStaffLeave(leave);
        await DatabaseHelper.instance.updateSyncStatus('staff_leave', leave.id!, 1);
      }

      await fetchStaff();
    } catch (e) {
      debugPrint("Background Staff Sync Error: $e");
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> addStaff(StaffModel staff) async {
    try {
      staff.name = staff.name.trim();
      staff.role = staff.role.trim();
      staff.isSynced = 0;
      double initialAdvance = staff.advance;
      staff.advance = 0; 

      // 1. Insert to local DB to get ID
      int id = await DatabaseHelper.instance.insertStaff(staff);
      staff.id = id;

      // 2. Handle initial advance (if any)
      if (initialAdvance > 0) {
        final advance = StaffAdvanceModel(
          staffId: id,
          amount: initialAdvance,
          date: staff.joinDate,
        );
        final db = await DatabaseHelper.instance.database;
        int advId = await db.insert('staff_advance', advance.toMap());
        advance.id = advId;
        
        try {
          await _firebaseService.syncStaffAdvance(advance);
          await DatabaseHelper.instance.updateSyncStatus('staff_advance', advId, 1);
        } catch (e) {
          debugPrint("Initial Advance Sync Error: $e");
        }
      }

      // 3. Process and upload image if exists
      if (staff.imagePath != null && staff.imagePath!.isNotEmpty) {
        final file = File(staff.imagePath!);
        if (await file.exists()) {
          final imageUrl = await _firebaseService.uploadStaffImage(file, id.toString());
          if (imageUrl != null) {
            staff.imageUrl = imageUrl;
            // Update local DB with imageUrl immediately
            await DatabaseHelper.instance.updateStaff(staff);
          }
        }
      }

      // 4. Refresh local list
      await fetchStaff();

      // 5. Sync final staff record (including imageUrl) to Firebase
      try {
        await _firebaseService.syncStaff(staff);
        await DatabaseHelper.instance.updateSyncStatus('staff', id, 1);
      } catch (e) {
        debugPrint("Immediate Staff Sync Failed: $e");
      }
    } catch (e) {
      debugPrint("Error adding staff: $e");
    }
  }

  Future<void> updateStaff(StaffModel staff) async {
    try {
      staff.name = staff.name.trim();
      staff.role = staff.role.trim();

      // 1. Find the old staff data to get the old image path
      final oldStaff = _staffList.firstWhere((s) => s.id == staff.id);
      final String? oldLocalPath = oldStaff.imagePath;

      staff.isSynced = 0;
      
      // 2. If image has changed, upload new one and delete old local file
      if (staff.imagePath != null && staff.imagePath!.isNotEmpty && 
          staff.imagePath != oldLocalPath && !staff.imagePath!.startsWith('http')) {
        
        final file = File(staff.imagePath!);
        if (await file.exists()) {
          final imageUrl = await _firebaseService.uploadStaffImage(file, staff.id.toString());
          if (imageUrl != null) {
            staff.imageUrl = imageUrl;
            
            // Delete OLD local file from phone to save space
            if (oldLocalPath != null && oldLocalPath.isNotEmpty) {
              final oldFile = File(oldLocalPath);
              if (await oldFile.exists()) {
                await oldFile.delete();
                debugPrint("Deleted old local image: $oldLocalPath");
              }
            }
          }
        }
      }

      await DatabaseHelper.instance.updateStaff(staff);
      await fetchStaff();
      
      try {
        await _firebaseService.syncStaff(staff);
        await DatabaseHelper.instance.updateSyncStatus('staff', staff.id!, 1);
      } catch (e) {
        debugPrint("Update Staff Sync Error: $e");
      }
    } catch (e) {
      debugPrint("Error updating staff: $e");
    }
  }

  Future<void> softDeleteStaff(int id) async {
    try {
      await DatabaseHelper.instance.softDeleteStaff(id);
      int index = _staffList.indexWhere((s) => s.id == id);
      if (index != -1) {
        _staffList[index].isDeleted = 1;
        _staffList[index].deletedAt = DateTime.now();
        _staffList[index].isSynced = 0;
        try {
          await _firebaseService.syncStaff(_staffList[index]);
          await DatabaseHelper.instance.updateSyncStatus('staff', id, 1);
        } catch (e) {
          debugPrint("Soft Delete Sync Error: $e");
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error soft deleting staff: $e");
    }
  }

  Future<void> restoreStaff(int id) async {
    try {
      await DatabaseHelper.instance.restoreStaff(id);
      int index = _staffList.indexWhere((s) => s.id == id);
      if (index != -1) {
        _staffList[index].isDeleted = 0;
        _staffList[index].deletedAt = null;
        _staffList[index].isSynced = 0;
        try {
          await _firebaseService.syncStaff(_staffList[index]);
          await DatabaseHelper.instance.updateSyncStatus('staff', id, 1);
        } catch (e) {
          debugPrint("Restore Sync Error: $e");
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error restoring staff: $e");
    }
  }

  Future<void> permanentDeleteStaff(int id) async {
    try {
      final staff = _staffList.firstWhere((s) => s.id == id);
      if (staff.imagePath != null && staff.imagePath!.isNotEmpty) {
        final file = File(staff.imagePath!);
        if (await file.exists()) await file.delete();
      }

      final db = await DatabaseHelper.instance.database;
      await db.delete('staff_advance', where: 'staff_id = ?', whereArgs: [id]);
      await db.delete('staff_leave', where: 'staff_id = ?', whereArgs: [id]);

      await DatabaseHelper.instance.permanentDeleteStaff(id);
      await _firebaseService.deleteStaff(id);
      _staffList.removeWhere((s) => s.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint("Error permanent deleting staff: $e");
    }
  }

  Future<void> updateAdvance(StaffAdvanceModel advance) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.update('staff_advance', advance.toMap(), where: 'id = ?', whereArgs: [advance.id]);
      
      // Sync to Firebase
      try {
        await _firebaseService.syncStaffAdvance(advance);
        await DatabaseHelper.instance.updateSyncStatus('staff_advance', advance.id!, 1);
      } catch (e) {
        debugPrint("Update Advance Sync Error: $e");
      }
      
      await fetchStaff();
    } catch (e) {
      debugPrint("Error updating advance: $e");
    }
  }

  Future<void> deleteAdvance(int id) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete('staff_advance', where: 'id = ?', whereArgs: [id]);
      
      // Sync to Firebase
      await _firebaseService.deleteStaffAdvance(id);
      
      await fetchStaff();
    } catch (e) {
      debugPrint("Error deleting advance: $e");
    }
  }

  Future<void> clearStaffAdvances(int staffId) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete('staff_advance', where: 'staff_id = ?', whereArgs: [staffId]);
      
      // Update from Firebase (Delete docs)
      await _firebaseService.deleteStaffAdvancesByStaffId(staffId);
      
      await fetchStaff();
    } catch (e) {
      debugPrint("Error clearing advances: $e");
    }
  }
  Future<void> clearStaffLeaves(int staffId) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete('staff_leaves', where: 'staff_id = ?', whereArgs: [staffId]);

      // Update from Firebase (Delete docs if needed)
      // await _firebaseService.deleteStaffLeavesByStaffId(staffId);

      await fetchStaff();
    } catch (e) {
      debugPrint("Error clearing leaves: $e");
    }
  }

  double calculatePayable(StaffModel staff) {
    return staff.calculateCurrentPayable();
  }

  DateTime calculateNextSalaryDate(DateTime joinDate) {
    DateTime now = DateTime.now();
    DateTime nextMonth = DateTime(now.year, now.month + 1, joinDate.day);
    if (nextMonth.month != (now.month + 1) % 12 && nextMonth.month != 12) {
       return DateTime(now.year, now.month + 2, 0);
    }
    return nextMonth;
  }

  double get totalMonthlySalary => _staffList.where((s) => s.isDeleted == 0).fold(0, (sum, s) => sum + s.monthlySalary);
  double get totalAdvanceGiven => _staffList.where((s) => s.isDeleted == 0).fold(0, (sum, s) => sum + s.advance);
  double get totalNetPayable => _staffList.where((s) => s.isDeleted == 0).fold(0, (sum, s) => sum + s.calculateCurrentPayable());
}
