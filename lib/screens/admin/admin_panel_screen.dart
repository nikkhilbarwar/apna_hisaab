import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:math';
import '../../services/license_service.dart';
import '../../providers/profile_provider.dart';
import 'package:provider/provider.dart';

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

  bool _isGenerating = false;
  String _selectedPlan = '1 Year';
  String? _generatedKey;

  final List<Map<String, dynamic>> _validityOptions = [
    {'label': '7 Days Trial', 'days': 7, 'planType': 'trial'},
    {'label': '30 Days', 'days': 30, 'planType': 'monthly'},
    {'label': '3 Months', 'days': 90, 'planType': 'quarterly'},
    {'label': '6 Months', 'days': 180, 'planType': 'half_yearly'},
    {'label': '1 Year', 'days': 365, 'planType': 'yearly'},
    {'label': 'Lifetime', 'days': null, 'planType': 'lifetime'},
  ];

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
      await LicenseService.init();
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

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      appBar: AppBar(title: const Text("ADMIN PANEL"), backgroundColor: profile.themeColor, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildGeneratorCard(profile),
            const SizedBox(height: 30),
            _buildSearchSection(profile),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneratorCard(ProfileProvider profile) {
    return Card(
      color: profile.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Create License", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: profile.textColor)),
            const SizedBox(height: 20),
            _buildField(_restaurantController, "Restaurant Name", Icons.store, profile),
            _buildField(_ownerController, "Owner Name", Icons.person, profile),
            _buildField(_phoneController, "Phone or Email", Icons.contact_mail, profile),
            const SizedBox(height: 15),
            DropdownButtonFormField<String>(
              value: _selectedPlan,
              dropdownColor: profile.cardColor,
              style: TextStyle(color: profile.textColor),
              decoration: InputDecoration(labelText: "Validity Plan", border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))),
              items: _validityOptions.map((e) => DropdownMenuItem(value: e['label'] as String, child: Text(e['label']))).toList(),
              onChanged: (v) => setState(() => _selectedPlan = v!),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isGenerating ? null : _handleGenerate,
              style: ElevatedButton.styleFrom(backgroundColor: profile.themeColor, minimumSize: const Size(double.infinity, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: _isGenerating ? const CircularProgressIndicator(color: Colors.white) : const Text("GENERATE LICENSE", style: TextStyle(color: Colors.white)),
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
      decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.withOpacity(0.5))),
      child: Column(
        children: [
          SelectableText(_generatedKey!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(icon: const Icon(Icons.copy, color: Colors.green), onPressed: () => Clipboard.setData(ClipboardData(text: _generatedKey!))),
              IconButton(icon: const Icon(Icons.share, color: Colors.green), onPressed: () => Share.share("Your License: $_generatedKey")),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildSearchSection(ProfileProvider profile) {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          style: TextStyle(color: profile.textColor),
          decoration: InputDecoration(
            hintText: "Search Phone/Email",
            suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () => _showSearchDialog(_searchController.text)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }

  Widget _buildField(TextEditingController c, String l, IconData i, ProfileProvider p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        style: TextStyle(color: p.textColor),
        decoration: InputDecoration(labelText: l, prefixIcon: Icon(i, color: p.themeColor), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))),
      ),
    );
  }

  void _showSearchDialog(String identifier) async {
    if (identifier.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => FutureBuilder<QuerySnapshot>(
        future: LicenseService.firestore.collection('licenses').where('phone', isEqualTo: identifier).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const AlertDialog(title: Text("Not Found"));
          
          final doc = snapshot.data!.docs.first;
          final data = doc.data() as Map<String, dynamic>;
          final bool isActive = data['status'] == 'active';

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text(data['restaurantName'] ?? "License Info"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Status: ${data['status'].toString().toUpperCase()}", style: TextStyle(color: isActive ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                Text("Expiry: ${data['validTillFormatted']}"),
                Text("Device: ${data['activeDeviceId'] ?? 'N/A'}"),
              ],
            ),
            actions: [
              // logic: BLOCK / UNBLOCK Toggle
              ElevatedButton(
                onPressed: () async {
                  await LicenseService.firestore.collection('licenses').doc(doc.id).update({
                    'status': isActive ? 'blocked' : 'active'
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isActive ? "License Blocked!" : "License Unblocked!"), backgroundColor: isActive ? Colors.red : Colors.green));
                },
                style: ElevatedButton.styleFrom(backgroundColor: isActive ? Colors.red : Colors.green),
                child: Text(isActive ? "BLOCK LICENSE" : "UNBLOCK LICENSE", style: const TextStyle(color: Colors.white)),
              ),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE")),
            ],
          );
        },
      ),
    );
  }
}
