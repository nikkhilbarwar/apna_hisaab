import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../providers/profile_provider.dart';
import 'staff_login_screen.dart';
import 'auth_wrapper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isTermsAccepted = false;

  void _showTermsDialog() {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: "Terms & Conditions",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTermItem("1. Data Retention:", "To maintain app performance, all Sales and Purchase records older than 365 days will be automatically deleted from the cloud.", profile),
          _buildTermItem("2. Privacy:", "Your business data and records are stored securely. We do not share your data with third parties.", profile),
          _buildTermItem("3. Image Storage:", "Staff and Business images are stored as encoded text within your database. High-resolution images are compressed to optimize space.", profile),
          _buildTermItem("4. User Responsibility:", "You are responsible for maintaining the confidentiality of your login credentials and ensuring the accuracy of your records.", profile),
          _buildTermItem("5. Modifications:", "Apna Hisaab reserves the right to update these terms to improve service quality.", profile),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: profile.themeColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("CLOSE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildTermItem(String title, String desc, ProfileProvider profile) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: profile.textColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            desc,
            style: TextStyle(
              fontSize: 13,
              color: profile.secondaryTextColor,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleEmailAuth() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = Provider.of<ProfileProvider>(context, listen: false);

    if (!_isTermsAccepted) {
      AppBottomSheet.showAction(
        context: context,
        profile: profile,
        title: "Terms Required",
        message: "Please accept the Terms & Conditions to proceed",
        confirmLabel: "OK",
        icon: Icons.info_outline,
      );
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        await _authService.loginWithEmail(_emailController.text.trim(), _passwordController.text.trim());
      } else {
        await _authService.registerWithEmail(_emailController.text.trim(), _passwordController.text.trim());
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const AuthWrapper()),
        );
      }
    } catch (e) {
      if (mounted) {
        String message = "An error occurred";
        if (e is FirebaseAuthException) {
          switch (e.code) {
            case 'invalid-credential':
              message = "Invalid email or password. If you deleted your account, please Register again.";
              break;
            case 'user-disabled':
              message = "This account has been disabled.";
              break;
            case 'too-many-requests':
              message = "Too many attempts. Please try again later.";
              break;
            default:
              message = e.message ?? "Authentication failed";
          }
        }
        AppBottomSheet.showAction(
          context: context,
          profile: profile,
          title: "Login Failed",
          message: message,
          confirmLabel: "RETRY",
          icon: Icons.error_outline,
          isDestructive: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    if (!_isTermsAccepted) {
      AppBottomSheet.showAction(
        context: context,
        profile: profile,
        title: "Terms Required",
        message: "Please accept the Terms & Conditions to proceed",
        confirmLabel: "OK",
        icon: Icons.info_outline,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = await _authService.signInWithGoogle();
      if (user != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const AuthWrapper()),
        );
      } else if (mounted) {
        AppBottomSheet.showAction(
          context: context,
          profile: profile,
          title: "Google Sign-In Failed",
          message: "Unable to complete Google authentication.",
          confirmLabel: "RETRY",
          icon: Icons.error_outline,
        );
      }
    } catch (e) {
      if (mounted) {
        AppBottomSheet.showAction(
          context: context,
          profile: profile,
          title: "Google Error",
          message: e.toString(),
          confirmLabel: "OK",
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showForgotPasswordDialog() {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final TextEditingController resetEmailController = TextEditingController(text: _emailController.text);

    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: "Forgot Password?",
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Enter your email address and we'll send you a link to reset your password.",
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.5),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: resetEmailController,
            decoration: InputDecoration(
              labelText: "Email Address",
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () async {
              final email = resetEmailController.text.trim();
              if (email.isEmpty || !email.contains('@')) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a valid email")));
                return;
              }
              try {
                await _authService.sendPasswordResetEmail(email);
                if (mounted) {
                  Navigator.pop(context);
                  AppBottomSheet.showAction(
                    context: context,
                    profile: profile,
                    title: "Email Sent",
                    message: "A password reset link has been sent to your email. Please check your inbox and also your SPAM folder.",
                    confirmLabel: "OK",
                    icon: Icons.mark_email_read,
                    confirmColor: Colors.green,
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error: ${e.toString().split(']').last}")),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: profile.themeColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(double.infinity, 54),
              elevation: 0,
            ),
            child: const Text("SEND RESET LINK", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "CANCEL",
              style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Provider.of<ProfileProvider>(context).themeColor;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [themeColor.withValues(alpha: 0.8), themeColor, Colors.black],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  const SizedBox(height: 30), // Reduced top margin
                  Container(
                    width: 100, // Reduced slightly to save space
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 2),
                      image: const DecorationImage(
                        image: AssetImage('assets/icon/app_icon.png'),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Apna Hisaab",
                    style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                  const Text("Your Business, Your Records, Secure.", style: TextStyle(color: Colors.white70, fontSize: 13)),
                  
                  const SizedBox(height: 30), // Reduced margin
                  
                  Card(
                    elevation: 10,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    color: Colors.white.withValues(alpha: 0.95),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            Text(
                              _isLogin ? "Welcome Back" : "Create Account",
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: themeColor),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: "Email Address",
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                              validator: (val) => val!.isEmpty || !val.contains('@') ? "Enter a valid email" : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: "Password",
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                              ),
                              validator: (val) => val!.length < 6 ? "Minimum 6 characters" : null,
                            ),
                            if (_isLogin)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _showForgotPasswordDialog,
                                  child: Text("Forgot Password?", style: TextStyle(color: themeColor, fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16.0),
                              child: Row(
                                children: [
                                  SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: Checkbox(
                                      value: _isTermsAccepted,
                                      activeColor: themeColor,
                                      onChanged: (val) => setState(() => _isTermsAccepted = val ?? false),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: _showTermsDialog,
                                      child: Text.rich(
                                        TextSpan(
                                          text: "I agree to the ",
                                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                                          children: [
                                            TextSpan(
                                              text: "Terms & Conditions",
                                              style: TextStyle(color: themeColor, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _isLoading 
                              ? CircularProgressIndicator(color: themeColor)
                              : Column(
                                  children: [
                                    ElevatedButton(
                                      onPressed: _isTermsAccepted ? _handleEmailAuth : null,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _isTermsAccepted ? themeColor : Colors.grey,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(double.infinity, 50), // Slightly reduced height
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      ),
                                      child: Text(_isLogin ? "LOGIN" : "REGISTER"),
                                    ),
                                    const SizedBox(height: 12),
                                    const Row(
                                      children: [
                                        Expanded(child: Divider()),
                                        Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                                          child: Text("OR", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                                        ),
                                        Expanded(child: Divider()),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      onPressed: _isTermsAccepted ? _handleGoogleSignIn : null,
                                      icon: Opacity(
                                        opacity: _isTermsAccepted ? 1.0 : 0.5,
                                        child: Image.network(
                                          'https://www.gstatic.com/marketing-cms/assets/images/d5/dc/cfe9ce8b4425b410b49b7f2dd3f3/g.webp=s96-fcrop64=1,00000000ffffffff-rw',
                                          height: 20,
                                        ),
                                      ),
                                      label: Text("Sign in with Google", style: TextStyle(fontSize: 13, color: _isTermsAccepted ? Colors.black87 : Colors.grey)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.black87,
                                        minimumSize: const Size(double.infinity, 50),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        side: BorderSide(color: _isTermsAccepted ? Colors.grey.shade300 : Colors.grey.shade200),
                                      ),
                                    ),
                                  ],
                                ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => setState(() => _isLogin = !_isLogin),
                              child: Text(
                                _isLogin ? "Don't have an account? Register" : "Already have an account? Login",
                                style: TextStyle(color: themeColor, fontSize: 13),
                              ),
                            ),
                            const Divider(height: 32),
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const StaffLoginScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.people_outline, size: 20),
                              label: const Text("Staff Login", style: TextStyle(fontSize: 13)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: themeColor,
                                minimumSize: const Size(double.infinity, 50),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                side: BorderSide(color: themeColor.withValues(alpha: 0.5)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text("App Developed By Nikkhil", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
