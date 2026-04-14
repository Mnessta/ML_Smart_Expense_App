import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../app_router.dart';
import '../utils/constants.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _showForgotPassword = false;
  bool _obscurePassword = true;
  bool _passwordVisibilityEnabled = true;
  bool _isPasswordAutoFilled = false; // Track if password is auto-filled with dots
  bool _isSettingPasswordProgrammatically = false; // Track if we're setting password programmatically

  @override
  void initState() {
    super.initState();
    // Load credentials immediately and after frame is built
    _loadSavedCredentials();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSavedCredentials();
    });
    
    // Listen to email changes to hide forgot password when email changes
    _emailController.addListener(() {
      if (_showForgotPassword) {
        setState(() {
          _showForgotPassword = false;
        });
      }
    });
    
    // Listen to password changes to detect if user is typing manually
    _passwordController.addListener(() {
      // Don't handle if we're setting it programmatically
      if (_isSettingPasswordProgrammatically) return;
      
      final String currentText = _passwordController.text;
      
      // Only handle manual typing if password was auto-filled
      if (_isPasswordAutoFilled) {
        // If user clears the field completely, keep it cleared
        if (currentText.isEmpty) {
          setState(() {
            _isPasswordAutoFilled = false;
            _passwordVisibilityEnabled = true;
          });
          return;
        }
        
        // If user is typing something different than dots, they're manually typing
        if (currentText != '••••••••' && !currentText.contains('•')) {
          setState(() {
            _isPasswordAutoFilled = false;
            _passwordVisibilityEnabled = true;
          });
        }
      }
    });
  }

  Future<void> _loadSavedCredentials() async {
    try {
      if (!mounted) return;
      
      // Only load saved email if user was previously logged in (not guest mode)
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool isGuestMode = prefs.getBool('isGuestMode') ?? false;
      
      // Only load email if not in guest mode
      if (isGuestMode) return;
      
      if (!mounted) return;
      
      // Check for saved email from multiple sources
      String? savedEmail = prefs.getString('saved_email') ?? prefs.getString('userEmail');
      
      // Try to get from AuthService if not found
      if (savedEmail == null || savedEmail.isEmpty) {
        try {
          savedEmail = await AuthService().getSavedEmail();
        } catch (e) {
          // Ignore errors
        }
      }
      
      if (savedEmail == null || savedEmail.isEmpty) return;
      if (!mounted) return;
      
      // Auto-fill email immediately
      setState(() {
        _emailController.text = savedEmail!;
      });
      
      // Wait for Supabase session to restore
      await Future.delayed(const Duration(milliseconds: 2000));
      
      if (!mounted) return;
      
      // Always auto-fill password if there's a saved email
      // This makes the UX smooth - if session exists, login will use it
      if (mounted) {
        setState(() {
          _isSettingPasswordProgrammatically = true;
        });
        
        // Set password directly
        _passwordController.text = '••••••••';
        
        setState(() {
          _isPasswordAutoFilled = true;
          _passwordVisibilityEnabled = false;
          _obscurePassword = true;
          _isSettingPasswordProgrammatically = false;
        });
      }
    } catch (e) {
      // Silently fail - don't crash the app
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final String email = _emailController.text.trim();
    String password = _passwordController.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email')),
      );
      return;
    }

    // If password was auto-filled with dots, check if user has active session
    if (_isPasswordAutoFilled && password.contains('•')) {
      // User has active session - try to use it directly
      try {
        if (AuthService().isLoggedIn) {
          // Session exists, user is already logged in - just navigate
          if (!context.mounted) return;
          context.go(AppRoutes.home);
          return;
        } else {
          // Session expired - clear auto-filled password
          if (mounted) {
            setState(() {
              _passwordController.clear();
              _isPasswordAutoFilled = false;
              _passwordVisibilityEnabled = true;
            });
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Session expired. Please enter your password')),
            );
          }
          return;
        }
      } catch (e) {
        // If Supabase check fails, clear auto-filled password and continue
        if (mounted) {
          setState(() {
            _passwordController.clear();
            _isPasswordAutoFilled = false;
            _passwordVisibilityEnabled = true;
          });
        }
      }
    }

    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your password')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await AuthService().signInWithEmail(email, password);
      
      // Save email (not password) after successful login
      await AuthService().saveEmail(email);
      
      if (!context.mounted) return;

      // Hide forgot password on successful login
      if (mounted) {
        setState(() {
          _showForgotPassword = false;
        });
      }

      // Sync data after successful login
      try {
        await SyncService().syncNow();
      } catch (e) {
        // Sync failed but login succeeded - continue
      }

      if (!context.mounted) return;
      // ignore: use_build_context_synchronously
      context.go(AppRoutes.home);
    } catch (e) {
      if (!context.mounted) return;
      String errorMessage = 'Login failed';
      bool isWrongPassword = false;

      if (e.toString().contains('user-not-found')) {
        errorMessage =
            'No account found with this email. Please sign up first.';
      } else if (e.toString().contains('wrong-password') ||
          e.toString().contains('Invalid login credentials')) {
        errorMessage = 'Incorrect password. Please try again.';
        isWrongPassword = true;
      } else if (e.toString().contains('invalid-email')) {
        errorMessage = 'Please enter a valid email address.';
      } else {
        errorMessage = 'Login failed: ${e.toString()}';
      }

      // Show forgot password link if wrong password was entered
      if (mounted) {
        setState(() {
          _showForgotPassword = isWrongPassword;
        });
      }

      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  Future<void> _forgot() async {
    if (!mounted) return;
    
    final String email = _emailController.text.trim();
    if (email.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email first')),
      );
      return;
    }

    if (mounted) {
      setState(() => _isLoading = true);
    }
    
    try {
      await AuthService().requestPasswordResetOtp(email);
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'A 6-digit reset code has been sent to $email. Enter it on the next screen.',
          ),
          duration: Duration(seconds: 5),
        ),
      );

      context.go(
        '${AppRoutes.resetPassword}?email=${Uri.encodeComponent(email)}&mode=otp',
      );
      
      // Hide the forgot password link after sending
      if (mounted) {
        setState(() {
          _showForgotPassword = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      
      String errorMessage = 'Failed to send reset code';
      if (e.toString().contains('user-not-found')) {
        errorMessage = 'No account found with this email address.';
      } else if (e.toString().contains('invalid-email')) {
        errorMessage = 'Please enter a valid email address.';
      } else {
        errorMessage = 'Failed to send reset code: ${e.toString()}';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 12),
              Text(
                'Welcome back',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                autofocus: false, // Don't autofocus to allow password auto-fill to work
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: _passwordVisibilityEnabled
                      ? IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isLoading ? null : _login,
                style:
                    ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ).merge(
                      ButtonStyle(
                        backgroundColor: WidgetStateProperty.all<Color>(
                          AppColors.primary,
                        ),
                        foregroundColor: WidgetStateProperty.all<Color>(
                          Colors.white,
                        ),
                      ),
                    ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Login'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () => context.go(AppRoutes.signup),
                child: const Text("Don't have an account? Sign up"),
              ),
              const SizedBox(height: 8),
              // Forgot Password link - always visible
              TextButton(
                onPressed: _isLoading ? null : () async {
                  if (!mounted) return;
                  final String email = _emailController.text.trim();
                  if (email.isEmpty) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter your email address first'),
                      ),
                    );
                    return;
                  }
                  // Show dialog to confirm sending reset email
                  if (!mounted) return;
                  final bool? confirm = await showDialog<bool>(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: const Text('Reset Password'),
                        content: Text(
                          'We will send a 6-digit reset code to:\n\n$email\n\nDo you want to continue?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Send Code'),
                          ),
                        ],
                      );
                    },
                  );
                  if (confirm == true && mounted) {
                    await _forgot();
                  }
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  foregroundColor: Theme.of(context).colorScheme.primary,
                ),
                child: const Text(
                  'Forgot Password?',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              // Show forgot password link only when wrong password is entered
              if (_showForgotPassword) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.orange.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Incorrect password?',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade900,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextButton(
                              onPressed: _isLoading ? null : _forgot,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Reset password via OTP',
                                style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontSize: 13,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              TextButton(
                onPressed: _isLoading
                    ? null
                      : () async {
                        final SharedPreferences prefs =
                            await SharedPreferences.getInstance();
                        await prefs.setBool('isGuestMode', true);
                        await prefs.setBool('isLoggedIn', false);
                        // Keep saved email for when user wants to log back in
                        await prefs.remove('authProvider');
                        // Clear profile photo when entering guest mode
                        // But preserve Supabase URLs so they can be restored on login
                        final String? imagePath = prefs.getString('profileImagePath');
                        
                        // Only remove if it's a local file (not a Supabase URL)
                        if (imagePath != null && imagePath.isNotEmpty) {
                          if (!imagePath.startsWith('http://') && !imagePath.startsWith('https://')) {
                            // It's a local file - remove it for guest mode
                            await prefs.remove('profileImagePath');
                            // Also delete the file if it exists
                            final file = File(imagePath);
                            if (file.existsSync()) {
                              try {
                                await file.delete();
                              } catch (_) {
                                // Ignore deletion errors
                              }
                            }
                          } else {
                            // It's a Supabase URL - keep it so it can be restored on login
                            // Don't remove it
                          }
                        }
                        // Keep profileImageUrl if it exists (it's a Supabase URL)
                        // This will be restored when user logs back in
                        if (context.mounted) {
                          context.go(AppRoutes.home);
                        }
                      },
                child: const Text('Continue as Guest'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
