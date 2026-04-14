import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
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
    bool isAdminEmail = user?.email == "nikkhilbarwar@gmail.com" || 
                        user?.email == "anitamishra1714@gmail.com" ||
                        user?.email == "missadvocate06@gmail.com";
    
    setState(() {
      _isSysAdmin = (prefs.getBool('is_sys_admin') ?? false) || isAdminEmail;
    });
  }

  Future<void> _pickAndCropImage(ProfileProvider profile, {bool isLogo = true}) async {
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Text("QR Code Type", style: TextStyle(fontWeight: FontWeight.bold)),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error picking image: $e")),
        );
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
          builder: (ctx) => AlertDialog(
            backgroundColor: profile.cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 12),
                Text('Backup Success', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text('Full backup created successfully!\n\nLocation: $path\n\nThis file will stay in your Documents folder even if you uninstall the app.', 
              style: TextStyle(color: profile.secondaryTextColor, fontSize: 13)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to create backup. Please check storage permissions.')));
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
            builder: (ctx) => AlertDialog(
              backgroundColor: profile.cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Text('Restore Data?', style: TextStyle(fontWeight: FontWeight.bold)),
              content: const Text('Warning: This will replace all current app data and settings with the data from backup file. This cannot be undone.', style: TextStyle(color: Colors.red)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true), 
                  child: const Text('PROCEED', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
                ),
              ],
            ),
          ) ?? false;

          if (confirm && mounted) {
            setState(() => _isBackingUp = true);
            bool success = await _exportService.restoreFromBackup(file);
            
            if (success) {
              await profile.loadProfile();
              if (mounted) {
                final transProvider = Provider.of<TransactionProvider>(context, listen: false);
                final itemProvider = Provider.of<ItemProvider>(context, listen: false);
                final catProvider = Provider.of<CategoryProvider>(context, listen: false);
                final staffProvider = Provider.of<StaffProvider>(context, listen: false);
                final unitProvider = Provider.of<UnitProvider>(context, listen: false);
                final suppProvider = Provider.of<SupplierProvider>(context, listen: false);
                final remProvider = Provider.of<PurchaseReminderProvider>(context, listen: false);

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
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Everything restored successfully!'), backgroundColor: Colors.green));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to restore data. Invalid backup file.'), backgroundColor: Colors.red));
              }
            }
          }
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _confirmLogout() {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text("${AppStrings.logout}?", style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold)),
        content: Text(AppStrings.confirmLogout, style: TextStyle(color: profile.secondaryTextColor)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(AppStrings.cancel)),
          TextButton(
            onPressed: () async {
              await _authService.signOut();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text(AppStrings.logout, style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showEditBottomSheet(BuildContext context, ProfileProvider profile) {
    final formKey = GlobalKey<FormState>();
    final n = TextEditingController(text: profile.businessName);
    final o = TextEditingController(text: profile.ownerName);
    final c = TextEditingController(text: profile.contact);
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
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize:
                  (profile.isPinEnabled ? {'pin': true} : {}).isNotEmpty
                      ? MainAxisSize.min
                      : MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(color: profile.secondaryTextColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Text(AppStrings.editBusiness, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: profile.textColor)),
                const SizedBox(height: 24),
                _buildField(n, AppStrings.businessName, Icons.business, profile),
                _buildField(o, AppStrings.ownerName, Icons.person_outline, profile),
                _buildField(c, AppStrings.contactNumber, Icons.phone_outlined, profile, keyboard: TextInputType.phone),
                Row(
                  children: [
                    Expanded(child: _buildField(t, AppStrings.taxPercentage, Icons.percent, profile, keyboard: TextInputType.number, suffix: '%')),
                    const SizedBox(width: 12),
                    Expanded(child: _buildField(tbl, 'Total Tables', Icons.table_restaurant, profile, keyboard: TextInputType.number)),
                  ],
                ),
                _buildField(a, AppStrings.address, Icons.location_on_outlined, profile, maxLines: 2),
                const SizedBox(height: 24),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text(AppStrings.saveChanges, style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
              ],
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
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(color: profile.secondaryTextColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text("Security Settings", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: profile.textColor)),
              const SizedBox(height: 24),
              
              // Custom PIN Toggle
              SwitchListTile(
                title: Text("Custom PIN Lock", style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold)),
                subtitle: Text(profile.isPinEnabled ? "PIN is active" : "Protect sensitive data with a PIN", style: TextStyle(fontSize: 12)),
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
                  title: Text("Change PIN", style: TextStyle(color: profile.textColor, fontSize: 14, fontWeight: FontWeight.bold)),
                  onTap: () => _showSetPinDialog(profile, setModalState),
                ),

              const Divider(),

              // Biometric Toggle
              SwitchListTile(
                title: Text("Device Lock (Biometric)", style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold)),
                subtitle: const Text("Use fingerprint or face ID", style: TextStyle(fontSize: 12)),
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
                style: ElevatedButton.styleFrom(backgroundColor: profile.themeColor, minimumSize: const Size(double.infinity, 50)),
                child: const Text("DONE", style: TextStyle(fontWeight: FontWeight.bold)),
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
          style: const TextStyle(fontSize: 24, letterSpacing: 10, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
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
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: profile.secondaryTextColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              children: [
                Icon(Icons.security_outlined, color: profile.themeColor, size: 28),
                const SizedBox(width: 12),
                Text("Data & Security", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: profile.textColor)),
              ],
            ),
            const SizedBox(height: 16),
            // Cloud Sync Toggle
            Container(
              decoration: BoxDecoration(
                color: profile.scaffoldColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SwitchListTile(
                title: Text("Cloud Backup & Sync", style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text("Sync business info across devices", style: TextStyle(fontSize: 11)),
                value: profile.isCloudSyncEnabled,
                activeThumbColor: profile.themeColor,
                onChanged: (val) => profile.toggleCloudSync(val),
              ),
            ),
            const SizedBox(height: 12),
            // Manual Sync Button
            OutlinedButton.icon(
              onPressed: () async {
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                bool success = await profile.fetchProfileFromCloud();
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? "Profile synced from cloud"
                          : "Failed to sync or no cloud data",
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              },
              icon: Icon(Icons.sync, size: 18, color: profile.themeColor),
              label: Text("SYNC PROFILE NOW", style: TextStyle(color: profile.themeColor, fontWeight: FontWeight.bold, fontSize: 12)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 45),
                side: BorderSide(color: profile.themeColor.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  "We are committed to safeguarding user information through robust technical and organizational measures. All data processed within the application is handled in accordance with industry-standard security protocols and applicable data protection regulations.\n\n"
                  "User-generated and transactional data is primarily stored in a secure local environment and, where applicable, may be synchronized with cloud-based services utilizing encrypted transmission channels (e.g., HTTPS/TLS). Sensitive information is neither exposed nor transmitted without appropriate safeguards and authentication layers.\n\n"
                  "We implement access control mechanisms, data minimization principles, and structured storage methodologies to ensure that only necessary information is retained for operational purposes. No personally identifiable information is shared with third parties except where explicitly required for service functionality, legal compliance, or authorized integrations.\n\n"
                  "The application does not engage in unauthorized data harvesting, background tracking, or intrusive analytics beyond the scope of essential service delivery. Any optional features involving external services are governed by their respective privacy frameworks.\n\n"
                  "While commercially reasonable efforts are made to ensure data integrity, availability, and confidentiality, users acknowledge that no digital system can guarantee absolute security. By using the application, users consent to data handling practices as outlined in this policy.",
                  style: TextStyle(color: profile.secondaryTextColor, fontSize: 14, height: 1.6, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.justify,
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: profile.themeColor, minimumSize: const Size(double.infinity, 50)),
              child: const Text("I UNDERSTAND", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showSupportTickets(ProfileProvider profile) {
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
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: profile.secondaryTextColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Support Tickets", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: profile.textColor)),
                  IconButton(
                    onPressed: () => _showCreateTicketDialog(profile),
                    icon: Icon(Icons.add_circle, color: profile.themeColor, size: 30),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: LicenseService.getTickets(profile.licenseKey),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.confirmation_number_outlined, size: 64, color: profile.secondaryTextColor.withValues(alpha: 0.5)),
                          const SizedBox(height: 16),
                          Text("No tickets found", style: TextStyle(color: profile.secondaryTextColor)),
                          TextButton(
                            onPressed: () => _showCreateTicketDialog(profile),
                            child: const Text("Create your first ticket"),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, index) {
                      final doc = snapshot.data!.docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final status = data['status'] ?? 'open';
                      
                      Color statusColor;
                      switch(status) {
                        case 'answered': statusColor = Colors.orange; break;
                        case 'resolved': statusColor = Colors.green; break;
                        case 'closed': statusColor = Colors.grey; break;
                        default: statusColor = Colors.blue;
                      }

                      return ListTile(
                        onTap: () => _showTicketChat(doc.id, profile),
                        leading: CircleAvatar(
                          backgroundColor: statusColor.withValues(alpha: 0.1),
                          child: Icon(Icons.help_outline, color: statusColor),
                        ),
                        title: Text(data['subject'] ?? 'No Subject', style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          "Last update: ${data['lastUpdate'] != null ? (data['lastUpdate'] as Timestamp).toDate().toString().split('.')[0] : 'N/A'}",
                          style: TextStyle(color: profile.secondaryTextColor, fontSize: 12),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
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
                decoration: const InputDecoration(labelText: "Subject", hintText: "e.g., License not working"),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: messageController,
                decoration: const InputDecoration(labelText: "Description", hintText: "Describe your issue"),
                maxLines: 3,
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                await LicenseService.createTicket(
                  licenseKey: profile.licenseKey,
                  restaurantName: profile.businessName,
                  phone: profile.contact,
                  subject: subjectController.text,
                  message: messageController.text,
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ticket created successfully!")));
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

  void _showTicketChat(String ticketId, ProfileProvider profile) {
    final replyController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: profile.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        height: MediaQuery.of(context).size.height * 0.9,
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: profile.secondaryTextColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            StreamBuilder<DocumentSnapshot>(
              stream: LicenseService.getTicketStream(ticketId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();
                final data = snapshot.data!.data() as Map<String, dynamic>;
                final replies = (data['replies'] as List? ?? []);

                return Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(child: Text(data['subject'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                                if (data['status'] != 'resolved')
                                  TextButton(
                                    onPressed: () => LicenseService.resolveTicket(ticketId),
                                    child: const Text("Mark Resolved", style: TextStyle(color: Colors.green)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(data['message'] ?? '', style: TextStyle(color: profile.secondaryTextColor)),
                            const Divider(),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: replies.length,
                          itemBuilder: (context, index) {
                            final reply = replies[index];
                            final isAdmin = reply['senderRole'] == 'admin';
                            return Align(
                              alignment: isAdmin ? Alignment.centerLeft : Alignment.centerRight,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isAdmin ? profile.themeColor.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: isAdmin ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                                  children: [
                                    Text(reply['message'], style: TextStyle(color: profile.textColor)),
                                    const SizedBox(height: 2),
                                    Text(
                                      "${reply['senderName']} • ${reply['timestamp']?.toString().split('T')[0] ?? ''}",
                                      style: TextStyle(fontSize: 10, color: profile.secondaryTextColor),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: replyController,
                      decoration: InputDecoration(
                        hintText: "Type a reply...",
                        fillColor: profile.scaffoldColor,
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    onPressed: () async {
                      if (replyController.text.isNotEmpty) {
                        await LicenseService.addTicketReply(
                          ticketId: ticketId,
                          message: replyController.text.trim(),
                          senderRole: 'user',
                          senderName: profile.businessName,
                        );
                        replyController.clear();
                      }
                    },
                    backgroundColor: profile.themeColor,
                    child: const Icon(Icons.send, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
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
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(color: profile.secondaryTextColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.feedback_outlined, color: profile.themeColor, size: 28),
                    const SizedBox(width: 12),
                    Text("Services & Feedback", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: profile.textColor)),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  "Tell us how we can improve. Your feedback helps us build a better experience for everyone.",
                  style: TextStyle(color: profile.secondaryTextColor, fontSize: 13),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: feedbackController,
                  maxLines: 5,
                  validator: (v) => v == null || v.trim().isEmpty ? "Please enter your message" : null,
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
                            final String msg = Uri.encodeComponent(feedbackController.text.trim());
                            final Uri emailUri = Uri.parse("mailto:Nikkhilbarwar@gmail.com?subject=App Feedback&body=$msg");
                            if (await canLaunchUrl(emailUri)) {
                              await launchUrl(emailUri);
                              if (ctx.mounted) Navigator.pop(ctx);
                            }
                          }
                        },
                        icon: const Icon(Icons.email_outlined, size: 20),
                        label: const Text("EMAIL", style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, minimumSize: const Size(0, 50)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            final String msg = Uri.encodeComponent(feedbackController.text.trim());
                            final Uri waUri = Uri.parse("https://wa.me/919992256959?text=$msg");
                            if (await canLaunchUrl(waUri)) {
                              await launchUrl(waUri);
                              if (ctx.mounted) Navigator.pop(ctx);
                            }
                          }
                        },
                        icon: const Icon(Icons.chat_outlined, size: 20),
                        label: const Text("WHATSAPP", style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, minimumSize: const Size(0, 50)),
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

  Widget _buildField(TextEditingController controller, String label, IconData icon, ProfileProvider profile, {TextInputType? keyboard, String? suffix, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: maxLines,
        style: TextStyle(color: profile.textColor, fontSize: 14, fontWeight: FontWeight.bold),
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
                final settings = ctx.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
                final deltaExtent = settings!.maxExtent - settings.minExtent;
                final t = (1.0 - (settings.currentExtent - settings.minExtent) / deltaExtent).clamp(0.0, 1.0);
                
                return FlexibleSpaceBar(
                  centerTitle: true,
                  title: Opacity(
                    opacity: t > 0.7 ? 1.0 : 0.0,
                    child: Text(
                      profile.businessName,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
                          child: CircleAvatar(radius: 100, backgroundColor: Colors.white.withValues(alpha: 0.05)),
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
                                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                      child: CircleAvatar(
                                        radius: 50,
                                        backgroundColor: profile.cardColor,
                                        backgroundImage: profile.logoPath.isNotEmpty && File(profile.logoPath).existsSync()
                                            ? FileImage(File(profile.logoPath))
                                            : (user?.photoURL != null ? NetworkImage(user!.photoURL!) : null) as ImageProvider?,
                                        child: (profile.logoPath.isEmpty || !File(profile.logoPath).existsSync()) && user?.photoURL == null
                                            ? Icon(Icons.business, size: 40, color: themeColor)
                                            : null,
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                        child: Icon(Icons.edit, size: 16, color: themeColor),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                profile.businessName,
                                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                profile.ownerName.isEmpty ? (user?.displayName ?? "") : profile.ownerName,
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
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
                  Text("SETTINGS", style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 12)),
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
                    subtitle: profile.qrPath.isNotEmpty ? "QR Code uploaded" : "Upload QR for Bill",
                    icon: Icons.qr_code_2_rounded,
                    onTap: () => _pickAndCropImage(profile, isLogo: false),
                    trailing: profile.qrPath.isNotEmpty 
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
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
                        MaterialPageRoute(builder: (context) => const PrinterSettingsScreen()),
                      );
                    },
                    profile: profile,
                  ),
                  ProfileActionCard(
                    title: "Theme Color",
                    subtitle: "Personalize your app look",
                    icon: Icons.palette_outlined,
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: profile.cardColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          title: Text("Select Theme Color", style: TextStyle(color: profile.textColor)),
                          content: SizedBox(
                            width: MediaQuery.of(context).size.width * 0.9,
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (profile.customThemeColors.isNotEmpty) ...[
                                    Text("Saved Custom Colors",
                                        style: TextStyle(
                                            color: profile.secondaryTextColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      height: 50,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: profile.customThemeColors.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(width: 12),
                                        itemBuilder: (context, index) {
                                          final colorVal =
                                              profile.customThemeColors[index];
                                          final color = Color(colorVal);
                                          final isSelected =
                                              profile.themeColorValue == colorVal;
                                          return GestureDetector(
                                            onTap: () {
                                              profile.savePresetTheme(color);
                                              Navigator.pop(ctx);
                                            },
                                            onLongPress: () {
                                              profile.removeCustomColor(colorVal);
                                            },
                                            child: Container(
                                              width: 50,
                                              height: 50,
                                              decoration: BoxDecoration(
                                                color: color,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: isSelected
                                                      ? profile.textColor
                                                      : Colors.transparent,
                                                  width: 2,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: color.withValues(
                                                        alpha: 0.3),
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 4),
                                                  )
                                                ],
                                              ),
                                              child: isSelected
                                                  ? const Icon(Icons.check,
                                                      color: Colors.white,
                                                      size: 20)
                                                  : null,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    const Divider(),
                                    const SizedBox(height: 12),
                                  ],
                                  Text("Presets",
                                      style: TextStyle(
                                          color: profile.secondaryTextColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 12),
                                  BlockPicker(
                                    pickerColor: themeColor,
                                    onColorChanged: (color) {
                                      profile.savePresetTheme(color);
                                      Navigator.pop(ctx);
                                    },
                                  ),
                                  const Divider(),
                                  const SizedBox(height: 8),
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          profile.themeColor.withValues(alpha: 0.1),
                                      child: Icon(Icons.colorize,
                                          color: themeColor),
                                    ),
                                    title: Text("Choose New Custom Color",
                                        style: TextStyle(
                                            color: profile.textColor,
                                            fontSize: 14)),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      Color pickedColor = themeColor;
                                      final hexController = TextEditingController(
                                        text: pickedColor
                                            .toARGB32()
                                            .toRadixString(16)
                                            .padLeft(8, '0')
                                            .substring(2)
                                            .toUpperCase(),
                                      );

                                      showDialog(
                                        context: context,
                                        builder: (ctx) => StatefulBuilder(
                                          builder: (context, setDialogState) =>
                                              AlertDialog(
                                            backgroundColor: profile.cardColor,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(24)),
                                            title: Text("Custom Theme Color",
                                                style: TextStyle(
                                                    color: profile.textColor,
                                                    fontSize: 18,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            content: SingleChildScrollView(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  ColorPicker(
                                                    pickerColor: pickedColor,
                                                    onColorChanged: (color) {
                                                      pickedColor = color;
                                                      final newHex = color
                                                          .toARGB32()
                                                          .toRadixString(16)
                                                          .padLeft(8, '0')
                                                          .substring(2)
                                                          .toUpperCase();
                                                      if (hexController.text
                                                              .toUpperCase() !=
                                                          newHex) {
                                                        hexController.text =
                                                            newHex;
                                                      }
                                                      setDialogState(() {});
                                                    },
                                                    enableAlpha: false,
                                                    displayThumbColor: true,
                                                    pickerAreaHeightPercent: 0.7,
                                                    hexInputBar: false,
                                                  ),
                                                  const SizedBox(height: 20),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 16,
                                                        vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          profile.scaffoldColor,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              16),
                                                      border: Border.all(
                                                          color: profile
                                                              .secondaryTextColor
                                                              .withValues(
                                                                  alpha: 0.1)),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Text("#",
                                                            style: TextStyle(
                                                                color: profile
                                                                    .secondaryTextColor,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 18)),
                                                        const SizedBox(
                                                            width: 12),
                                                        Expanded(
                                                          child: TextField(
                                                            controller:
                                                                hexController,
                                                            style: TextStyle(
                                                                color: profile
                                                                    .textColor,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                letterSpacing:
                                                                    1.5),
                                                            decoration:
                                                                const InputDecoration(
                                                              border: InputBorder
                                                                  .none,
                                                              hintText:
                                                                  "RRGGBB",
                                                              counterText: "",
                                                            ),
                                                            maxLength: 6,
                                                            onChanged: (val) {
                                                              if (val.length ==
                                                                  6) {
                                                                try {
                                                                  final color = Color(
                                                                      int.parse(
                                                                          "FF$val",
                                                                          radix:
                                                                              16));
                                                                  setDialogState(
                                                                      () {
                                                                    pickedColor =
                                                                        color;
                                                                  });
                                                                } catch (_) {}
                                                              }
                                                            },
                                                          ),
                                                        ),
                                                        Container(
                                                          width: 30,
                                                          height: 30,
                                                          decoration:
                                                              BoxDecoration(
                                                            color: pickedColor,
                                                            shape:
                                                                BoxShape.circle,
                                                            border: Border.all(
                                                                color:
                                                                    Colors.white,
                                                                width: 2),
                                                            boxShadow: [
                                                              BoxShadow(
                                                                  color: pickedColor
                                                                      .withValues(
                                                                          alpha:
                                                                              0.3),
                                                                  blurRadius: 4)
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx),
                                                  child: Text("CANCEL",
                                                      style: TextStyle(
                                                          color: profile
                                                              .secondaryTextColor))),
                                              ElevatedButton(
                                                onPressed: () {
                                                  profile.updateThemeColor(
                                                      pickedColor);
                                                  Navigator.pop(ctx);
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: pickedColor,
                                                  foregroundColor: Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              15)),
                                                  elevation: 0,
                                                ),
                                                child: const Text(
                                                    "SAVE & APPLY THEME",
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    profile: profile,
                  ),
                  ProfileActionCard(
                    title: "Dark Mode",
                    subtitle: "Easier on your eyes",
                    icon: Icons.dark_mode_outlined,
                    trailing: Switch(
                      value: profile.isDarkMode,
                      activeThumbColor: themeColor,
                      onChanged: (val) => profile.toggleDarkMode(val),
                    ),
                    onTap: () => profile.toggleDarkMode(!profile.isDarkMode),
                    profile: profile,
                  ),
                  const SizedBox(height: 24),
                  Text("DATA & LICENSE", style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 12)),
                  const SizedBox(height: 12),
                  if (!_isSysAdmin)
                  ProfileActionCard(
                    title: profile.isActivated ? "License Active" : AppStrings.activatePro,
                    subtitle: profile.isActivated 
                      ? "Expires on: ${profile.expiryDate != null ? profile.expiryDate!.toString().split(' ')[0] : 'Lifetime'}"
                      : "Unlock full features",
                    icon: Icons.vpn_key_outlined,
                    onTap: () {
                      if (!profile.isActivated) {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const ActivationScreen()));
                      }
                    },
                    profile: profile,
                  ),
                  ProfileActionCard(
                    title: "Backup & Sync",
                    subtitle: _isBackingUp ? "Backing up..." : "Secure your data offline",
                    icon: Icons.cloud_upload_outlined,
                    onTap: () => _handleBackup(profile),
                    profile: profile,
                  ),
                  ProfileActionCard(
                    title: "Restore Data",
                    subtitle: "Import from local backup",
                    icon: Icons.restore_rounded,
                    onTap: () => _handleRestore(profile),
                    profile: profile,
                  ),
                  ProfileActionCard(
                    title: "Data & Security",
                    subtitle: "Privacy policy and security settings",
                    icon: Icons.security_outlined,
                    onTap: () => _showDataSecurityPopup(profile),
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
                    ProfileActionCard(
                      title: "Support Tickets",
                      subtitle: "Raise a ticket for help",
                      icon: Icons.help_outline_rounded,
                      onTap: () => _showSupportTickets(profile),
                      profile: profile,
                    ),
                  const SizedBox(height: 24),
                  Center(
                    child: TextButton.icon(
                      onPressed: _confirmLogout,
                      icon: const Icon(Icons.logout, color: Colors.red),
                      label: const Text(AppStrings.logout, style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
