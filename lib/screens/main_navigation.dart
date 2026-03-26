import 'package:flutter/material.dart';
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
import 'admin/admin_login_screen.dart';

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
    final syncProvider = Provider.of<SyncProvider>(context, listen: false);
    final unsynced = txProvider.transactions.where((tx) => tx.isSynced == 0).length + 
                     txProvider.pendingTransactions.where((tx) => tx.isSynced == 0).length;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
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
                  Text('CLOUD SYNC STATUS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: profile.textColor)),
                ],
              ),
              const SizedBox(height: 24),
              _syncInfoRow('Total Transactions', (txProvider.transactions.length + txProvider.pendingTransactions.length).toString(), profile),
              const Divider(height: 32),
              _syncInfoRow('Synced Data', (txProvider.transactions.length + txProvider.pendingTransactions.length - unsynced).toString(), profile, icon: Icons.check_circle_outline_rounded, color: Colors.green),
              const SizedBox(height: 12),
              _syncInfoRow('Pending Sync', unsynced.toString(), profile, icon: Icons.pending_outlined, color: Colors.orange),
              const SizedBox(height: 32),
              
              if (syncProvider.isSyncing) ...[
                LinearProgressIndicator(value: syncProvider.syncProgress, color: profile.themeColor, backgroundColor: profile.themeColor.withOpacity(0.1)),
                const SizedBox(height: 8),
                Text(syncProvider.syncStatus, style: TextStyle(fontSize: 12, color: profile.secondaryTextColor, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
              ],

              ElevatedButton(
                onPressed: syncProvider.isSyncing ? null : () async {
                  await syncProvider.syncAllToCloudSilently();
                  if (context.mounted) Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: profile.themeColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('SYNC NOW', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: syncProvider.isSyncing ? null : () {
                  _showFullRestoreConfirm(context, syncProvider, profile);
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  side: BorderSide(color: Colors.red.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text('RESTORE ALL FROM CLOUD', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold)),
              ),
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
        title: const Text('Full Restore?'),
        content: const Text('This will delete all local data and replace it with cloud data. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx); // Close dialog
              bool success = await syncProvider.fullRestoreFromServer(context);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? 'Full Restore Successful!' : 'Restore Failed!'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  )
                );
                if (success) {
                   Navigator.pop(context); // Close bottom sheet
                }
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
        Text(value, style: TextStyle(color: profile.textColor, fontWeight: FontWeight.w900, fontSize: 16)),
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

    final Color appBarContentColor = ThemeData.estimateBrightnessForColor(themeColor) == Brightness.dark 
        ? Colors.white 
        : Colors.black;

    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      appBar: AppBar(
        toolbarHeight: 62,
        elevation: 0,
        backgroundColor: themeColor,
        centerTitle: true,
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
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: Icon(
                  Icons.cloud_done_rounded, 
                  color: (txProvider.isSyncing || syncProvider.isSyncing) ? appBarContentColor.withOpacity(0.3) : Colors.greenAccent,
                  size: 24,
                ),
                onPressed: () => _showSyncStatus(context, txProvider, profile),
                tooltip: "Sync Status",
              ),
              if (txProvider.isSyncing || syncProvider.isSyncing)
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            ],
          ),
          IconButton(
            icon: Icon(
              _isSysAdmin ? Icons.admin_panel_settings : Icons.shield_outlined, 
              color: _isSysAdmin ? (_isSysAdmin && appBarContentColor == Colors.black ? Colors.deepOrange : Colors.orangeAccent) : appBarContentColor.withValues(alpha: 0.8),
              size: 26,
            ),
            onPressed: () {
              if (_isSysAdmin) {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminPanelScreen()));
              } else {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminLoginScreen()));
              }
            },
            tooltip: "Admin Panel",
          ),
        ],
        bottom: PreferredSize(
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
      body: TabBarView(
        controller: _tabController,
        children: const [
          DashboardScreen(),
          StockScreen(),
          ReportsScreen(),
          StaffScreen(),
        ],
      ),
    );
  }
}
