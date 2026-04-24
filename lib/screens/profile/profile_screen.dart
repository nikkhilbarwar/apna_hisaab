import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/sync_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/purchase_reminder_provider.dart';
import '../../providers/supplier_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/item_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/staff_provider.dart';
import '../../providers/unit_provider.dart';
import '../../services/auth_service.dart';
import '../../services/export_service.dart';
import '../../services/license_service.dart';
import '../../utils/app_strings.dart';
import '../../utils/image_helper.dart';
import '../auth/login_screen.dart';
import '../auth/activation_screen.dart';
import 'printer_settings_screen.dart';
import 'widgets/business_card.dart';
import 'widgets/profile_action_card.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final ExportService _exportService = ExportService();
  bool _isBackingUp = false;
  bool _isSysAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
  }

  Future<void> _checkAdminStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    bool isAdminEmail =
        user?.email == "nikkhilbarwar@gmail.com" ||
        user?.email == "anitamishra1714@gmail.com" ||
        user?.email == "missadvocate06@gmail.com";

    setState(() {
      _isSysAdmin = (prefs.getBool('is_sys_admin') ?? false) || isAdminEmail;
    });
  }

  Future<void> _pickAndCropImage(
    ProfileProvider profile, {
    bool isLogo = true,
  }) async {
    try {
      final String? croppedPath = await ImageHelper.pickAndCropItemIcon(
        context: context,
        themeColor: profile.themeColor,
        isCircle: false, // QR aur Logo ke liye Square crop chahiye
      );

      if (croppedPath != null && mounted) {
        if (isLogo) {
          profile.updateProfile(logoPath: croppedPath);
        } else {
          // Ask for QR Label
          final String? selectedLabel = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: profile.cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text(
                "QR Code Type",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: const Text("Select what this QR code is for:"),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, "Scan for Payment"),
                  child: const Text("PAYMENT"),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, "Scan for Review"),
                  child: const Text("REVIEW"),
                ),
              ],
            ),
          );

          if (selectedLabel != null) {
            profile.updateProfile(qrPath: croppedPath, qrLabel: selectedLabel);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error picking image: $e")));
      }
    }
  }

  Future<void> _handleBackup(ProfileProvider profile) async {
    setState(() => _isBackingUp = true);
    final path = await _exportService.createFullBackup();
    setState(() => _isBackingUp = false);

    if (mounted) {
      if (path != null) {
        showDialog(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: profile.cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 48),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Backup Successful",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: profile.textColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Your data is safe! The backup file is stored in your Documents folder and will persist even if you uninstall the app.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: profile.secondaryTextColor,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: profile.scaffoldColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      path,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: profile.themeColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: profile.themeColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: const Text("GREAT", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create backup. Check storage permissions.')),
        );
      }
    }
  }

  Future<void> _handleRestore(ProfileProvider profile) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);

        if (mounted) {
          bool confirm = await showDialog(
            context: context,
            builder: (ctx) => Dialog(
              backgroundColor: profile.cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.warning_rounded, color: Colors.red, size: 48),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "Restore Data?",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: profile.textColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Warning: This will permanently replace all current app data and settings with the backup file. This cannot be undone.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 13,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(
                              "CANCEL",
                              style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                            child: const Text("PROCEED", style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ) ?? false;

          if (confirm && mounted) {
            setState(() => _isBackingUp = true);
            bool success = await _exportService.restoreFromBackup(file);
            // ... (rest of the restore logic remains same)

            if (success) {
              await profile.loadProfile();
              if (mounted) {
                final transProvider = Provider.of<TransactionProvider>(
                  context,
                  listen: false,
                );
                final itemProvider = Provider.of<ItemProvider>(
                  context,
                  listen: false,
                );
                final catProvider = Provider.of<CategoryProvider>(
                  context,
                  listen: false,
                );
                final staffProvider = Provider.of<StaffProvider>(
                  context,
                  listen: false,
                );
                final unitProvider = Provider.of<UnitProvider>(
                  context,
                  listen: false,
                );
                final suppProvider = Provider.of<SupplierProvider>(
                  context,
                  listen: false,
                );
                final remProvider = Provider.of<PurchaseReminderProvider>(
                  context,
                  listen: false,
                );

                transProvider.fetchTransactions();
                itemProvider.refreshData();
                catProvider.fetchCategories();
                staffProvider.fetchStaff();
                unitProvider.fetchUnits();
                suppProvider.fetchSuppliers();
                remProvider.fetchReminders();
              }
            }

            setState(() => _isBackingUp = false);

            if (mounted) {
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Everything restored successfully!'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Failed to restore data. Invalid backup file.',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          }
        }
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _confirmDeleteAccount(ProfileProvider profile) {
    final TextEditingController confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text("Delete Account?"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Warning: This action is permanent and cannot be undone.",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              "Your items, transactions, licenses, and all cloud data will be deleted forever.",
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 20),
            Text(
              "Type 'DELETE' below to confirm:",
              style: TextStyle(color: profile.secondaryTextColor, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmController,
              decoration: const InputDecoration(
                hintText: "DELETE",
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("CANCEL", style: TextStyle(color: profile.textColor)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (confirmController.text.trim().toUpperCase() == "DELETE") {
                Navigator.pop(ctx);
                _showDeletingOverlay(profile);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Type DELETE to confirm")),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              "DELETE EVERYTHING",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeletingOverlay(ProfileProvider profile) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: profile.cardColor,
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.red),
              SizedBox(height: 24),
              Text(
                "Deleting your data...",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                "Please wait, this may take a moment",
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );

    _performFinalDeletion();
  }

  Future<void> _performFinalDeletion() async {
    try {
      await AuthService().deleteAccount();

      if (mounted) {
        // 1. Close the "Deleting..." overlay (using rootNavigator to ensure we close the dialog)
        Navigator.of(context, rootNavigator: true).pop();

        // 2. Force navigate to Login Screen
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        // Close overlay on error
        Navigator.of(context, rootNavigator: true).pop();
        _showDeletionErrorDialog(e.toString());
      }
    }
  }

  void _showDeletionErrorDialog(String error) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.lock_clock_rounded, color: Colors.orange),
            SizedBox(width: 12),
            Text("Re-authentication\nRequired"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "For security reasons, you must have logged in recently to delete your entire profile and data.",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
              ),
              child: const Text(
                "Please Logout and Login again, then try deleting your profile.",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: profile.themeColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(120, 45),
              ),
              child: const Text(
                "OK, I UNDERSTAND",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _confirmLogout() {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          "${AppStrings.logout}?",
          style: TextStyle(
            color: profile.textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          AppStrings.confirmLogout,
          style: TextStyle(color: profile.secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () async {
              await _authService.signOut();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text(
              AppStrings.logout,
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditBottomSheet(BuildContext context, ProfileProvider profile) {
    final formKey = GlobalKey<FormState>();
    final n = TextEditingController(text: profile.displayBusinessName);
    final o = TextEditingController(text: profile.displayOwnerName);
    final c = TextEditingController(text: profile.displayPhone);
    final a = TextEditingController(text: profile.address);
    final t = TextEditingController(text: profile.taxPercentage.toString());
    final tbl = TextEditingController(text: profile.totalTables.toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: profile.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: EdgeInsets.fromLTRB(
          24,
          12,
          24,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: profile.secondaryTextColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  "Edit Business Details",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: profile.textColor,
                  ),
                ),
                const SizedBox(height: 24),
                _buildField(
                  n,
                  "Business Name",
                  Icons.business_rounded,
                  profile,
                ),
                _buildField(
                  o,
                  "Owner Name",
                  Icons.person_outline_rounded,
                  profile,
                ),
                _buildField(
                  c,
                  "Contact Number",
                  Icons.phone_android_rounded,
                  profile,
                  keyboard: TextInputType.phone,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _buildField(
                        t,
                        "Tax Percentage (%)",
                        Icons.percent_rounded,
                        profile,
                        keyboard: TextInputType.number,
                        suffix: "%",
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildField(
                        tbl,
                        "Total Tables",
                        Icons.table_bar_rounded,
                        profile,
                        keyboard: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                _buildField(
                  a,
                  "Address",
                  Icons.location_on_outlined,
                  profile,
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      profile.updateProfile(
                        businessName: n.text.trim(),
                        ownerName: o.text.trim(),
                        contact: c.text.trim(),
                        address: a.text.trim(),
                        taxPercentage: double.tryParse(t.text) ?? 0.0,
                        totalTables: int.tryParse(tbl.text) ?? 20,
                      );
                      Navigator.pop(ctx);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: profile.themeColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    "SAVE CHANGES",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAppearanceSettings(ProfileProvider profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Consumer<ProfileProvider>(
        builder: (context, profile, child) => Container(
          height: MediaQuery.of(ctx).size.height * 0.7, // Restricted to 70%
          decoration: BoxDecoration(
            color: profile.cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              // Header Drag Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: profile.secondaryTextColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Text(
                      "App Appearance",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: profile.textColor,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close, color: profile.secondaryTextColor),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section: Dark Mode
                      _buildSectionHeader("VISUAL MODE", profile),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: profile.scaffoldColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: profile.secondaryTextColor.withValues(alpha: 0.05),
                          ),
                        ),
                        child: SwitchListTile(
                          title: Text(
                            "Dark Mode",
                            style: TextStyle(
                              color: profile.textColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            "Reduce eye strain in low light",
                            style: TextStyle(
                              color: profile.secondaryTextColor,
                              fontSize: 12,
                            ),
                          ),
                          secondary: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: profile.themeColor.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              profile.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                              color: profile.themeColor,
                              size: 20,
                            ),
                          ),
                          value: profile.isDarkMode,
                          activeColor: profile.themeColor,
                          onChanged: (val) => profile.toggleDarkMode(val),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Section: Theme Color
                      _buildSectionHeader("THEME COLOR", profile),
                      const SizedBox(height: 16),
                      
                      // Custom Picker Trigger
                      InkWell(
                        onTap: () => _showCustomColorPicker(profile),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: profile.scaffoldColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: profile.themeColor.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: profile.themeColor,
                                child: const Icon(Icons.colorize, size: 16, color: Colors.white),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Custom Color Picker",
                                      style: TextStyle(
                                        color: profile.textColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      "Create your unique branding",
                                      style: TextStyle(
                                        color: profile.secondaryTextColor,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: profile.secondaryTextColor),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 20),

                      // Grid of Presets (Compact)
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                        ),
                        itemCount: Colors.primaries.length,
                        itemBuilder: (context, index) {
                          final color = Colors.primaries[index];
                          final isSelected = profile.themeColor.toARGB32() == color.toARGB32();
                          return GestureDetector(
                            onTap: () => profile.savePresetTheme(color),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? profile.textColor : Colors.transparent,
                                  width: 3,
                                ),
                                boxShadow: [
                                  if (isSelected)
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.4),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                ],
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                                  : null,
                            ),
                          );
                        },
                      ),

                      if (profile.customThemeColors.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        _buildSectionHeader("SAVED COLORS", profile),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 50,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: profile.customThemeColors.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final colorVal = profile.customThemeColors[index];
                              final color = Color(colorVal);
                              final isSelected = profile.themeColorValue == colorVal;
                              return GestureDetector(
                                onTap: () => profile.savePresetTheme(color),
                                onLongPress: () => profile.removeCustomColor(colorVal),
                                child: Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? profile.textColor : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Bottom Action Button
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: profile.themeColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    "SAVE CHANGES",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDataManagement(ProfileProvider profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Consumer<ProfileProvider>(
        builder: (context, profile, child) => Container(
          height: MediaQuery.of(ctx).size.height * 0.7,
          decoration: BoxDecoration(
            color: profile.cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: profile.secondaryTextColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Text(
                      "Data Management",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: profile.textColor,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close, color: profile.secondaryTextColor),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader("STORAGE & BACKUP", profile),
                      const SizedBox(height: 12),
                      
                      // Last Sync Indicator
                      _buildLastSyncCard(profile),
                      
                      const SizedBox(height: 16),
                      
                      // Smart Sync Selection
                      _buildSyncSelectionCard(profile),
                      
                      const SizedBox(height: 24),

                      // Backup Option
                      _buildDataActionCard(
                        title: "Manual Backup",
                        subtitle: "Export all data to a secure local file.",
                        icon: Icons.cloud_upload_rounded,
                        iconColor: Colors.blue,
                        onTap: () {
                          Navigator.pop(ctx);
                          _handleBackup(profile);
                        },
                        profile: profile,
                      ),
                      
                      const SizedBox(height: 16),

                      // Restore Option
                      _buildDataActionCard(
                        title: "Restore Data",
                        subtitle: "Import your data from a previously saved backup file.",
                        icon: Icons.settings_backup_restore_rounded,
                        iconColor: Colors.orange,
                        onTap: () {
                          Navigator.pop(ctx);
                          _handleRestore(profile);
                        },
                        profile: profile,
                      ),

                      const SizedBox(height: 32),
                      _buildSectionHeader("PRIVACY", profile),
                      const SizedBox(height: 16),

                      _buildDataActionCard(
                        title: "Data & Security",
                        subtitle: "Manage your privacy settings and view security protocols.",
                        icon: Icons.security_rounded,
                        iconColor: Colors.green,
                        onTap: () => _showDataSecurityPopup(profile),
                        profile: profile,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    required ProfileProvider profile,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: profile.scaffoldColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: profile.secondaryTextColor.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: profile.secondaryTextColor, fontSize: 12, height: 1.3),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: profile.secondaryTextColor),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncSelectionCard(ProfileProvider profile) {
    final syncProvider = Provider.of<SyncProvider>(context);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: profile.scaffoldColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: profile.themeColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: profile.themeColor, size: 20),
              const SizedBox(width: 8),
              Text(
                "SMART SYNC ENGINE",
                style: TextStyle(
                  color: profile.themeColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              if (syncProvider.isSyncing)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(profile.themeColor),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildSyncOption(
                mode: 'offline',
                icon: Icons.cloud_off_rounded,
                label: "Local",
                currentMode: profile.syncMode,
                profile: profile,
              ),
              const SizedBox(width: 8),
              _buildSyncOption(
                mode: 'online',
                icon: Icons.cloud_done_rounded,
                label: "Cloud",
                currentMode: profile.syncMode,
                profile: profile,
              ),
              const SizedBox(width: 8),
              _buildSyncOption(
                mode: 'hybrid',
                icon: Icons.offline_pin_rounded,
                label: "Smart",
                currentMode: profile.syncMode,
                profile: profile,
              ),
            ],
          ),
          if (syncProvider.isSyncing) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: syncProvider.syncProgress,
                backgroundColor: profile.themeColor.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(profile.themeColor),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              syncProvider.syncStatus,
              style: TextStyle(
                color: profile.themeColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              profile.syncMode == 'hybrid'
                  ? "Recommended: Fast local access with real-time cloud backup."
                  : profile.syncMode == 'online'
                      ? "Strict Cloud: Requires active internet for all operations."
                      : "Strict Local: All data stays on this device only.",
              style: TextStyle(color: profile.secondaryTextColor, fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLastSyncCard(ProfileProvider profile) {
    final syncProvider = Provider.of<SyncProvider>(context);
    final String lastSync = syncProvider.lastSyncTimestamp != null
        ? DateFormat('dd MMM, hh:mm a').format(syncProvider.lastSyncTimestamp!)
        : "Never Synced";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: profile.themeColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: profile.themeColor.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(Icons.history_rounded, color: profile.themeColor, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Last Cloud Sync",
                style: TextStyle(
                  color: profile.secondaryTextColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                lastSync,
                style: TextStyle(
                  color: profile.textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const Spacer(),
          TextButton(
            onPressed: syncProvider.isSyncing 
              ? null 
              : () => syncProvider.manualSyncToCloud(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              "SYNC NOW",
              style: TextStyle(
                color: profile.themeColor,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncOption({
    required String mode,
    required IconData icon,
    required String label,
    required String currentMode,
    required ProfileProvider profile,
  }) {
    final bool isSelected = currentMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () => profile.updateSyncMode(mode),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? profile.themeColor : profile.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? profile.themeColor : profile.secondaryTextColor.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? Colors.white : profile.secondaryTextColor, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : profile.textColor,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, ProfileProvider profile) {
    return Text(
      title,
      style: TextStyle(
        color: profile.secondaryTextColor,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
        fontSize: 11,
      ),
    );
  }

  void _showCustomColorPicker(ProfileProvider profile) {
    Color pickedColor = profile.themeColor;
    final hexController = TextEditingController(
      text: pickedColor.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase(),
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: profile.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.brush_rounded, color: pickedColor, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        "Custom Theme",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: profile.textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Modern Color Picker
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: ColorPicker(
                      pickerColor: pickedColor,
                      onColorChanged: (color) {
                        pickedColor = color;
                        final newHex = color.value
                            .toRadixString(16)
                            .padLeft(8, '0')
                            .substring(2)
                            .toUpperCase();
                        if (hexController.text.toUpperCase() != newHex) {
                          hexController.text = newHex;
                        }
                        setDialogState(() {});
                      },
                      enableAlpha: false,
                      displayThumbColor: true,
                      pickerAreaHeightPercent: 0.7,
                      hexInputBar: false,
                      labelTypes: const [], // Cleaner UI
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Hex Input Box
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    decoration: BoxDecoration(
                      color: profile.scaffoldColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: pickedColor.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          "#",
                          style: TextStyle(
                            color: pickedColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: hexController,
                            maxLength: 6,
                            style: TextStyle(
                              color: profile.textColor,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 3,
                              fontSize: 18,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              counterText: "",
                              hintText: "FFFFFF",
                            ),
                            onChanged: (val) {
                              if (val.length == 6) {
                                try {
                                  final color = Color(int.parse("FF$val", radix: 16));
                                  setDialogState(() {
                                    pickedColor = color;
                                  });
                                } catch (_) {}
                              }
                            },
                          ),
                        ),
                        // Small Preview Circle
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: pickedColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: pickedColor.withValues(alpha: 0.3),
                                blurRadius: 4,
                              )
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(
                            "CANCEL",
                            style: TextStyle(
                              color: profile.secondaryTextColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            profile.updateThemeColor(pickedColor);
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: pickedColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            "APPLY THEME",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSecuritySettings(ProfileProvider profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: BoxDecoration(
            color: profile.cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: profile.secondaryTextColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                "Security Settings",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: profile.textColor,
                ),
              ),
              const SizedBox(height: 24),

              // Custom PIN Toggle
              SwitchListTile(
                title: Text(
                  "Custom PIN Lock",
                  style: TextStyle(
                    color: profile.textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  profile.isPinEnabled
                      ? "PIN is active"
                      : "Protect sensitive data with a PIN",
                  style: TextStyle(fontSize: 12),
                ),
                value: profile.isPinEnabled,
                activeThumbColor: profile.themeColor,
                onChanged: (val) {
                  if (!val) {
                    profile.setPin("");
                    setModalState(() {});
                  } else {
                    _showSetPinDialog(profile, setModalState);
                  }
                },
              ),

              if (profile.isPinEnabled)
                ListTile(
                  leading: Icon(Icons.edit_outlined, color: profile.themeColor),
                  title: Text(
                    "Change PIN",
                    style: TextStyle(
                      color: profile.textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () => _showSetPinDialog(profile, setModalState),
                ),

              const Divider(),

              // Biometric Toggle
              SwitchListTile(
                title: Text(
                  "Device Lock (Biometric)",
                  style: TextStyle(
                    color: profile.textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  "Use fingerprint or face ID",
                  style: TextStyle(fontSize: 12),
                ),
                value: profile.isBiometricEnabled,
                activeThumbColor: profile.themeColor,
                onChanged: (val) {
                  profile.setBiometric(val);
                  setModalState(() {});
                },
              ),

              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: profile.themeColor,
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text(
                  "DONE",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSetPinDialog(ProfileProvider profile, StateSetter parentState) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Set 4-Digit PIN"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          autofocus: true,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(hintText: "****", counterText: ""),
          style: const TextStyle(
            fontSize: 24,
            letterSpacing: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.length == 4) {
                profile.setPin(controller.text);
                parentState(() {});
                Navigator.pop(context);
              }
            },
            child: const Text("SAVE"),
          ),
        ],
      ),
    );
  }

  void _showDataSecurityPopup(ProfileProvider profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: profile.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(24),
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: profile.secondaryTextColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Icon(
                  Icons.security_outlined,
                  color: profile.themeColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  "Data & Security",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: profile.textColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Text(
                      "We are committed to safeguarding user information through robust technical and organizational measures. All data processed within the application is handled in accordance with industry-standard security protocols and applicable data protection regulations.\n\n"
                      "User-generated and transactional data is primarily stored in a secure local environment and, where applicable, may be synchronized with cloud-based services utilizing encrypted transmission channels (e.g., HTTPS/TLS). Sensitive information is neither exposed nor transmitted without appropriate safeguards and authentication layers.\n\n"
                      "We implement access control mechanisms, data minimization principles, and structured storage methodologies to ensure that only necessary information is retained for operational purposes. No personally identifiable information is shared with third parties except where explicitly required for service functionality, legal compliance, or authorized integrations.\n\n"
                      "The application does not engage in unauthorized data harvesting, background tracking, or intrusive analytics beyond the scope of essential service delivery. Any optional features involving external services are governed by their respective privacy frameworks.\n\n"
                      "While commercially reasonable efforts are made to ensure data integrity, availability, and confidentiality, users acknowledge that no digital system can guarantee absolute security. By using the application, users consent to data handling practices as outlined in this policy.",
                      style: TextStyle(
                        color: profile.secondaryTextColor,
                        fontSize: 14,
                        height: 1.6,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.justify,
                    ),
                    if (!_isSysAdmin) ...[
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(ctx);
                            _confirmDeleteAccount(profile);
                          },
                          child: Text(
                            "Account Termination & Permanent Data Wipeout",
                            style: TextStyle(
                              color: Colors.red.withValues(
                                alpha: 0.2,
                              ), // Very faded
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: profile.themeColor,
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text(
                "I UNDERSTAND",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSupportTickets(ProfileProvider profile) async {
    // Ensure auth once
    await LicenseService.ensureAuth();
    if (!mounted) return;

    // Create the stream instance once here so it's stable inside the bottom sheet
    final ticketsStream = LicenseService.getTickets(profile.licenseKey);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: profile.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.only(top: 12),
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: profile.secondaryTextColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Support Tickets",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: profile.textColor,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showCreateTicketDialog(profile),
                    icon: Icon(
                      Icons.add_circle,
                      color: profile.themeColor,
                      size: 30,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: ticketsStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        "Error: ${snapshot.error}",
                        style: const TextStyle(color: Colors.red),
                      ),
                    );
                  }

                  // Fix: Only show loader if we have NO data and are waiting.
                  // If hasData is true, we keep showing the cards even if connectionState is waiting.
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allDocs = snapshot.data?.docs ?? [];
                  final docs = allDocs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['status'] != 'deleted';
                  }).toList();

                  if (docs.isEmpty &&
                      snapshot.connectionState != ConnectionState.waiting) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.confirmation_number_outlined,
                            size: 64,
                            color: profile.secondaryTextColor.withValues(
                              alpha: 0.3,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            profile.licenseKey.isEmpty
                                ? "License not found"
                                : "No tickets yet",
                            style: TextStyle(color: profile.secondaryTextColor),
                          ),
                          TextButton.icon(
                            onPressed: () => _showCreateTicketDialog(profile),
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text("Create Ticket"),
                          ),
                        ],
                      ),
                    );
                  }

                  // Sorting
                  docs.sort((a, b) {
                    final aTime =
                        (a.data() as Map<String, dynamic>)['lastUpdate']
                            as Timestamp?;
                    final bTime =
                        (b.data() as Map<String, dynamic>)['lastUpdate']
                            as Timestamp?;
                    if (aTime == null) return 1;
                    if (bTime == null) return -1;
                    return bTime.compareTo(aTime);
                  });

                  return ListView.builder(
                    itemCount: docs.length,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final status = data['status'] ?? 'open';
                      final lastUpdate = data['lastUpdate'] as Timestamp?;

                      Color statusColor = status == 'answered'
                          ? Colors.orange
                          : (status == 'resolved' ? Colors.green : Colors.blue);

                      return Card(
                        color: profile.cardColor,
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: profile.themeColor.withValues(alpha: 0.1),
                          ),
                        ),
                        child: ListTile(
                          onTap: () => _showTicketChat(doc.id, profile),
                          contentPadding: const EdgeInsets.all(16),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  data['subject'] ?? 'No Subject',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 8),
                              Text(
                                data['message'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: profile.secondaryTextColor,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 14,
                                    color: profile.secondaryTextColor
                                        .withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    lastUpdate != null
                                        ? DateFormat(
                                            'dd MMM, hh:mm a',
                                          ).format(lastUpdate.toDate())
                                        : 'Recently',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: profile.secondaryTextColor
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (data['hasUnreadReply'] == true)
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Colors.orange,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateTicketDialog(ProfileProvider profile) {
    final subjectController = TextEditingController();
    final messageController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Create Support Ticket"),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: subjectController,
                decoration: const InputDecoration(
                  labelText: "Subject",
                  hintText: "e.g., License not working",
                ),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: messageController,
                decoration: const InputDecoration(
                  labelText: "Description",
                  hintText: "Describe your issue",
                ),
                maxLines: 3,
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final lKey = profile.licenseKey.trim();
                if (lKey.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Error: Your license key is missing. Please contact support.",
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                await LicenseService.createTicket(
                  licenseKey: lKey,
                  restaurantName: profile.displayBusinessName,
                  phone: profile.displayPhone,
                  subject: subjectController.text,
                  message: messageController.text,
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Ticket created successfully!"),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              }
            },
            child: const Text("SUBMIT"),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteTicket(String ticketId, ProfileProvider profile) {
    // Placeholder implementation - unused method
  }

  void _confirmDeleteReply(
    String ticketId,
    String replyId,
    ProfileProvider profile,
  ) {
    if (replyId.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "Delete Message?",
          style: TextStyle(color: profile.textColor),
        ),
        content: Text(
          "This will permanently delete this message for everyone.",
          style: TextStyle(color: profile.secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await LicenseService.deleteTicketReply(ticketId, replyId);
            },
            child: const Text(
              "DELETE",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showTicketChat(String ticketId, ProfileProvider profile) {
    final replyController = TextEditingController();
    final scrollController = ScrollController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: profile.scaffoldColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        height: MediaQuery.of(context).size.height * 0.9,
        // Remove direct padding here, Scaffold handles it better
        child: StreamBuilder<DocumentSnapshot>(
          stream: LicenseService.getTicketStream(ticketId),
          builder: (context, snapshot) {
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final replies = (data['replies'] as List? ?? []);
            final isResolved = data['status'] == 'resolved';
            final subject = data['subject'] ?? 'Support Ticket';
            final initialMessage = data['message'] ?? '';
            final createdAt =
                (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

            return Scaffold(
              backgroundColor: Colors.transparent,
              resizeToAvoidBottomInset: true,
              body: Column(
                children: [
                  // --- Premium Header ---
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    decoration: BoxDecoration(
                      color: profile.cardColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: profile.secondaryTextColor.withValues(
                              alpha: 0.2,
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: profile.themeColor.withValues(
                                  alpha: 0.1,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.support_agent_rounded,
                                color: profile.themeColor,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    subject,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: profile.textColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    isResolved
                                        ? "Closed • View Only"
                                        : "Active Support",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isResolved
                                          ? Colors.green
                                          : Colors.orange,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isResolved)
                              IconButton(
                                onPressed: () =>
                                    _confirmResolve(ticketId, profile),
                                icon: const Icon(
                                  Icons.check_circle_outline,
                                  color: Colors.green,
                                ),
                                tooltip: "Mark as Resolved",
                              ),
                            IconButton(
                              onPressed: () => Navigator.pop(ctx),
                              icon: Icon(
                                Icons.close_rounded,
                                color: profile.secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // --- Chat Messages List ---
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 20),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: profile.cardColor.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: profile.themeColor.withValues(
                                  alpha: 0.1,
                                ),
                              ),
                            ),
                            child: Text(
                              "Ticket Created on ${DateFormat('dd MMM, hh:mm a').format(createdAt)}",
                              style: TextStyle(
                                fontSize: 11,
                                color: profile.secondaryTextColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                        _buildChatBubble(
                          message: initialMessage,
                          time: DateFormat('hh:mm a').format(createdAt),
                          isAdmin: false,
                          senderName: profile.displayBusinessName,
                          profile: profile,
                        ),

                        ...replies.map((reply) {
                          DateTime? dt;
                          try {
                            dt = DateTime.parse(reply['timestamp']);
                          } catch (_) {}
                          final replyId = reply['id']?.toString() ?? '';

                          return GestureDetector(
                            onLongPress: isResolved
                                ? null
                                : () => _confirmDeleteReply(
                                    ticketId,
                                    replyId,
                                    profile,
                                  ),
                            child: _buildChatBubble(
                              message: reply['message'],
                              time: dt != null
                                  ? DateFormat('hh:mm a').format(dt)
                                  : '',
                              isAdmin: reply['senderRole'] == 'admin',
                              senderName: reply['senderRole'] == 'admin'
                                  ? (reply['senderName'] ?? 'Support Team')
                                  : profile.displayBusinessName,
                              profile: profile,
                            ),
                          );
                        }),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: !isResolved
                    ? _buildChatInput(
                        ticketId,
                        replyController,
                        profile,
                        scrollController,
                      )
                    : _buildResolvedBanner(profile),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildChatBubble({
    required String message,
    required String time,
    required bool isAdmin,
    required String senderName,
    required ProfileProvider profile,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isAdmin
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isAdmin) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: profile.themeColor,
                child: const Icon(
                  Icons.headset_mic_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isAdmin
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isAdmin ? profile.cardColor : profile.themeColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isAdmin ? 4 : 20),
                      bottomRight: Radius.circular(isAdmin ? 20 : 4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    message,
                    style: TextStyle(
                      color: isAdmin ? profile.textColor : Colors.white,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    "$senderName • $time",
                    style: TextStyle(
                      fontSize: 10,
                      color: profile.secondaryTextColor.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!isAdmin) const SizedBox(width: 40),
          if (isAdmin) const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildChatInput(
    String ticketId,
    TextEditingController controller,
    ProfileProvider profile,
    ScrollController sc,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: profile.cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: profile.scaffoldColor,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: profile.secondaryTextColor.withValues(alpha: 0.1),
                  ),
                ),
                child: TextField(
                  controller: controller,
                  style: TextStyle(color: profile.textColor),
                  maxLines: 4,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: "Type a reply...",
                    hintStyle: TextStyle(
                      color: profile.secondaryTextColor.withValues(alpha: 0.5),
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () async {
                if (controller.text.trim().isNotEmpty) {
                  final msg = controller.text.trim();
                  controller.clear();
                  await LicenseService.addTicketReply(
                    ticketId: ticketId,
                    message: msg,
                    senderRole: 'user',
                    senderName: profile.displayBusinessName,
                  );
                  // Auto scroll to bottom
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (sc.hasClients)
                      sc.animateTo(
                        sc.position.maxScrollExtent,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                  });
                }
              },
              child: Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: profile.themeColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: profile.themeColor.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResolvedBanner(ProfileProvider profile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      color: Colors.green.withValues(alpha: 0.05),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.verified_user_rounded,
              color: Colors.green,
              size: 32,
            ),
            const SizedBox(height: 8),
            const Text(
              "Conversation Resolved",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            Text(
              "This ticket is closed. Please create a new one if you need further help.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: profile.secondaryTextColor),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmResolve(String ticketId, ProfileProvider profile) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Resolve Ticket?"),
        content: const Text(
          "Marking this as resolved will close the conversation.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL"),
          ),
          TextButton(
            onPressed: () {
              LicenseService.resolveTicket(ticketId);
              Navigator.pop(ctx);
            },
            child: const Text(
              "YES, RESOLVE",
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLicenseDetails(ProfileProvider profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: profile.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: profile.secondaryTextColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  color: Colors.green,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  "License Information",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: profile.textColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildDetailRow("License Key", profile.licenseKey, profile),
            _buildDetailRow(
              "Status",
              "ACTIVE",
              profile,
              valueColor: Colors.green,
            ),
            _buildDetailRow(
              "Type",
              profile.isLifetime ? "LIFETIME" : "SUBSCRIPTION",
              profile,
            ),
            _buildDetailRow(
              "Amount Paid",
              "${profile.currencySymbol}${profile.amountPaid.toStringAsFixed(2)}",
              profile,
            ),
            if (profile.expiryDate != null)
              _buildDetailRow(
                "Expiry Date",
                DateFormat('dd-MM-yyyy').format(profile.expiryDate!),
                profile,
              ),

            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showDigitalReceipt(profile),
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text(
                      "VIEW RECEIPT",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: profile.themeColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final bName = profile.displayBusinessName;
                      final phone = profile.displayPhone;
                      final msg = Uri.encodeComponent(
                        "Hello, I want to renew my license for $bName.\nMobile: $phone\nLicense Key: ${profile.licenseKey}",
                      );
                      final uri = Uri.parse(
                        "https://wa.me/919992256959?text=$msg",
                      );
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text(
                      "RENEW",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              "Your license is linked to this device. For any issues regarding license transfer, please contact support.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: profile.themeColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(120, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  "CLOSE",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDigitalReceipt(ProfileProvider profile) {
    // Replaced UI receipt with professional PDF generation
    ExportService().generateLicenseInvoice({
      'licenseKey': profile.licenseKey,
      'restaurantName': profile.displayBusinessName,
      'ownerName': profile.displayOwnerName,
      'phone': profile.displayPhone,
      'price': profile.amountPaid,
      'planType': profile.planType,
      'validTillFormatted': profile.expiryDate != null
          ? DateFormat('dd-MM-yyyy').format(profile.expiryDate!)
          : (profile.isLifetime ? 'Lifetime' : 'N/A'),
      'isLifetime': profile.isLifetime,
    });
  }

  Widget _buildDetailRow(
    String label,
    String value,
    ProfileProvider profile, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: profile.secondaryTextColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? profile.textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _showFeedbackPopup(ProfileProvider profile) {
    final TextEditingController feedbackController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: profile.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: profile.secondaryTextColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      Icons.feedback_outlined,
                      color: profile.themeColor,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "Services & Feedback",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: profile.textColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  "Tell us how we can improve. Your feedback helps us build a better experience for everyone.",
                  style: TextStyle(
                    color: profile.secondaryTextColor,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: feedbackController,
                  maxLines: 5,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? "Please enter your message"
                      : null,
                  style: TextStyle(color: profile.textColor, fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: "Your Feedback",
                    hintText: "",
                    filled: true,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            final String msg = Uri.encodeComponent(
                              feedbackController.text.trim(),
                            );
                            final Uri emailUri = Uri.parse(
                              "mailto:Nikkhilbarwar@gmail.com?subject=App Feedback&body=$msg",
                            );
                            if (await canLaunchUrl(emailUri)) {
                              await launchUrl(emailUri);
                              if (ctx.mounted) Navigator.pop(ctx);
                            }
                          }
                        },
                        icon: const Icon(Icons.email_outlined, size: 20),
                        label: const Text(
                          "EMAIL",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey,
                          minimumSize: const Size(0, 50),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            final String msg = Uri.encodeComponent(
                              feedbackController.text.trim(),
                            );
                            final Uri waUri = Uri.parse(
                              "https://wa.me/919992256959?text=$msg",
                            );
                            if (await canLaunchUrl(waUri)) {
                              await launchUrl(waUri);
                              if (ctx.mounted) Navigator.pop(ctx);
                            }
                          }
                        },
                        icon: const Icon(Icons.chat_outlined, size: 20),
                        label: const Text(
                          "WHATSAPP",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          minimumSize: const Size(0, 50),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label,
    IconData icon,
    ProfileProvider profile, {
    TextInputType? keyboard,
    String? suffix,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: maxLines,
        style: TextStyle(
          color: profile.textColor,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: profile.themeColor),
          suffixText: suffix,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final themeColor = profile.themeColor;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: themeColor,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: LayoutBuilder(
              builder: (ctx, constraints) {
                final settings = ctx
                    .dependOnInheritedWidgetOfExactType<
                      FlexibleSpaceBarSettings
                    >();
                final deltaExtent = settings!.maxExtent - settings.minExtent;
                final t =
                    (1.0 -
                            (settings.currentExtent - settings.minExtent) /
                                deltaExtent)
                        .clamp(0.0, 1.0);

                return FlexibleSpaceBar(
                  centerTitle: true,
                  title: Opacity(
                    opacity: t > 0.7 ? 1.0 : 0.0,
                    child: Text(
                      profile.displayBusinessName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [themeColor, themeColor.withValues(alpha: 0.8)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -50,
                          top: -50,
                          child: CircleAvatar(
                            radius: 100,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.05,
                            ),
                          ),
                        ),
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(height: 40),
                              GestureDetector(
                                onTap: () => _pickAndCropImage(profile),
                                child: Stack(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: CircleAvatar(
                                        radius: 50,
                                        backgroundColor: profile.cardColor,
                                        backgroundImage:
                                            profile.logoPath.isNotEmpty &&
                                                File(
                                                  profile.logoPath,
                                                ).existsSync()
                                            ? FileImage(File(profile.logoPath))
                                            : (user?.photoURL != null
                                                      ? NetworkImage(
                                                          user!.photoURL!,
                                                        )
                                                      : null)
                                                  as ImageProvider?,
                                        child:
                                            (profile.logoPath.isEmpty ||
                                                    !File(
                                                      profile.logoPath,
                                                    ).existsSync()) &&
                                                user?.photoURL == null
                                            ? Icon(
                                                Icons.business,
                                                size: 40,
                                                color: themeColor,
                                              )
                                            : null,
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.edit,
                                          size: 16,
                                          color: themeColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                profile.displayBusinessName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                profile.displayOwnerName,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BusinessCard(
                    profile: profile,
                    user: user,
                    onEdit: () => _showEditBottomSheet(context, profile),
                    onPickImage: () => _pickAndCropImage(profile),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "SETTINGS",
                    style: TextStyle(
                      color: profile.secondaryTextColor,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ProfileActionCard(
                    title: "Security & Lock",
                    subtitle: "PIN and Fingerprint settings",
                    icon: Icons.lock_outline_rounded,
                    onTap: () => _showSecuritySettings(profile),
                    profile: profile,
                  ),
                  ProfileActionCard(
                    title: "Payment / Review QR",
                    subtitle: profile.qrPath.isNotEmpty
                        ? "QR Code uploaded"
                        : "Upload QR for Bill",
                    icon: Icons.qr_code_2_rounded,
                    onTap: () => _pickAndCropImage(profile, isLogo: false),
                    trailing: profile.qrPath.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                            onPressed: () => profile.updateProfile(qrPath: ""),
                          )
                        : null,
                    profile: profile,
                  ),
                  ProfileActionCard(
                    title: "Printer Settings",
                    subtitle: "Configure Bill and KOT printers",
                    icon: Icons.print_outlined,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PrinterSettingsScreen(),
                        ),
                      );
                    },
                    profile: profile,
                  ),
                  ProfileActionCard(
                    title: "App Appearance",
                    subtitle: "Dark Mode and Theme Colors",
                    icon: Icons.palette_outlined,
                    onTap: () => _showAppearanceSettings(profile),
                    profile: profile,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "DATA & LICENSE",
                    style: TextStyle(
                      color: profile.secondaryTextColor,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!_isSysAdmin)
                    ProfileActionCard(
                      title: profile.isActivated
                          ? "License Active"
                          : AppStrings.activatePro,
                      subtitle: profile.isActivated
                          ? "Expires on: ${profile.expiryDate != null ? profile.expiryDate!.toString().split(' ')[0] : 'Lifetime'}"
                          : "Unlock full features",
                      icon: Icons.vpn_key_outlined,
                      onTap: () {
                        if (!profile.isActivated) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ActivationScreen(),
                            ),
                          );
                        } else {
                          _showLicenseDetails(profile);
                        }
                      },
                      profile: profile,
                    ),
                  ProfileActionCard(
                    title: "Data Management",
                    subtitle: "Backup, Restore and Privacy",
                    icon: Icons.storage_rounded,
                    onTap: () => _showDataManagement(profile),
                    profile: profile,
                  ),
                  ProfileActionCard(
                    title: "Services & Feedback",
                    subtitle: "Contact support or give feedback",
                    icon: Icons.feedback_outlined,
                    onTap: () => _showFeedbackPopup(profile),
                    profile: profile,
                  ),
                  if (profile.isActivated)
                    StreamBuilder<QuerySnapshot>(
                      stream: LicenseService.getTickets(profile.licenseKey),
                      builder: (context, snapshot) {
                        bool hasUpdate = false;
                        if (snapshot.hasData) {
                          hasUpdate = snapshot.data!.docs.any(
                            (doc) =>
                                (doc.data()
                                    as Map<String, dynamic>)['status'] ==
                                'answered',
                          );
                        }
                        return ProfileActionCard(
                          title: "Support Tickets",
                          subtitle: "Raise a ticket for help",
                          icon: Icons.help_outline_rounded,
                          trailing: hasUpdate
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    "NEW REPLY",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              : null,
                          onTap: () => _showSupportTickets(profile),
                          profile: profile,
                        );
                      },
                    ),
                  const SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: [
                        TextButton.icon(
                          onPressed: _confirmLogout,
                          icon: const Icon(Icons.logout, color: Colors.red),
                          label: const Text(
                            AppStrings.logout,
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
