import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';

class LocalAuthService {
  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> canCheckBiometrics() async {
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      return canAuthenticate;
    } on PlatformException catch (_) {
      return false;
    }
  }

  static Future<bool> isBiometricEnrolled() async {
    try {
      final List<BiometricType> availableBiometrics = await _auth.getAvailableBiometrics();
      return availableBiometrics.isNotEmpty;
    } on PlatformException catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate() async {
    final bool canCheck = await canCheckBiometrics();
    final bool isEnrolled = await isBiometricEnrolled();
    
    if (!canCheck || !isEnrolled) return false;

    try {
      return await _auth.authenticate(
        localizedReason: 'Authenticate to access sensitive data',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true, // Only allow biometrics, fallback handled by app PIN
        ),
      );
    } on PlatformException catch (_) {
      return false;
    }
  }
}
