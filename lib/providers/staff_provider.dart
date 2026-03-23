import 'package:flutter/material.dart';
import '../models/staff_model.dart';
import '../core/database/database_helper.dart';
import '../services/firebase_service.dart';

class StaffProvider with ChangeNotifier {
  List<StaffModel> _staffList = [];
  final FirebaseService _firebaseService = FirebaseService();

  List<StaffModel> get staffList => _staffList;

  Future<void> fetchStaff() async {
    try {
      _staffList = await DatabaseHelper.instance.getAllStaff();
      notifyListeners();
    } catch (e) {
      print("Error fetching staff: $e");
    }
  }

  // Sync Down from Cloud
  Future<void> syncDownFromCloud() async {
    try {
      final cloudStaff = await _firebaseService.fetchAllStaff();
      for (var s in cloudStaff) {
        await DatabaseHelper.instance.updateStaff(s);
      }
      await fetchStaff();
    } catch (e) {
      print("Error syncing down staff: $e");
    }
  }

  Future<void> addStaff(StaffModel staff) async {
    try {
      int id = await DatabaseHelper.instance.insertStaff(staff);
      staff.id = id;
      await fetchStaff();
      await _firebaseService.syncStaff(staff);
    } catch (e) {
      print("Error adding staff: $e");
    }
  }

  Future<void> updateStaff(StaffModel staff) async {
    try {
      await DatabaseHelper.instance.updateStaff(staff);
      await fetchStaff();
      await _firebaseService.syncStaff(staff);
    } catch (e) {
      print("Error updating staff: $e");
    }
  }

  // logic: user just enters new advance, it adds up automatically
  Future<void> addAdvance(int staffId, double newAdvanceAmount) async {
    try {
      final staff = _staffList.firstWhere((s) => s.id == staffId);
      staff.advance += newAdvanceAmount;
      await updateStaff(staff);
    } catch (e) {
      print("Error adding advance: $e");
    }
  }

  // logic: update leave days (set total instead of adding)
  Future<void> setLeave(int staffId, int totalLeaveDays) async {
    try {
      final staff = _staffList.firstWhere((s) => s.id == staffId);
      staff.totalLeaves = totalLeaveDays;
      await updateStaff(staff);
    } catch (e) {
      print("Error setting leave: $e");
    }
  }

  // logic: add leave days
  Future<void> addLeave(int staffId, int leaveDays) async {
    try {
      final staff = _staffList.firstWhere((s) => s.id == staffId);
      staff.totalLeaves += leaveDays;
      await updateStaff(staff);
    } catch (e) {
      print("Error adding leave: $e");
    }
  }

  Future<void> deleteStaff(int id) async {
    try {
      await DatabaseHelper.instance.deleteStaff(id);
      await _firebaseService.deleteStaff(id);
      await fetchStaff();
    } catch (e) {
      print("Error deleting staff: $e");
    }
  }

  double get totalMonthlySalary => _staffList.fold(0, (sum, s) => sum + s.monthlySalary);
  double get totalAdvanceGiven => _staffList.fold(0, (sum, s) => sum + s.advance);
  double get totalNetPayable => _staffList.fold(0, (sum, s) => sum + calculatePayable(s));

  double calculatePayable(StaffModel staff) {
    return staff.calculateCurrentPayable();
  }

  DateTime calculateNextSalaryDate(DateTime joinDate) {
    DateTime now = DateTime.now();
    // Logic: Same day next month
    DateTime nextMonth = DateTime(now.year, now.month + 1, joinDate.day);
    // Adjust if day doesn't exist in next month (e.g. 31st)
    if (nextMonth.month != (now.month + 1) % 12 && nextMonth.month != 12) {
       return DateTime(now.year, now.month + 2, 0); // Last day of target month
    }
    return nextMonth;
  }
}
