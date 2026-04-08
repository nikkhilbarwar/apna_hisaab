import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import '../../services/license_service.dart';
import '../../providers/profile_provider.dart';
import '../../utils/report_helper.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final TextEditingController _restaurantController = TextEditingController();
  final TextEditingController _ownerController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _announcementController = TextEditingController();

  bool _isGenerating = false;
  bool _isInitializing = true;
  bool _isPostingAnnouncement = false;
  String _selectedPlan = '1 Year';
  String? _generatedKey;
  
  final String _driveLink = "https://drive.google.com/drive/folders/1560Q2Lju7iBDBwKAYC0UOwkSV7NAvMM6?usp=sharing";

  final List<Map<String, dynamic>> _validityOptions = [
    {'label': '7 Days Trial', 'days': 7, 'planType': 'trial'},
    {'label': '30 Days', 'days': 30, 'planType': 'monthly'},
    {'label': '3 Months', 'days': 90, 'planType': 'quarterly'},
    {'label': '6 Months', 'days': 180, 'planType': 'half_yearly'},
    {'label': '1 Year', 'days': 365, 'planType': 'yearly'},
    {'label': 'Lifetime', 'days': null, 'planType': 'lifetime'},
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
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Init Error: $e")));
        setState(() => _isInitializing = false);
      }
    }
  }

  Future<void> _loadCurrentAnnouncement() async {
    try {
      final doc = await LicenseService.firestore.collection('admin_settings').doc('announcement').get();
      if (doc.exists) {
        _announcementController.text = doc.data()?['message'] ?? "";
      }
    } catch (_) {}
  }

  String _generateLicenseKey(String restaurant, String owner, String phone) {
    final year = DateTime.now().year.toString();
    final restCode = restaurant.replaceAll(RegExp(r'[^A-Za-z]'), '').toUpperCase().padRight(3, 'X').substring(0, 3);
    final ownerCode = owner.replaceAll(RegExp(r'[^A-Za-z]'), '').toUpperCase().padRight(2, 'X').substring(0, 2);
    final phoneCode = phone.length >= 4 ? phone.substring(phone.length - 4) : phone.padLeft(4, '0');
    
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final randomCode = List.generate(6, (_) => chars[Random().nextInt(chars.length)]).join();

    return 'RESTO-$year-$restCode$ownerCode-$randomCode-$phoneCode';
  }

  Future<void> _handleGenerate() async {
    if (_restaurantController.text.isEmpty || _ownerController.text.isEmpty || _phoneController.text.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all details correctly")));
      return;
    }

    setState(() => _isGenerating = true);
    try {
      final key = _generateLicenseKey(_restaurantController.text, _ownerController.text, _phoneController.text);
      final plan = _validityOptions.firstWhere((e) => e['label'] == _selectedPlan);
      final now = DateTime.now();
      final expiry = plan['days'] == null ? null : now.add(Duration(days: plan['days']));

      await LicenseService.firestore.collection('licenses').doc(key).set({
        'licenseKey': key,
        'restaurantName': _restaurantController.text.trim(),
        'ownerName': _ownerController.text.trim(),
        'phone': _phoneController.text.trim(),
        'status': 'active',
        'planType': plan['planType'],
        'isLifetime': plan['days'] == null,
        'createdAt': FieldValue.serverTimestamp(),
        'validTill': expiry?.toIso8601String(),
        'validTillFormatted': expiry == null ? 'Lifetime' : DateFormat('dd/MM/yyyy').format(expiry),
        'activated': false,
        'activeDeviceId': null,
        'isReminderEnabled': true,
        'saleBlocked': false,
        'expenseBlocked': false,
        'bypassCheck': false, // New Field for Bypass
      });

      setState(() {
        _generatedKey = key;
        _isGenerating = false;
      });
      _restaurantController.clear(); _ownerController.clear(); _phoneController.clear();
    } catch (e) {
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _postAnnouncement() async {
    setState(() => _isPostingAnnouncement = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final adminId = prefs.getString('admin_id') ?? FirebaseAuth.instance.currentUser?.email ?? "Unknown Admin";

      await LicenseService.firestore.collection('admin_settings').doc('announcement').set({
        'message': _announcementController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      await LicenseService.logAdminAction(adminId, "POST_ANNOUNCEMENT", "Published: ${_announcementController.text.trim()}");

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Announcement Published!"), backgroundColor: Colors.green));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _isPostingAnnouncement = false);
    }
  }

  void _showLicenseDetails(Map<String, dynamic> data, ProfileProvider profile) {
    bool isActive = data['status'] == 'active';
    bool isReminderEnabled = data['isReminderEnabled'] ?? true;
    bool saleBlocked = data['saleBlocked'] ?? false;
    bool expenseBlocked = data['expenseBlocked'] ?? false;
    bool bypassCheck = data['bypassCheck'] ?? false;
    String appVersion = data['appVersion'] ?? "Unknown";
    String lastUsed = data['lastUsedAt'] != null 
        ? DateFormat('dd MMM, hh:mm a').format((data['lastUsedAt'] as Timestamp).toDate()) 
        : "Never";

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
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(color: profile.secondaryTextColor.withOpacity(0.2), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(data['restaurantName'] ?? "License Info", 
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: profile.textColor)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isActive ? "ACTIVE" : "BLOCKED",
                        style: TextStyle(color: isActive ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _detailRow("License Key", data['licenseKey'] ?? "N/A", Icons.vpn_key, profile, isSelectable: true),
                Row(
                  children: [
                    Expanded(child: _detailRow("Validity", data['validTillFormatted'] ?? "N/A", Icons.calendar_today, profile)),
                    Expanded(child: _detailRow("App Version", appVersion, Icons.phonelink_setup_rounded, profile)),
                  ],
                ),
                _detailRow("Last Active", lastUsed, Icons.access_time_rounded, profile),
                
                const Divider(height: 32),
                Text("USER PERMISSIONS & CONTROLS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: profile.secondaryTextColor, letterSpacing: 1)),
                const SizedBox(height: 16),
                
                _toggleTile("Bypass License Check", "Allow app access even if license is invalid", bypassCheck, Icons.verified_user_outlined, profile, (val) async {
                  final prefs = await SharedPreferences.getInstance();
                  final adminId = prefs.getString('admin_id') ?? FirebaseAuth.instance.currentUser?.email ?? "Unknown Admin";
                  await LicenseService.firestore.collection('licenses').doc(data['licenseKey']).update({'bypassCheck': val});
                  await LicenseService.logAdminAction(adminId, "TOGGLE_BYPASS", "Set bypass to $val for ${data['licenseKey']}");
                  setModalState(() => bypassCheck = val);
                }),
                _toggleTile("Payment Reminder", "Show daily payment alerts to user", isReminderEnabled, Icons.notifications_active_rounded, profile, (val) async {
                  final prefs = await SharedPreferences.getInstance();
                  final adminId = prefs.getString('admin_id') ?? FirebaseAuth.instance.currentUser?.email ?? "Unknown Admin";
                  await LicenseService.firestore.collection('licenses').doc(data['licenseKey']).update({'isReminderEnabled': val});
                  await LicenseService.logAdminAction(adminId, "TOGGLE_REMINDER", "Set reminder to $val for ${data['licenseKey']}");
                  setModalState(() => isReminderEnabled = val);
                }),
                _toggleTile("Block Sales", "Prevent user from creating new sales", saleBlocked, Icons.block_flipped, profile, (val) async {
                  final prefs = await SharedPreferences.getInstance();
                  final adminId = prefs.getString('admin_id') ?? FirebaseAuth.instance.currentUser?.email ?? "Unknown Admin";
                  await LicenseService.firestore.collection('licenses').doc(data['licenseKey']).update({'saleBlocked': val});
                  await LicenseService.logAdminAction(adminId, "BLOCK_SALES", "Set block_sales to $val for ${data['licenseKey']}");
                  setModalState(() => saleBlocked = val);
                }),
                
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          final adminId = prefs.getString('admin_id') ?? FirebaseAuth.instance.currentUser?.email ?? "Unknown Admin";
                          await LicenseService.resetDevice(data['licenseKey'], adminId);
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Device Reset Successful!")));
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text("RESET DEVICE"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade800,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      final adminId = prefs.getString('admin_id') ?? FirebaseAuth.instance.currentUser?.email ?? "Unknown Admin";
                      await LicenseService.firestore.collection('licenses').doc(data['licenseKey']).update({
                        'status': isActive ? 'blocked' : 'active'
                      });
                      await LicenseService.logAdminAction(adminId, isActive ? "BLOCK_APP" : "ACTIVATE_APP", "License ${data['licenseKey']} status set to ${isActive ? 'blocked' : 'active'}");
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(isActive ? "License Blocked!" : "License Unblocked!"),
                        backgroundColor: isActive ? Colors.red : Colors.green,
                      ));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isActive ? Colors.red : Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(isActive ? "BLOCK APP" : "ACTIVATE APP", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    onPressed: () => _deleteLicense(data['licenseKey'], data['restaurantName'] ?? "N/A", profile),
                    icon: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                    label: const Text("DELETE LICENSE PERMANENTLY", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: () => Share.share("Restaurant: ${data['restaurantName']}\nLicense: ${data['licenseKey']}\nDownload App: $_driveLink"),
                    icon: const Icon(Icons.share),
                    label: const Text("SHARE LICENSE KEY"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteLicense(String key, String restaurant, ProfileProvider profile) async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Delete License?", style: TextStyle(color: profile.textColor)),
        content: Text("Are you sure you want to permanently delete the license for '$restaurant'? This cannot be undone.", 
          style: TextStyle(color: profile.secondaryTextColor)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("DELETE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;

    if (confirm) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final adminId = prefs.getString('admin_id') ?? FirebaseAuth.instance.currentUser?.email ?? "Unknown Admin";

        await LicenseService.firestore.collection('licenses').doc(key).delete();
        await LicenseService.logAdminAction(adminId, "DELETE_LICENSE", "Permanently deleted license for $restaurant ($key)");

        if (mounted) {
          Navigator.pop(context); // Close details modal
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("License Deleted Successfully"),
            backgroundColor: Colors.red,
          ));
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Widget _toggleTile(String title, String sub, bool value, IconData icon, ProfileProvider profile, Function(bool) onChanged) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      secondary: Icon(icon, color: value ? profile.themeColor : profile.secondaryTextColor),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 14)),
      subtitle: Text(sub, style: TextStyle(fontSize: 11, color: profile.secondaryTextColor)),
      activeColor: profile.themeColor,
      contentPadding: EdgeInsets.zero,
    );
  }

  void _editExpiryDate(Map<String, dynamic> data, ProfileProvider profile) async {
    DateTime initial = data['validTill'] != null ? DateTime.parse(data['validTill']) : DateTime.now();
    final DateTime? picked = await ReportHelper.showAppDatePicker(
      context, 
      initial, 
      profile.themeColor,
      lastDate: DateTime(2030),
    );

    if (picked != null) {
      final prefs = await SharedPreferences.getInstance();
      final adminId = prefs.getString('admin_id') ?? FirebaseAuth.instance.currentUser?.email ?? "Unknown Admin";
      
      await LicenseService.firestore.collection('licenses').doc(data['licenseKey']).update({
        'validTill': picked.toIso8601String(),
        'validTillFormatted': DateFormat('dd/MM/yyyy').format(picked),
        'isLifetime': false,
      });
      await LicenseService.logAdminAction(adminId, "EDIT_EXPIRY", "Changed expiry to ${DateFormat('dd/MM/yyyy').format(picked)} for ${data['licenseKey']}");
      
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Expiry Date Updated!")));
    }
  }

  Widget _detailRow(String label, String value, IconData icon, ProfileProvider profile, {bool isSelectable = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: profile.themeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 20, color: profile.themeColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: profile.secondaryTextColor, fontSize: 12)),
                if (isSelectable)
                  SelectableText(value, style: TextStyle(color: valueColor ?? profile.textColor, fontWeight: FontWeight.bold, fontSize: 14))
                else
                  Text(value, style: TextStyle(color: valueColor ?? profile.textColor, fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final Color appBarContentColor = ThemeData.estimateBrightnessForColor(profile.themeColor) == Brightness.dark 
        ? Colors.white 
        : Colors.black;

    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      appBar: AppBar(
        title: const Text("ADMIN PANEL", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)), 
        backgroundColor: profile.themeColor, 
        foregroundColor: appBarContentColor,
        elevation: 0,
        iconTheme: IconThemeData(color: appBarContentColor),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            onPressed: () => _showLogsModal(profile),
            tooltip: "Admin Logs",
          ),
        ],
      ),
      body: _isInitializing 
        ? const Center(child: CircularProgressIndicator()) 
        : StreamBuilder<QuerySnapshot>(
            stream: LicenseService.firestore.collection('licenses').snapshots(),
            builder: (context, snapshot) {
              final allDocs = snapshot.data?.docs ?? [];
              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatsOverview(allDocs, profile),
                    const SizedBox(height: 24),
                    _buildAnnouncementSection(profile),
                    const SizedBox(height: 24),
                    _buildGeneratorCard(profile),
                    const SizedBox(height: 30),
                    Text("LICENSE HISTORY", style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 12)),
                    const SizedBox(height: 12),
                    _buildSearchSection(profile),
                    const SizedBox(height: 12),
                    _buildHistoryList(allDocs, profile),
                  ],
                ),
              );
            }
          ),
    );
  }

  Widget _buildStatsOverview(List<QueryDocumentSnapshot> docs, ProfileProvider profile) {
    int total = docs.length;
    int active = docs.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'active').length;
    int blocked = total - active;

    return Row(
      children: [
        _statItem("Total", total.toString(), Colors.blue, profile),
        const SizedBox(width: 12),
        _statItem("Active", active.toString(), Colors.green, profile),
        const SizedBox(width: 12),
        _statItem("Blocked", blocked.toString(), Colors.red, profile),
      ],
    );
  }

  Widget _statItem(String label, String value, Color color, ProfileProvider profile) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: profile.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: profile.secondaryTextColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildAnnouncementSection(ProfileProvider profile) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: profile.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.orange.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.campaign_outlined, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Text("Global Announcement", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: profile.textColor)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _announcementController,
            maxLines: 2,
            style: TextStyle(color: profile.textColor, fontSize: 13),
            decoration: InputDecoration(
              hintText: "Enter message for all users...",
              fillColor: profile.scaffoldColor,
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _isPostingAnnouncement ? null : _postAnnouncement,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _isPostingAnnouncement 
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text("PUBLISH ANNOUNCEMENT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratorCard(ProfileProvider profile) {
    return Card(
      elevation: 0,
      color: profile.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Create New License", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: profile.textColor)),
            const SizedBox(height: 20),
            _buildField(_restaurantController, "Restaurant Name", Icons.store, profile),
            _buildField(_ownerController, "Owner Name", Icons.person, profile),
            _buildField(_phoneController, "Phone or Email", Icons.contact_mail, profile),
            const SizedBox(height: 15),
            DropdownButtonFormField<String>(
              value: _selectedPlan,
              dropdownColor: profile.cardColor,
              style: TextStyle(color: profile.textColor),
              decoration: InputDecoration(
                labelText: "Validity Plan", 
                labelStyle: TextStyle(color: profile.secondaryTextColor),
                filled: true,
                fillColor: profile.scaffoldColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
              items: _validityOptions.map((e) => DropdownMenuItem(value: e['label'] as String, child: Text(e['label']))).toList(),
              onChanged: (v) => setState(() => _selectedPlan = v!),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isGenerating ? null : _handleGenerate,
              style: ElevatedButton.styleFrom(
                backgroundColor: profile.themeColor, 
                minimumSize: const Size(double.infinity, 56), 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _isGenerating 
                ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                : const Text("GENERATE LICENSE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            if (_generatedKey != null) _buildResultCard(profile),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(ProfileProvider profile) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.green.withOpacity(0.3))),
      child: Column(
        children: [
          SelectableText(_generatedKey!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.green), 
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _generatedKey!));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Key Copied!")));
                }
              ),
              IconButton(
                icon: const Icon(Icons.share, color: Colors.green), 
                onPressed: () => Share.share("Restaurant: ${_restaurantController.text}\nLicense: $_generatedKey\nDownload App: $_driveLink")
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildSearchSection(ProfileProvider profile) {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() {}),
      style: TextStyle(color: profile.textColor),
      decoration: InputDecoration(
        hintText: "Search Phone/Email...",
        hintStyle: TextStyle(color: profile.secondaryTextColor),
        prefixIcon: Icon(Icons.search, color: profile.themeColor),
        filled: true,
        fillColor: profile.cardColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildHistoryList(List<QueryDocumentSnapshot> docs, ProfileProvider profile) {
    var filteredDocs = docs;
    if (_searchController.text.isNotEmpty) {
      filteredDocs = docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final phone = (data['phone'] ?? "").toString().toLowerCase();
        final name = (data['restaurantName'] ?? "").toString().toLowerCase();
        return phone.contains(_searchController.text.toLowerCase()) || name.contains(_searchController.text.toLowerCase());
      }).toList();
    }

    if (filteredDocs.isEmpty) return Center(child: Text("No licenses found", style: TextStyle(color: profile.secondaryTextColor)));

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filteredDocs.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final data = filteredDocs[index].data() as Map<String, dynamic>;
        final bool isActive = data['status'] == 'active';
        final bool isRegistered = data['activated'] == true;

        return Card(
          elevation: 0,
          color: profile.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100)),
          child: ListTile(
            onTap: () => _showLicenseDetails(data, profile),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: CircleAvatar(
              backgroundColor: (isActive ? profile.themeColor : Colors.red).withOpacity(0.1),
              child: Icon(isActive ? Icons.check_circle_outline : Icons.block, color: isActive ? profile.themeColor : Colors.red),
            ),
            title: Text(data['restaurantName'] ?? "N/A", style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor)),
            subtitle: Text("${data['phone'] ?? 'N/A'} • ${data['validTillFormatted'] ?? 'N/A'}", style: TextStyle(fontSize: 12, color: profile.secondaryTextColor)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.share, size: 20),
                  onPressed: () => Share.share("Restaurant: ${data['restaurantName']}\nLicense: ${data['licenseKey']}\nDownload App: $_driveLink"),
                  tooltip: "Share License",
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Icon(isRegistered ? Icons.smartphone : Icons.phonelink_erase, size: 18, color: isRegistered ? Colors.blue : profile.secondaryTextColor),
                    const SizedBox(height: 4),
                    Text(isRegistered ? "Mobile OK" : "Pending", style: TextStyle(fontSize: 10, color: isRegistered ? Colors.blue : profile.secondaryTextColor)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildField(TextEditingController c, String l, IconData i, ProfileProvider p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        style: TextStyle(color: p.textColor, fontSize: 14),
        decoration: InputDecoration(
          labelText: l, 
          labelStyle: TextStyle(color: p.secondaryTextColor),
          prefixIcon: Icon(i, color: p.themeColor), 
          filled: true,
          fillColor: p.scaffoldColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  void _showLogsModal(ProfileProvider profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: profile.scaffoldColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: profile.secondaryTextColor.withOpacity(0.2), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text("ADMIN ACTION LOGS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1)),
            const Divider(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: LicenseService.firestore.collection('admin_logs').orderBy('timestamp', descending: true).limit(50).snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final logs = snapshot.data!.docs;
                  if (logs.isEmpty) return const Center(child: Text("No logs found"));

                  return ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, i) {
                      final log = logs[i].data() as Map<String, dynamic>;
                      final time = log['timestamp'] != null 
                          ? DateFormat('dd MMM, hh:mm a').format((log['timestamp'] as Timestamp).toDate()) 
                          : "Just now";
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: profile.themeColor.withOpacity(0.1),
                          child: Icon(_getLogIcon(log['action']), color: profile.themeColor, size: 20),
                        ),
                        title: Text(log['details'] ?? "No details", style: TextStyle(fontSize: 13, color: profile.textColor, fontWeight: FontWeight.w600)),
                        subtitle: Text("By: ${log['adminId']} • $time", style: TextStyle(fontSize: 11, color: profile.secondaryTextColor)),
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

  IconData _getLogIcon(String? action) {
    switch (action) {
      case 'RESET_DEVICE': return Icons.refresh_rounded;
      case 'BLOCK_APP': return Icons.block_flipped;
      case 'ACTIVATE_APP': return Icons.check_circle_rounded;
      case 'EDIT_EXPIRY': return Icons.edit_calendar_rounded;
      case 'POST_ANNOUNCEMENT': return Icons.campaign_rounded;
      case 'DELETE_LICENSE': return Icons.delete_forever_rounded;
      default: return Icons.info_outline_rounded;
    }
  }
}
