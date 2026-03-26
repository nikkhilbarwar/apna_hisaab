import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/license_service.dart';

class ProfileProvider with ChangeNotifier {
  String _businessName = 'My Business';
  String _ownerName = '';
  String _contact = '';
  String _address = '';
  String _logoPath = '';
  bool _isCloudSyncEnabled = true;
  String _currencySymbol = '₹';
  int _themeColorValue = 0xFF5E35B1;
  double _taxPercentage = 0.0;
  bool _isDarkMode = false;
  int _totalTables = 20;

  // License Logic Fields
  bool _isActivated = false;
  DateTime? _expiryDate;
  String _licenseKey = '';
  bool _isLifetime = false;
  bool _isReminderEnabled = true;
  bool _saleBlocked = false;
  bool _expenseBlocked = false;
  
  // Real-time listener subscription
  StreamSubscription? _licenseSub;

  String get businessName => _businessName;
  String get ownerName => _ownerName;
  String get contact => _contact;
  String get address => _address;
  String get logoPath => _logoPath;
  bool get isCloudSyncEnabled => _isCloudSyncEnabled;
  String get currencySymbol => _currencySymbol;
  int get totalTables => _totalTables;
  
  Color get themeColor {
    try {
      return _isDarkMode ? const Color(0xDDFF9F00) : Color(_themeColorValue);
    } catch (e) {
      return Colors.deepPurple;
    }
  }
  
  int get themeColorValue => _themeColorValue;
  double get taxPercentage => _taxPercentage;
  bool get isActivated => _isActivated;
  DateTime? get expiryDate => _expiryDate;
  String get licenseKey => _licenseKey;
  bool get isLifetime => _isLifetime;
  bool get isDarkMode => _isDarkMode;
  bool get isReminderEnabled => _isReminderEnabled;
  bool get saleBlocked => _saleBlocked;
  bool get expenseBlocked => _expenseBlocked;

  Color get scaffoldColor => _isDarkMode ? const Color(0xFF10142A) : const Color(0xFFF8F9FE);
  Color get cardColor => _isDarkMode ? const Color(0xFF1B263B) : Colors.white;
  Color get textColor => _isDarkMode ? Colors.white : Colors.black87;
  
  Color get secondaryTextColor {
    if (_isDarkMode) return Colors.white70;
    return Colors.grey.shade600;
  }

