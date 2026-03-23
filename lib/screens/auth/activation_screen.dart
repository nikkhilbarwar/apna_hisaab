import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/profile_provider.dart';
import '../../services/license_service.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  bool _isLoading = false;
  String _deviceId = "Loading...";

  @override
  void initState() {
    super.initState();
    _fetchDeviceId();
  }

  Future<void> _fetchDeviceId() async {
    final id = await LicenseService.getDeviceId();
    setState(() => _deviceId = id);
  }

  void _contactSupport() async {
    const phone = "+919992256959"; // REPLACE WITH YOUR ACTUAL WHATSAPP NUMBER
    final message = "Hello, I need a license key for Apna Hisaab.\nMy Device ID: $_deviceId";
    final url = Uri.parse("https://wa.me/$phone?text=${Uri.encodeComponent(message)}");
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open WhatsApp. Please email us.")),
        );
      }
    }
  }

  Future<void> _handleActivation() async {
    final key = _keyController.text.trim();
    final identifier = _phoneController.text.trim();

    if (key.isEmpty || identifier.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter License Key and Registered Phone/Email")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await LicenseService.init();
      final result = await LicenseService.verifyLicense(key);

      if (result['success']) {
        if (mounted) {
          final profile = Provider.of<ProfileProvider>(context, listen: false);
          bool success = await profile.activateLicense(key);
          
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Premium Activated! Welcome to Apna Hisaab."), backgroundColor: Colors.green),
            );
          }
        }
      } else {
        throw result['message'] ?? "Activation Failed";
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final themeColor = profile.themeColor;

    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      appBar: AppBar(
        title: const Text('PRO ACTIVATION', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
        backgroundColor: themeColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Icon(Icons.vpn_key_rounded, size: 70, color: themeColor),
            const SizedBox(height: 20),
            Text("Unlock Professional Features", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: profile.textColor)),
            const SizedBox(height: 8),
            Text(
              "Enter your license key provided by the administrator.",
              textAlign: TextAlign.center, style: TextStyle(color: profile.secondaryTextColor, fontSize: 13),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _keyController,
              style: TextStyle(color: profile.textColor),
              decoration: InputDecoration(
                labelText: "License Key",
                hintText: "RESTO-XXXX-XXXX-XXXX",
                prefixIcon: const Icon(Icons.key),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(color: profile.textColor),
              decoration: InputDecoration(
                labelText: "Registered Phone or Email",
                prefixIcon: const Icon(Icons.person_pin_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 32),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _handleActivation,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                      backgroundColor: themeColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text("ACTIVATE NOW", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
            const SizedBox(height: 40),
            const Divider(),
            const SizedBox(height: 20),
            Text("NEED HELP?", style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 16),
            // Device ID Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.devices, size: 20, color: Colors.grey),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Your Device ID:", style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text(_deviceId, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: profile.textColor)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _deviceId));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Device ID copied!")));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _contactSupport,
                    icon: const Icon(Icons.chat, size: 18, color: Colors.green),
                    label: const Text("WhatsApp Support", style: TextStyle(color: Colors.green)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.green),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text("Email: nikkhilbarwar@gmail.com", style: TextStyle(color: profile.secondaryTextColor, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
