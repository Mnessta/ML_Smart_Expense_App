import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as path;
import '../utils/logger.dart';
import '../utils/supabase_guard.dart';

/// Service for managing profile images with Supabase Storage
class ProfileImageService {
  static final ProfileImageService _instance = ProfileImageService._internal();
  factory ProfileImageService() => _instance;
  ProfileImageService._internal();

  static const String _bucketName = 'profile-images';
  static const String _storageFolder = 'profiles';

  SupabaseClient? get _supabase {
    if (!isSupabaseInitialized()) return null;
    return Supabase.instance.client;
  }

  /// Upload profile image to Supabase Storage
  /// Returns the public URL of the uploaded image, or null if upload fails
  Future<String?> uploadProfileImage(File imageFile, String userId) async {
    try {
      final supabase = _supabase;
      if (supabase == null) return null;

      // Check if bucket exists by trying to list it first
      try {
        await supabase.storage.from(_bucketName).list();
      } catch (e) {
        // Bucket doesn't exist - log warning and return null
        AppLogger.w('Storage bucket "$_bucketName" not found. Please create it in Supabase Dashboard. Profile image will be saved locally only.');
        return null;
      }
      
      // Generate unique filename
      final String fileName = '$userId-${DateTime.now().millisecondsSinceEpoch}${path.extension(imageFile.path)}';
      final String filePath = '$_storageFolder/$fileName';

      // Read file bytes
      final Uint8List fileBytes = await imageFile.readAsBytes();

      // Upload to Supabase Storage
      await supabase.storage
          .from(_bucketName)
          .uploadBinary(
            filePath,
            fileBytes,
            fileOptions: const FileOptions(
              upsert: true, // Replace existing file with same name
              contentType: 'image/jpeg',
            ),
          );

      // Get public URL
      final String imageUrl = supabase.storage
          .from(_bucketName)
          .getPublicUrl(filePath);

      AppLogger.i('Profile image uploaded successfully: $imageUrl');
      return imageUrl;
    } catch (e, stackTrace) {
      AppLogger.e('Error uploading profile image: $e', e, stackTrace);
      // Don't rethrow - return null so app can continue with local storage
      return null;
    }
  }

  /// Delete profile image from Supabase Storage
  Future<void> deleteProfileImage(String imageUrl) async {
    try {
      final supabase = _supabase;
      if (supabase == null) return;

      if (imageUrl.isEmpty) return;

      // Check if bucket exists
      try {
        await supabase.storage.from(_bucketName).list();
      } catch (e) {
        // Bucket doesn't exist - nothing to delete
        AppLogger.w('Storage bucket "$_bucketName" not found. Cannot delete image.');
        return;
      }

      // Extract file path from URL
      final String? filePath = _extractFilePathFromUrl(imageUrl);
      if (filePath == null) {
        AppLogger.w('Could not extract file path from URL: $imageUrl');
        return;
      }

      await supabase.storage
          .from(_bucketName)
          .remove([filePath]);

      AppLogger.i('Profile image deleted successfully');
    } catch (e, stackTrace) {
      AppLogger.e('Error deleting profile image: $e', e, stackTrace);
      // Don't rethrow - deletion failure is not critical
    }
  }

  /// Extract file path from Supabase Storage URL for deletion
  String? _extractFilePathFromUrl(String imageUrl) {
    try {
      final Uri uri = Uri.parse(imageUrl);
      // Supabase storage URLs contain the path after /storage/v1/object/public/bucket-name/
      final pathSegments = uri.pathSegments;
      final bucketIndex = pathSegments.indexOf(_bucketName);
      if (bucketIndex != -1 && bucketIndex < pathSegments.length - 1) {
        return pathSegments.sublist(bucketIndex + 1).join('/');
      }
      return null;
    } catch (e) {
      AppLogger.e('Error extracting file path from URL: $e', e);
      return null;
    }
  }

  /// Get profile image URL from user metadata
  String? getProfileImageUrlFromUser(User? user) {
    if (user == null) return null;
    return user.userMetadata?['profile_image_url'] as String?;
  }

  /// Update profile image URL in user metadata
  Future<void> updateProfileImageUrl(String imageUrl) async {
    try {
      final supabase = _supabase;
      if (supabase == null) return;

      await supabase.auth.updateUser(
        UserAttributes(
          data: {
            'profile_image_url': imageUrl,
          },
        ),
      );
      AppLogger.i('Profile image URL updated in user metadata');
    } catch (e, stackTrace) {
      AppLogger.e('Error updating profile image URL: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Clear profile image URL from user metadata
  Future<void> clearProfileImageUrl() async {
    try {
      final supabase = _supabase;
      if (supabase == null) return;

      await supabase.auth.updateUser(
        UserAttributes(
          data: {
            'profile_image_url': null,
          },
        ),
      );
      AppLogger.i('Profile image URL cleared from user metadata');
    } catch (e, stackTrace) {
      AppLogger.e('Error clearing profile image URL: $e', e, stackTrace);
      // Don't rethrow - clearing failure is not critical
    }
  }
}
