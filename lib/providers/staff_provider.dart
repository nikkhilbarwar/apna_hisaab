import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/staff_model.dart';
import '../core/database/database_helper.dart';
import '../services/firebase_service.dart';

class StaffProvider with ChangeNotifier {
  List<StaffModel> _staffList = [];
  final FirebaseService _firebaseService = FirebaseService();
  bool _isSyncing = false;

  List<StaffModel> get staffList => _staffList;
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
      notifyListeners();
    } catch (e) {
      debugPrint("Error fetching staff: $e");
    }
  }

  Future<void> syncAllPendingStaff() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final unsynced = await DatabaseHelper.instance.getUnsyncedData('staff');
      for (var map in unsynced) {
        final staff = StaffModel.fromMap(map);
        await _firebaseService.syncStaff(staff);
        await DatabaseHelper.instance.updateSyncStatus('staff', staff.id!, 1);
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
      staff.isSynced = 0;
      int id = await DatabaseHelper.instance.insertStaff(staff);
      staff.id = id;
      await fetchStaff();
      
      _firebaseService.syncStaff(staff).then((_) {
        DatabaseHelper.instance.updateSyncStatus('staff', id, 1);
      }).catchError((e) {
         debugPrint("Immediate Staff Sync Failed, will retry on next connection: $e");
         return null;
      });
    } catch (e) {
      debugPrint("Error adding staff: $e");
    }
  }

  Future<void> updateStaff(StaffModel staff) async {
    try {
      staff.isSynced = 0;
      await DatabaseHelper.instance.updateStaff(staff);
      await fetchStaff();
      
      _firebaseService.syncStaff(staff).then((_) {
        DatabaseHelper.instance.updateSyncStatus('staff', staff.id!, 1);
      }).catchError((e) {
        debugPrint("Update Staff Sync Error: $e");
        return null;
      });
    } catch (e) {
      debugPrint("Error updating staff: $e");
    }
  }

  Future<void> addAdvance(int staffId, double newAdvanceAmount) async {
    try {
      final staff = _staffList.firstWhere((s) => s.id == staffId);
      staff.advance += newAdvanceAmount;
      await updateStaff(staff);
    } catch (e) {
      debugPrint("Error adding advance: $e");
    }
  }

  Future<void> addLeave(int staffId, int leaveDays) async {
    try {
      final staff = _staffList.firstWhere((s) => s.id == staffId);
      staff.totalLeaves += leaveDays;
      await updateStaff(staff);
    } catch (e) {
      debugPrint("Error adding leave: $e");
    }
  }

  Future<void> setLeave(int staffId, int totalLeaveDays) async {
    try {
      final staff = _staffList.firstWhere((s) => s.id == staffId);
      staff.totalLeaves = totalLeaveDays;
      await updateStaff(staff);
    } catch (e) {
      debugPrint("Error setting leave: $e");
    }
  }

  Future<void> deleteStaff(int id) async {
    try {
      await DatabaseHelper.instance.deleteStaff(id);
      await _firebaseService.deleteStaff(id);
      await fetchStaff();
    } catch (e) {
      debugPrint("Error deleting staff: $e");
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

  double get totalMonthlySalary => _staffList.fold(0, (sum, s) => sum + s.monthlySalary);
  double get totalAdvanceGiven => _staffList.fold(0, (sum, s) => sum + s.advance);
  double get totalNetPayable => _staffList.fold(0, (sum, s) => sum + s.calculateCurrentPayable());
}
