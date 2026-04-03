import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../main.dart';
import '../providers/profile_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/sync_provider.dart';
import '../services/export_service.dart';
import 'dashboard/dashboard_screen.dart';
import 'stock/stock_screen.dart';
import 'reports/reports_screen.dart';
import 'staff/staff_screen.dart';
import 'profile/profile_screen.dart';
import 'admin/admin_panel_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isSysAdmin = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _checkAdminStatus();
    _checkAutoBackup();
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

  Future<void> _checkAutoBackup() async {
    final prefs = await SharedPreferences.getInstance();
    bool hasCheckedBackup = prefs.getBool('auto_backup_checked') ?? false;
    if (hasCheckedBackup) return;

    final exportService = ExportService();
    final backupFile = await exportService.getAutoBackupFile();
    
    if (backupFile != null && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Backup Found!'),
          content: const Text('An automatic backup was found on this device. Would you like to restore your data?'),
          actions: [
            TextButton(
              onPressed: () async {
                await prefs.setBool('auto_backup_checked', true);
                if (mounted) Navigator.pop(context);
              },
              child: const Text('IGNORE'),
            ),
            ElevatedButton(
              onPressed: () async {
                bool success = await exportService.restoreFromBackup(backupFile);
                await prefs.setBool('auto_backup_checked', true);
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? 'Data Restored Successfully!' : 'Restore Failed!'),
                      backgroundColor: success ? Colors.green : Colors.red,
                    ),
                  );
                  if (success) {
                    RestartWidget.restartApp(context);
                  }
                }
              },
              child: const Text('RESTORE NOW'),
            ),
          ],
        ),
      );
    } else {
      await prefs.setBool('auto_backup_checked', true);
    }
  }

  void _showSyncStatus(BuildContext context, TransactionProvider txProvider, ProfileProvider profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Consumer<SyncProvider>(
        builder: (context, syncProvider, _) => Container(
          decoration: BoxDecoration(
            color: profile.cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
              Row(
                children: [
                  Icon(Icons.cloud_sync_rounded, color: profile.themeColor, size: 28),
                  const SizedBox(width: 16),
                  Text('CLOUD BACKUP & RESTORE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: profile.textColor)),
                ],
              ),
              const SizedBox(height: 24),
              
              // Cloud Sync Toggle
              Container(
                decoration: BoxDecoration(
                  color: profile.scaffoldColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade200),
                ),
                child: SwitchListTile(
                  title: const Text('Auto Cloud Sync', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(profile.isCloudSyncEnabled ? 'Enabled (Every 5 mins)' : 'Disabled', style: const TextStyle(fontSize: 11)),
                  value: profile.isCloudSyncEnabled,
                  activeColor: profile.themeColor,
                  onChanged: (val) => profile.toggleCloudSync(val),
                ),
              ),
              const SizedBox(height: 24),

              if (syncProvider.isSyncing) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: profile.themeColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: profile.themeColor.withOpacity(0.1)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(syncProvider.syncStatus, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 13)),
                          Text('${(syncProvider.syncProgress * 100).toInt()}%', style: TextStyle(fontWeight: FontWeight.w900, color: profile.themeColor)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: syncProvider.syncProgress, 
                          minHeight: 10,
                          color: profile.themeColor, 
                          backgroundColor: profile.themeColor.withOpacity(0.1),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ] else ...[
                _syncInfoRow('Data Protection', 'Securely synced with cloud', profile, icon: Icons.security_rounded, color: Colors.blue),
                const Divider(height: 32),
                _syncInfoRow('Storage', 'Backup includes all transactions', profile, icon: Icons.storage_rounded, color: Colors.green),
                const SizedBox(height: 32),
              ],

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: syncProvider.isSyncing ? null : () async {
                        bool success = await syncProvider.manualSyncToCloud(context);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(success ? 'Sync Successful!' : 'Sync Failed!'),
                              backgroundColor: success ? Colors.green : Colors.red,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: const Text('SYNC NOW', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: profile.themeColor,
                        minimumSize: const Size(0, 56),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: syncProvider.isSyncing ? null : () => _showFullRestoreConfirm(context, syncProvider, profile),
                      icon: const Icon(Icons.cloud_download_outlined, size: 18),
                      label: const Text('RESTORE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 56),
                        side: BorderSide(color: Colors.red.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullRestoreConfirm(BuildContext context, SyncProvider syncProvider, ProfileProvider profile) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Full Restore Data?'),
        content: const Text('This will replace ALL local data with Cloud data. Current unsynced changes might be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx); 
              bool success = await syncProvider.fullRestoreFromServer(context);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? 'Restore Successful!' : 'Restore Failed!'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            child: const Text('RESTORE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _syncInfoRow(String label, String value, ProfileProvider profile, {IconData? icon, Color? color}) {
    return Row(
      children: [
        if (icon != null) ...[Icon(icon, size: 18, color: color), const SizedBox(width: 12)],
        Text(label, style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(value, style: TextStyle(color: profile.textColor, fontWeight: FontWeight.w900, fontSize: 13)),
      ],
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final txProvider = Provider.of<TransactionProvider>(context);
    final syncProvider = Provider.of<SyncProvider>(context);
    final themeColor = profile.themeColor;
    final user = FirebaseAuth.instance.currentUser;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    final Color appBarContentColor = ThemeData.estimateBrightnessForColor(themeColor) == Brightness.dark 
        ? Colors.white 
        : Colors.black;

    final bool globalSyncing = txProvider.isSyncing || syncProvider.isSyncing;

    // Common AppBar Actions
    List<Widget> appBarActions = [
      Stack(
        alignment: Alignment.center,
        children: [
          IconButton(
            icon: Icon(
              globalSyncing ? Icons.cloud_sync_rounded : Icons.cloud_done_rounded, 
              color: globalSyncing ? appBarContentColor.withOpacity(0.5) : Colors.greenAccent,
              size: 26,
            ),
            onPressed: () => _showSyncStatus(context, txProvider, profile),
            tooltip: "Sync Status",
          ),
          if (globalSyncing)
            SizedBox(
              width: 32, height: 32, 
              child: CircularProgressIndicator(
                strokeWidth: 2, 
                color: appBarContentColor.withOpacity(0.8),
                backgroundColor: appBarContentColor.withOpacity(0.1),
              )
            ),
        ],
      ),
      if (_isSysAdmin)
        IconButton(
          icon: Icon(
            Icons.admin_panel_settings, 
            color: appBarContentColor == Colors.black ? Colors.deepOrange : Colors.orangeAccent,
            size: 26,
          ),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminPanelScreen())),
          tooltip: "Admin Panel",
        ),
    ];

    Widget body = TabBarView(
      controller: _tabController,
      physics: isTablet ? const NeverScrollableScrollPhysics() : null,
      children: const [
        DashboardScreen(),
        StockScreen(),
        ReportsScreen(),
        StaffScreen(),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (_tabController.index != 0) {
          _tabController.animateTo(0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: profile.scaffoldColor,
        appBar: AppBar(
          toolbarHeight: 62,
          elevation: 0,
          backgroundColor: themeColor,
          centerTitle: !isTablet,
          leadingWidth: 80,
          leading: Padding(
            padding: const EdgeInsets.only(left: 12.0),
            child: Center(
              child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen())),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: appBarContentColor.withValues(alpha: 0.2), width: 1.5),
                    color: Colors.black.withValues(alpha: 0.1),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.transparent,
                    backgroundImage: profile.logoPath.isNotEmpty && File(profile.logoPath).existsSync()
                        ? FileImage(File(profile.logoPath)) 
                        : (user?.photoURL != null ? NetworkImage(user!.photoURL!) as ImageProvider : null),
                    child: (profile.logoPath.isEmpty || !File(profile.logoPath).existsSync()) && user?.photoURL == null
                        ? Icon(Icons.person, color: appBarContentColor, size: 24)
                        : null,
                  ),
                ),
              ),
            ),
          ),
          title: Text(profile.businessName.toUpperCase(), 
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1, color: appBarContentColor)),
          actions: appBarActions,
          bottom: isTablet ? null : PreferredSize(
            preferredSize: const Size.fromHeight(65),
            child: Column(
              children: [
                Container(height: 1, width: double.infinity, color: appBarContentColor.withValues(alpha: 0.1)),
                Container(
                  color: themeColor,
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: appBarContentColor,
                    indicatorWeight: 4,
                    labelColor: appBarContentColor,
                    unselectedLabelColor: appBarContentColor.withValues(alpha: 0.6),
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    tabs: const [
                      Tab(text: 'HOME', icon: Icon(Icons.dashboard_rounded, size: 20)),
                      Tab(text: 'STOCK', icon: Icon(Icons.inventory_2_rounded, size: 20)),
                      Tab(text: 'REPORTS', icon: Icon(Icons.analytics_rounded, size: 20)),
                      Tab(text: 'STAFF', icon: Icon(Icons.people_alt_rounded, size: 20)),
                    ],
                  ),
                ),
                Container(height: 1, width: double.infinity, color: appBarContentColor.withValues(alpha: 0.1)),
              ],
            ),
          ),
        ),
        body: isTablet 
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _tabController.index,
                  onDestinationSelected: (index) => _tabController.animateTo(index),
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: profile.cardColor,
                  selectedIconTheme: IconThemeData(color: themeColor),
                  selectedLabelTextStyle: TextStyle(color: themeColor, fontWeight: FontWeight.bold, fontSize: 12),
                  unselectedLabelTextStyle: TextStyle(color: profile.secondaryTextColor, fontSize: 11),
                  destinations: const [
                    NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: Text('Home')),
                    NavigationRailDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2_rounded), label: Text('Stock')),
                    NavigationRailDestination(icon: Icon(Icons.analytics_outlined), selectedIcon: Icon(Icons.analytics_rounded), label: Text('Reports')),
                    NavigationRailDestination(icon: Icon(Icons.people_alt_outlined), selectedIcon: Icon(Icons.people_alt_rounded), label: Text('Staff')),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      ),
    );
  }
}
