import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:io';
import '../app_router.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../widgets/password_strength_indicator.dart';
import '../widgets/glow_snake_border.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String _password = '';

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scaleAnim = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutBack,
    );
    _fadeAnim = CurvedAnimation(parent: _entryController, curve: Curves.easeIn);
    _entryController.forward();

    // Listen to password changes for strength indicator
    _passwordController.addListener(() {
      setState(() {
        _password = _passwordController.text;
      });
    });
  }

  @override
  void dispose() {
    _entryController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    final String name = _nameController.text.trim();
    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();

    setState(() => _isLoading = true);
    try {
      await AuthService().signUpWithEmail(email, password);

      // Store name if provided
      if (name.isNotEmpty) {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('userName', name);

        // Also save to Supabase user metadata if user is logged in
        if (AuthService().isLoggedIn) {
          try {
            await AuthService().updateProfile(name: name);
          } catch (e) {
            // If Supabase update fails, continue - name is already in SharedPreferences
          }
        }
      }

      if (!mounted) return;

      // Sync data after successful signup
      try {
        await SyncService().syncNow();
      } catch (e) {
        // Sync failed but signup succeeded - continue
      }

      if (!mounted) return;
      context.go(AppRoutes.home);
    } catch (e) {
      if (!mounted) return;
      String errorMessage = 'Signup failed';
      if (e.toString().contains('email-already-in-use') ||
          e.toString().contains('email already registered')) {
        errorMessage =
            'This email is already registered. Please sign in instead.';
      } else if (e.toString().contains('invalid-email')) {
        errorMessage = 'Please enter a valid email address.';
      } else if (e.toString().contains('weak-password')) {
        errorMessage =
            'Password is too weak. Please ensure it meets all requirements shown below.';
      } else {
        errorMessage = 'Signup failed: ${e.toString()}';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Use Guest Mode',
            onPressed: () async {
              if (!mounted) return;
              final SharedPreferences prefs =
                  await SharedPreferences.getInstance();
              await prefs.setBool('isGuestMode', true);
              await prefs.setBool('isLoggedIn', false);
              // Keep userEmail and savedPassword for when user wants to log back in
              await prefs.remove('authProvider');
              // Clear profile photo when entering guest mode
              // But preserve Supabase URLs so they can be restored on login
              final String? imagePath = prefs.getString('profileImagePath');

              // Only remove if it's a local file (not a Supabase URL)
              if (imagePath != null && imagePath.isNotEmpty) {
                if (!imagePath.startsWith('http://') &&
                    !imagePath.startsWith('https://')) {
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
              if (!mounted) return;
              context.go(AppRoutes.home);
            },
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF081229), Color(0xFF0A4B8C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'My Life',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.all(8.0), // Space for glow effect
              child: GlowSnakeBorder(
                glowColor: Colors.green, // Green glow color
                thickness: 5,
                borderRadius: 24,
                snakeSpeed: 5.0, // Slower snake animation
                enableRotation: true, // Slow rotation
                enablePulse: true, // Pulse effect
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    // Removed white border - only snake border will be visible
                    boxShadow: const [
                      BoxShadow(
                        blurRadius: 15,
                        spreadRadius: 2,
                        color: Colors.black26,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Transform.scale(
                      scale: 1.3,
                      child: Image.asset(
                        'assets/icon/ml251106_141948_0000.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Smart Expense',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(horizontal: 22),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            blurRadius: 25,
            color: Colors.black26,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Create Account',
              style: TextStyle(
                fontFamily: 'Times New Roman',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Sign up to track expenses',
              style: TextStyle(
                fontFamily: 'Times New Roman',
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Full Name'),
              validator: (v) =>
                  v == null || v.trim().length < 2 ? 'Enter your name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) =>
                  v != null && v.contains('@') ? null : 'Enter a valid email',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              obscureText: _obscurePassword,
              validator: (v) {
                if (v == null || v.isEmpty) {
                  return 'Password is required';
                }
                if (v.length < 8) {
                  return 'Password must be at least 8 characters';
                }
                final hasUpperCase = v.contains(RegExp(r'[A-Z]'));
                final hasLowerCase = v.contains(RegExp(r'[a-z]'));
                final hasDigits = v.contains(RegExp(r'[0-9]'));
                final hasSpecialChar = v.contains(
                  RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=~`\[\]\\/]'),
                );

                if (!hasUpperCase ||
                    !hasLowerCase ||
                    !hasDigits ||
                    !hasSpecialChar) {
                  return 'Password must meet all requirements';
                }
                return null;
              },
            ),
            PasswordStrengthIndicator(
              password: _password,
              showOnlyWhenNotEmpty: true,
            ),
            const SizedBox(height: 18),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _signup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0A6BFF),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 5,
                    ),
                    child: const Text(
                      'Sign Up',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _isLoading ? null : () => context.go(AppRoutes.login),
              child: const Text("Already have an account? Sign in"),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isLoading
                  ? null
                  : () async {
                      final SharedPreferences prefs =
                          await SharedPreferences.getInstance();
                      await prefs.setBool('isGuestMode', true);
                      await prefs.setBool('isLoggedIn', false);
                      // Keep userEmail and savedPassword for when user wants to log back in
                      await prefs.remove('authProvider');
                      // Clear profile photo when entering guest mode
                      // But preserve Supabase URLs so they can be restored on login
                      final String? imagePath = prefs.getString(
                        'profileImagePath',
                      );

                      // Only remove if it's a local file (not a Supabase URL)
                      if (imagePath != null && imagePath.isNotEmpty) {
                        if (!imagePath.startsWith('http://') &&
                            !imagePath.startsWith('https://')) {
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
                      if (!mounted) return;
                      context.go(AppRoutes.home);
                    },
              icon: const Icon(Icons.person_outline),
              label: const Text('Continue as Guest'),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF0A6BFF), width: 3.0),
                foregroundColor: const Color(0xFF0A6BFF),
                backgroundColor: const Color(0x1F0A6BFF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildLogo(),
                    const SizedBox(height: 28),
                    _buildCard(),
                    const SizedBox(height: 22),
                    const Text(
                      'By continuing, you agree to our Terms & Privacy',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    _buildSocialMediaIcons(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Could not launch URL')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  Widget _buildSocialMediaIcons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Reach us on:',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () =>
                  _launchURL('https://www.instagram.com/your_handle'),
              icon: const FaIcon(
                FontAwesomeIcons.instagram,
                color: Color(0xFFE4405F),
                size: 32,
              ),
              tooltip: 'Instagram',
            ),
            const SizedBox(width: 20),
            IconButton(
              onPressed: () => _launchURL('https://www.facebook.com/your_page'),
              icon: const FaIcon(
                FontAwesomeIcons.facebook,
                color: Color(0xFF1877F2),
                size: 32,
              ),
              tooltip: 'Facebook',
            ),
            const SizedBox(width: 20),
            IconButton(
              onPressed: () => _launchURL('https://www.x.com/your_handle'),
              icon: const FaIcon(
                FontAwesomeIcons.xTwitter,
                color: Color(0xFF000000),
                size: 32,
              ),
              tooltip: 'X',
            ),
          ],
        ),
      ],
    );
  }
}
