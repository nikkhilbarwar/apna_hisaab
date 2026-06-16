import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/staff_model.dart';
import '../services/firebase_service.dart';

class StaffAuthProvider with ChangeNotifier {
  StaffModel? _currentStaff;
  bool _isStaffLoggedIn = false;
  bool _isLoading = true;

  StaffModel? get currentStaff => _currentStaff;
  bool get isStaffLoggedIn => _isStaffLoggedIn;
  bool get isLoading => _isLoading;

  StaffAuthProvider() {
    loadStaffSession();
  }

  Future<void> loadStaffSession() async {
    _isLoading = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final staffData = prefs.getString('current_staff_session');
      final licenseKey = prefs.getString('staff_license_key');
      
      if (staffData != null && licenseKey != null) {
        FirebaseService.activeLicenseKey = licenseKey;
        _currentStaff = StaffModel.fromMap(jsonDecode(staffData));
        _isStaffLoggedIn = true;
      } else {
        _currentStaff = null;
        _isStaffLoggedIn = false;
      }
    } catch (e) {
      debugPrint("Error loading staff session: $e");
      _isStaffLoggedIn = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loginStaff(StaffModel staff, String licenseKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_staff_session', jsonEncode(staff.toMap()));
      await prefs.setString('staff_license_key', licenseKey); // Save license key
      _currentStaff = staff;
      _isStaffLoggedIn = true;
      notifyListeners();
    } catch (e) {
      debugPrint("Error saving staff session: $e");
    }
  }

  Future<void> logoutStaff() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('current_staff_session');
      await prefs.remove('staff_license_key'); // Remove license key
      _currentStaff = null;
      _isStaffLoggedIn = false;
      notifyListeners();
    } catch (e) {
      debugPrint("Error clearing staff session: $e");
    }
  }

  bool hasPermission(String permission) {
    if (_currentStaff == null) return true; // Default to true for owner (Firebase session)
    try {
      final perms = jsonDecode(_currentStaff!.permissions);
      // Fallback to true for basic dashboard access if not specified
      if (permission == 'can_sale') return perms['can_sale'] ?? true;
      return perms[permission] ?? false;
    } catch (e) {
      debugPrint("Error checking permission: $e");
      return false;
    }
  }
}
