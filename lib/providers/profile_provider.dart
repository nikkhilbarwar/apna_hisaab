import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import '../services/license_service.dart';
import '../services/local_auth_service.dart';
import '../services/firebase_service.dart';
import '../core/widgets/app_bottom_sheet.dart';

class ProfileProvider with ChangeNotifier {
  final FirebaseService _firebaseService = FirebaseService();
  String _businessName = 'My Business';
  String _ownerName = '';
  String _contact = '';
  String _address = '';
  String _logoPath = '';
  String _qrPath = '';
  String _qrLabel = 'Scan for Payment/Review'; 
  String _footerNote = '';
  bool _isCloudSyncEnabled = true;
  String _syncMode = 'hybrid'; // 'offline', 'online', 'hybrid'
  String _currencySymbol = '₹';
  int _themeColorValue = 0xFF5E35B1;
  List<int> _customThemeColors = [0xFF5E35B1]; 

  List<int> get customThemeColors => _customThemeColors;
  double _taxPercentage = 0.0;
  bool _isDarkMode = false;
  int _totalTables = 20;
  bool _showAmount = true;
  bool _isAutoPrintEnabled = false; 
  bool _isKotEnabled = true; 

  // Security Settings
  String _customPin = '';
  bool _isPinEnabled = false;
  bool _isBiometricEnabled = false;

  // License Logic Fields
  bool _isActivated = false;
  DateTime? _expiryDate;
  String _licenseKey = '';
  bool _isLifetime = false;
  double _amountPaid = 0.0;
  String _planType = 'N/A';
  String _licenseBusinessName = '';
  String _licenseOwnerName = '';
  String _licensePhone = '';
  bool _isReminderEnabled = true;
  bool _saleBlocked = false;
  bool _expenseBlocked = false;
  bool _isSysAdmin = false;
  String _adminRole = 'user';
  bool _isLoading = true;
  bool _hasUnreadSupportReply = false;
  StreamSubscription? _authSub;
  StreamSubscription? _licenseSub;
  StreamSubscription? _supportSub;

  bool get isSysAdmin => _isSysAdmin;
  String get adminRole => _adminRole;
  bool get hasUnreadSupportReply => _hasUnreadSupportReply;

  String get businessName => _businessName;
  String get ownerName => _ownerName;
  String get contact => _contact;
  String get address => _address;
  String get logoPath => _logoPath;
  String get qrPath => _qrPath;
  String get qrLabel => _qrLabel;
  String get footerNote => _footerNote;
  bool get isCloudSyncEnabled => _isCloudSyncEnabled;
  String get syncMode => _syncMode;
  String get currencySymbol => _currencySymbol;
  int get totalTables => _totalTables;
  bool get showAmount => _showAmount;
  bool get isAutoPrintEnabled => _isAutoPrintEnabled;
  bool get isKotEnabled => _isKotEnabled;

  String get customPin => _customPin;
  bool get isPinEnabled => _isPinEnabled;
  bool get isBiometricEnabled => _isBiometricEnabled;

  Color get themeColor => Color(_themeColorValue);
  int get themeColorValue => _themeColorValue;
  int get customThemeColor => _customThemeColors.isNotEmpty ? _customThemeColors.first : 0xFF5E35B1;
  double get taxPercentage => _taxPercentage;
  bool get isActivated => _isActivated;
  DateTime? get expiryDate => _expiryDate;
  String get licenseKey => _licenseKey;
  bool get isLifetime => _isLifetime;
  double get amountPaid => _amountPaid;
  String get planType => _planType;
  String get licenseBusinessName => _licenseBusinessName;
  String get licenseOwnerName => _licenseOwnerName;
  String get licensePhone => _licensePhone;

  String get displayBusinessName {
    // 1. अगर यूजर ने खुद नाम सेट किया है, तो वही दिखाओ
    if (_businessName.isNotEmpty && _businessName != 'My Business') {
      return _businessName;
    }
    // 2. वरना अगर लाइसेंस में कोई नाम है, तो वो दिखाओ
    if (_licenseBusinessName.isNotEmpty) {
      return _licenseBusinessName;
    }
    // 3. अगर आप एडमिन हैं और कुछ भी सेट नहीं है, तब "Support Team" दिखाओ
    if (_isSysAdmin) return "Support Team";
    
    return _businessName; // डिफ़ॉल्ट 'My Business'
  }

