import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../services/auth_service.dart';
import '../services/profile_image_service.dart';
import '../utils/error_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _isChangingPassword = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  String? _initialName;
  String? _initialUsername;
  String? _initialEmail;
  String? _profileImagePath;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // Reload when screen appears (after navigating back from other screens)
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload profile image when screen becomes visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadUserData();
      }
    });
  }

  Future<void> _loadUserData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // Prioritize SharedPreferences name (from signup) over Supabase
    final String? userName = prefs.getString('userName');
    final String? displayUsername = prefs.getString('displayUsername');
    final String? userEmail = prefs.getString('userEmail');
    String? imagePath = prefs.getString('profileImagePath');
    String? profileImageUrl;

    // Also try to get from Supabase as fallback
    final String? supabaseName = AuthService().getCurrentUserName();
    final String? supabaseEmail = AuthService().getCurrentUserEmail();

    // Get profile image URL from Supabase user metadata (if logged in)
    // This is the source of truth - it persists across logins
    if (AuthService().isLoggedIn) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        // Get from Supabase user metadata first (primary source)
        profileImageUrl = ProfileImageService().getProfileImageUrlFromUser(
          user,
        );

        // Prioritize Supabase URL if it exists (this is the source of truth)
        if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
          // Store the URL in SharedPreferences for quick access
          await prefs.setString('profileImageUrl', profileImageUrl);
          await prefs.setString('profileImagePath', profileImageUrl);
          imagePath = profileImageUrl;
        }
      }
    }

    // If no URL from Supabase, check SharedPreferences (fallback for both logged in and logged out)
    if ((imagePath ?? '').isEmpty) {
      final String? savedUrl = prefs.getString('profileImageUrl');
      if (savedUrl != null &&
          savedUrl.isNotEmpty &&
          (savedUrl.startsWith('http://') || savedUrl.startsWith('https://'))) {
        // Use the saved URL from SharedPreferences
        imagePath = savedUrl;
        await prefs.setString('profileImagePath', savedUrl);
      }
    }

    // Final fallback: check profileImagePath in SharedPreferences
    if ((imagePath?.isEmpty ?? true) &&
        (prefs.getString('profileImagePath') != null)) {
      final String? savedPath = prefs.getString('profileImagePath');
      if (savedPath != null && savedPath.isNotEmpty) {
        // Check if it's a URL
        if (savedPath.startsWith('http://') ||
            savedPath.startsWith('https://')) {
          imagePath = savedPath;
          await prefs.setString('profileImageUrl', savedPath);
        } else {
          // It's a local file path
          imagePath = savedPath;
        }
      }
    }

    setState(() {
      // Prioritize SharedPreferences name (from signup) - this is the name entered during signup
      _initialName = userName ?? supabaseName ?? '';
      _initialUsername = displayUsername ?? '';
      _initialEmail = userEmail ?? supabaseEmail ?? '';
      _nameController.text = _initialName ?? '';
      _usernameController.text = _initialUsername ?? '';
      _emailController.text = _initialEmail ?? '';
      _profileImagePath = imagePath;
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final String newName = _nameController.text.trim();
      final String newUsername = _usernameController.text.trim();
      final String newEmail = _emailController.text.trim();
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      // Update name in SharedPreferences
      if (newName.isNotEmpty && newName != _initialName) {
        await prefs.setString('userName', newName);

        // Update in Supabase if logged in
        if (AuthService().isLoggedIn) {
          try {
            await AuthService().updateProfile(name: newName);
          } catch (e) {
            // If Supabase update fails, continue with local update
          }
        }
      }

      // Update username in SharedPreferences (used for greetings)
      if (newUsername.isNotEmpty && newUsername != _initialUsername) {
        await prefs.setString('displayUsername', newUsername);
      } else if (newUsername.isEmpty && _initialUsername != null) {
        // If username is cleared, remove it from preferences
        await prefs.remove('displayUsername');
      }

      // Update email in Supabase if changed and user is logged in
      if (newEmail.isNotEmpty &&
          newEmail != _initialEmail &&
          AuthService().isLoggedIn) {
        try {
          await AuthService().updateProfile(email: newEmail);
        } catch (e) {
          if (mounted) {
            ErrorHandler.handleError(
              context,
              e,
              customMessage: 'Failed to update email. Please try again.',
            );
            setState(() {
              _isLoading = false;
            });
            return;
          }
        }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ErrorHandler.showSuccess(context, 'Profile updated successfully');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to update profile. Please try again.',
        );
      }
    }
  }

  /// Get the appropriate image provider for the profile image
  /// Returns FileImage for local files, NetworkImage for URLs, or null
  ImageProvider? _getProfileImageProvider() {
    if (_profileImagePath != null && _profileImagePath!.isNotEmpty) {
      if (_profileImagePath!.startsWith('http://') ||
          _profileImagePath!.startsWith('https://')) {
        // URL from Supabase
        return NetworkImage(_profileImagePath!);
      } else {
        // Local file path
        final file = File(_profileImagePath!);
        if (file.existsSync()) {
          return FileImage(file);
        }
      }
    }
    return null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!AuthService().isLoggedIn) {
      if (!mounted) return;
      ErrorHandler.handleError(
        context,
        'You must be logged in to change your password.',
        customMessage: 'You must be logged in to change your password.',
      );
      return;
    }

    final String current = _currentPasswordController.text.trim();
    final String next = _newPasswordController.text.trim();
    final String confirm = _confirmPasswordController.text.trim();

    if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
      if (!mounted) return;
      ErrorHandler.handleError(
        context,
        'Please fill in all password fields.',
        customMessage: 'Please fill in all password fields.',
      );
      return;
    }
    if (next != confirm) {
      if (!mounted) return;
      ErrorHandler.handleError(
        context,
        'New passwords do not match.',
        customMessage: 'New passwords do not match.',
      );
      return;
    }
    if (next.length < 8) {
      if (!mounted) return;
      ErrorHandler.handleError(
        context,
        'Password must be at least 8 characters.',
        customMessage: 'Password must be at least 8 characters.',
      );
      return;
    }

    setState(() {
      _isChangingPassword = true;
    });

    try {
      await AuthService().changePassword(
        currentPassword: current,
        newPassword: next,
      );
      if (!mounted) return;
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      ErrorHandler.showSuccess(context, 'Password updated successfully');
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.handleError(
        context,
        e,
        customMessage:
            'Failed to change password. Please check your current password and try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isChangingPassword = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _saveProfile,
              child: const Text('Save', style: TextStyle(fontSize: 16)),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Profile Picture Section (Display Only)
            Center(
              child: CircleAvatar(
                radius: 50,
                backgroundColor: Theme.of(context).colorScheme.primary,
                backgroundImage: _getProfileImageProvider(),
                child: _getProfileImageProvider() == null
                    ? Text(
                        _nameController.text.isNotEmpty
                            ? _nameController.text[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 32),

            // Name Field
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                hintText: 'Enter your full name',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your name';
                }
                if (value.trim().length < 2) {
                  return 'Name must be at least 2 characters';
                }
                return null;
              },
              onChanged: (value) {
                setState(() {}); // Update avatar initial
              },
            ),
            const SizedBox(height: 16),

            // Username Field (for greetings)
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                hintText: 'Enter your preferred name (for greetings)',
                prefixIcon: Icon(Icons.alternate_email),
                border: OutlineInputBorder(),
                helperText:
                    'This name will be used in greetings. Leave empty to use your first name.',
              ),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value != null &&
                    value.trim().isNotEmpty &&
                    value.trim().length < 2) {
                  return 'Username must be at least 2 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Email Field
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'Enter your email',
                prefixIcon: Icon(Icons.email),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              enabled: AuthService().isLoggedIn, // Only editable if logged in
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your email';
                }
                if (!value.contains('@') || !value.contains('.')) {
                  return 'Please enter a valid email address';
                }
                return null;
              },
            ),
            if (!AuthService().isLoggedIn) ...[
              const SizedBox(height: 8),
              Text(
                'Email can only be changed when logged in',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
            const SizedBox(height: 24),
            // Info Card
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Changing your email will require verification. Make sure you have access to the new email address.',
                        style: TextStyle(fontSize: 12, color: Colors.blue[900]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Change Password Section
            if (AuthService().isLoggedIn) ...[
              Text(
                'Change Password',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _currentPasswordController,
                        decoration: InputDecoration(
                          labelText: 'Current Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureCurrentPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureCurrentPassword =
                                    !_obscureCurrentPassword;
                              });
                            },
                          ),
                        ),
                        obscureText: _obscureCurrentPassword,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _newPasswordController,
                        decoration: InputDecoration(
                          labelText: 'New Password',
                          prefixIcon: const Icon(Icons.lock),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureNewPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureNewPassword = !_obscureNewPassword;
                              });
                            },
                          ),
                        ),
                        obscureText: _obscureNewPassword,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirmPasswordController,
                        decoration: const InputDecoration(
                          labelText: 'Confirm New Password',
                          prefixIcon: Icon(Icons.lock),
                          border: OutlineInputBorder(),
                        ),
                        obscureText: _obscureNewPassword,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isChangingPassword
                              ? null
                              : _changePassword,
                          child: _isChangingPassword
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Update Password'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'Log in to change your password.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
