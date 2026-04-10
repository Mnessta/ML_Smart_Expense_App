import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';

/// Service to manage user context and data isolation
/// Handles guest mode vs logged-in user data separation
class UserContextService {
  static final UserContextService _instance = UserContextService._internal();
  factory UserContextService() => _instance;
  UserContextService._internal();

  /// Get current user ID - returns null for guest mode
  /// For logged-in users, returns Supabase user ID
  /// For guest mode, returns null
  String? getCurrentUserId() {
    return AuthService().currentUserId;
  }

  /// Check if currently in guest mode
  Future<bool> isGuestMode() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isGuestMode') ?? false;
  }

  /// Clear all guest mode data from database and SharedPreferences
  /// This should be called when user logs in
  Future<void> clearGuestData() async {
    // This will be implemented to delete guest expenses/budgets from database
    // and clear guest-specific SharedPreferences
  }

  /// Clear all logged-in user data from database
  /// This should be called when entering guest mode
  Future<void> clearLoggedInUserData() async {
    // This will be implemented to clear logged-in user's local data
    // (but keep it for when they log back in - actually, we should keep it)
    // Instead, we should just ensure queries filter properly
  }
}












