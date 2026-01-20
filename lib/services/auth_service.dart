import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/logger.dart';
import '../services/db_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  bool get isInitialized => true;
  
  Stream<AuthState> get authChanges => _supabase.auth.onAuthStateChange;
  
  String? get currentUserId => _supabase.auth.currentUser?.id;
  
  User? get currentUser => _supabase.auth.currentUser;

  Future<void> signInWithEmail(String email, String password) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    
    if (response.user != null) {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      
      // Clear guest mode data before setting logged-in user data
      await _clearGuestModeData(prefs);
      
      // Store email only (not password for security)
      await prefs.setString('userEmail', email);
      await prefs.setString('saved_email', email); // Separate key for saved email
      await prefs.setBool('isLoggedIn', true);
      await prefs.setBool('isGuestMode', false); // Ensure guest mode is off
      await prefs.setString('authProvider', 'email');
    }
  }
  
  /// Clear guest mode data when logging in
  /// IMPORTANT: Only clears GUEST data, preserves logged-in user's saved data
  Future<void> _clearGuestModeData(SharedPreferences prefs) async {
    try {
      // Clear guest mode flag
      await prefs.setBool('isGuestMode', false);
      
      // Clear guest mode expenses from database (expenses with user_id = null)
      await DbService().clearGuestData();
      
      // Only clear guest profile image if it's a local file (not a Supabase URL)
      // Preserve logged-in user's profile image
      final String? imagePath = prefs.getString('profileImagePath');
      if (imagePath != null && imagePath.isNotEmpty) {
        // Only delete if it's a local file (not a URL from Supabase)
        // This means it's a guest mode image, not a logged-in user's image
        if (!imagePath.startsWith('http://') && !imagePath.startsWith('https://')) {
          try {
            final imageFile = File(imagePath);
            if (imageFile.existsSync()) {
              await imageFile.delete();
            }
            // Remove local guest image paths, but keep Supabase URLs
            await prefs.remove('profileImagePath');
          } catch (_) {
            // Ignore file deletion errors
          }
        }
        // Note: If it's a Supabase URL (starts with http/https), keep it
        // This is the logged-in user's profile image
      }
      
      // IMPORTANT: Do NOT remove userName or displayUsername
      // These are user preferences that should persist across sessions
      // They are saved by the user and should stay until the user explicitly changes them
    } catch (e, stackTrace) {
      AppLogger.e('Error clearing guest mode data: $e', e, stackTrace);
      // Continue even if clearing fails
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );
      
      // Check if signup was successful
      if (response.user == null) {
        throw Exception('Signup failed: No user was created. Please check your information and try again.');
      }
      
      // If session is null, it means email confirmation is required
      // This is normal behavior for Supabase when email confirmation is enabled
      if (response.session == null) {
        // User was created but needs to confirm email
        // Still save the email for future reference
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('userEmail', email);
        await prefs.setBool('isLoggedIn', false); // Not logged in until email confirmed
        await prefs.setString('authProvider', 'email');
        
        // Don't throw error - this is expected behavior
        // The user will need to confirm their email before logging in
        return;
      }
      
      // User is fully signed up and logged in (email confirmation disabled or already confirmed)
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      
      // Clear guest mode data before setting logged-in user data
      await _clearGuestModeData(prefs);
      
      // Store email only (not password for security)
      await prefs.setString('userEmail', email);
      await prefs.setString('saved_email', email); // Separate key for saved email
      await prefs.setBool('isLoggedIn', true);
      await prefs.setBool('isGuestMode', false); // Ensure guest mode is off
      await prefs.setString('authProvider', 'email');
    } catch (e) {
      // Re-throw the error so it can be handled by the UI
      rethrow;
    }
  }

  Future<void> sendPasswordReset(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  /// Update password from password reset token
  /// This is called when user clicks the reset link from email
  Future<void> updatePasswordFromReset(String newPassword) async {
    final UserAttributes attributes = UserAttributes(password: newPassword);
    await _supabase.auth.updateUser(attributes);
  }

  Future<void> signInWithPhone(String phone) async {
    await _supabase.auth.signInWithOtp(phone: phone);
  }

  Future<void> verifyOtp(String phone, String token) async {
    await _supabase.auth.verifyOTP(
      phone: phone,
      token: token,
      type: OtpType.sms,
    );
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('userName');
    // Keep saved_email for auto-fill on next login (password is never stored)
    await prefs.setBool('isLoggedIn', false);
    await prefs.setBool('isGuestMode', false);
    await prefs.remove('authProvider');
    
    // IMPORTANT: Do NOT remove profileImagePath or profileImageUrl
    // These should persist across logout/login so the profile image remains visible
    // The image URL is stored in Supabase user metadata and will be restored on login
  }
  
  String? getCurrentUserName() {
    final user = _supabase.auth.currentUser;
    return user?.userMetadata?['name'] as String? ?? 
           user?.email?.split('@')[0];
  }
  
  String? getCurrentUserEmail() {
    return _supabase.auth.currentUser?.email;
  }
  
  bool get isLoggedIn => _supabase.auth.currentUser != null;
  
  /// Update user profile (name and email)
  Future<void> updateProfile({
    String? name,
    String? email,
  }) async {
    final Map<String, dynamic> data = {};
    
    if (name != null) {
      data['name'] = name;
    }
    
    final UserAttributes attributes = UserAttributes(
      email: email,
      data: data.isNotEmpty ? data : null,
    );
    
    await _supabase.auth.updateUser(attributes);
    
    // Update local storage
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (name != null) {
      await prefs.setString('userName', name);
    }
    if (email != null) {
      await prefs.setString('userEmail', email);
    }
  }

  /// Change password with current-password verification
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final User? user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in to change your password.');
    }
    final String? email = user.email;
    if (email == null || email.isEmpty) {
      throw Exception('No email is associated with this account.');
    }

    // Re-authenticate with current password
    final AuthResponse response = await _supabase.auth.signInWithPassword(
      email: email,
      password: currentPassword,
    );

    if (response.user == null) {
      throw Exception('Current password is incorrect.');
    }

    // Update password
    final UserAttributes attributes = UserAttributes(password: newPassword);
    await _supabase.auth.updateUser(attributes);
  }

  /// Get user display name (from metadata or email)
  Future<String> getUserDisplayName() async {
    final user = currentUser;
    if (user != null) {
      final String? name = user.userMetadata?['name'] as String?;
      if (name != null && name.isNotEmpty) {
        return name;
      }
    }
    
    // Fallback to SharedPreferences
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? storedName = prefs.getString('userName');
    if (storedName != null && storedName.isNotEmpty) {
      return storedName;
    }
    
    // Fallback to email username
    final String? email = getCurrentUserEmail();
    if (email != null) {
      return email.split('@')[0];
    }
    
    return 'User';
  }
  
  /// Get user email (from Supabase or SharedPreferences)
  Future<String?> getUserEmail() async {
    final String? email = getCurrentUserEmail();
    if (email != null) {
      return email;
    }
    
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('userEmail');
  }
  
  /// Get saved credentials for auto-fill
  /// Save email only (not password for security)
  Future<void> saveEmail(String email) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_email', email);
      await prefs.setString('userEmail', email);
    } catch (e) {
      AppLogger.e('Error saving email: $e', e);
    }
  }

  /// Get saved email (password is never stored)
  Future<String?> getSavedEmail() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getString('saved_email') ?? prefs.getString('userEmail');
    } catch (e) {
      AppLogger.e('Error getting saved email: $e', e);
      return null;
    }
  }

  /// Legacy method - kept for compatibility but returns null for password
  /// Use getSavedEmail() instead
  @Deprecated('Use getSavedEmail() instead. Password is never stored for security.')
  Future<Map<String, String>?> getSavedCredentials() async {
    try {
      final String? email = await getSavedEmail();
      if (email != null) {
        return {
          'email': email,
          'password': '', // Password is never stored
        };
      }
      return null;
    } catch (e) {
      return null;
    }
  }
  
  /// Clear saved email (for logout)
  Future<void> clearSavedCredentials() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_email');
      // Note: Password is never stored, so nothing to clear
    } catch (e) {
      // Ignore errors when clearing
    }
  }

  /// Clear all cached sessions and authentication data
  /// This will sign out from Supabase and clear all local session data
  Future<void> clearCachedSessions() async {
    try {
      // Sign out from Supabase (clears Supabase session)
      await _supabase.auth.signOut();
      
      // Clear all SharedPreferences session data
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('userName');
      await prefs.remove('userEmail');
      await prefs.setBool('isLoggedIn', false);
      await prefs.setBool('isGuestMode', false);
      await prefs.remove('authProvider');
      // Clear saved email
      await prefs.remove('saved_email');
      
      // Note: Password is never stored in secure storage for security
      
      // Clear all secure storage keys (if any others exist)
      await _secureStorage.deleteAll();
    } catch (e, stackTrace) {
      // Log error but don't throw - try to clear as much as possible
      AppLogger.e('Error clearing cached sessions: $e', e, stackTrace);
    }
  }
}
