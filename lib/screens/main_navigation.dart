import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../providers/profile_provider.dart';
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
                    // Refresh app state
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

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final themeColor = profile.themeColor;
    final user = FirebaseAuth.instance.currentUser;

    // Logic: Dynamic foreground color for contrast
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

class RestartWidget extends StatefulWidget {
  const RestartWidget({super.key, required this.child});
  final Widget child;

  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_RestartWidgetState>()?.restartApp();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key key = UniqueKey();

  void restartApp() {
    setState(() {
      key = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: key,
      child: widget.child,
    );
  }
}
