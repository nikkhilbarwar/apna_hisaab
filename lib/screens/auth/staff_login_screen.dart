import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/staff_model.dart';
import '../../providers/profile_provider.dart';
import '../../providers/staff_provider.dart';
import '../../services/firebase_service.dart';
import '../main_navigation.dart';

class StaffLoginScreen extends StatefulWidget {
  const StaffLoginScreen({super.key});

  @override
  State<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends State<StaffLoginScreen> {
  final TextEditingController _licenseController = TextEditingController();
  int _step = 0; // 0: License Input, 1: Staff Selection
  bool _isLoading = false;
  String? _errorMessage;
  List<dynamic> _foundStaff = []; // Will be replaced by actual data

  Future<void> _verifyLicense() async {
    final license = _licenseController.text.trim();
    if (license.isEmpty) {
      setState(() => _errorMessage = "Please enter License Number");
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Verify license with Firebase/Firestore first
      final doc = await FirebaseFirestore.instance.collection('licenses').doc(license).get();
      if (!doc.exists) {
        throw "Invalid License Key";
      }

      // 2. Set the global license key for partitioning
      FirebaseService.activeLicenseKey = license;
      
      // 3. Fetch staff for this license
      await Provider.of<StaffProvider>(context, listen: false).fetchStaff();
      
      setState(() {
        _step = 1;
        _isLoading = false;
        _foundStaff = Provider.of<StaffProvider>(context, listen: false).staffList;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _showPinBottomSheet(StaffModel staff) {
    final themeColor = Provider.of<ProfileProvider>(context, listen: false).themeColor;
    final List<TextEditingController> pinControllers = List.generate(4, (_) => TextEditingController());
    final List<FocusNode> focusNodes = List.generate(4, (_) => FocusNode());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 24, left: 24, right: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Enter PIN for ${staff.name}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(4, (index) => SizedBox(
                width: 50,
                child: TextField(
                  controller: pinControllers[index],
                  focusNode: focusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  obscureText: true,
                  decoration: InputDecoration(counterText: "", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  onChanged: (val) async {
                    if (val.isNotEmpty && index < 3) focusNodes[index+1].requestFocus();
                    if (index == 3 && val.isNotEmpty) {
                      String pin = pinControllers.map((c) => c.text).join();
                      if (pin == staff.loginPin) {
                        // Persist session
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('saved_license_key', FirebaseService.activeLicenseKey ?? '');
                        await prefs.setInt('saved_staff_id', staff.id!);
                        await prefs.setString('saved_staff_name', staff.name);

                        Navigator.pop(context);
                        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const MainNavigation()), (route) => false);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid PIN"), backgroundColor: Colors.red));
                      }
                    }
                  },
                ),
              )),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Provider.of<ProfileProvider>(context).themeColor;

    return Scaffold(
      appBar: AppBar(title: Text(_step == 0 ? "Staff Login" : "Select Staff")),
      body: _step == 0 ? _buildLicenseInput(themeColor) : _buildStaffGrid(themeColor),
    );
  }

  Widget _buildLicenseInput(Color themeColor) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextField(
            controller: _licenseController,
            decoration: const InputDecoration(labelText: "Owner License Number", prefixIcon: Icon(Icons.key)),
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 24),
          _isLoading ? const CircularProgressIndicator() : ElevatedButton(onPressed: _verifyLicense, child: const Text("VERIFY LICENSE")),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }

  Widget _buildStaffGrid(Color themeColor) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16),
      itemCount: _foundStaff.length,
      itemBuilder: (context, index) {
        final staff = _foundStaff[index] as StaffModel;
        return InkWell(
          onTap: () => _showPinBottomSheet(staff),
          child: Container(
            decoration: BoxDecoration(color: themeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.person, size: 50),
                Text(staff.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(staff.role),
              ],
            ),
          ),
        );
      },
    );
  }
}
