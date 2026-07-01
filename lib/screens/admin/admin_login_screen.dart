import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/license_service.dart';
import '../../providers/profile_provider.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import 'package:provider/provider.dart';
import 'admin_panel_screen.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscure = true;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPhone = prefs.getString('remembered_admin_phone') ?? '';
    final savedPassword = prefs.getString('remembered_admin_password') ?? '';
    final remember = prefs.getBool('admin_remember_me') ?? false;

    if (remember) {
      setState(() {
        _phoneController.text = savedPhone;
        _passwordController.text = savedPassword;
        _rememberMe = true;
      });
    }
  }

  Future<void> _handleLogin() async {
    final phone = _phoneController.text.trim();
    final pass = _passwordController.text.trim();
    final profile = Provider.of<ProfileProvider>(context, listen: false);

    if (phone.isEmpty || pass.isEmpty) {
      AppBottomSheet.showAction(
        context: context,
        profile: profile,
        title: "Input Required",
        message: "Phone and Password are required",
        confirmLabel: "OK",
        confirmColor: Colors.red,
        icon: Icons.error_outline,
      );
      return;
    }

    setState(() => _isLoading = true);
    final result = await LicenseService.loginAdmin(phone, pass);
    setState(() => _isLoading = false);

    if (result['success']) {
      // Refresh ProfileProvider so the Shield icon shows up immediately
      if (mounted) {
        await Provider.of<ProfileProvider>(context, listen: false).loadProfile();
      }

      // Save credentials if remember me is checked
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('remembered_admin_phone', phone);
        await prefs.setString('remembered_admin_password', pass);
        await prefs.setBool('admin_remember_me', true);
      } else {
        await prefs.remove('remembered_admin_phone');
        await prefs.remove('remembered_admin_password');
        await prefs.setBool('admin_remember_me', false);
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const AdminPanelScreen()),
        );
      }
    } else {
      if (mounted) {
        AppBottomSheet.showAction(
          context: context,
          profile: profile,
          title: "Login Failed",
          message: result['message'],
          confirmLabel: "OK",
          confirmColor: Colors.red,
          icon: Icons.error_outline,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final themeColor = profile.themeColor;

    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      appBar: AppBar(
        title: const Text("ADMIN LOGIN"),
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.admin_panel_settings, size: 80, color: themeColor),
              const SizedBox(height: 32),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                style: TextStyle(color: profile.textColor),
                decoration: InputDecoration(
                  labelText: "Admin Phone Number",
                  prefixIcon: const Icon(Icons.phone_android),
                  counterText: "",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscure,
                style: TextStyle(color: profile.textColor),
                decoration: InputDecoration(
                  labelText: "Password",
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 8),
              Theme(
                data: ThemeData(unselectedWidgetColor: profile.secondaryTextColor),
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    "Remember Me",
                    style: TextStyle(color: profile.textColor, fontSize: 14),
                  ),
                  value: _rememberMe,
                  activeColor: themeColor,
                  checkColor: Colors.white,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (val) {
                    setState(() {
                      _rememberMe = val ?? false;
                    });
                  },
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("LOGIN TO ADMIN PANEL", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