  String get displayOwnerName {
    if (_ownerName.isNotEmpty && _ownerName != 'Owner') return _ownerName;
    if (_licenseOwnerName.isNotEmpty) return _licenseOwnerName;
    if (_isSysAdmin) return "System Admin";
    return "Owner";
  }

  String get displayPhone {
    if (_contact.isNotEmpty) return _contact;
    if (_licensePhone.isNotEmpty) return _licensePhone;
    return "";
  }

  bool get isDarkMode => _isDarkMode;
  bool get isReminderEnabled => _isReminderEnabled;
  bool get saleBlocked => _saleBlocked;
  bool get expenseBlocked => _expenseBlocked;
  bool get isLoading => _isLoading;

  Color get scaffoldColor => _isDarkMode ? const Color(0xFF0F111A) : const Color(0xFFF8F9FE);
  Color get cardColor => _isDarkMode ? const Color(0xFF1A1D2D) : Colors.white;
  Color get textColor => _isDarkMode ? Colors.white : const Color(0xFF2D3436);
  Color get secondaryTextColor => _isDarkMode ? Colors.white60 : Colors.grey.shade600;

  List<BoxShadow> get themeShadow {
    if (_isDarkMode) {
      return [BoxShadow(color: themeColor.withValues(alpha: 0.2), blurRadius: 15, offset: const Offset(0, 4))];
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
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        loadProfile();
      } else {
        // Only reset if we are sure there is no user and we are not in initializing state
        // FirebaseAuth.instance.currentUser is a synchronous way to check
        if (FirebaseAuth.instance.currentUser == null) {
          _resetToDefaults();
        }
      }
    });
  }

  void _resetToDefaults() {
    _businessName = 'My Business';
    _isActivated = false;
    _licenseKey = '';
    _isAutoPrintEnabled = false;
    _isPinEnabled = false;
    _isBiometricEnabled = false;
    notifyListeners();
  }

  String _getUKey(String key) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    return "${key}_$uid";
  }

  Future<void> loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      _isLoading = true;
      final prefs = await SharedPreferences.getInstance();

      // Admin Check (Partitioned by UID for security)
      _isSysAdmin = prefs.getBool(_getUKey('is_sys_admin')) ?? false;
      _adminRole = prefs.getString(_getUKey('admin_role')) ?? 'user';

      // Always try to recover license key and device id from persistent storage if missing for this UID
      _licenseKey = prefs.getString(_getUKey('license_key')) ?? prefs.getString('license_key') ?? '';
      _isActivated = prefs.getBool(_getUKey('is_app_activated')) ?? (_licenseKey.isNotEmpty);

      // Check if we have local data, if not try fetching from cloud
      final hasLocalData = prefs.containsKey(_getUKey('business_name'));
      
      // Update active license key in FirebaseService for partitioning
      FirebaseService.activeLicenseKey = _licenseKey.isNotEmpty ? _licenseKey : 'NONE';
      
      if (!hasLocalData && _isCloudSyncEnabled) {
        await fetchProfileFromCloud();
      } else {
        _businessName = prefs.getString(_getUKey('business_name')) ?? 'My Business';
        _ownerName = prefs.getString(_getUKey('owner_name')) ?? '';
        _contact = prefs.getString(_getUKey('contact')) ?? '';
        _address = prefs.getString(_getUKey('address')) ?? '';
        _logoPath = prefs.getString(_getUKey('logo_path')) ?? '';
        _qrPath = prefs.getString(_getUKey('qr_path')) ?? '';
        _qrLabel = prefs.getString(_getUKey('qr_label')) ?? 'Scan for Payment/Review';
        _footerNote = prefs.getString(_getUKey('footer_note')) ?? '';
        _isCloudSyncEnabled = prefs.getBool(_getUKey('cloud_sync')) ?? true;
        _syncMode = prefs.getString(_getUKey('sync_mode')) ?? 'hybrid';
        _currencySymbol = prefs.getString(_getUKey('currency')) ?? '₹';
        _themeColorValue = prefs.getInt(_getUKey('theme_color')) ?? 0xFF5E35B1;
        final colorStrings = prefs.getStringList(_getUKey('custom_theme_colors'));
        if (colorStrings != null) {
          _customThemeColors = colorStrings.map((s) => int.parse(s)).toList();
        } else {
          _customThemeColors = [0xFF5E35B1];
        }
        _taxPercentage = prefs.getDouble(_getUKey('tax_percentage')) ?? 0.0;
        _isDarkMode = prefs.getBool(_getUKey('is_dark_mode')) ?? false;
        _totalTables = prefs.getInt(_getUKey('total_tables')) ?? 20;
        _showAmount = prefs.getBool(_getUKey('show_amount')) ?? true;
        _isAutoPrintEnabled = prefs.getBool(_getUKey('auto_print')) ?? false;
        _isKotEnabled = prefs.getBool(_getUKey('kot_enabled')) ?? true;

        _customPin = prefs.getString(_getUKey('custom_pin')) ?? '';
        _isPinEnabled = prefs.getBool(_getUKey('is_pin_enabled')) ?? false;
        _isBiometricEnabled = prefs.getBool(_getUKey('is_biometric_enabled')) ?? false;

        _isLifetime = prefs.getBool(_getUKey('is_lifetime')) ?? false;
        
        String? expiryStr = prefs.getString(_getUKey('expiry_date'));
        if (expiryStr != null && expiryStr.isNotEmpty) {
          _expiryDate = DateTime.tryParse(expiryStr);
        }

        // Start listening to license status if key exists
        if (_licenseKey.isNotEmpty) {
          // Force network verification to prevent device-to-device bypass
          _verifyLicenseStatusNetwork(_licenseKey);
          listenToLicenseRealTime();
          _listenToSupportTickets();
        }
      }
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      debugPrint("Profile Load Error: $e");
      notifyListeners();
    }
  }

  Future<bool> fetchProfileFromCloud() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final cloudData = await _firebaseService.fetchProfile();
      if (cloudData != null) {
        // First restore logo and QR if they are base64
        if (cloudData['logo_path'] != null && cloudData['logo_path'].startsWith('base64:')) {
          cloudData['logo_path'] = await _saveBase64Image(cloudData['logo_path'], 'business_logo');
        }
        if (cloudData['qr_path'] != null && cloudData['qr_path'].startsWith('base64:')) {
          cloudData['qr_path'] = await _saveBase64Image(cloudData['qr_path'], 'payment_qr');
        }

        await loadFromMap(cloudData);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Error fetching profile from cloud: $e");
      return false;
    }
  }

  Future<String?> _saveBase64Image(String base64Data, String prefix) async {
    try {
      final String pureBase64 = base64Data.replaceFirst('base64:', '');
      final bytes = base64Decode(pureBase64);
      final directory = await getApplicationDocumentsDirectory();
      final String filePath = '${directory.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      return filePath;
    } catch (e) {
      debugPrint("Error saving base64 image: $e");
      return null;
    }
  }

  Future<void> toggleAutoPrint(bool value) async {
    _isAutoPrintEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_getUKey('auto_print'), value);
    notifyListeners();
  }

  Future<bool> authenticate(BuildContext context) async {
    if (!_isPinEnabled && !_isBiometricEnabled) return true;

    bool authenticated = false;
    if (_isBiometricEnabled) {
      authenticated = await LocalAuthService.authenticate();
    }

    if (!authenticated && _isPinEnabled) {
      final pin = await _showPinVerifyDialog(context);
      authenticated = (pin == _customPin);
    }

    return authenticated;
  }

  Future<String?> _showPinVerifyDialog(BuildContext context) async {
    return await AppBottomSheet.show<String>(
      context: context,
      profile: this,
      title: 'ENTER PIN',
      child: _PinEntryBottomSheet(
        subtitle: 'Verify your 4-digit PIN to reveal data',
        profile: this,
      ),
    );
  }

  Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    
    _customPin = pin;
    _isPinEnabled = pin.isNotEmpty;
    await prefs.setString(_getUKey('custom_pin'), pin);
    await prefs.setBool(_getUKey('is_pin_enabled'), _isPinEnabled);
    
    if (_isPinEnabled) {
      _isBiometricEnabled = false;
      await prefs.setBool(_getUKey('is_biometric_enabled'), false);
    }
    
    notifyListeners();
  }

  Future<void> setBiometric(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    
    _isBiometricEnabled = enabled;
    await prefs.setBool(_getUKey('is_biometric_enabled'), enabled);
    
    if (enabled) {
      _isPinEnabled = false;
      _customPin = "";
      await prefs.setBool(_getUKey('is_pin_enabled'), false);
      await prefs.setString(_getUKey('custom_pin'), "");
    }
    
    notifyListeners();
  }

  void listenToLicenseRealTime() async {
    if (_licenseKey.isEmpty) return;
    await _licenseSub?.cancel();
    
    try {
      await LicenseService.init();
      final deviceId = await LicenseService.getDeviceId();

      _licenseSub = LicenseService.firestore.collection('licenses').doc(_licenseKey).snapshots().listen((doc) async {
        if (doc.exists) {
          final data = doc.data()!;
          bool newActivated = data['status'] == 'active';
          
          // Device Lock Check
          if (data['activated'] == true && data['activeDeviceId'] != null && data['activeDeviceId'] != deviceId) {
            newActivated = false;
          }

          if (newActivated && data['isLifetime'] != true && data['validTill'] != null) {
            final expiry = DateTime.tryParse(data['validTill']);
            if (expiry != null && expiry.isBefore(DateTime.now())) {
              newActivated = false;
            }
          }
          
          _isReminderEnabled = data['isReminderEnabled'] ?? true;
          _saleBlocked = data['saleBlocked'] ?? false;
          _expenseBlocked = data['expenseBlocked'] ?? false;
          _isLifetime = data['isLifetime'] ?? false;
          _amountPaid = (data['price'] ?? 0.0).toDouble();
          _planType = data['planType'] ?? (_isLifetime ? 'Lifetime' : 'Standard');
          _licenseBusinessName = data['restaurantName'] ?? '';
          _licenseOwnerName = data['ownerName'] ?? '';
          _licensePhone = data['phone'] ?? '';

          // Auto-link UID if missing for existing users
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser != null && data['activatedBy'] == null) {
            LicenseService.firestore.collection('licenses').doc(_licenseKey).update({
              'activatedBy': currentUser.uid,
            });
          }

          if (data['validTill'] != null) {
            _expiryDate = DateTime.tryParse(data['validTill']);
          }

          // Auto-fill profile if local profile is default/empty
          if (_businessName == 'My Business' && _licenseBusinessName.isNotEmpty) {
            _businessName = _licenseBusinessName;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_getUKey('business_name'), _businessName);
          }
          if (_ownerName.isEmpty && _licenseOwnerName.isNotEmpty) {
            _ownerName = _licenseOwnerName;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_getUKey('owner_name'), _ownerName);
          }
          if (_contact.isEmpty && _licensePhone.isNotEmpty) {
            _contact = _licensePhone;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_getUKey('contact'), _contact);
          }

          if (_isActivated != newActivated) {
            _isActivated = newActivated;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(_getUKey('is_app_activated'), _isActivated);
            if (_expiryDate != null) {
              await prefs.setString(_getUKey('expiry_date'), _expiryDate!.toIso8601String());
            }
            await prefs.setBool(_getUKey('is_lifetime'), _isLifetime);
            
            // Sync status to cloud so it persists across reloads
            if (_isCloudSyncEnabled) _syncToFirebase();
          }
          notifyListeners();
        } else {
          // Key deleted from database
          _isActivated = false;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_getUKey('is_app_activated'), false);
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint("License Listener Error: $e");
    }
  }

  Future<bool> activateLicense(String key) async {
    _licenseKey = key.trim();
    FirebaseService.activeLicenseKey = _licenseKey;
    _isActivated = true; // Set locally first to allow navigation
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_getUKey('license_key'), _licenseKey);
    await prefs.setBool(_getUKey('is_app_activated'), true);
    
    listenToLicenseRealTime();
    
    if (_isCloudSyncEnabled) {
      await _syncToFirebase();
    }
    
    notifyListeners();
    return true;
  }

  Future<void> toggleAmountVisibility(BuildContext context) async {
    if (_showAmount) {
      _showAmount = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_getUKey('show_amount'), _showAmount);
      notifyListeners();
    } else {
      final authenticated = await authenticate(context);
      if (authenticated && context.mounted) {
        _showAmount = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_getUKey('show_amount'), _showAmount);
        notifyListeners();
      }
    }
  }

  Future<void> updateThemeColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    _themeColorValue = color.toARGB32();
    
    // Add to custom colors if not already present
    if (!_customThemeColors.contains(_themeColorValue)) {
      _customThemeColors.insert(0, _themeColorValue);
      // Keep only top 10
      if (_customThemeColors.length > 10) {
        _customThemeColors = _customThemeColors.sublist(0, 10);
      }
      final colorStrings = _customThemeColors.map((c) => c.toString()).toList();
      await prefs.setStringList(_getUKey('custom_theme_colors'), colorStrings);
    }
    
    await prefs.setInt(_getUKey('theme_color'), _themeColorValue);
    notifyListeners();
    if (_isCloudSyncEnabled) _syncToFirebase();
  }

  Future<void> removeCustomColor(int colorValue) async {
    final prefs = await SharedPreferences.getInstance();
    _customThemeColors.remove(colorValue);
    final colorStrings = _customThemeColors.map((c) => c.toString()).toList();
    await prefs.setStringList(_getUKey('custom_theme_colors'), colorStrings);
    notifyListeners();
    if (_isCloudSyncEnabled) _syncToFirebase();
  }

  Future<void> savePresetTheme(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    _themeColorValue = color.toARGB32();
    await prefs.setInt(_getUKey('theme_color'), _themeColorValue);
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

  Future<void> toggleCloudSync(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    _isCloudSyncEnabled = value;
    await prefs.setBool(_getUKey('cloud_sync'), value);
    if (!value) {
      _syncMode = 'offline';
      await prefs.setString(_getUKey('sync_mode'), 'offline');
    } else if (_syncMode == 'offline') {
      _syncMode = 'hybrid';
      await prefs.setString(_getUKey('sync_mode'), 'hybrid');
    }
    notifyListeners();
    if (value) {
      String? logoB64;
      if (_logoPath.isNotEmpty && !_logoPath.startsWith('base64:')) {
        logoB64 = await _firebaseService.uploadBusinessLogo(File(_logoPath));
      }
      String? qrB64;
      if (_qrPath.isNotEmpty && !_qrPath.startsWith('base64:')) {
        qrB64 = await _firebaseService.uploadBusinessLogo(File(_qrPath));
      }
      await _syncToFirebase(overrideLogo: logoB64, overrideQR: qrB64);
    }
  }

  Future<void> updateSyncMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    _syncMode = mode;
    await prefs.setString(_getUKey('sync_mode'), mode);
    
    if (mode == 'offline') {
      _isCloudSyncEnabled = false;
      await prefs.setBool(_getUKey('cloud_sync'), false);
    } else {
      _isCloudSyncEnabled = true;
      await prefs.setBool(_getUKey('cloud_sync'), true);
    }
    
    notifyListeners();
    if (_isCloudSyncEnabled) _syncToFirebase();
  }

  Future<void> updateProfile({String? businessName, String? ownerName, String? contact, String? address, String? logoPath, String? qrPath, String? qrLabel, String? footerNote, bool? isCloudSyncEnabled, String? currencySymbol, double? taxPercentage, int? totalTables}) async {
    final prefs = await SharedPreferences.getInstance();
    if (businessName != null) { _businessName = businessName; await prefs.setString(_getUKey('business_name'), businessName); }
    if (ownerName != null) { _ownerName = ownerName; await prefs.setString(_getUKey('owner_name'), ownerName); }
    if (contact != null) { _contact = contact; await prefs.setString(_getUKey('contact'), contact); }
    if (address != null) { _address = address; await prefs.setString(_getUKey('address'), address); }
    if (footerNote != null) { _footerNote = footerNote; await prefs.setString(_getUKey('footer_note'), footerNote); }
    
    String? logoB64;
    if (logoPath != null) { 
      _logoPath = logoPath; 
      await prefs.setString(_getUKey('logo_path'), logoPath); 
      if (_isCloudSyncEnabled && logoPath.isNotEmpty && !logoPath.startsWith('base64:')) {
        logoB64 = await _firebaseService.uploadBusinessLogo(File(logoPath));
      }
    }
    
    String? qrB64;
    if (qrPath != null) { 
      _qrPath = qrPath; 
      await prefs.setString(_getUKey('qr_path'), qrPath); 
      if (_isCloudSyncEnabled && qrPath.isNotEmpty && !qrPath.startsWith('base64:')) {
        qrB64 = await _firebaseService.uploadBusinessLogo(File(qrPath));
      }
    }

    if (qrLabel != null) { _qrLabel = qrLabel; await prefs.setString(_getUKey('qr_label'), qrLabel); }
    if (isCloudSyncEnabled != null) { _isCloudSyncEnabled = isCloudSyncEnabled; await prefs.setBool(_getUKey('cloud_sync'), isCloudSyncEnabled); }
    if (currencySymbol != null) { _currencySymbol = currencySymbol; await prefs.setString(_getUKey('currency'), currencySymbol); }
    if (taxPercentage != null) { _taxPercentage = taxPercentage; await prefs.setDouble(_getUKey('tax_percentage'), taxPercentage); }
    if (totalTables != null) { _totalTables = totalTables; await prefs.setInt(_getUKey('total_tables'), totalTables); }
    
    notifyListeners();
    if (_isCloudSyncEnabled) {
      await _syncToFirebase(overrideLogo: logoB64, overrideQR: qrB64);
    }
  }

  Map<String, dynamic> getProfileMap() {
    return {
      'business_name': _businessName,
      'owner_name': _ownerName,
      'contact': _contact,
      'address': _address,
      'logo_path': _logoPath,
      'qr_path': _qrPath,
      'qr_label': _qrLabel,
      'footer_note': _footerNote,
      'sync_mode': _syncMode,
      'currency': _currencySymbol,
      'theme_color': _themeColorValue,
      'custom_theme_colors': _customThemeColors,
      'tax_percentage': _taxPercentage,
      'is_dark_mode': _isDarkMode,
      'total_tables': _totalTables,
      'show_amount': _showAmount,
      'auto_print': _isAutoPrintEnabled,
      'kot_enabled': _isKotEnabled,
      'custom_pin': _customPin,
      'is_pin_enabled': _isPinEnabled,
      'is_biometric_enabled': _isBiometricEnabled,
      'is_sys_admin': _isSysAdmin,
      'admin_role': _adminRole,
      'license_key': _licenseKey,
      'is_app_activated': _isActivated,
      'is_lifetime': _isLifetime,
      'amount_paid': _amountPaid,
      'expiry_date': _expiryDate?.toIso8601String(),
    };
  }

  bool _toBool(dynamic val) {
    if (val == null) return false;
    if (val is bool) return val;
    if (val is num) return val.toInt() != 0;
    if (val is String) {
      final s = val.toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }
    return false;
  }

  Future<void> loadFromMap(Map<String, dynamic> map) async {
    final prefs = await SharedPreferences.getInstance();

    if (map['business_name'] != null) { _businessName = map['business_name']; await prefs.setString(_getUKey('business_name'), _businessName); }
    if (map['owner_name'] != null) { _ownerName = map['owner_name']; await prefs.setString(_getUKey('owner_name'), _ownerName); }
    if (map['contact'] != null) { _contact = map['contact']; await prefs.setString(_getUKey('contact'), _contact); }
    if (map['address'] != null) { _address = map['address']; await prefs.setString(_getUKey('address'), _address); }
    if (map['logo_path'] != null) { _logoPath = map['logo_path']; await prefs.setString(_getUKey('logo_path'), _logoPath); }
    if (map['qr_path'] != null) { _qrPath = map['qr_path']; await prefs.setString(_getUKey('qr_path'), _qrPath); }
    if (map['qr_label'] != null) { _qrLabel = map['qr_label']; await prefs.setString(_getUKey('qr_label'), _qrLabel); }
    if (map['sync_mode'] != null) { _syncMode = map['sync_mode']; await prefs.setString(_getUKey('sync_mode'), _syncMode); }
    if (map['currency'] != null) { _currencySymbol = map['currency']; await prefs.setString(_getUKey('currency'), _currencySymbol); }
    
    // Theme color can be stored as 'theme_color' or 'themeColor' in older backups
    final themeCol = map['theme_color'] ?? map['themeColor'];
    if (themeCol != null) { 
      _themeColorValue = themeCol is String ? int.parse(themeCol) : themeCol; 
      await prefs.setInt(_getUKey('theme_color'), _themeColorValue); 
    }

    if (map['custom_theme_colors'] != null) {
      _customThemeColors = List<int>.from(map['custom_theme_colors']);
      await prefs.setStringList(_getUKey('custom_theme_colors'), _customThemeColors.map((e) => e.toString()).toList());
    }

    if (map['tax_percentage'] != null) { _taxPercentage = (map['tax_percentage'] as num).toDouble(); await prefs.setDouble(_getUKey('tax_percentage'), _taxPercentage); }
    
    final darkMode = map['is_dark_mode'] ?? map['isDarkMode'];
    if (darkMode != null) { 
      _isDarkMode = _toBool(darkMode);
      await prefs.setBool(_getUKey('is_dark_mode'), _isDarkMode); 
    }

    if (map['total_tables'] != null) { _totalTables = map['total_tables']; await prefs.setInt(_getUKey('total_tables'), _totalTables); }
    if (map['show_amount'] != null) { _showAmount = _toBool(map['show_amount']); await prefs.setBool(_getUKey('show_amount'), _showAmount); }
    if (map['auto_print'] != null) { _isAutoPrintEnabled = _toBool(map['auto_print']); await prefs.setBool(_getUKey('auto_print'), _isAutoPrintEnabled); }
    if (map['kot_enabled'] != null) { _isKotEnabled = _toBool(map['kot_enabled']); await prefs.setBool(_getUKey('kot_enabled'), _isKotEnabled); }
    if (map['custom_pin'] != null) { _customPin = map['custom_pin']; await prefs.setString(_getUKey('custom_pin'), _customPin); }
    if (map['is_pin_enabled'] != null) { _isPinEnabled = _toBool(map['is_pin_enabled']); await prefs.setBool(_getUKey('is_pin_enabled'), _isPinEnabled); }
    if (map['is_biometric_enabled'] != null) { _isBiometricEnabled = _toBool(map['is_biometric_enabled']); await prefs.setBool(_getUKey('is_biometric_enabled'), _isBiometricEnabled); }
    
    if (map['is_sys_admin'] != null) { 
      _isSysAdmin = _toBool(map['is_sys_admin']); 
      await prefs.setBool(_getUKey('is_sys_admin'), _isSysAdmin); 
    }
    if (map['admin_role'] != null) { 
      _adminRole = map['admin_role'].toString(); 
      await prefs.setString(_getUKey('admin_role'), _adminRole); 
    }

    if (map['license_key'] != null) { 
      _licenseKey = map['license_key'].toString().trim(); 
      await prefs.setString(_getUKey('license_key'), _licenseKey); 
    }
    if (map['is_app_activated'] != null) { _isActivated = _toBool(map['is_app_activated']); await prefs.setBool(_getUKey('is_app_activated'), _isActivated); }
    if (map['is_lifetime'] != null) { _isLifetime = _toBool(map['is_lifetime']); await prefs.setBool(_getUKey('is_lifetime'), _isLifetime); }
    if (map['amount_paid'] != null) { _amountPaid = (map['amount_paid'] as num).toDouble(); }
    if (map['expiry_date'] != null) { _expiryDate = DateTime.tryParse(map['expiry_date'].toString()); await prefs.setString(_getUKey('expiry_date'), map['expiry_date'].toString()); }

    notifyListeners();
  }


  Future<void> _syncToFirebase({String? overrideLogo, String? overrideQR}) async {
    if (!_isCloudSyncEnabled) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final profileData = getProfileMap();
      
      // Safety: Never sync a local file path to cloud. Only sync if it's base64 or overridden.
      if (overrideLogo != null) {
        profileData['logo_path'] = overrideLogo;
      } else if (_logoPath.isNotEmpty && !_logoPath.startsWith('base64:')) {
        profileData.remove('logo_path');
      }

      if (overrideQR != null) {
        profileData['qr_path'] = overrideQR;
      } else if (_qrPath.isNotEmpty && !_qrPath.startsWith('base64:')) {
        profileData.remove('qr_path');
      }

      profileData['last_updated'] = FieldValue.serverTimestamp();
      await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('profile').doc('business_info').set(profileData, SetOptions(merge: true));    } catch (e) { debugPrint("Error syncing profile: $e"); }
  }

  void _listenToSupportTickets() {
    if (_licenseKey.isEmpty) return;
    _supportSub?.cancel();
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _supportSub = FirebaseFirestore.instance
        .collection('support_tickets')
        .where('licenseKey', isEqualTo: _licenseKey)
        .where('createdBy', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) {
      bool unread = false;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['hasUnreadReply'] == true) {
          unread = true;
          break;
        }
      }
      if (_hasUnreadSupportReply != unread) {
        _hasUnreadSupportReply = unread;
        notifyListeners();
      }
    });
  }

  Future<void> markSupportAsRead() async {
    if (_licenseKey.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final batch = FirebaseFirestore.instance.batch();
    final snapshot = await FirebaseFirestore.instance
        .collection('support_tickets')
        .where('licenseKey', isEqualTo: _licenseKey)
        .where('createdBy', isEqualTo: user.uid)
        .where('hasUnreadReply', isEqualTo: true)
        .get();

    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {'hasUnreadReply': false});
    }
    
    await batch.commit();
    _hasUnreadSupportReply = false;
    notifyListeners();
  }

  Future<void> _verifyLicenseStatusNetwork(String licenseKey) async {
    try {
      final doc = await LicenseService.firestore.collection('licenses').doc(licenseKey).get();
      if (doc.exists) {
        final data = doc.data()!;
        _isActivated = data['status'] == 'active';
        _saleBlocked = data['saleBlocked'] ?? false;
        _expenseBlocked = data['expenseBlocked'] ?? false;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Network License Verification Error: $e");
    }
  }
}

