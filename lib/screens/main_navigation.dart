import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../main.dart';
import '../core/widgets/app_bottom_sheet.dart';
import '../providers/profile_provider.dart';
import '../providers/staff_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/sync_provider.dart';
import '../providers/staff_auth_provider.dart';
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

class _MainNavigationState extends State<MainNavigation>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _checkAdminStatus();
    _checkAutoBackup();
    _checkRestoreNag();
    _checkAccess(); // Added Security Check
  }

  Future<void> _checkAccess() async {
    final staffAuth = Provider.of<StaffAuthProvider>(context, listen: false);
    final staffProvider = Provider.of<StaffProvider>(context, listen: false);
    
    if (staffAuth.isStaffLoggedIn && staffAuth.currentStaff != null) {
      // Reload the staff list to get the latest status
      await staffProvider.fetchStaff();
      final latestStaff = staffProvider.allStaff.firstWhere(
        (s) => s.id == staffAuth.currentStaff!.id,
        orElse: () => staffAuth.currentStaff!,
      );

      if (!latestStaff.isLoginEnabled) {
        await staffAuth.logoutStaff();
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
        }
      }
    }
  }

  Future<void> _checkRestoreNag() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final nagKey = 'restore_nag_shown_$uid';
    bool alreadyShown = prefs.getBool(nagKey) ?? false;

    if (alreadyShown) return;

    // Give it a small delay so screen finishes loading
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      _showRestoreNagDialog();
    });

    await prefs.setBool(nagKey, true);
  }

  void _showRestoreNagDialog() {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final syncProvider = Provider.of<SyncProvider>(context, listen: false);

    AppBottomSheet.show(
      context: context,
      profile: profile,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              color: profile.themeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.cloud_download_rounded,
                    size: 60,
                    color: profile.themeColor,
                  ),
                  Positioned(
                    bottom: 10,
                    child: Text(
                      "RESTORE RECOMMENDATION",
                      style: TextStyle(
                        color: profile.themeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "Restore Your Data",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: profile.textColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "We recommend performing a one-time 'Full Restore' to ensure all your previous items, transactions, and settings are correctly synced to this device.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: profile.secondaryTextColor,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSyncStatus(
                context,
                Provider.of<TransactionProvider>(
                  context,
                  listen: false,
                ),
                profile,
              );
              _showFullRestoreConfirm(context, syncProvider, profile);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: profile.themeColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: const Text(
              "RESTORE FROM CLOUD",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "I'LL DO IT LATER",
              style: TextStyle(
                color: profile.secondaryTextColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkAdminStatus() async {
    // Admin status check can be implemented via provider logic
  }

  Future<void> _checkAutoBackup() async {
    final prefs = await SharedPreferences.getInstance();
    bool hasCheckedBackup = prefs.getBool('auto_backup_checked') ?? false;
    if (hasCheckedBackup) return;

    final exportService = ExportService();
    final backupFile = await exportService.getAutoBackupFile();

    if (backupFile != null && mounted) {
      final profile = Provider.of<ProfileProvider>(context, listen: false);
      
      final bool? shouldRestore = await AppBottomSheet.showAction(
        context: context,
        profile: profile,
        title: "Backup Found!",
        message: "An automatic backup was found on this device. Would you like to restore your data?",
        confirmLabel: "RESTORE NOW",
        cancelLabel: "IGNORE",
        icon: Icons.backup_rounded,
      );

      if (mounted) {
        if (shouldRestore == true) {
          bool success = await exportService.restoreFromBackup(backupFile);
          await prefs.setBool('auto_backup_checked', true);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  success ? 'Data Restored Successfully!' : 'Restore Failed!',
                ),
                backgroundColor: success ? Colors.green : Colors.red,
              ),
            );
            if (success) {
              RestartWidget.restartApp(context);
            }
          }
        } else if (shouldRestore == false) {
          await prefs.setBool('auto_backup_checked', true);
        }
      }
    } else {
      await prefs.setBool('auto_backup_checked', true);
    }
  }

  void _showSyncStatus(
    BuildContext context,
    TransactionProvider txProvider,
    ProfileProvider profile,
  ) {
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
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  Icon(
                    Icons.cloud_sync_rounded,
                    color: profile.themeColor,
                    size: 28,
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'CLOUD BACKUP & RESTORE',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: profile.textColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Cloud Sync Toggle
              Container(
                decoration: BoxDecoration(
                  color: profile.scaffoldColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: profile.isDarkMode
                        ? Colors.white10
                        : Colors.grey.shade200,
                  ),
                ),
                child: SwitchListTile(
                  title: const Text(
                    'Auto Cloud Sync',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    profile.isCloudSyncEnabled
                        ? 'Enabled (Every 5 mins)'
                        : 'Disabled',
                    style: const TextStyle(fontSize: 11),
                  ),
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
                    color: profile.themeColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: profile.themeColor.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              syncProvider.syncStatus,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: profile.textColor,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${(syncProvider.syncProgress * 100).toInt()}%',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: profile.themeColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: syncProvider.syncProgress,
                          minHeight: 10,
                          color: profile.themeColor,
                          backgroundColor: profile.themeColor.withValues(
                            alpha: 0.1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () => syncProvider.resetSync(),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text(
                          "RESET SYNC",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ] else ...[
                _syncInfoRow(
                  'Data Protection',
                  'Securely synced with cloud',
                  profile,
                  icon: Icons.security_rounded,
                  color: Colors.blue,
                ),
                const Divider(height: 32),
                _syncInfoRow(
                  'Storage',
                  'Backup includes all transactions',
                  profile,
                  icon: Icons.storage_rounded,
                  color: Colors.green,
                ),
                const SizedBox(height: 32),
              ],

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: syncProvider.isSyncing
                          ? null
                          : () async {
                              bool success = await syncProvider
                                  .manualSyncToCloud(context);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      success
                                          ? 'Sync Successful!'
                                          : 'Sync Failed!',
                                    ),
                                    backgroundColor: success
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: const Text(
                        'SYNC NOW',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: profile.themeColor,
                        minimumSize: const Size(0, 56),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: syncProvider.isSyncing
                          ? null
                          : () => _showFullRestoreConfirm(
                              context,
                              syncProvider,
                              profile,
                            ),
                      icon: const Icon(Icons.cloud_download_outlined, size: 18),
                      label: const Text(
                        'RESTORE',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 56),
                        side: BorderSide(color: Colors.red.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
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

  void _showFullRestoreConfirm(
    BuildContext context,
    SyncProvider syncProvider,
    ProfileProvider profile,
  ) async {
    final bool? confirm = await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: 'Full Restore Data?',
      message: 'This will replace ALL local data with Cloud data. Current unsynced changes might be lost.',
      confirmLabel: 'RESTORE',
      confirmColor: Colors.red,
      icon: Icons.cloud_download_rounded,
      isDestructive: true,
    );

    if (confirm == true && context.mounted) {
      bool success = await syncProvider.fullRestoreFromServer(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? 'Restore Successful!' : 'Restore Failed!',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  Widget _syncInfoRow(
    String label,
    String value,
    ProfileProvider profile, {
    IconData? icon,
    Color? color,
  }) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
        ],
        Text(
          label,
          style: TextStyle(
            color: profile.secondaryTextColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: profile.textColor,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
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
    final staffAuth = Provider.of<StaffAuthProvider>(context);
    final themeColor = profile.themeColor;
    final user = FirebaseAuth.instance.currentUser;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    final Color appBarContentColor =
        ThemeData.estimateBrightnessForColor(themeColor) == Brightness.dark
        ? Colors.white
        : Colors.black;

    final bool globalSyncing = txProvider.isSyncing || syncProvider.isSyncing;

    // Admin List (In emails ko kabhi login nahi maangega)
    const adminEmails = [
      "nikkhilbarwar@gmail.com",
      "anitamishra1714@gmail.com",
      "missadvocate06@gmail.com",
    ];

    bool isUserAdmin =
        (user?.email != null && adminEmails.contains(user!.email!.toLowerCase()));

    // Common AppBar Actions
    List<Widget> appBarActions = [
      if (isUserAdmin)
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('support_tickets')
              .where('status', isNotEqualTo: 'deleted')
              .where('status', isEqualTo: 'open')
              .snapshots(),
          builder: (context, snapshot) {
            int openTickets = snapshot.hasData ? snapshot.data!.docs.length : 0;
            return IconButton(
              icon: Badge.count(
                count: openTickets,
                isLabelVisible: openTickets > 0,
                child: Icon(
                  Icons.shield_rounded,
                  color: appBarContentColor == Colors.black
                      ? Colors.deepOrange
                      : Colors.orangeAccent,
                  size: 26,
                ),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdminPanelScreen(),
                ),
              ),
              tooltip: "Admin Panel",
            );
          },
        ),
      Stack(
        alignment: Alignment.center,
        children: [
          IconButton(
            icon: Icon(
              globalSyncing
                  ? Icons.cloud_sync_rounded
                  : Icons.cloud_done_rounded,
              color: globalSyncing
                  ? appBarContentColor.withValues(alpha: 0.5)
                  : Colors.greenAccent,
              size: 26,
            ),
            onPressed: () => _showSyncStatus(context, txProvider, profile),
            tooltip: "Sync Status",
          ),
          if (globalSyncing)
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: appBarContentColor.withValues(alpha: 0.8),
                backgroundColor: appBarContentColor.withValues(alpha: 0.1),
              ),
            ),
        ],
      ),
    ];

    Widget body = TabBarView(
      controller: _tabController,
      physics: isTablet ? const NeverScrollableScrollPhysics() : null,
      children: [
        const DashboardScreen(),
        if (staffAuth.hasPermission('can_stock'))
          const StockScreen()
        else
          _PermissionDeniedPlaceholder(
            permission: 'View Stock',
            themeColor: themeColor,
          ),
        if (staffAuth.hasPermission('can_reports'))
          const ReportsScreen()
        else
          _PermissionDeniedPlaceholder(
            permission: 'View Reports',
            themeColor: themeColor,
          ),
        if (staffAuth.hasPermission('can_manage_staff'))
          const StaffScreen()
        else
          _PermissionDeniedPlaceholder(
            permission: 'Manage Staff',
            themeColor: themeColor,
          ),
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
          toolbarHeight: 45,
          elevation: 0,
          backgroundColor: themeColor,
          centerTitle: true,
          leadingWidth: 80,
          leading: Padding(
            padding: const EdgeInsets.only(left: 12.0),
            child: Center(
              child: GestureDetector(
                onTap: () {
                  profile
                      .markSupportAsRead(); // Mark as read when entering profile
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfileScreen(),
                    ),
                  );
                },
                child: Badge(
                  isLabelVisible: profile.hasUnreadSupportReply,
                  backgroundColor: Colors.red,
                  smallSize: 12,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: appBarContentColor.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                      color: Colors.black.withValues(alpha: 0.1),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.transparent,
                      backgroundImage:
                          profile.logoPath.isNotEmpty &&
                              File(profile.logoPath).existsSync()
                          ? FileImage(File(profile.logoPath))
                          : (user?.photoURL != null
                                ? NetworkImage(user!.photoURL!) as ImageProvider
                                : null),
                      child:
                          (profile.logoPath.isEmpty ||
                                  !File(profile.logoPath).existsSync()) &&
                              user?.photoURL == null
                          ? Icon(
                              Icons.person,
                              color: appBarContentColor,
                              size: 24,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
          title: Text(
            profile.displayBusinessName.toUpperCase(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: appBarContentColor,
            ),
          ),
          actions: appBarActions,
          bottom: isTablet
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(65),
                  child: Column(
                    children: [
                      Container(
                        height: 1,
                        width: double.infinity,
                        color: appBarContentColor.withValues(alpha: 0.1),
                      ),
                      Container(
                        height: 55,
                        color: themeColor,
                        child: TabBar(
                          controller: _tabController,
                          indicatorColor: appBarContentColor,
                          indicatorWeight: 4,
                          labelColor: appBarContentColor,
                          unselectedLabelColor: appBarContentColor.withValues(
                            alpha: 0.6,
                          ),
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                          tabs: const [
                            Tab(
                              text: 'HOME',
                              icon: Icon(Icons.dashboard_rounded, size: 20),
                            ),
                            Tab(
                              text: 'STOCK',
                              icon: Icon(Icons.inventory_2_rounded, size: 20),
                            ),
                            Tab(
                              text: 'REPORTS',
                              icon: Icon(Icons.analytics_rounded, size: 20),
                            ),
                            Tab(
                              text: 'STAFF',
                              icon: Icon(Icons.people_alt_rounded, size: 20),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 1,
                        width: double.infinity,
                        color: appBarContentColor.withValues(alpha: 0.1),
                      ),
                    ],
                  ),
                ),
        ),
        body: isTablet
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: _tabController.index,
                    onDestinationSelected: (index) =>
                        _tabController.animateTo(index),
                    labelType: NavigationRailLabelType.all,
                    backgroundColor: profile.cardColor,
                    selectedIconTheme: IconThemeData(color: themeColor),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.dashboard_outlined),
                        selectedIcon: Icon(Icons.dashboard_rounded),
                        label: Text('Home'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.inventory_2_outlined),
                        selectedIcon: Icon(Icons.inventory_2_rounded),
                        label: Text('Stock'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.analytics_outlined),
                        selectedIcon: Icon(Icons.analytics_rounded),
                        label: Text('Reports'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.people_alt_outlined),
                        selectedIcon: Icon(Icons.people_alt_rounded),
                        label: Text('Staff'),
                      ),
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

class _PermissionDeniedPlaceholder extends StatelessWidget {
  final String permission;
  final Color themeColor;

  const _PermissionDeniedPlaceholder({
    required this.permission,
    required this.themeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_person_rounded, size: 80, color: themeColor.withValues(alpha: 0.3)),
            const SizedBox(height: 24),
            Text(
              "Access Denied",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: themeColor,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "You do not have permission to $permission. Please contact your manager/owner for access.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
