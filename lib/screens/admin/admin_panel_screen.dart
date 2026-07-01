import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'dart:async';
import '../../services/license_service.dart';
import '../../providers/profile_provider.dart';

import '../../utils/report_helper.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/export_service.dart';
import '../../services/firebase_service.dart';
import '../../core/widgets/app_bottom_sheet.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _restaurantController = TextEditingController();
  final TextEditingController _ownerController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _announcementController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  bool _isGenerating = false;
  bool _isInitializing = true;
  bool _isPostingAnnouncement = false;
  bool _sendPushNotification = true;
  bool _isAnnouncementExpanded = false;
  bool _isSelectionMode = false;
  final Set<String> _selectedPhones = {};
  int _secretTapCount = 0;

  String _adminRole = 'staff';
  String _selectedPlan = '1 Year (365 Days)';
  String _statusFilter = 'All';
  String? _generatedKey;

  final String _driveLink =
      "https://drive.google.com/drive/folders/1560Q2Lju7iBDBwKAYC0UOwkSV7NAvMM6?usp=sharing";

  final List<Map<String, dynamic>> _validityOptions = [
    {'label': '1 Month (28 Days)', 'days': 28, 'planType': 'monthly'},
    {'label': '3 Months (84 Days)', 'days': 84, 'planType': 'quarterly'},
    {'label': '6 Months (168 Days)', 'days': 168, 'planType': 'half_yearly'},
    {'label': '1 Year (365 Days)', 'days': 365, 'planType': 'yearly'},
    {'label': 'Lifetime (10 Years)', 'days': 3650, 'planType': 'lifetime'},
  ];

  @override
  void initState() {
    super.initState();
    _initLicenseSystem();
    _loadCurrentAnnouncement();
  }

  Future<void> _initLicenseSystem() async {
    try {
      await LicenseService.init();
      final user = FirebaseAuth.instance.currentUser;
      final userEmail = user?.email?.toLowerCase() ?? '';
      final uid = user?.uid;

      const adminEmails = [
        "nikkhilbarwar@gmail.com",
        "anitamishra1714@gmail.com",
        "missadvocate06@gmail.com",
      ];

      if (mounted) {
        setState(() {
          _adminRole = 'staff';

          if (adminEmails.contains(userEmail)) {
            _adminRole = 'super_admin';

            if (uid != null) {
              LicenseService.firestore
                  .collection('admins')
                  .doc(uid)
                  .set({
                    'email': userEmail,
                    'role': 'super_admin',
                    'status': 'active',
                    'lastLogin': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true))
                  .catchError((_) {});
            }
          }

          _isInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<void> _loadCurrentAnnouncement() async {
    try {
      final doc = await LicenseService.firestore
          .collection('admin_settings')
          .doc('announcement')
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _announcementController.text = doc.data()?['message'] ?? "";
        });
      }
    } catch (_) {}
  }

  Timer? _debounce;
  void _onAnnouncementChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 1000), () async {
      await LicenseService.firestore
          .collection('admin_settings')
          .doc('announcement')
          .set({
            'message': value.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    });
  }

  String _generateLicenseKey(String restaurant, String owner, String phone) {
    final year = DateTime.now().year.toString();
    final restCode = restaurant
        .replaceAll(RegExp(r'[^A-Za-z]'), '')
        .toUpperCase()
        .padRight(3, 'X')
        .substring(0, 3);
    final ownerCode = owner
        .replaceAll(RegExp(r'[^A-Za-z]'), '')
        .toUpperCase()
        .padRight(2, 'X')
        .substring(0, 2);
    final phoneCode = phone.length >= 4
        ? phone.substring(phone.length - 4)
        : phone.padLeft(4, '0');

    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final randomCode = List.generate(
      6,
      (_) => chars[Random().nextInt(chars.length)],
    ).join();

    return 'RESTO-$year-$restCode$ownerCode-$randomCode-$phoneCode';
  }

  Future<void> _handleGenerate() async {
    if (_restaurantController.text.isEmpty ||
        _ownerController.text.isEmpty ||
        _phoneController.text.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all details correctly")),
      );
      return;
    }

    setState(() => _isGenerating = true);
    try {
      final key = _generateLicenseKey(
        _restaurantController.text,
        _ownerController.text,
        _phoneController.text,
      );
      final plan = _validityOptions.firstWhere(
        (e) => e['label'] == _selectedPlan,
      );
      final now = DateTime.now();
      final days = plan['days'] as int;
      final expiry = now.add(Duration(days: days));

      await LicenseService.firestore.collection('licenses').doc(key).set({
        'licenseKey': key,
        'restaurantName': _restaurantController.text.trim(),
        'ownerName': _ownerController.text.trim(),
        'phone': _phoneController.text.trim(),
        'status': 'active',
        'planType': plan['planType'],
        'price': int.tryParse(_priceController.text) ?? 0,
        'isLifetime': plan['days'] == 3650,
        'createdAt': FieldValue.serverTimestamp(),
        'validTill': expiry.toIso8601String(),
        'validTillFormatted': DateFormat('dd/MM/yyyy').format(expiry),
        'activated': false,
        'activeDeviceId': null,
        'isReminderEnabled': true,
        'saleBlocked': false,
        'expenseBlocked': false,
        'bypassCheck': false,
      });

      setState(() {
        _generatedKey = key;
        _isGenerating = false;
      });
      _restaurantController.clear();
      _ownerController.clear();
      _phoneController.clear();
      _priceController.clear();
    } catch (e) {
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _postAnnouncement() async {
    if (_announcementController.text.trim().isEmpty) return;

    setState(() => _isPostingAnnouncement = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final adminId =
          prefs.getString('admin_id') ??
          FirebaseAuth.instance.currentUser?.email ??
          "Unknown Admin";

      await LicenseService.firestore
          .collection('admin_settings')
          .doc('announcement')
          .set({
            'message': _announcementController.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
            'targetUsers': _selectedPhones.isEmpty
                ? 'all'
                : _selectedPhones.toList(),
          });

      await LicenseService.logAdminAction(
        adminId,
        "POST_ANNOUNCEMENT",
        "Published: ${_announcementController.text.trim()} to ${_selectedPhones.isEmpty ? 'All' : _selectedPhones.length} users",
      );

      if (_sendPushNotification) {
        await LicenseService.queueAnnouncementNotification(
          "New Announcement",
          _announcementController.text.trim(),
        );
      }

      if (mounted) {
        setState(() {
          _isAnnouncementExpanded = false;
          _isSelectionMode = false;
          _selectedPhones.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Announcement Published!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isPostingAnnouncement = false);
    }
  }

  Future<void> _showStaffManagement(ProfileProvider profile) async {
    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: "STAFF MANAGEMENT",
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(Icons.person_add_alt_1, color: profile.themeColor),
                  onPressed: () => _editAdminDialog(null, profile),
                ),
              ],
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: LicenseService.getAdminStream(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final admins = snapshot.data!.docs;
                  return ListView.builder(
                    itemCount: admins.length,
                    itemBuilder: (context, index) {
                      final data = admins[index].data() as Map<String, dynamic>;
                      final id = admins[index].id;
                      final email = data['email'] ?? "No Email";
                      final role = data['role'] ?? 'staff';
                      final status = data['status'] ?? 'active';

                      final displayRole =
                          email.toLowerCase() == 'nikkhilbarwar@gmail.com'
                          ? 'super_admin'
                          : role;
                      final isSuper = displayRole == 'super_admin';

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSuper
                              ? Colors.purple
                              : Colors.blue,
                          child: Icon(
                            isSuper ? Icons.verified_user : Icons.person,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          email,
                          style: TextStyle(
                            color: profile.textColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          "Role: ${displayRole.toUpperCase()} | Status: ${status.toUpperCase()}",
                          style: TextStyle(
                            color: profile.secondaryTextColor,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.edit_note_rounded,
                                color: profile.themeColor,
                              ),
                              onPressed: () =>
                                  _editAdminDialog(admins[index], profile),
                            ),
                            if (email.toLowerCase() !=
                                'nikkhilbarwar@gmail.com')
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_sweep_rounded,
                                  color: Colors.red,
                                  size: 22,
                                ),
                                onPressed: () => _confirmDeleteAdmin(id, email),
                              ),
                          ],
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

  Future<void> _editAdminDialog(
    DocumentSnapshot? admin,
    ProfileProvider profile,
  ) async {
    final emailController = TextEditingController(
      text: admin != null ? admin['email'] : '',
    );
    final passController = TextEditingController(
      text: admin != null ? admin['password'] : '',
    );
    String selectedRole =
        (admin != null &&
            admin.data() != null &&
            (admin.data() as Map).containsKey('role'))
        ? admin['role']
        : 'staff';
    String selectedStatus =
        (admin != null &&
            admin.data() != null &&
            (admin.data() as Map).containsKey('status'))
        ? admin['status']
        : 'active';

    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: admin == null ? "Add New Staff" : "Update Profile",
      child: StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _buildStyledField(
              emailController,
              "Email Address",
              Icons.email_outlined,
              profile,
            ),
            const SizedBox(height: 16),
            _buildStyledField(
              passController,
              "Password",
              Icons.lock_outline,
              profile,
            ),
            const SizedBox(height: 24),
            _buildDropdown(
              "Access Level",
              selectedRole,
              ['staff', 'super_admin'],
              (v) => setDialogState(() => selectedRole = v!),
              profile,
            ),
            const SizedBox(height: 16),
            _buildDropdown(
              "Account Status",
              selectedStatus,
              ['active', 'disabled'],
              (v) => setDialogState(() => selectedStatus = v!),
              profile,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: profile.themeColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  if (emailController.text.isEmpty ||
                      passController.text.length < 4) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Invalid Email or Password"),
                      ),
                    );
                    return;
                  }

                  final prefs = await SharedPreferences.getInstance();
                  final currentAdmin =
                      prefs.getString('admin_id') ?? "SuperAdmin";
                  final isYourEmail =
                      emailController.text.trim().toLowerCase() ==
                      'nikkhilbarwar@gmail.com';

                  await LicenseService.updateAdmin(
                    id:
                        admin?.id ??
                        emailController.text.trim().replaceAll('.', '_'),
                    email: emailController.text.trim(),
                    password: passController.text.trim(),
                    role: isYourEmail ? 'super_admin' : selectedRole,
                    status: isYourEmail ? 'active' : selectedStatus,
                  );

                  await LicenseService.logAdminAction(
                    currentAdmin,
                    admin == null ? "ADD_STAFF" : "UPDATE_STAFF",
                    "${admin == null ? 'Added' : 'Updated'} staff: ${emailController.text.trim()}",
                  );

                  if (mounted) Navigator.pop(context);
                },
                child: const Text(
                  "SAVE CHANGES",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStyledField(
    TextEditingController controller,
    String label,
    IconData icon,
    ProfileProvider profile,
  ) {
    return TextField(
      controller: controller,
      style: TextStyle(color: profile.textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: profile.secondaryTextColor, fontSize: 14),
        prefixIcon: Icon(icon, color: profile.themeColor, size: 20),
        filled: true,
        fillColor: profile.scaffoldColor.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: profile.themeColor, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    String value,
    List<String> items,
    Function(String?) onChanged,
    ProfileProvider profile,
  ) {
    return DropdownButtonFormField<String>(
      value: value,
      dropdownColor: profile.cardColor,
      style: TextStyle(color: profile.textColor, fontWeight: FontWeight.w500),
      items: items
          .map(
            (e) => DropdownMenuItem(
              value: e,
              child: Text(
                e.toUpperCase(),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: profile.secondaryTextColor, fontSize: 12),
        filled: true,
        fillColor: profile.scaffoldColor.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  Future<void> _confirmDeleteAdmin(String id, String email) async {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final confirm = await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: "Remove Staff?",
      message:
          "Are you sure you want to remove $email? They will lose all admin access.",
      confirmLabel: "REMOVE",
      isDestructive: true,
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      final currentAdmin = prefs.getString('admin_id') ?? "SuperAdmin";

      await LicenseService.deleteAdmin(id);
      await LicenseService.logAdminAction(
        currentAdmin,
        "DELETE_STAFF",
        "Removed staff access for: $email",
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Staff Removed Successfully")),
        );
      }
    }
  }

  void _showLicenseDetails(Map<String, dynamic> data, ProfileProvider profile) {
    bool isActive = data['status'] == 'active';
    bool isSyncingStats = false; // Define here so it persists in the modal scope
    bool isReminderEnabled = data['isReminderEnabled'] ?? true;
    bool saleBlocked = data['saleBlocked'] ?? false;
    bool bypassCheck = data['bypassCheck'] ?? false;
    String appVersion = data['appVersion'] ?? "Unknown";
    int txCount = data['tx_count'] ?? 0;
    String lastUsed = data['lastUsedAt'] != null
        ? DateFormat(
            'dd MMM, hh:mm a',
          ).format((data['lastUsedAt'] as Timestamp).toDate())
        : "Never";

    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: data['restaurantName'] ?? "License Info",
      child: StatefulBuilder(
        builder: (context, setModalState) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isActive ? "ACTIVE" : "BLOCKED",
                      style: TextStyle(
                        color: isActive ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _detailRow(
                "Business Name",
                data['restaurantName'] ?? "N/A",
                Icons.storefront_rounded,
                profile,
              ),
              Row(
                children: [
                  Expanded(
                    child: _detailRow(
                      "Owner Name",
                      data['ownerName'] ?? "N/A",
                      Icons.person_outline_rounded,
                      profile,
                    ),
                  ),
                  Expanded(
                    child: _detailRow(
                      "Phone",
                      data['phone'] ?? "N/A",
                      Icons.phone_android_rounded,
                      profile,
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),
              _detailRow(
                "License Key",
                data['licenseKey'] ?? "N/A",
                Icons.vpn_key,
                profile,
                isSelectable: true,
              ),
              Row(
                children: [
                  Expanded(
                    child: _detailRow(
                      "Validity",
                      data['validTillFormatted'] ?? "N/A",
                      Icons.calendar_today,
                      profile,
                    ),
                  ),
                  Expanded(
                    child: _detailRow(
                      "Plan Type",
                      (data['planType'] ?? "N/A").toString().toUpperCase(),
                      Icons.card_membership_rounded,
                      profile,
                    ),
                  ),
                ],
              ),
              _detailRow(
                "Amount Collected",
                "₹${data['price'] ?? 0}",
                Icons.payments_outlined,
                profile,
                valueColor: Colors.green,
              ),

              const Divider(height: 12),
              StatefulBuilder(
                builder: (context, setBtnState) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "USAGE ACTIVITY (TX COUNT)",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: profile.secondaryTextColor,
                          letterSpacing: 1,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: isSyncingStats
                            ? null
                            : () async {
                                setBtnState(() => isSyncingStats = true);
                                try {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Deep scanning transactions..."),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                  final count = await FirebaseService().recalculateLicenseStats(data['licenseKey']);
                                  
                                  if (context.mounted) {
                                    setModalState(() {}); // Refresh the FutureBuilder
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(count > 0 
                                          ? "Success: $count transactions found & synced!" 
                                          : "No transactions found in database for this license."),
                                        backgroundColor: count > 0 ? Colors.green : Colors.orange,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text("Error: $e")),
                                    );
                                  }
                                } finally {
                                  if (context.mounted) {
                                    setBtnState(() => isSyncingStats = false);
                                  }
                                }
                              },
                        icon: isSyncingStats
                            ? const SizedBox(
                                height: 12,
                                width: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.blue,
                                ),
                              )
                            : Icon(Icons.sync_rounded, size: 14, color: profile.themeColor),
                        label: Text(
                          isSyncingStats ? "SYNCING..." : "FIX DATA",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isSyncingStats ? profile.secondaryTextColor : profile.themeColor,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          backgroundColor: profile.themeColor.withOpacity(0.1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              FutureBuilder<Map<String, int>>(
                future: FirebaseService().getLicenseStats(data['licenseKey']),
                builder: (context, statsSnapshot) {
                  final stats =
                      statsSnapshot.data ?? {'today': 0, 'week': 0, 'month': 0, 'total': 0};
                  final isLoading =
                      statsSnapshot.connectionState == ConnectionState.waiting;

                  return Column(
                    children: [
                      Row(
                        children: [
                          _buildUsageBox(
                            "Today",
                            stats['today']!,
                            Colors.blue,
                            isLoading,
                            profile,
                          ),
                          const SizedBox(width: 8),
                          _buildUsageBox(
                            "7 Days",
                            stats['week']!,
                            Colors.orange,
                            isLoading,
                            profile,
                          ),
                          const SizedBox(width: 8),
                          _buildUsageBox(
                            "30 Days",
                            stats['month']!,
                            Colors.purple,
                            isLoading,
                            profile,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildUsageBox(
                        "Lifetime Total Transactions",
                        stats['total']!,
                        profile.themeColor,
                        isLoading,
                        profile,
                        isFullWidth: true,
                      ),
                    ],
                  );
                },
              ),

              if (data['upgradeRequest'] != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.upgrade_rounded, color: Colors.orange),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "UPGRADE REQUESTED: ${data['upgradeRequest']}",
                          style: const TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              const Divider(height: 24),
              Text(
                "QUICK EXTEND",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: profile.secondaryTextColor,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _quickExtendBtn(data, 7, "7D", profile),
                  const SizedBox(width: 8),
                  _quickExtendBtn(data, 28, "28D", profile),
                  const SizedBox(width: 8),
                  _quickExtendBtn(data, 84, "3M", profile),
                  const SizedBox(width: 8),
                  _quickExtendBtn(data, 365, "1Y", profile),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _detailRow(
                      "App Version",
                      appVersion,
                      Icons.phonelink_setup_rounded,
                      profile,
                    ),
                  ),
                  Expanded(
                    child: _detailRow(
                      "Total Trans.",
                      txCount.toString(),
                      Icons.receipt_long_rounded,
                      profile,
                      valueColor: profile.themeColor,
                    ),
                  ),
                ],
              ),
              _detailRow(
                "Device ID",
                data['activeDeviceId'] ?? "NOT LINKED",
                Icons.phone_android_rounded,
                profile,
                valueColor: data['activeDeviceId'] == null ? Colors.orange : null,
                trailing: data['activeDeviceId'] != null
                    ? TextButton(
                        onPressed: () => _resetDevice(
                          data['licenseKey'],
                          data['restaurantName'] ?? "User",
                          profile,
                        ),
                        child: const Text(
                          "RESET",
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : null,
              ),
              _detailRow(
                "Last Active",
                lastUsed,
                Icons.access_time_rounded,
                profile,
              ),
              const Divider(height: 32),
              Text(
                "USER PERMISSIONS & CONTROLS",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: profile.secondaryTextColor,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              _toggleTile(
                "Bypass License Check",
                "Allow app access even if license is invalid",
                bypassCheck,
                Icons.verified_user_outlined,
                profile,
                (val) async {
                  final prefs = await SharedPreferences.getInstance();
                  final adminId =
                      prefs.getString('admin_id') ??
                      FirebaseAuth.instance.currentUser?.email ??
                      "Unknown Admin";
                  await LicenseService.firestore
                      .collection('licenses')
                      .doc(data['licenseKey'])
                      .update({'bypassCheck': val});
                  await LicenseService.logAdminAction(
                    adminId,
                    "TOGGLE_BYPASS",
                    "Set bypass to $val for ${data['licenseKey']}",
                  );
                  setModalState(() => bypassCheck = val);
                },
              ),
              _toggleTile(
                "Payment Reminder",
                "Show daily payment alerts to user",
                isReminderEnabled,
                Icons.notifications_active_rounded,
                profile,
                (val) async {
                  final prefs = await SharedPreferences.getInstance();
                  final adminId =
                      prefs.getString('admin_id') ??
                      FirebaseAuth.instance.currentUser?.email ??
                      "Unknown Admin";
                  await LicenseService.firestore
                      .collection('licenses')
                      .doc(data['licenseKey'])
                      .update({'isReminderEnabled': val});
                  await LicenseService.logAdminAction(
                    adminId,
                    "TOGGLE_REMINDER",
                    "Set reminder to $val for ${data['licenseKey']}",
                  );
                  setModalState(() => isReminderEnabled = val);
                },
              ),
              _toggleTile(
                "Block Sales",
                "Prevent user from creating new sales",
                saleBlocked,
                Icons.block_flipped,
                profile,
                (val) async {
                  final prefs = await SharedPreferences.getInstance();
                  final adminId =
                      prefs.getString('admin_id') ??
                      FirebaseAuth.instance.currentUser?.email ??
                      "Unknown Admin";
                  await LicenseService.firestore
                      .collection('licenses')
                      .doc(data['licenseKey'])
                      .update({'saleBlocked': val});
                  await LicenseService.logAdminAction(
                    adminId,
                    "BLOCK_SALES",
                    "Set block_sales to $val for ${data['licenseKey']}",
                  );
                  setModalState(() => saleBlocked = val);
                },
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _editExpiryDate(data, profile),
                      icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                      label: const Text("EDIT EXPIRY"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        final adminId =
                            prefs.getString('admin_id') ??
                            FirebaseAuth.instance.currentUser?.email ??
                            "Unknown Admin";
                        await LicenseService.resetDevice(
                          data['licenseKey'],
                          adminId,
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Device Reset Successful!"),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text("RESET DEVICE"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade800,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_adminRole == 'super_admin')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      final adminId =
                          prefs.getString('admin_id') ??
                          FirebaseAuth.instance.currentUser?.email ??
                          "Unknown Admin";
                      await LicenseService.firestore
                          .collection('licenses')
                          .doc(data['licenseKey'])
                          .update({'status': isActive ? 'blocked' : 'active'});
                      await LicenseService.logAdminAction(
                        adminId,
                        isActive ? "BLOCK_APP" : "ACTIVATE_APP",
                        "License ${data['licenseKey']} status set to ${isActive ? 'blocked' : 'active'}",
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isActive
                                  ? "License Blocked!"
                                  : "License Unblocked!",
                            ),
                            backgroundColor: isActive
                                ? Colors.red
                                : Colors.green,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isActive ? Colors.red : Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      isActive ? "BLOCK APP" : "ACTIVATE APP",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              if (_adminRole == 'super_admin')
                Center(
                  child: TextButton.icon(
                    onPressed: () => _deleteLicense(
                      data['licenseKey'],
                      data['restaurantName'] ?? "N/A",
                      profile,
                    ),
                    icon: const Icon(
                      Icons.delete_forever_rounded,
                      color: Colors.red,
                    ),
                    label: const Text(
                      "DELETE LICENSE PERMANENTLY",
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => _launchWhatsApp(
                        data['phone'],
                        data['restaurantName'],
                        data['ownerName'],
                      ),
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: Colors.green,
                      ),
                      label: const Text(
                        "WHATSAPP USER",
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => Share.share(
                        "Restaurant: ${data['restaurantName']}\nLicense: ${data['licenseKey']}\nDownload App: $_driveLink",
                      ),
                      icon: const Icon(Icons.share),
                      label: const Text("SHARE KEY"),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => ExportService().generateLicenseInvoice(data),
                  icon: const Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 20,
                    color: Colors.blue,
                  ),
                  label: const Text(
                    "GENERATE CASH MEMO",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                      fontSize: 13,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Colors.blue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _launchWhatsApp(String? phone, String? restaurant, String? owner) async {
    if (phone == null || phone.isEmpty) return;
    String cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.length == 10) cleanPhone = "91$cleanPhone";
    String message =
        "Hello ${owner ?? 'Sir/Madam'},\nGreetings from Apna Hisaab!\nRegarding your restaurant: ${restaurant ?? 'N/A'}";
    String url =
        "https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}";
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _deleteLicense(
    String key,
    String restaurant,
    ProfileProvider profile, {
    bool isFromList = false,
  }) async {
    final confirm = await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: "Delete License?",
      message:
          "Are you sure you want to permanently delete the license for '$restaurant'?",
      confirmLabel: "DELETE",
      isDestructive: true,
    );

    if (confirm == true) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final adminId = prefs.getString('admin_id') ?? "Admin";
        await LicenseService.firestore.collection('licenses').doc(key).delete();
        await LicenseService.logAdminAction(
          adminId,
          "DELETE_LICENSE",
          "Deleted license for $restaurant ($key)",
        );
        if (mounted) {
          if (!isFromList) Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("License Deleted"),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _deleteTicket(
    String ticketId,
    String restaurantName,
    ProfileProvider profile, {
    bool shouldPop = false,
  }) async {
    final confirm = await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: "Delete Ticket?",
      message:
          "Are you sure you want to permanently delete the support ticket from '$restaurantName'?",
      confirmLabel: "DELETE",
      isDestructive: true,
    );

    if (confirm == true) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final adminId = prefs.getString('admin_id') ?? "Admin";
        // Use the service's delete method (Soft Delete) to avoid permission issues
        await LicenseService.deleteTicket(ticketId);
        await LicenseService.logAdminAction(
          adminId,
          "DELETE_TICKET",
          "Deleted ticket for $restaurantName ($ticketId)",
        );

        if (mounted) {
          if (shouldPop) Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Ticket Deleted (Soft Delete)"),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          String errorMsg = e.toString();
          if (errorMsg.contains("permission-denied")) {
            errorMsg = "Permission Denied: Only System Admins can hard delete.";
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $errorMsg"), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _showExtensionConfirmDialog(
    Map<String, dynamic> data,
    int days,
    String label,
    ProfileProvider profile,
  ) {
    final TextEditingController amountController = TextEditingController();
    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: "EXTEND LICENSE: $label",
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Confirm extending '${data['restaurantName']}' for $days days.",
            style: TextStyle(color: profile.secondaryTextColor, fontSize: 13),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: amountController,
            keyboardType: TextInputType.number,
            style: TextStyle(color: profile.textColor),
            decoration: InputDecoration(
              labelText: "Amount Collected (₹)",
              hintText: "Enter 0 if free",
              fillColor: profile.scaffoldColor,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                int newAmount = int.tryParse(amountController.text) ?? 0;
                DateTime currentExpiry = data['validTill'] != null
                    ? DateTime.parse(data['validTill'])
                    : DateTime.now();
                if (currentExpiry.isBefore(DateTime.now()))
                  currentExpiry = DateTime.now();
                final newExpiry = currentExpiry.add(Duration(days: days));
                final prefs = await SharedPreferences.getInstance();
                final adminId = prefs.getString('admin_id') ?? "Admin";

                await LicenseService.firestore
                    .collection('licenses')
                    .doc(data['licenseKey'])
                    .update({
                      'validTill': newExpiry.toIso8601String(),
                      'validTillFormatted': DateFormat(
                        'dd/MM/yyyy',
                      ).format(newExpiry),
                      'price': (data['price'] ?? 0) + newAmount,
                      'isLifetime': false,
                    });
                await LicenseService.logAdminAction(
                  adminId,
                  "QUICK_EXTEND",
                  "Extended ${data['licenseKey']} by $days days",
                );
                if (mounted) {
                  Navigator.pop(context);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Extended Successful!"),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: profile.themeColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "CONFIRM EXTENSION",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _editExpiryDate(
    Map<String, dynamic> data,
    ProfileProvider profile,
  ) async {
    DateTime initial = data['validTill'] != null
        ? DateTime.parse(data['validTill'])
        : DateTime.now();
    final DateTime? picked = await ReportHelper.showAppDatePicker(
      context,
      initial,
      profile.themeColor,
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      await LicenseService.firestore
          .collection('licenses')
          .doc(data['licenseKey'])
          .update({
            'validTill': picked.toIso8601String(),
            'validTillFormatted': DateFormat('dd/MM/yyyy').format(picked),
            'isLifetime': false,
          });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Expiry Updated!")));
      }
    }
  }

  Widget _buildTopIcon(
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Icon(icon, color: color ?? Colors.white, size: 18),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final appBarColor =
        ThemeData.estimateBrightnessForColor(profile.themeColor) ==
            Brightness.dark
        ? Colors.white
        : Colors.black;

    return GestureDetector(
      onTap: () => setState(() => _isAnnouncementExpanded = false),
      child: Scaffold(
        backgroundColor: profile.scaffoldColor,
        appBar: AppBar(
          title: GestureDetector(
            onTap: () {
              _secretTapCount++;
              if (_secretTapCount >= 7) {
                setState(() => _adminRole = 'super_admin');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Super Admin Mode Activated (Temporary)"),
                    backgroundColor: Colors.purple,
                  ),
                );
              }
            },
            child: const Text(
              "Admin Console",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: -0.5,
              ),
            ),
          ),
          backgroundColor: profile.themeColor,
          foregroundColor: appBarColor,
          elevation: 0,
          actions: [
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('support_tickets')
                  .where('status', isEqualTo: 'open')
                  .snapshots(),
              builder: (context, snapshot) {
                int openTickets = snapshot.hasData
                    ? snapshot.data!.docs.length
                    : 0;
                return _buildTopIcon(
                  openTickets > 0
                      ? Icons.notification_important_rounded
                      : Icons.support_agent_rounded,
                  "Support Center",
                  () => _showSupportCenter(profile),
                  color: openTickets > 0 ? Colors.orangeAccent : null,
                );
              },
            ),
            _buildAnnouncementIcon(profile),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerTheme: const DividerThemeData(thickness: 0.5)),
              child: PopupMenuButton<String>(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.more_vert_rounded,
                    color: appBarColor,
                    size: 18,
                  ),
                ),
                position: PopupMenuPosition.under,
                offset: const Offset(0, 8),
                color: profile.cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (value) {
                  if (value == 'staff') _showStaffManagement(profile);
                  if (value == 'cleanup') _performDataCleanup(profile);
                  if (value == 'logs') _showLogsModal(profile);

                },
                itemBuilder: (context) => [
                  if (_adminRole == 'super_admin')
                    PopupMenuItem(
                      value: 'staff',
                      child: _buildPopupItem(
                        Icons.people_alt_rounded,
                        "Staff Control",
                        profile,
                      ),
                    ),
                  if (_adminRole == 'super_admin')
                    PopupMenuItem(
                      value: 'templates',
                      child: _buildPopupItem(
                        Icons.auto_awesome_motion_rounded,
                        "Starter Packs",
                        profile,
                        iconColor: Colors.teal,
                      ),
                    ),
                  if (_adminRole == 'super_admin')
                    PopupMenuItem(
                      value: 'cleanup',
                      child: _buildPopupItem(
                        Icons.auto_fix_high_rounded,
                        "System Cleanup",
                        profile,
                        iconColor: Colors.amber,
                      ),
                    ),
                  PopupMenuItem(
                    value: 'logs',
                    child: _buildPopupItem(
                      Icons.history_rounded,
                      "Activity Logs",
                      profile,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: _isInitializing
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: LicenseService.firestore
                        .collection('licenses')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: Colors.red,
                                  size: 48,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  "Permission Denied or Connection Error",
                                  style: TextStyle(
                                    color: profile.textColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  snapshot.error.toString(),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: profile.secondaryTextColor,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton(
                                  onPressed: () => setState(() {}),
                                  child: const Text("RETRY"),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final allDocs = snapshot.data?.docs ?? [];

                      final filteredDocs = allDocs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final search = _searchController.text.toLowerCase();
                        final phone = (data['phone'] ?? '')
                            .toString()
                            .toLowerCase();
                        final name = (data['restaurantName'] ?? '')
                            .toString()
                            .toLowerCase();
                        final status = data['status'] ?? 'active';

                        bool matchesSearch =
                            phone.contains(search) || name.contains(search);
                        bool matchesFilter = true;

                        if (_statusFilter == 'Active')
                          matchesFilter = status == 'active';
                        if (_statusFilter == 'Blocked')
                          matchesFilter = status == 'blocked';
                        if (_statusFilter == 'Expiring') {
                          if (data['validTill'] == null) return false;
                          final expiry = DateTime.tryParse(data['validTill']);
                          matchesFilter =
                              expiry != null &&
                              expiry.difference(DateTime.now()).inDays <= 7;
                        }

                        return matchesSearch && matchesFilter;
                      }).toList();

                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_adminRole == 'super_admin') ...[
                              _buildRevenueDashboard(allDocs, profile),
                              const SizedBox(height: 24),
                            ],
                            _buildExpiringSoonSection(allDocs, profile),
                            const SizedBox(height: 20),
                            _buildGeneratorCard(profile),
                            const SizedBox(height: 30),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "LICENSE HISTORY (${filteredDocs.length})",
                                  style: TextStyle(
                                    color: profile.secondaryTextColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                if (_isSelectionMode)
                                  TextButton(
                                    onPressed: () => setState(
                                      () => _isSelectionMode = false,
                                    ),
                                    child: const Text(
                                      "CANCEL",
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  )
                                else
                                  TextButton.icon(
                                    onPressed: () =>
                                        setState(() => _isSelectionMode = true),
                                    icon: const Icon(
                                      Icons.checklist_rtl_rounded,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      "SELECT USERS",
                                      style: TextStyle(fontSize: 10),
                                    ),
                                  ),
                              ],
                            ),
                            _buildSearchSection(profile),
                            const SizedBox(height: 12),
                            _buildFilterChips(profile),
                            const SizedBox(height: 12),
                            _buildHistoryList(filteredDocs, profile),
                            const SizedBox(height: 30),
                          ],
                        ),
                      );
                    },
                  ),
                  _buildAnnouncementOverlay(profile),
                ],
              ),
      ),
    );
  }

  Widget _buildAnnouncementIcon(ProfileProvider profile) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: "Announcements",
        child: InkWell(
          onTap: () => setState(
            () => _isAnnouncementExpanded = !_isAnnouncementExpanded,
          ),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _isAnnouncementExpanded
                  ? Colors.orange
                  : Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Icon(
              _isAnnouncementExpanded
                  ? Icons.close_rounded
                  : Icons.campaign_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnnouncementOverlay(ProfileProvider profile) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutBack,
      top: _isAnnouncementExpanded ? 10 : -450,
      right: 12,
      left: 12,
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: profile.cardColor.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.campaign_rounded,
                          color: Colors.orange,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Global Broadcast",
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            "Send alert to all users",
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (_selectedPhones.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: profile.themeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "${_selectedPhones.length} Targeted",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: profile.themeColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _announcementController,
                    maxLines: 3,
                    onChanged: _onAnnouncementChanged,
                    style: TextStyle(color: profile.textColor, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: "Type message for users...",
                      hintStyle: TextStyle(
                        color: profile.secondaryTextColor.withValues(
                          alpha: 0.5,
                        ),
                        fontSize: 13,
                      ),
                      fillColor: profile.scaffoldColor.withValues(alpha: 0.5),
                      filled: true,
                      contentPadding: const EdgeInsets.all(16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        "Push Notify",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Transform.scale(
                        scale: 0.7,
                        child: Switch(
                          value: _sendPushNotification,
                          activeColor: Colors.orange,
                          onChanged: (v) =>
                              setState(() => _sendPushNotification = v),
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: _isPostingAnnouncement
                            ? null
                            : _postAnnouncement,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isPostingAnnouncement
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                "PUBLISH",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
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

  Widget _buildRevenueDashboard(
    List<QueryDocumentSnapshot> docs,
    ProfileProvider profile,
  ) {
    double totalRevenue = 0;
    for (var doc in docs) {
      totalRevenue += (doc.data() as Map<String, dynamic>)['price'] ?? 0;
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            profile.themeColor,
            profile.themeColor.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "TOTAL REVENUE",
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            "₹${totalRevenue.toInt()}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _statMini(docs.length.toString(), "Total Users"),
              const SizedBox(width: 20),
              _statMini(
                docs
                    .where((e) => (e.data() as Map).containsKey('activatedAt'))
                    .length
                    .toString(),
                "Activated",
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statMini(String val, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          val,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildGeneratorCard(ProfileProvider profile) {
    return Card(
      elevation: 0,
      color: profile.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildField(
              _restaurantController,
              "Restaurant Name",
              Icons.store,
              profile,
            ),
            _buildField(_ownerController, "Owner Name", Icons.person, profile),
            _buildField(
              _phoneController,
              "Phone",
              Icons.phone_android,
              profile,
              isNumber: true,
              maxLength: 10,
            ),
            _buildField(
              _priceController,
              "Price (₹)",
              Icons.currency_rupee,
              profile,
              isNumber: true,
            ),
            DropdownButtonFormField<String>(
              value: _selectedPlan,
              dropdownColor: profile.cardColor,
              style: TextStyle(color: profile.textColor),
              decoration: InputDecoration(
                labelText: "Select Plan",
                labelStyle: TextStyle(color: profile.secondaryTextColor),
                fillColor: profile.scaffoldColor,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              items: _validityOptions
                  .map(
                    (e) => DropdownMenuItem(
                      value: e['label'] as String,
                      child: Text(e['label']),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _selectedPlan = v!),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isGenerating ? null : _handleGenerate,
              style: ElevatedButton.styleFrom(
                backgroundColor: profile.themeColor,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isGenerating
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      "GENERATE LICENSE",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            if (_generatedKey != null) ...[
              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        _generatedKey!,
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.green),
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: _generatedKey!),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryList(
    List<QueryDocumentSnapshot> filtered,
    ProfileProvider profile,
  ) {
    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 48,
                color: profile.secondaryTextColor.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                "No licenses found",
                style: TextStyle(color: profile.secondaryTextColor),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final data = filtered[i].data() as Map<String, dynamic>;
        final phone = data['phone'] ?? "";
        final isSelected = _selectedPhones.contains(phone);

        return Card(
          color: profile.cardColor,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isSelected ? Colors.orange : Colors.transparent,
            ),
          ),
          child: ListTile(
            onTap: _isSelectionMode
                ? () => setState(
                    () => isSelected
                        ? _selectedPhones.remove(phone)
                        : _selectedPhones.add(phone),
                  )
                : () => _showLicenseDetails(data, profile),
            leading: _isSelectionMode
                ? Checkbox(
                    value: isSelected,
                    onChanged: (v) => setState(
                      () => v!
                          ? _selectedPhones.add(phone)
                          : _selectedPhones.remove(phone),
                    ),
                  )
                : CircleAvatar(
                    backgroundColor: data['status'] == 'active'
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    child: Icon(
                      data['status'] == 'active' ? Icons.check : Icons.block,
                      color: data['status'] == 'active'
                          ? Colors.green
                          : Colors.red,
                      size: 16,
                    ),
                  ),
            title: Text(
              data['restaurantName'] ?? "N/A",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              "${data['phone']} • ${data['validTillFormatted']}",
              style: const TextStyle(fontSize: 11),
            ),
            trailing: _adminRole == 'super_admin' && !_isSelectionMode
                ? IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                    onPressed: () => _deleteLicense(
                      data['licenseKey'],
                      data['restaurantName'],
                      profile,
                      isFromList: true,
                    ),
                  )
                : const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }

  Widget _buildField(
    TextEditingController c,
    String l,
    IconData i,
    ProfileProvider p, {
    bool isNumber = false,
    int? maxLength,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        inputFormatters: isNumber
            ? [FilteringTextInputFormatter.digitsOnly]
            : [],
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: l,
          prefixIcon: Icon(i, color: p.themeColor),
          filled: true,
          fillColor: p.scaffoldColor,
          counterText: "",
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchSection(ProfileProvider profile) {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() {}),
      decoration: InputDecoration(
        hintText: "Search Phone or Name...",
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: profile.cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildFilterChips(ProfileProvider profile) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ['All', 'Active', 'Blocked', 'Expiring']
            .map(
              (f) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f, style: const TextStyle(fontSize: 10)),
                  selected: _statusFilter == f,
                  onSelected: (v) => setState(() => _statusFilter = f),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildExpiringSoonSection(
    List<QueryDocumentSnapshot> docs,
    ProfileProvider profile,
  ) {
    final expiring = docs.where((doc) {
      if (doc['isLifetime'] == true || doc['validTill'] == null) return false;
      final expiry = DateTime.parse(doc['validTill']);
      return expiry.isAfter(DateTime.now()) &&
          expiry.isBefore(DateTime.now().add(const Duration(days: 7)));
    }).toList();
    if (expiring.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "EXPIRING SOON",
          style: TextStyle(
            color: Colors.orange,
            fontWeight: FontWeight.bold,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: expiring.length,
            itemBuilder: (context, i) => Container(
              width: 150,
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expiring[i]['restaurantName'],
                    maxLines: 1,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    "In ${DateTime.parse(expiring[i]['validTill']).difference(DateTime.now()).inDays} days",
                    style: const TextStyle(color: Colors.orange, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showLogsModal(ProfileProvider profile) {
    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: "ADMIN",
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: StreamBuilder<QuerySnapshot>(
          stream: LicenseService.firestore
              .collection('admin_logs')
              .orderBy('timestamp', descending: true)
              .limit(30)
              .snapshots(),
          builder: (context, snapshot) {
            final logs = snapshot.data?.docs ?? [];
            return ListView.builder(
              itemCount: logs.length,
              itemBuilder: (context, i) => ListTile(
                title: Text(
                  logs[i]['details'],
                  style: const TextStyle(fontSize: 12),
                ),
                subtitle: Text(
                  DateFormat(
                    'dd MMM, hh:mm a',
                  ).format((logs[i]['timestamp'] as Timestamp).toDate()),
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            );
          },
        ),
      ),
    );
  }



  void _showSupportCenter(ProfileProvider profile) {
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
        height: MediaQuery.of(context).size.height * 0.9,
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
                children: [
                  Icon(
                    Icons.support_agent_rounded,
                    color: profile.themeColor,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "Support Center",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: profile.textColor,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('support_tickets')
                    .where('status', isNotEqualTo: 'deleted') // Filter at source
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    // Log to console instead of showing annoying snackbar for stream sync errors
                    debugPrint("Admin Support Stream Error: ${snapshot.error}");
                    return Center(child: Text("Unable to load some tickets. Check permissions."));
                  }
                  if (snapshot.connectionState == ConnectionState.waiting)
                    return const Center(child: CircularProgressIndicator());

                  final docs = (snapshot.data?.docs ?? []).toList();

                  // Sort in memory because Firestore requires index for multiple field filters/orders
                  docs.sort((a, b) {
                    final aData = a.data() as Map<String, dynamic>;
                    final bData = b.data() as Map<String, dynamic>;
                    final aTime = aData['createdAt'] as Timestamp? ?? Timestamp.now();
                    final bTime = bData['createdAt'] as Timestamp? ?? Timestamp.now();
                    return bTime.compareTo(aTime);
                  });

                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        "No support tickets found",
                        style: TextStyle(color: profile.secondaryTextColor),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    padding: const EdgeInsets.all(16),
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final status = data['status'] ?? 'open';
                      final lastUpdate =
                          data['lastUpdate'] as Timestamp? ??
                          data['createdAt'] as Timestamp?;

                      Color statusColor;
                      if (status == 'open') {
                        statusColor = Colors.red;
                      } else if (status == 'answered') {
                        statusColor = Colors.orange;
                      } else {
                        statusColor = Colors.green;
                      }

                      final licenseKey = data['licenseKey'] ?? '';

                      return FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('licenses')
                            .doc(licenseKey)
                            .get(),
                        builder: (context, licSnapshot) {
                          // If still loading from licenses, show ticket data as fallback immediately
                          final licData =
                              licSnapshot.data?.data()
                                  as Map<String, dynamic>? ??
                              {};

                          final businessName =
                              licData['restaurantName'] ??
                              data['restaurantName'] ??
                              data['businessName'] ??
                              'Loading...';
                          final ownerName =
                              licData['ownerName'] ??
                              data['ownerName'] ??
                              'User';
                          final subject = data['subject'] ?? 'No Subject';
                          final message = data['message'] ?? 'No Message';

                          return Card(
                            elevation: 0,
                            color: profile.scaffoldColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: statusColor.withValues(alpha: 0.3),
                              ),
                            ),
                            child: ListTile(
                              onTap: () =>
                                  _showAdminChat(docs[index].id, profile),
                              leading: CircleAvatar(
                                backgroundColor: statusColor.withValues(
                                  alpha: 0.1,
                                ),
                                child: Icon(
                                  Icons.help_center_outlined,
                                  color: statusColor,
                                ),
                              ),
                              title: Text(
                                businessName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: profile.textColor,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "By: $ownerName",
                                    style: TextStyle(
                                      color: profile.secondaryTextColor,
                                      fontSize: 10,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    subject,
                                    style: TextStyle(
                                      color: profile.themeColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    message,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: profile.secondaryTextColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    "Updated: ${lastUpdate != null ? DateFormat('dd-MMM HH:mm').format(lastUpdate.toDate()) : 'N/A'}",
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
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
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Colors.red,
                                      size: 20,
                                    ),
                                    onPressed: () => _deleteTicket(
                                      docs[index].id,
                                      businessName,
                                      profile,
                                    ),
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(4),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
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

  void _performDataCleanup(ProfileProvider profile) async {
    final confirm = await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: "Permanent Data Cleanup?",
      message:
          "This will permanently purge all tickets marked as 'deleted' more than 30 days ago. This action cannot be undone.",
      confirmLabel: "CLEANUP NOW",
    );

    if (confirm == true) {
      try {
        final cutoff = DateTime.now().subtract(const Duration(days: 30));
        final snapshot = await FirebaseFirestore.instance
            .collection('support_tickets')
            .where('status', isEqualTo: 'deleted')
            .get();

        int deletedCount = 0;
        final batch = FirebaseFirestore.instance.batch();

        for (var doc in snapshot.docs) {
          final lastUpdate = (doc.data()['lastUpdate'] as Timestamp?)?.toDate();
          if (lastUpdate != null && lastUpdate.isBefore(cutoff)) {
            batch.delete(doc.reference);
            deletedCount++;
          }
        }

        if (deletedCount > 0) {
          await batch.commit();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Successfully purged $deletedCount old tickets."),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No old data found to cleanup.")),
          );
        }
      } catch (e) {
        String errorMsg = e.toString();
        if (errorMsg.contains("permission-denied")) {
          errorMsg = "Permission Denied: Server rules prevent permanent deletion.";
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Cleanup Error: $errorMsg"), backgroundColor: Colors.red));
      }
    }
  }

  void _showAdminChat(String ticketId, ProfileProvider profile) {
    final TextEditingController replyController = TextEditingController();
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
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: Scaffold(
            backgroundColor: profile.cardColor,
            resizeToAvoidBottomInset: true,
            appBar: AppBar(
              backgroundColor: profile.cardColor,
              elevation: 0,
              automaticallyImplyLeading: false,
              title: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('support_tickets')
                    .doc(ticketId)
                    .snapshots(),
                builder: (context, snapshot) {
                  final data =
                      snapshot.data?.data() as Map<String, dynamic>? ?? {};
                  final licenseKey = data['licenseKey'] ?? '';

                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('licenses')
                        .doc(licenseKey)
                        .get(),
                    builder: (context, licSnapshot) {
                      final licData =
                          licSnapshot.data?.data() as Map<String, dynamic>? ??
                          {};
                      final bName =
                          licData['restaurantName'] ??
                          data['restaurantName'] ??
                          data['businessName'] ??
                          'Support Chat';
                      final oName =
                          licData['ownerName'] ?? data['ownerName'] ?? 'User';
                      final phone =
                          (licData['phone'] ??
                                  licData['mobile'] ??
                                  data['phone'] ??
                                  '')
                              .toString();

                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  bName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  "$oName ${phone.isNotEmpty ? '• $phone' : ''}",
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (phone.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.call, color: Colors.green),
                              onPressed: () =>
                                  launchUrl(Uri.parse('tel:$phone')),
                              tooltip: 'Call $oName',
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            body: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('support_tickets')
                  .doc(ticketId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                final data = snapshot.data!.data() as Map<String, dynamic>;
                final List replies = data['replies'] ?? [];

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  reverse: true,
                  children: [
                    ...replies.reversed.map((reply) {
                      return _buildChatBubble(
                        message: reply['message'] ?? '',
                        sender: reply['senderName'] ?? '',
                        time: reply['timestamp'],
                        isMe: reply['senderRole'] == 'admin',
                        profile: profile,
                      );
                    }),
                    _buildChatBubble(
                      message: data['message'] ?? '',
                      sender: data['restaurantName'] ?? "User",
                      time: data['createdAt'],
                      isMe: false,
                      profile: profile,
                    ),
                  ],
                );
              },
            ),
            bottomNavigationBar: Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                left: 16,
                right: 16,
                top: 8,
              ),
              decoration: BoxDecoration(
                color: profile.cardColor,
                border: Border(
                  top: BorderSide(
                    color: profile.secondaryTextColor.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: replyController,
                      style: TextStyle(color: profile.textColor),
                      decoration: InputDecoration(
                        hintText: "Type reply...",
                        filled: true,
                        fillColor: profile.scaffoldColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () async {
                      if (replyController.text.trim().isNotEmpty) {
                        await LicenseService.addTicketReply(
                          ticketId: ticketId,
                          message: replyController.text.trim(),
                          senderRole: 'admin',
                          senderName: 'Support Team',
                        );
                        replyController.clear();
                      }
                    },
                    icon: const Icon(Icons.send),
                    style: IconButton.styleFrom(
                      backgroundColor: profile.themeColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatBubble({
    required String message,
    required String sender,
    required dynamic time,
    required bool isMe,
    required ProfileProvider profile,
  }) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            margin: const EdgeInsets.only(bottom: 2),
            constraints: const BoxConstraints(maxWidth: 280),
            decoration: BoxDecoration(
              color: isMe
                  ? profile.themeColor
                  : (profile.isDarkMode
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.grey.shade200),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isMe ? 12 : 0),
                bottomRight: Radius.circular(isMe ? 0 : 12),
              ),
            ),
            child: Text(
              message,
              style: TextStyle(
                color: isMe ? Colors.white : profile.textColor,
                fontSize: 14,
              ),
            ),
          ),
          if (time != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
              child: Text(
                _formatTime(time),
                style: TextStyle(
                  fontSize: 9,
                  color: profile.secondaryTextColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(dynamic timeData) {
    if (timeData == null) return "";
    try {
      DateTime dt;
      if (timeData is Timestamp) {
        dt = timeData.toDate();
      } else if (timeData is String) {
        if (timeData.isEmpty) return "";
        dt = DateTime.tryParse(timeData) ?? DateTime.now();
      } else {
        return "";
      }
      return DateFormat('hh:mm a').format(dt);
    } catch (e) {
      return "";
    }
  }

  Widget _buildPopupItem(
    IconData icon,
    String title,
    ProfileProvider profile, {
    Color? iconColor,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: iconColor ?? profile.textColor.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            color: profile.textColor,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _detailRow(
    String l,
    String v,
    IconData i,
    ProfileProvider p, {
    bool isSelectable = false,
    Color? valueColor,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(i, size: 20, color: p.themeColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l,
                  style: TextStyle(color: p.secondaryTextColor, fontSize: 10),
                ),
                if (isSelectable)
                  SelectableText(
                    v,
                    style: TextStyle(
                      color: valueColor ?? p.textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  )
                else
                  Text(
                    v,
                    style: TextStyle(
                      color: valueColor ?? p.textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Future<void> _resetDevice(
    String key,
    String restaurant,
    ProfileProvider profile,
  ) async {
    final confirm = await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: "Reset Device Binding?",
      message:
          "This will allow the license to be activated on a new phone. Current device link for '$restaurant' will be removed.",
      confirmLabel: "RESET NOW",
    );

    if (confirm == true) {
      try {
        await LicenseService.firestore.collection('licenses').doc(key).update({
          'activated': false,
          'activeDeviceId': null,
          'lastActivatedAt': null,
        });
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Device Reset Successful! User can now login on any phone.",
              ),
              backgroundColor: Colors.blue,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Widget _buildUsageBox(
    String label,
    int count,
    Color color,
    bool isLoading,
    ProfileProvider p, {
    bool isFullWidth = false,
  }) {
    final content = Column(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: p.secondaryTextColor,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        isLoading
            ? SizedBox(
                height: 14,
                width: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color,
                ),
              )
            : Text(
                count.toString(),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: isFullWidth ? 22 : 18,
                ),
              ),
      ],
    );

    return isFullWidth
        ? Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: content,
          )
        : Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: content,
            ),
          );
  }

  Widget _toggleTile(
    String t,
    String s,
    bool v,
    IconData i,
    ProfileProvider p,
    Function(bool) c,
  ) {
    return SwitchListTile(
      value: v,
      onChanged: c,
      secondary: Icon(i, color: p.themeColor),
      title: Text(
        t,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      subtitle: Text(s, style: const TextStyle(fontSize: 10)),
    );
  }

  Widget _quickExtendBtn(
    Map<String, dynamic> data,
    int d,
    String l,
    ProfileProvider p,
  ) {
    return Expanded(
      child: OutlinedButton(
        onPressed: () => _showExtensionConfirmDialog(data, d, l, p),
        child: Text("+ $l", style: const TextStyle(fontSize: 10)),
      ),
    );
  }


}
