import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../providers/profile_provider.dart';
import '../../services/license_service.dart';
import '../../services/auth_service.dart';
import '../../providers/transaction_provider.dart';
import 'setup_wizard_screen.dart';
import '../../main.dart';
import 'login_screen.dart';
import '../../core/widgets/app_bottom_sheet.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  bool _isLoading = false;
  bool _isTermsAccepted = false;
  String _deviceId = "Loading...";

  @override
  void initState() {
    super.initState();
    _fetchDeviceId();
  }

  Future<void> _fetchDeviceId() async {
    final id = await LicenseService.getDeviceId();
    setState(() => _deviceId = id);
  }

  void _contactSupport() async {
    const phone = "+919992256959";
    final message =
        "Hello, I need a license key for Apna Hisaab.\nMy Device ID: $_deviceId";
    final url = Uri.parse(
      "https://wa.me/$phone?text=${Uri.encodeComponent(message)}",
    );

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Could not open WhatsApp. Please email us."),
          ),
        );
      }
    }
  }

  Future<void> _handleActivation() async {
    final key = _keyController.text.trim();
    final identifier = _phoneController.text.trim();

    if (key.isEmpty || identifier.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter License Key and Registered Phone"),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await LicenseService.init();
      final result = await LicenseService.verifyLicense(key);

      if (result['success']) {
        if (mounted) {
          final profile = Provider.of<ProfileProvider>(context, listen: false);
          bool success = await profile.activateLicense(key);

          if (success) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Premium Activated! Welcome to Apna Hisaab."),
                  backgroundColor: Colors.green,
                ),
              );

              // Check if database is empty to show Setup Wizard
              final txProvider =
                  Provider.of<TransactionProvider>(context, listen: false);
              await txProvider.fetchTransactions();

              if (mounted) {
                if (txProvider.transactions.isEmpty) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder:
                          (context) => SetupWizardScreen(licenseId: key),
                    ),
                  );
                } else {
                  // Restart app to refresh all providers and navigation state
                  RestartWidget.restartApp(context);
                }
              }
            }
          }
        }
      } else {
        throw result['message'] ?? "Activation Failed";
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogout() async {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final confirm = await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: "Logout",
      message: "Are you sure you want to logout?",
      confirmLabel: "LOGOUT",
      isDestructive: true,
    );

    if (confirm == true) {
      await AuthService().signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _handleDeleteAccount() async {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final confirm = await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: "Delete Account",
      message:
          "This action is permanent and will delete all your cloud data. Are you sure?",
      confirmLabel: "DELETE",
      isDestructive: true,
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await AuthService().deleteAccount();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Account Deleted Successfully")),
          );
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          String errorMessage = "Error deleting account: $e";

          if (e is FirebaseAuthException && e.code == 'requires-recent-login') {
            errorMessage =
                "For security, please logout and login again to delete your account.";
            final logoutNow = await AppBottomSheet.showAction(
              context: context,
              profile: profile,
              title: "Re-authentication Required",
              message:
                  "For your security, you must have logged in recently to delete your account. Please log out and log back in, then try again.",
              confirmLabel: "LOGOUT NOW",
              cancelLabel: "OK",
              isDestructive: true,
            );

            if (logoutNow == true) {
              await AuthService().signOut();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            }
          } else {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(errorMessage)));
          }
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
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
        title: const Text(
          'PRO ACTIVATION',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        backgroundColor: themeColor,
        elevation: 0,
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'logout') _handleLogout();
              if (value == 'delete') _handleDeleteAccount();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20),
                    SizedBox(width: 8),
                    Text("Logout"),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, size: 20, color: Colors.red),
                    SizedBox(width: 8),
                    Text("Delete Account", style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Icon(Icons.vpn_key_rounded, size: 70, color: themeColor),
            const SizedBox(height: 20),
            Text(
              "Unlock Professional Features",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: profile.textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Enter your license key provided by the administrator.",
              textAlign: TextAlign.center,
              style: TextStyle(color: profile.secondaryTextColor, fontSize: 13),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _keyController,
              style: TextStyle(color: profile.textColor),
              decoration: InputDecoration(
                labelText: "License Key",
                hintText: "RESTO-XXXX-XXXX-XXXX",
                prefixIcon: const Icon(Icons.key),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.number,
              maxLength: 10,
              style: TextStyle(color: profile.textColor),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: "Registered Phone",
                prefixIcon: const Icon(Icons.phone_android),
                counterText: "",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _isTermsAccepted,
              onChanged: (value) =>
                  setState(() => _isTermsAccepted = value ?? false),
              title: Text(
                "I agree to the Terms & Conditions. (Note: Data older than 365 days will be automatically cleared to maintain performance)",
                style: TextStyle(
                  fontSize: 11,
                  color: profile.secondaryTextColor,
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: themeColor,
            ),
            const SizedBox(height: 16),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _isTermsAccepted ? _handleActivation : null,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                      backgroundColor: _isTermsAccepted
                          ? themeColor
                          : Colors.grey,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      "ACTIVATE NOW",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
            const SizedBox(height: 40),
            const Divider(),
            const SizedBox(height: 20),
            Text(
              "NEED HELP?",
              style: TextStyle(
                color: profile.secondaryTextColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.devices, size: 20, color: Colors.grey),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Your Device ID:",
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        Text(
                          _deviceId,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: profile.textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _deviceId));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Device ID copied!")),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _contactSupport,
                    icon: const Icon(Icons.chat, size: 18, color: Colors.green),
                    label: const Text(
                      "WhatsApp Support",
                      style: TextStyle(color: Colors.green),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.green),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "Email: dev.grillerzone@gmail.com",
              style: TextStyle(color: profile.secondaryTextColor, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
