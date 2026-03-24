import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/profile_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/item_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/staff_provider.dart';
import '../../services/auth_service.dart';
import '../../services/export_service.dart';
import '../../utils/app_strings.dart';
import '../auth/login_screen.dart';
import '../auth/activation_screen.dart';
import 'widgets/business_card.dart';
import 'widgets/profile_action_card.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();
  final AuthService _authService = AuthService();
  final ExportService _exportService = ExportService();
  bool _isBackingUp = false;
  bool _isSysAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
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

  Future<void> _pickAndCropImage(ProfileProvider profile) async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: image.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Logo',
            toolbarColor: profile.themeColor,
            toolbarWidgetColor: Colors.white,
            statusBarColor: Colors.black,
            backgroundColor: Colors.black,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            hideBottomControls: false,
            cropFrameColor: Colors.white,
            cropGridColor: Colors.white,
            activeControlsWidgetColor: Colors.white,
          ),
          IOSUiSettings(
            title: 'Crop Logo',
            aspectRatioLockEnabled: true,
            resetButtonHidden: false,
            doneButtonTitle: 'Done',
            cancelButtonTitle: 'Cancel',
          ),
        ],
      );

      if (croppedFile != null && mounted) {
        profile.updateProfile(logoPath: croppedFile.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error picking image: $e")),
        );
      }
    }
  }

  Future<void> _handleBackup(ProfileProvider profile) async {
    setState(() => _isBackingUp = true);
    final path = await _exportService.createFullBackup();
    setState(() => _isBackingUp = false);

    if (mounted) {
      if (path != null) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: profile.cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 12),
                Text('Backup Success', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text('Full backup created successfully!\n\nLocation: $path\n\nThis file will stay in your Documents folder even if you uninstall the app.', 
              style: TextStyle(color: profile.secondaryTextColor, fontSize: 13)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to create backup. Please check storage permissions.')));
      }
    }
  }

  Future<void> _handleRestore(ProfileProvider profile) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        
        if (mounted) {
          bool confirm = await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: profile.cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Text('Restore Data?', style: TextStyle(fontWeight: FontWeight.bold)),
              content: const Text('Warning: This will replace all current app data and settings with the data from backup file. This cannot be undone.', style: TextStyle(color: Colors.red)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true), 
                  child: const Text('PROCEED', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
                ),
              ],
            ),
          ) ?? false;

          if (confirm && mounted) {
            setState(() => _isBackingUp = true);
            bool success = await _exportService.restoreFromBackup(file);
            
            if (success) {
              // Refresh all providers
              await profile.loadProfile();
              if (mounted) {
                Provider.of<TransactionProvider>(context, listen: false).fetchTransactions();
                Provider.of<ItemProvider>(context, listen: false).fetchItems();
                Provider.of<CategoryProvider>(context, listen: false).fetchCategories();
                Provider.of<StaffProvider>(context, listen: false).fetchStaff();
              }
            }
            
            setState(() => _isBackingUp = false);

            if (mounted) {
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Everything restored successfully!'), backgroundColor: Colors.green));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to restore data. Invalid backup file.'), backgroundColor: Colors.red));
              }
            }
          }
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _confirmLogout() {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text("${AppStrings.logout}?", style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold)),
        content: Text(AppStrings.confirmLogout, style: TextStyle(color: profile.secondaryTextColor)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(AppStrings.cancel)),
          TextButton(
            onPressed: () async {
              await _authService.signOut();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text(AppStrings.logout, style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showEditBottomSheet(BuildContext context, ProfileProvider profile) {
    final formKey = GlobalKey<FormState>();
    final n = TextEditingController(text: profile.businessName);
    final o = TextEditingController(text: profile.ownerName);
    final c = TextEditingController(text: profile.contact);
    final a = TextEditingController(text: profile.address);
    final t = TextEditingController(text: profile.taxPercentage.toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: profile.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
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
                Text(AppStrings.editBusiness, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: profile.textColor)),
                const SizedBox(height: 24),
                _buildField(n, AppStrings.businessName, Icons.business, profile),
                _buildField(o, AppStrings.ownerName, Icons.person_outline, profile),
                _buildField(c, AppStrings.contactNumber, Icons.phone_outlined, profile, keyboard: TextInputType.phone),
                _buildField(t, AppStrings.taxPercentage, Icons.percent, profile, keyboard: TextInputType.number, suffix: '%'),
                _buildField(a, AppStrings.address, Icons.location_on_outlined, profile, maxLines: 2),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      profile.updateProfile(
                        businessName: n.text.trim(),
                        ownerName: o.text.trim(),
                        contact: c.text.trim(),
                        address: a.text.trim(),
                        taxPercentage: double.tryParse(t.text) ?? 0.0,
                      );
                      Navigator.pop(ctx);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: profile.themeColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text(AppStrings.saveChanges, style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDataSecurityPopup(ProfileProvider profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: profile.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(24),
        height: MediaQuery.of(context).size.height * 0.8,
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
              children: [
                Icon(Icons.security_outlined, color: profile.themeColor, size: 28),
                const SizedBox(width: 12),
                Text("Data & Security", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: profile.textColor)),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  "We are committed to safeguarding user information through robust technical and organizational measures. All data processed within the application is handled in accordance with industry-standard security protocols and applicable data protection regulations.\n\n"
                  "User-generated and transactional data is primarily stored in a secure local environment and, where applicable, may be synchronized with cloud-based services utilizing encrypted transmission channels (e.g., HTTPS/TLS). Sensitive information is neither exposed nor transmitted without appropriate safeguards and authentication layers.\n\n"
                  "We implement access control mechanisms, data minimization principles, and structured storage methodologies to ensure that only necessary information is retained for operational purposes. No personally identifiable information is shared with third parties except where explicitly required for service functionality, legal compliance, or authorized integrations.\n\n"
                  "The application does not engage in unauthorized data harvesting, background tracking, or intrusive analytics beyond the scope of essential service delivery. Any optional features involving external services are governed by their respective privacy frameworks.\n\n"
                  "While commercially reasonable efforts are made to ensure data integrity, availability, and confidentiality, users acknowledge that no digital system can guarantee absolute security. By using the application, users consent to data handling practices as outlined in this policy.",
                  style: TextStyle(color: profile.secondaryTextColor, fontSize: 14, height: 1.6, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.justify,
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: profile.themeColor, minimumSize: const Size(double.infinity, 50)),
              child: const Text("I UNDERSTAND", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showFeedbackPopup(ProfileProvider profile) {
    final TextEditingController feedbackController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: profile.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
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
                  children: [
                    Icon(Icons.feedback_outlined, color: profile.themeColor, size: 28),
                    const SizedBox(width: 12),
                    Text("Services & Feedback", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: profile.textColor)),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  "Tell us how we can improve. Your feedback helps us build a better experience for everyone.",
                  style: TextStyle(color: profile.secondaryTextColor, fontSize: 13),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: feedbackController,
                  maxLines: 5,
                  validator: (v) => v == null || v.trim().isEmpty ? "Please enter your message" : null,
                  style: TextStyle(color: profile.textColor, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: "Enter your feedback or queries here...",
                    hintStyle: TextStyle(color: profile.secondaryTextColor.withOpacity(0.5)),
                    filled: true,
                    fillColor: profile.scaffoldColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            final String msg = Uri.encodeComponent(feedbackController.text.trim());
                            final Uri emailUri = Uri.parse("mailto:Nikkhilbarwar@gmail.com?subject=App Feedback&body=$msg");
                            if (await canLaunchUrl(emailUri)) {
                              await launchUrl(emailUri);
                              Navigator.pop(ctx);
                            }
                          }
                        },
                        icon: const Icon(Icons.email_outlined, size: 20),
                        label: const Text("EMAIL", style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, minimumSize: const Size(0, 50)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            final String msg = Uri.encodeComponent(feedbackController.text.trim());
                            final Uri waUri = Uri.parse("https://wa.me/919992256959?text=$msg");
                            if (await canLaunchUrl(waUri)) {
                              await launchUrl(waUri);
                              Navigator.pop(ctx);
                            }
                          }
                        },
                        icon: const Icon(Icons.chat_outlined, size: 20),
                        label: const Text("WHATSAPP", style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, minimumSize: const Size(0, 50)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, ProfileProvider profile, {TextInputType? keyboard, String? suffix, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: maxLines,
        style: TextStyle(color: profile.textColor, fontSize: 14, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: profile.secondaryTextColor),
          prefixIcon: Icon(icon, color: profile.themeColor),
          suffixText: suffix,
          filled: true,
          fillColor: profile.scaffoldColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: profile.themeColor, width: 2)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final themeColor = profile.themeColor;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: themeColor,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            title: LayoutBuilder(
              builder: (ctx, constraints) {
                final settings = ctx.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
                if (settings == null) return const SizedBox.shrink();
                
                final deltaExtent = settings.maxExtent - settings.minExtent;
                final t = (1.0 - (settings.currentExtent - settings.minExtent) / deltaExtent).clamp(0.0, 1.0);
                
                return Opacity(
                  opacity: t > 0.7 ? 1.0 : 0.0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.white,
                        backgroundImage: profile.logoPath.isNotEmpty && File(profile.logoPath).existsSync()
                            ? FileImage(File(profile.logoPath))
                            : (user?.photoURL != null ? NetworkImage(user!.photoURL!) : null) as ImageProvider?,
                        child: (profile.logoPath.isEmpty || !File(profile.logoPath).existsSync()) && user?.photoURL == null
                            ? Icon(Icons.business, size: 16, color: themeColor)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        profile.businessName,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              }
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [themeColor, themeColor.withOpacity(0.8)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -50,
                      top: -50,
                      child: CircleAvatar(radius: 100, backgroundColor: Colors.white.withOpacity(0.05)),
                    ),
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 40),
                          GestureDetector(
                            onTap: () => _pickAndCropImage(profile),
                            child: Stack(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                  child: CircleAvatar(
                                    radius: 50,
                                    backgroundColor: profile.cardColor,
                                    backgroundImage: profile.logoPath.isNotEmpty && File(profile.logoPath).existsSync()
                                        ? FileImage(File(profile.logoPath))
                                        : (user?.photoURL != null ? NetworkImage(user!.photoURL!) : null) as ImageProvider?,
                                    child: (profile.logoPath.isEmpty || !File(profile.logoPath).existsSync()) && user?.photoURL == null
                                        ? Icon(Icons.business, size: 40, color: themeColor)
                                        : null,
                                  ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                    child: Icon(Icons.edit, size: 16, color: themeColor),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            profile.businessName,
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            profile.ownerName.isEmpty ? (user?.displayName ?? "") : profile.ownerName,
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BusinessCard(
                    profile: profile, 
                    user: user, 
                    onEdit: () => _showEditBottomSheet(context, profile),
                    onPickImage: () => _pickAndCropImage(profile),
                  ),
                  const SizedBox(height: 24),
                  Text("SETTINGS", style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 12)),
                  const SizedBox(height: 12),
                  ProfileActionCard(
                    title: AppStrings.editBusiness,
                    subtitle: "Update name, contact and address",
                    icon: Icons.edit_note_rounded,
                    onTap: () => _showEditBottomSheet(context, profile),
                    profile: profile,
                  ),
                  ProfileActionCard(
                    title: "Theme Color",
                    subtitle: "Personalize your app look",
                    icon: Icons.palette_outlined,
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: profile.cardColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          title: Text("Select Theme Color", style: TextStyle(color: profile.textColor)),
                          content: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                BlockPicker(
                                  pickerColor: themeColor,
                                  onColorChanged: (color) {
                                    profile.updateThemeColor(color);
                                    Navigator.pop(ctx);
                                  },
                                ),
                                const Divider(),
                                ListTile(
                                  leading: Icon(Icons.colorize, color: themeColor),
                                  title: Text("Custom Color", style: TextStyle(color: profile.textColor)),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor: profile.cardColor,
                                        title: const Text("Pick Custom Color"),
                                        content: SingleChildScrollView(
                                          child: ColorPicker(
                                            pickerColor: themeColor,
                                            onColorChanged: (color) => profile.updateThemeColor(color),
                                          ),
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("DONE")),
                                        ],
                                      ),
                                    );
                                  },
                                )
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    profile: profile,
                  ),
                  ProfileActionCard(
                    title: "Dark Mode",
                    subtitle: "Easier on your eyes",
                    icon: Icons.dark_mode_outlined,
                    trailing: Switch(
                      value: profile.isDarkMode,
                      activeColor: themeColor,
                      onChanged: (val) => profile.toggleDarkMode(val),
                    ),
                    onTap: () => profile.toggleDarkMode(!profile.isDarkMode),
                    profile: profile,
                  ),
                  const SizedBox(height: 24),
                  Text("DATA & LICENSE", style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 12)),
                  const SizedBox(height: 12),
                  if (!_isSysAdmin)
                  ProfileActionCard(
                    title: profile.isActivated ? "License Active" : AppStrings.activatePro,
                    subtitle: profile.isActivated 
                      ? "Expires on: ${profile.expiryDate != null ? profile.expiryDate!.toString().split(' ')[0] : 'Lifetime'}"
                      : "Unlock full features",
                    icon: Icons.vpn_key_outlined,
                    onTap: () {
                      if (!profile.isActivated) {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const ActivationScreen()));
                      }
                    },
                    profile: profile,
                  ),
                  ProfileActionCard(
                    title: "Backup & Sync",
                    subtitle: _isBackingUp ? "Backing up..." : "Secure your data offline",
                    icon: Icons.cloud_upload_outlined,
                    onTap: () => _handleBackup(profile),
                    profile: profile,
                  ),
                  ProfileActionCard(
                    title: "Restore Data",
                    subtitle: "Import from local backup",
                    icon: Icons.restore_rounded,
                    onTap: () => _handleRestore(profile),
                    profile: profile,
                  ),
                  ProfileActionCard(
                    title: "Data & Security",
                    subtitle: "Privacy policy and security settings",
                    icon: Icons.security_outlined,
                    onTap: () => _showDataSecurityPopup(profile),
                    profile: profile,
                  ),
                  ProfileActionCard(
                    title: "Services & Feedback",
                    subtitle: "Contact support or give feedback",
                    icon: Icons.feedback_outlined,
                    onTap: () => _showFeedbackPopup(profile),
                    profile: profile,
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: TextButton.icon(
                      onPressed: _confirmLogout,
                      icon: const Icon(Icons.logout, color: Colors.red),
                      label: const Text(AppStrings.logout, style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
