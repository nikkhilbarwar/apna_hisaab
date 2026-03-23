import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../providers/profile_provider.dart';
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
  }

  Future<void> _checkAdminStatus() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isSysAdmin = prefs.getBool('is_sys_admin') ?? false;
    });
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
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                ),
                padding: const EdgeInsets.all(2),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.transparent,
                  backgroundImage: profile.logoPath.isNotEmpty && File(profile.logoPath).existsSync()
                      ? FileImage(File(profile.logoPath)) 
                      : (user?.photoURL != null ? NetworkImage(user!.photoURL!) as ImageProvider : null),
                  child: (profile.logoPath.isEmpty || !File(profile.logoPath).existsSync()) && user?.photoURL == null
                      ? const Icon(Icons.person, color: Colors.white, size: 30)
                      : null,
                ),
              ),
            ),
          ),
        ),
        title: Text(profile.businessName.toUpperCase(), 
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.white)),
        actions: [
          // Admin icon logic: Always visible but requires login if not already admin
          IconButton(
            icon: Icon(
              _isSysAdmin ? Icons.admin_panel_settings : Icons.shield_outlined, 
              color: _isSysAdmin ? Colors.orangeAccent : Colors.white70,
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
              Container(height: 1, width: double.infinity, color: Colors.white12),
              Container(
                color: themeColor,
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.white,
                  indicatorWeight: 4,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  tabs: const [
                    Tab(text: 'HOME', icon: Icon(Icons.dashboard_rounded, size: 20)),
                    Tab(text: 'STOCK', icon: Icon(Icons.inventory_2_rounded, size: 20)),
                    Tab(text: 'REPORTS', icon: Icon(Icons.analytics_rounded, size: 20)),
                    Tab(text: 'STAFF', icon: Icon(Icons.people_alt_rounded, size: 20)),
                  ],
                ),
              ),
              Container(height: 1, width: double.infinity, color: Colors.white12),
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
