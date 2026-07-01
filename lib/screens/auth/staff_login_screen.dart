import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/staff_model.dart';
import '../../providers/profile_provider.dart';
import '../../providers/staff_auth_provider.dart';
import '../../providers/staff_provider.dart';
import '../../services/firebase_service.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../main_navigation.dart';

class StaffLoginScreen extends StatefulWidget {
  const StaffLoginScreen({super.key});

  @override
  State<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends State<StaffLoginScreen> {
  final TextEditingController _licenseController = TextEditingController();
  final TextEditingController _staffCodeController = TextEditingController();
  final List<TextEditingController> _pinControllers = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _pinFocusNodes = List.generate(4, (_) => FocusNode());

  int _step = 0; // 0: License Input, 1: Staff Code + PIN
  bool _isLoading = false;

  Future<void> _showError(String title, String message) async {
    if (!mounted) return;
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: title,
      message: message,
      confirmLabel: "OK",
      confirmColor: Colors.red,
      icon: Icons.error_outline,
    );
  }

  Future<void> _verifyLicense() async {
    final inputKey = _licenseController.text.trim(); // Don't force uppercase for Store IDs
    if (inputKey.isEmpty) {
      _showError("Input Required", "Please enter Store ID or License Key");
      return;
    }
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. First, try as a License Key
      final licenseDoc = await FirebaseFirestore.instance.collection('licenses').doc(inputKey.toUpperCase()).get();
      
      String finalKey;
      if (licenseDoc.exists) {
        finalKey = inputKey.toUpperCase();
      } else {
        // 2. If not a license, try as a Store ID (User UID)
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(inputKey).get();
        if (userDoc.exists) {
          finalKey = inputKey;
        } else {
          throw "Invalid Store ID or License Key. Please check with your manager.";
        }
      }

      // 3. Set the global key for partitioning
      FirebaseService.activeLicenseKey = finalKey;
      
      // 4. Store locally for future quick login
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('staff_license_key', finalKey);
      
      setState(() {
        _step = 1;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showError("Verification Failed", e.toString());
    }
  }

  Future<void> _attemptLogin() async {
    final code = _staffCodeController.text.trim();
    final pin = _pinControllers.map((c) => c.text).join();

    if (code.isEmpty || pin.length < 4) {
      _showError("Login Required", "Enter Staff Code and 4-digit PIN");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Fetch staff from local/sync provider
      final staffProvider = Provider.of<StaffProvider>(context, listen: false);
      await staffProvider.fetchStaff(); // Ensure data is loaded
      
      final staff = await staffProvider.getStaffByCode(code);

      if (staff == null) {
        throw "Invalid Staff Code or Login Disabled";
      }

      if (staff.loginPin != pin) {
        throw "Incorrect PIN. Please try again.";
      }

      // 2. Save session in StaffAuthProvider
      await Provider.of<StaffAuthProvider>(context, listen: false).loginStaff(staff, FirebaseService.activeLicenseKey!);

      // 3. Navigate to Main App
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context, 
          MaterialPageRoute(builder: (context) => const MainNavigation()), 
          (route) => false
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showError("Login Failed", e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Provider.of<ProfileProvider>(context).themeColor;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(_step == 0 ? "Connect to Store" : "Staff Login"),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        leading: _step == 1 ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _step = 0)) : null,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              Icon(Icons.store_rounded, size: 80, color: themeColor),
              const SizedBox(height: 24),
              Text(
                _step == 0 ? "License Verification" : "Identity Verification",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _step == 0 
                    ? "Enter the store license key provided by your manager." 
                    : "Enter your unique staff code and security PIN.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 40),
              _step == 0 ? _buildLicenseInput(themeColor) : _buildStaffLoginForm(themeColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLicenseInput(Color themeColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _licenseController,
          decoration: InputDecoration(
            labelText: "Store License Key",
            prefixIcon: const Icon(Icons.vpn_key_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
            filled: true,
            fillColor: Colors.white,
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 55,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyLicense,
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("VERIFY & CONTINUE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildStaffLoginForm(Color themeColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _staffCodeController,
          decoration: InputDecoration(
            labelText: "Staff ID / Code",
            prefixIcon: const Icon(Icons.badge_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 24),
        const Text("Security PIN", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(4, (index) => SizedBox(
            width: 60,
            child: TextField(
              controller: _pinControllers[index],
              focusNode: _pinFocusNodes[index],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 1,
              obscureText: true,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                counterText: "",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (val) {
                if (val.isNotEmpty && index < 3) {
                  _pinFocusNodes[index+1].requestFocus();
                } else if (val.isEmpty && index > 0) {
                  _pinFocusNodes[index-1].requestFocus();
                }
                
                if (index == 3 && val.isNotEmpty) {
                  _attemptLogin();
                }
              },
            ),
          )),
        ),
        const SizedBox(height: 40),
        SizedBox(
          height: 55,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _attemptLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("SECURE LOGIN", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

}