  List<BoxShadow> get themeShadow {
    if (_isDarkMode) {
      return [BoxShadow(color: const Color(0xDDFF9F00).withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 4))];
    }
    return [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))];
  }

  int get remainingDays {
    if (_isLifetime) return 9999;
    if (_expiryDate == null) return 0;
    try {
      final diff = _expiryDate!.difference(DateTime.now()).inDays;
      return diff > 0 ? diff : 0;
    } catch (e) {
      return 0;
    }
  }

  ProfileProvider() {
    loadProfile();
  }

  String _getUKey(String key) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    return "${key}_$uid";
  }

  Future<void> loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;

    try {
      final prefs = await SharedPreferences.getInstance();
      _businessName = prefs.getString('business_name_$uid') ?? 'My Business';
      _ownerName = prefs.getString('owner_name_$uid') ?? '';
      _contact = prefs.getString('contact_$uid') ?? '';
      _address = prefs.getString('address_$uid') ?? '';
      _logoPath = prefs.getString('logo_path_$uid') ?? '';
      _isCloudSyncEnabled = prefs.getBool('cloud_sync_$uid') ?? true;
      _currencySymbol = prefs.getString('currency_$uid') ?? '₹';
      _themeColorValue = prefs.getInt('theme_color_$uid') ?? 0xFF5E35B1;
      _taxPercentage = prefs.getDouble('tax_percentage_$uid') ?? 0.0;
      _isDarkMode = prefs.getBool('is_dark_mode_$uid') ?? false;
      _totalTables = prefs.getInt('total_tables_$uid') ?? 20;

      _licenseKey = prefs.getString('license_key_$uid') ?? '';
      _isActivated = prefs.getBool('is_app_activated_$uid') ?? false;
      _isLifetime = prefs.getBool('is_lifetime_$uid') ?? false;
      
      String? expiryStr = prefs.getString('expiry_date_$uid');
      if (expiryStr != null && expiryStr.isNotEmpty) {
        _expiryDate = DateTime.tryParse(expiryStr);
      }

      notifyListeners();
      
      if (_licenseKey.isNotEmpty) {
        listenToLicenseRealTime();
      }
    } catch (e) {
      debugPrint("Profile Load Error: $e");
    }
  }

  // logic: Real-time listener for instant blocking/activation
  void listenToLicenseRealTime() async {
    if (_licenseKey.isEmpty) return;
    await _licenseSub?.cancel();
    
    try {
      await LicenseService.init();
      _licenseSub = LicenseService.firestore.collection('licenses').doc(_licenseKey).snapshots().listen((doc) async {
        if (doc.exists) {
          final data = doc.data()!;
          
          bool newActivated = data['status'] == 'active';
          
          // Expiry Check
          if (newActivated && data['isLifetime'] != true && data['validTill'] != null) {
            final expiry = DateTime.tryParse(data['validTill']);
            if (expiry != null && expiry.isBefore(DateTime.now())) {
              newActivated = false;
            }
          }

          _isReminderEnabled = data['isReminderEnabled'] ?? true;
          _saleBlocked = data['saleBlocked'] ?? false;
          _expenseBlocked = data['expenseBlocked'] ?? false;

          if (_isActivated != newActivated) {
            _isActivated = newActivated;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(_getUKey('is_app_activated'), _isActivated);
            notifyListeners();
          }
        }
      });
    } catch (e) {
      debugPrint("License Listener Error: $e");
    }
  }

  Future<bool> activateLicense(String key) async {
    _licenseKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_getUKey('license_key'), key);
    listenToLicenseRealTime();
    return _isActivated;
  }

  Future<void> updateThemeColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    _themeColorValue = color.toARGB32();
    await prefs.setInt(_getUKey('theme_color'), color.toARGB32());
    notifyListeners();
    if (_isCloudSyncEnabled) _syncToFirebase();
  }

  Future<void> toggleDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = value;
    await prefs.setBool(_getUKey('is_dark_mode'), value);
    notifyListeners();
    if (_isCloudSyncEnabled) _syncToFirebase();
  }

  Future<void> updateProfile({String? businessName, String? ownerName, String? contact, String? address, String? logoPath, bool? isCloudSyncEnabled, String? currencySymbol, double? taxPercentage, int? totalTables}) async {
    final prefs = await SharedPreferences.getInstance();
    if (businessName != null) { _businessName = businessName; await prefs.setString(_getUKey('business_name'), businessName); }
    if (ownerName != null) { _ownerName = ownerName; await prefs.setString(_getUKey('owner_name'), ownerName); }
    if (contact != null) { _contact = contact; await prefs.setString(_getUKey('contact'), contact); }
    if (address != null) { _address = address; await prefs.setString(_getUKey('address'), address); }
    if (logoPath != null) { _logoPath = logoPath; await prefs.setString(_getUKey('logo_path'), logoPath); }
    if (isCloudSyncEnabled != null) { _isCloudSyncEnabled = isCloudSyncEnabled; await prefs.setBool(_getUKey('cloud_sync'), isCloudSyncEnabled); }
    if (currencySymbol != null) { _currencySymbol = currencySymbol; await prefs.setString(_getUKey('currency'), currencySymbol); }
    if (taxPercentage != null) { _taxPercentage = taxPercentage; await prefs.setDouble(_getUKey('tax_percentage'), taxPercentage); }
    if (totalTables != null) { _totalTables = totalTables; await prefs.setInt(_getUKey('total_tables'), totalTables); }
    notifyListeners();
    if (_isCloudSyncEnabled) _syncToFirebase();
  }

  Future<void> _syncToFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('profile').doc('business_info').set({
        'business_name': _businessName, 'owner_name': _ownerName, 'contact': _contact, 'address': _address,
        'currency': _currencySymbol, 'theme_color': _themeColorValue, 'expiry_date': _expiryDate?.toIso8601String(), 
        'tax_percentage': _taxPercentage, 'is_dark_mode': _isDarkMode, 'total_tables': _totalTables, 'last_updated': FieldValue.serverTimestamp(),
      });
    } catch (e) { debugPrint("Error syncing profile: $e"); }
  }

  @override
  void dispose() {
    _licenseSub?.cancel();
    super.dispose();
  }
}