class _PinEntryBottomSheet extends StatefulWidget {
  final String subtitle;
  final ProfileProvider profile;

  const _PinEntryBottomSheet({
    required this.subtitle,
    required this.profile,
  });

  @override
  State<_PinEntryBottomSheet> createState() => _PinEntryBottomSheetState();
}

class _PinEntryBottomSheetState extends State<_PinEntryBottomSheet> {
  final List<TextEditingController> _controllers =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onChanged(String value, int index) {
    if (value.length == 1 && index < 3) {
      _focusNodes[index + 1].requestFocus();
    }

    String pin = _controllers.map((c) => c.text).join();
    if (pin.length == 4) {
      Navigator.pop(context, pin);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.subtitle,
          style: TextStyle(color: profile.secondaryTextColor, fontSize: 13),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            4,
            (index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 60,
                height: 70,
                child: TextField(
                  controller: _controllers[index],
                  focusNode: _focusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  autofocus: index == 0,
                  obscureText: true,
                  onChanged: (v) => _onChanged(v, index),
                  style: TextStyle(
                    color: profile.textColor,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    counterText: "",
                    filled: true,
                    fillColor: profile.scaffoldColor,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: profile.themeColor.withValues(alpha: 0.1),
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: profile.themeColor, width: 2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'CANCEL',
            style: TextStyle(
              color: profile.secondaryTextColor,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
