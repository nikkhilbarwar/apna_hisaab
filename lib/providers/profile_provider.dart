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

class ProfileProvider with ChangeNotifier {
  final FirebaseService _firebaseService = FirebaseService();
  String _businessName = 'My Business';
  String _ownerName = '';
  String _contact = '';
  String _address = '';
  String _logoPath = '';
  String _qrPath = '';
  String _qrLabel = 'Scan for Payment/Review'; 
  bool _isCloudSyncEnabled = true;
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
  bool _isReminderEnabled = true;
  bool _saleBlocked = false;
  bool _expenseBlocked = false;
  bool _isLoading = true;
  
  StreamSubscription? _licenseSub;
  StreamSubscription? _authSub;

  String get businessName => _businessName;
  String get ownerName => _ownerName;
  String get contact => _contact;
  String get address => _address;
  String get logoPath => _logoPath;
  String get qrPath => _qrPath;
  String get qrLabel => _qrLabel;
  bool get isCloudSyncEnabled => _isCloudSyncEnabled;
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
    final uid = user.uid;

    try {
      _isLoading = true;
      final prefs = await SharedPreferences.getInstance();
      
      // Check if we have local data, if not try fetching from cloud
      final hasLocalData = prefs.containsKey('business_name_$uid');
      
      if (!hasLocalData && _isCloudSyncEnabled) {
        await fetchProfileFromCloud();
      } else {
        _businessName = prefs.getString('business_name_$uid') ?? 'My Business';
        _ownerName = prefs.getString('owner_name_$uid') ?? '';
        _contact = prefs.getString('contact_$uid') ?? '';
        _address = prefs.getString('address_$uid') ?? '';
        _logoPath = prefs.getString('logo_path_$uid') ?? '';
        _qrPath = prefs.getString('qr_path_$uid') ?? '';
        _qrLabel = prefs.getString('qr_label_$uid') ?? 'Scan for Payment/Review';
        _isCloudSyncEnabled = prefs.getBool('cloud_sync_$uid') ?? true;
        _currencySymbol = prefs.getString('currency_$uid') ?? '₹';
        _themeColorValue = prefs.getInt('theme_color_$uid') ?? 0xFF5E35B1;
        final colorStrings = prefs.getStringList('custom_theme_colors_$uid');
        if (colorStrings != null) {
          _customThemeColors = colorStrings.map((s) => int.parse(s)).toList();
        } else {
          _customThemeColors = [0xFF5E35B1];
        }
        _taxPercentage = prefs.getDouble('tax_percentage_$uid') ?? 0.0;
        _isDarkMode = prefs.getBool('is_dark_mode_$uid') ?? false;
        _totalTables = prefs.getInt('total_tables_$uid') ?? 20;
        _showAmount = prefs.getBool('show_amount_$uid') ?? true;
        _isAutoPrintEnabled = prefs.getBool('auto_print_$uid') ?? false;
        _isKotEnabled = prefs.getBool('kot_enabled_$uid') ?? true;

        _customPin = prefs.getString('custom_pin_$uid') ?? '';
        _isPinEnabled = prefs.getBool('is_pin_enabled_$uid') ?? false;
        _isBiometricEnabled = prefs.getBool('is_biometric_enabled_$uid') ?? false;

        _licenseKey = prefs.getString('license_key_$uid') ?? '';
        _isActivated = prefs.getBool('is_app_activated_$uid') ?? false;
        _isLifetime = prefs.getBool('is_lifetime_$uid') ?? false;
        
        String? expiryStr = prefs.getString('expiry_date_$uid');
        if (expiryStr != null && expiryStr.isNotEmpty) {
          _expiryDate = DateTime.tryParse(expiryStr);
        }
      }

      _isLoading = false;
      notifyListeners();
      
      if (_licenseKey.isNotEmpty) {
        listenToLicenseRealTime();
      }
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
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    _isAutoPrintEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_print_$uid', value);
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
    return await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return _PinEntryDialog(
          title: 'ENTER PIN',
          subtitle: 'Verify your 4-digit PIN to reveal data',
          themeColor: themeColor,
          cardColor: cardColor,
          textColor: textColor,
          scaffoldColor: scaffoldColor,
          secondaryTextColor: secondaryTextColor,
        );
      },
    );
  }

  Future<void> setPin(String pin) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    final prefs = await SharedPreferences.getInstance();
    
    _customPin = pin;
    _isPinEnabled = pin.isNotEmpty;
    await prefs.setString('custom_pin_$uid', pin);
    await prefs.setBool('is_pin_enabled_$uid', _isPinEnabled);
    
    if (_isPinEnabled) {
      _isBiometricEnabled = false;
      await prefs.setBool('is_biometric_enabled_$uid', false);
    }
    
    notifyListeners();
  }

  Future<void> setBiometric(bool enabled) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    final prefs = await SharedPreferences.getInstance();
    
    _isBiometricEnabled = enabled;
    await prefs.setBool('is_biometric_enabled_$uid', enabled);
    
    if (enabled) {
      _isPinEnabled = false;
      _customPin = "";
      await prefs.setBool('is_pin_enabled_$uid', false);
      await prefs.setString('custom_pin_$uid', "");
    }
    
    notifyListeners();
  }

  void listenToLicenseRealTime() async {
    if (_licenseKey.isEmpty) return;
    await _licenseSub?.cancel();
    
    try {
      await LicenseService.init();
      _licenseSub = LicenseService.firestore.collection('licenses').doc(_licenseKey).snapshots().listen((doc) async {
        if (doc.exists) {
          final data = doc.data()!;
          bool newActivated = data['status'] == 'active';
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
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    final prefs = await SharedPreferences.getInstance();
    _isCloudSyncEnabled = value;
    await prefs.setBool('cloud_sync_$uid', value);
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

  Future<void> updateProfile({String? businessName, String? ownerName, String? contact, String? address, String? logoPath, String? qrPath, String? qrLabel, bool? isCloudSyncEnabled, String? currencySymbol, double? taxPercentage, int? totalTables}) async {
    final prefs = await SharedPreferences.getInstance();
    if (businessName != null) { _businessName = businessName; await prefs.setString(_getUKey('business_name'), businessName); }
    if (ownerName != null) { _ownerName = ownerName; await prefs.setString(_getUKey('owner_name'), ownerName); }
    if (contact != null) { _contact = contact; await prefs.setString(_getUKey('contact'), contact); }
    if (address != null) { _address = address; await prefs.setString(_getUKey('address'), address); }
    
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
      'license_key': _licenseKey,
      'is_app_activated': _isActivated,
      'is_lifetime': _isLifetime,
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
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    final prefs = await SharedPreferences.getInstance();

    if (map['business_name'] != null) { _businessName = map['business_name']; await prefs.setString('business_name_$uid', _businessName); }
    if (map['owner_name'] != null) { _ownerName = map['owner_name']; await prefs.setString('owner_name_$uid', _ownerName); }
    if (map['contact'] != null) { _contact = map['contact']; await prefs.setString('contact_$uid', _contact); }
    if (map['address'] != null) { _address = map['address']; await prefs.setString('address_$uid', _address); }
    if (map['logo_path'] != null) { _logoPath = map['logo_path']; await prefs.setString('logo_path_$uid', _logoPath); }
    if (map['qr_path'] != null) { _qrPath = map['qr_path']; await prefs.setString('qr_path_$uid', _qrPath); }
    if (map['qr_label'] != null) { _qrLabel = map['qr_label']; await prefs.setString('qr_label_$uid', _qrLabel); }
    if (map['currency'] != null) { _currencySymbol = map['currency']; await prefs.setString('currency_$uid', _currencySymbol); }
    
    // Theme color can be stored as 'theme_color' or 'themeColor' in older backups
    final themeCol = map['theme_color'] ?? map['themeColor'];
    if (themeCol != null) { 
      _themeColorValue = themeCol is String ? int.parse(themeCol) : themeCol; 
      await prefs.setInt('theme_color_$uid', _themeColorValue); 
    }

    if (map['custom_theme_colors'] != null) {
      _customThemeColors = List<int>.from(map['custom_theme_colors']);
      await prefs.setStringList('custom_theme_colors_$uid', _customThemeColors.map((e) => e.toString()).toList());
    }

    if (map['tax_percentage'] != null) { _taxPercentage = (map['tax_percentage'] as num).toDouble(); await prefs.setDouble('tax_percentage_$uid', _taxPercentage); }
    
    final darkMode = map['is_dark_mode'] ?? map['isDarkMode'];
    if (darkMode != null) { 
      _isDarkMode = _toBool(darkMode);
      await prefs.setBool('is_dark_mode_$uid', _isDarkMode); 
    }

    if (map['total_tables'] != null) { _totalTables = map['total_tables']; await prefs.setInt('total_tables_$uid', _totalTables); }
    if (map['show_amount'] != null) { _showAmount = _toBool(map['show_amount']); await prefs.setBool('show_amount_$uid', _showAmount); }
    if (map['auto_print'] != null) { _isAutoPrintEnabled = _toBool(map['auto_print']); await prefs.setBool('auto_print_$uid', _isAutoPrintEnabled); }
    if (map['kot_enabled'] != null) { _isKotEnabled = _toBool(map['kot_enabled']); await prefs.setBool('kot_enabled_$uid', _isKotEnabled); }
    if (map['custom_pin'] != null) { _customPin = map['custom_pin']; await prefs.setString('custom_pin_$uid', _customPin); }
    if (map['is_pin_enabled'] != null) { _isPinEnabled = _toBool(map['is_pin_enabled']); await prefs.setBool('is_pin_enabled_$uid', _isPinEnabled); }
    if (map['is_biometric_enabled'] != null) { _isBiometricEnabled = _toBool(map['is_biometric_enabled']); await prefs.setBool('is_biometric_enabled_$uid', _isBiometricEnabled); }
    if (map['license_key'] != null) { _licenseKey = map['license_key']; await prefs.setString('license_key_$uid', _licenseKey); }
    if (map['is_app_activated'] != null) { _isActivated = _toBool(map['is_app_activated']); await prefs.setBool('is_app_activated_$uid', _isActivated); }
    if (map['is_lifetime'] != null) { _isLifetime = _toBool(map['is_lifetime']); await prefs.setBool('is_lifetime_$uid', _isLifetime); }
    if (map['expiry_date'] != null) { _expiryDate = DateTime.tryParse(map['expiry_date'].toString()); await prefs.setString('expiry_date_$uid', map['expiry_date'].toString()); }

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
      await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('profile').doc('business_info').set(profileData, SetOptions(merge: true));
    } catch (e) { debugPrint("Error syncing profile: $e"); }
  }

  @override
  void dispose() {
    _licenseSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}

class _PinEntryDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final Color themeColor;
  final Color cardColor;
  final Color textColor;
  final Color scaffoldColor;
  final Color secondaryTextColor;

  const _PinEntryDialog({
    required this.title,
    required this.subtitle,
    required this.themeColor,
    required this.cardColor,
    required this.textColor,
    required this.scaffoldColor,
    required this.secondaryTextColor,
  });

  @override
  State<_PinEntryDialog> createState() => _PinEntryDialogState();
}

class _PinEntryDialogState extends State<_PinEntryDialog> {
  final List<TextEditingController> _controllers = List.generate(4, (_) => TextEditingController());
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
    return AlertDialog(
      backgroundColor: widget.cardColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Center(child: Text(widget.title, style: TextStyle(color: widget.themeColor, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1))),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.subtitle, style: TextStyle(color: widget.secondaryTextColor, fontSize: 12)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8), 
              child: SizedBox(
                width: 55,
                child: TextField(
                  controller: _controllers[index],
                  focusNode: _focusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  autofocus: index == 0,
                  obscureText: true,
                  onChanged: (v) => _onChanged(v, index),
                  style: TextStyle(color: widget.textColor, fontSize: 24, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    counterText: "",
                    filled: true,
                    fillColor: widget.scaffoldColor,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: widget.themeColor.withValues(alpha: 0.1), width: 1)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: widget.themeColor, width: 2)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
              ),
            )),
          ),
          const SizedBox(height: 12),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), 
          child: Text('CANCEL', style: TextStyle(color: widget.secondaryTextColor, fontWeight: FontWeight.bold))
        ),
      ],
    );
  }
}
