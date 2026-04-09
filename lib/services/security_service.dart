import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// Check if device supports biometric authentication
  Future<bool> isBiometricAvailable() async {
    try {
      final bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final bool isDeviceSupported = await _localAuth.isDeviceSupported();
      return canCheckBiometrics && isDeviceSupported;
    } catch (e) {
      return false;
    }
  }

  /// Check if fingerprint is specifically available
  Future<bool> isFingerprintAvailable() async {
    try {
      final List<BiometricType> availableBiometrics = await getAvailableBiometrics();
      return availableBiometrics.contains(BiometricType.fingerprint) ||
             availableBiometrics.contains(BiometricType.strong) ||
             availableBiometrics.contains(BiometricType.weak);
    } catch (e) {
      return false;
    }
  }

  /// Get available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  /// Get biometric type name for display
  Future<String> getBiometricTypeName() async {
    try {
      final List<BiometricType> available = await getAvailableBiometrics();
      if (available.contains(BiometricType.fingerprint)) {
        return 'Fingerprint';
      } else if (available.contains(BiometricType.face)) {
        return 'Face ID';
      } else if (available.contains(BiometricType.iris)) {
        return 'Iris';
      } else if (available.isNotEmpty) {
        return 'Biometric';
      }
      return 'Biometric';
    } catch (e) {
      return 'Biometric';
    }
  }

  /// Check if device has biometrics enrolled
  Future<bool> hasBiometricsEnrolled() async {
    try {
      final bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      if (!canCheckBiometrics) {
        return false;
      }
      final List<BiometricType> available = await getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Authenticate with biometrics
  Future<bool> authenticateWithBiometrics({
    String reason = 'Please authenticate to access the app',
    bool useErrorDialogs = true,
    bool stickyAuth = true,
  }) async {
    try {
      final bool isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        return false;
      }

      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          useErrorDialogs: useErrorDialogs,
          stickyAuth: stickyAuth,
          biometricOnly: true,
        ),
      );

      return didAuthenticate;
    } catch (e) {
      return false;
    }
  }

  /// Setup biometric lock - guides user through the process
  Future<Map<String, dynamic>> setupBiometricLock() async {
    try {
      // Step 1: Check if device supports biometrics
      final bool isDeviceSupported = await _localAuth.isDeviceSupported();
      if (!isDeviceSupported) {
        return {
          'success': false,
          'error': 'Your device does not support biometric authentication.',
        };
      }

      // Step 2: Check if biometrics are available
      final bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      if (!canCheckBiometrics) {
        return {
          'success': false,
          'error': 'Biometric authentication is not available on this device.',
        };
      }

      // Step 3: Check if biometrics are enrolled
      final bool hasEnrolled = await hasBiometricsEnrolled();
      if (!hasEnrolled) {
        return {
          'success': false,
          'error': 'Please set up a fingerprint or face unlock in your device settings first.',
          'needsSetup': true,
        };
      }

      // Step 4: Get biometric type
      final String biometricType = await getBiometricTypeName();
      final bool isFingerprint = await isFingerprintAvailable();

      // Step 5: Authenticate to register/enable
      final String reason = isFingerprint
          ? 'Place your finger on the fingerprint sensor to enable fingerprint lock'
          : 'Authenticate to enable ${biometricType.toLowerCase()} lock';

      final bool authenticated = await _localAuth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          useErrorDialogs: true,
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (authenticated) {
        return {
          'success': true,
          'biometricType': biometricType,
          'isFingerprint': isFingerprint,
        };
      } else {
        return {
          'success': false,
          'error': 'Authentication was cancelled or failed.',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'An error occurred: ${e.toString()}',
      };
    }
  }

  /// Check if PIN is set
  Future<bool> isPinSet() async {
    try {
      final String? pin = await _secureStorage.read(key: 'app_pin');
      return pin != null && pin.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Set PIN
  Future<bool> setPin(String pin) async {
    try {
      if (pin.length < 4) {
        return false;
      }
      await _secureStorage.write(key: 'app_pin', value: pin);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Verify PIN
  Future<bool> verifyPin(String pin) async {
    try {
      final String? storedPin = await _secureStorage.read(key: 'app_pin');
      return storedPin != null && storedPin == pin;
    } catch (e) {
      return false;
    }
  }

  /// Remove PIN
  Future<void> removePin() async {
    try {
      await _secureStorage.delete(key: 'app_pin');
    } catch (e) {
      // Ignore errors
    }
  }

  /// Check if PIN protection is enabled
  Future<bool> isPinEnabled() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool('pinEnabled') ?? false;
  }

  /// Enable/Disable PIN protection
  Future<void> setPinEnabled(bool enabled) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pinEnabled', enabled);
    if (!enabled) {
      await removePin();
    }
  }

  /// Check if biometric lock is enabled
  Future<bool> isBiometricEnabled() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool('biometricEnabled') ?? false;
  }

  /// Enable/Disable biometric lock
  Future<void> setBiometricEnabled(bool enabled) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometricEnabled', enabled);
  }

  /// Check if app should be locked (PIN only)
  Future<bool> shouldLockApp() async {
    final bool pinEnabled = await isPinEnabled();
    return pinEnabled;
  }

  /// Authenticate user (tries biometric first, then PIN if needed)
  Future<bool> authenticate() async {
    final bool biometricEnabled = await isBiometricEnabled();
    final bool pinEnabled = await isPinEnabled();

    // Try biometric first if enabled
    if (biometricEnabled) {
      final bool biometricAvailable = await isBiometricAvailable();
      if (biometricAvailable) {
        final bool authenticated = await authenticateWithBiometrics();
        if (authenticated) {
          return true;
        }
      }
    }

    // If biometric failed or not enabled, and PIN is enabled, return false
    // (PIN verification should be handled by the UI)
    if (pinEnabled) {
      return false; // PIN verification needs to be done in UI
    }

    return true; // No lock enabled
  }
}













