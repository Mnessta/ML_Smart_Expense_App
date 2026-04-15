import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'app_router.dart';
import 'services/auth_service.dart';
import 'widgets/password_strength_indicator.dart';
import 'widgets/glow_snake_border.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with TickerProviderStateMixin {
  late final AnimationController _entryController;

  late final Animation<double> _scaleAnim;

  late final Animation<double> _fadeAnim;
  late final AnimationController _buttonPulseController;

  // Always in login mode - signup is accessed through separate route
  final bool _isLogin = true;

  bool _loading = false;
  bool _isPasswordAutoFilled = false;
  final FocusNode _passwordFocusNode = FocusNode();

  bool _obscurePassword = true;

  String _password = '';

  final _formKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();

  final _passCtrl = TextEditingController();

  final _nameCtrl = TextEditingController();

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
    _buttonPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    // Listen to password changes for strength indicator
    _passCtrl.addListener(() {
      setState(() {
        _password = _passCtrl.text;
      });
    });

    _passwordFocusNode.addListener(() {
      if (_passwordFocusNode.hasFocus && _isPasswordAutoFilled) {
        setState(() {
          _isPasswordAutoFilled = false;
          _passCtrl.clear();
          _obscurePassword = true;
        });
      }
    });

    // Load saved credentials for auto-fill
    _loadSavedCredentials();
  }

  /// Load saved email and auto-fill password if session exists
  Future<void> _loadSavedCredentials() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool isGuestMode = prefs.getBool('isGuestMode') ?? false;
      final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

      if (isGuestMode) return;

      final String? savedEmail = await AuthService().getSavedEmail();
      if (savedEmail != null && savedEmail.isNotEmpty && mounted) {
        setState(() {
          _emailCtrl.text = savedEmail;
        });

        // Wait a bit for Supabase session to restore
        await Future.delayed(const Duration(milliseconds: 300));

        // Check if user is marked as logged in or has an active auth state
        if ((isLoggedIn || AuthService().isLoggedIn) && mounted) {
          // User has an active session - auto-fill password with masked dots
          setState(() {
            _passCtrl.text = '••••••••'; // Fake masked password
            _password = '••••••••';
            _obscurePassword = true;
            _isPasswordAutoFilled = true;
          });
        }
      }
    } catch (e) {
      // Silently fail if credentials can't be loaded
    }
  }

  @override
  void dispose() {
    _entryController.dispose();
    _buttonPulseController.dispose();
    _passwordFocusNode.dispose();

    _emailCtrl.dispose();

    _passCtrl.dispose();

    _nameCtrl.dispose();

    super.dispose();
  }

  Future<void> _onSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final String email = _emailCtrl.text.trim();
      final String password = _passCtrl.text.trim();

      if (_isPasswordAutoFilled && password == '••••••••') {
        if (AuthService().isLoggedIn) {
          if (!mounted) return;
          setState(() => _loading = false);
          context.go(AppRoutes.home);
          return;
        }

        if (!mounted) return;
        setState(() {
          _loading = false;
          _isPasswordAutoFilled = false;
          _passCtrl.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session expired. Please enter your password.'),
          ),
        );
        return;
      }

      if (_isLogin) {
        // Login existing user
        await AuthService().signInWithEmail(email, password);

        // Clear guest mode flag when user authenticates
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isGuestMode', false);

        if (!mounted) return;

        setState(() => _loading = false);
        // ignore: use_build_context_synchronously
        context.go(AppRoutes.home);
      } else {
        // Sign up new user
        await AuthService().signUpWithEmail(email, password);

        // Store name if provided
        if (_nameCtrl.text.isNotEmpty) {
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setString('userName', _nameCtrl.text.trim());
        }

        // Check if user needs to confirm email
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

        if (!mounted) return;

        setState(() => _loading = false);

        if (!isLoggedIn) {
          // Email confirmation required
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Account created! Please check your email to confirm your account before signing in.',
              ),
              duration: Duration(seconds: 6),
            ),
          );
          // Stay on auth page for user to sign in after confirming email
          return;
        }

        // User is fully signed up and logged in
        await prefs.setBool('isGuestMode', false);
        // ignore: use_build_context_synchronously
        context.go(AppRoutes.home);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);

      String errorMessage = _getErrorMessage(e, _isLogin);

      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(label: 'OK', onPressed: () {}),
        ),
      );
    }
  }

  Future<void> _sendPasswordReset() async {
    final String email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email address first.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await AuthService().requestPasswordResetOtp(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('A 6-digit reset code was sent to $email.'),
          duration: const Duration(seconds: 5),
        ),
      );
      context.go(
        '${AppRoutes.resetPassword}?email=${Uri.encodeComponent(email)}&mode=otp',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not send reset email: ${e.toString()}'),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _getErrorMessage(dynamic error, bool isLogin) {
    final String errorString = error.toString().toLowerCase();

    // Check for Supabase AuthApiException
    if (errorString.contains('authapiexception') ||
        errorString.contains('auth_api_exception')) {
      // Extract the actual error message from Supabase
      if (errorString.contains('email already registered') ||
          errorString.contains('email-already-in-use') ||
          errorString.contains('user already registered')) {
        return 'This email is already registered. Please sign in instead.';
      }
      if (errorString.contains('invalid email') ||
          errorString.contains('invalid-email')) {
        return 'Please enter a valid email address.';
      }
      if (errorString.contains('password') &&
          (errorString.contains('weak') || errorString.contains('too short'))) {
        return 'Password is too weak. Please ensure it meets all requirements shown below.';
      }
      if (errorString.contains('user not found') ||
          errorString.contains('user-not-found')) {
        return isLogin
            ? 'No account found with this email. Please sign up first.'
            : 'Signup failed. Please try again.';
      }
      if (errorString.contains('wrong password') ||
          errorString.contains('wrong-password') ||
          errorString.contains('invalid login')) {
        return 'Incorrect password. Please try again.';
      }
      if (errorString.contains('network') ||
          errorString.contains('connection')) {
        return 'Network error. Please check your internet connection and try again.';
      }
      if (errorString.contains('timeout')) {
        return 'Request timed out. Please check your connection and try again.';
      }
      // Try to extract the actual error message
      final match = RegExp(
        r'message[:\s]+([^,}]+)',
        caseSensitive: false,
      ).firstMatch(errorString);
      if (match != null) {
        return match.group(1)?.trim() ?? 'Signup failed. Please try again.';
      }
    }

    // Generic error patterns
    if (errorString.contains('email-already-in-use') ||
        errorString.contains('email already registered')) {
      return 'This email is already registered. Please sign in instead.';
    }
    if (errorString.contains('invalid-email') ||
        errorString.contains('invalid email')) {
      return 'Please enter a valid email address.';
    }
    if (errorString.contains('weak-password') ||
        (errorString.contains('password') && errorString.contains('weak'))) {
      return 'Password is too weak. Please ensure it meets all requirements shown below.';
    }
    if (errorString.contains('user-not-found')) {
      return isLogin
          ? 'No account found with this email. Please sign up first.'
          : 'Signup failed. Please try again.';
    }
    if (errorString.contains('wrong-password') ||
        errorString.contains('invalid login')) {
      return 'Incorrect password. Please try again.';
    }
    if (errorString.contains('network') || errorString.contains('connection')) {
      return 'Network error. Please check your internet connection and try again.';
    }

    // Show the actual error for debugging (in development)
    // In production, you might want to log this and show a generic message
    return isLogin
        ? 'Login failed: ${error.toString()}'
        : 'Signup failed: ${error.toString()}';
  }

  void _continueAsGuest() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isGuestMode', true);
    await prefs.setBool('isLoggedIn', false);
    await prefs.remove('userEmail');
    await prefs.remove('authProvider');

    if (mounted) {
      context.go(AppRoutes.home);
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
                fontFamily: 'Times New Roman',
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
                fontFamily: 'Times New Roman',
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

  Widget _buildCard(bool login) {
    final bool isLogin = login;

    final String title = isLogin ? "Welcome Back" : "Create Account";

    final String subtitle = isLogin
        ? "Login to continue"
        : "Sign up to track expenses";

    final String actionLabel = isLogin ? "Login" : "Sign Up";

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
            Text(
              title,

              style: const TextStyle(
                fontFamily: 'Times New Roman',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              subtitle,

              style: const TextStyle(
                fontFamily: 'Times New Roman',
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),

            const SizedBox(height: 18),

            if (!isLogin)
              TextFormField(
                controller: _nameCtrl,

                decoration: const InputDecoration(labelText: "Full Name"),

                validator: (v) =>
                    v == null || v.trim().length < 2 ? "Enter your name" : null,
              ),

            if (!isLogin) const SizedBox(height: 12),

            TextFormField(
              controller: _emailCtrl,

              decoration: const InputDecoration(labelText: "Email"),

              validator: (v) =>
                  v != null && v.contains("@") ? null : "Enter a valid email",
            ),

            const SizedBox(height: 12),

            TextFormField(
              focusNode: _passwordFocusNode,
              controller: _passCtrl,

              decoration: InputDecoration(
                labelText: "Password",
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
                  return "Password is required";
                }
                if (isLogin) {
                  // For login, just check minimum length
                  return v.length >= 6 ? null : "Min 6 characters";
                } else {
                  // For signup, check all requirements
                  if (v.length < 8) {
                    return "Password must be at least 8 characters";
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
                    return "Password must meet all requirements";
                  }
                  return null;
                }
              },
            ),

            // Show password strength indicator only during signup
            if (!isLogin)
              PasswordStrengthIndicator(
                password: _password,
                showOnlyWhenNotEmpty: true,
              ),

            const SizedBox(height: 18),

            _loading
                ? const CircularProgressIndicator()
                : AnimatedBuilder(
                    animation: _buttonPulseController,
                    builder: (context, child) {
                      final double pulseScale =
                          1 + (_buttonPulseController.value * 0.04);
                      final double glowOpacity =
                          0.35 + (_buttonPulseController.value * 0.4);
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF0A6BFF,
                              ).withValues(alpha: glowOpacity),
                              blurRadius:
                                  24 + (_buttonPulseController.value * 12),
                              spreadRadius:
                                  1 + (_buttonPulseController.value * 3),
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Transform.scale(
                          scale: pulseScale,
                          child: ElevatedButton(
                            onPressed: _onSubmit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0A6BFF),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 6,
                            ),
                            child: Text(
                              actionLabel,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

            const SizedBox(height: 12),

            OutlinedButton(
              onPressed: _loading ? null : () => context.go(AppRoutes.signup),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF0A6BFF), width: 3.0),
                foregroundColor: const Color(0xFF0A6BFF),
                backgroundColor: const Color(0x1F0A6BFF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(double.infinity, 52),
              ),
              child: const Text("Don't have an account? Sign up"),
            ),

            const SizedBox(height: 12),

            OutlinedButton(
              onPressed: _loading
                  ? null
                  : () async {
                      final String email = _emailCtrl.text.trim();
                      final bool? confirm = await showDialog<bool>(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            title: const Text('Reset Password'),
                            content: Text(
                              email.isEmpty
                                  ? 'Enter your registered email, then tap Forgot Password again to receive a 6-digit reset code.'
                                  : 'Send a 6-digit password reset code to:\n\n$email',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text('Send Code'),
                              ),
                            ],
                          );
                        },
                      );
                      if (confirm == true && mounted) {
                        await _sendPasswordReset();
                      }
                    },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF0A6BFF), width: 3.0),
                foregroundColor: const Color(0xFF0A6BFF),
                backgroundColor: const Color(0x1F0A6BFF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(double.infinity, 52),
              ),
              child: const Text('Forgot Password?'),
            ),

            const SizedBox(height: 12),

            OutlinedButton.icon(
              onPressed: _continueAsGuest,
              icon: const Icon(Icons.person_outline),
              label: const Text("Continue as Guest"),
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
      backgroundColor: Colors.transparent,

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

                    _buildCard(true), // Always show login card

                    const SizedBox(height: 22),

                    const Text(
                      "By continuing, you agree to our Terms & Privacy",

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
            _buildSnakeIconButton(
              color: const Color(0xFFE4405F),
              tooltip: 'Instagram',
              icon: FontAwesomeIcons.instagram,
              onTap: () => _launchURL('https://www.instagram.com/your_handle'),
            ),
            const SizedBox(width: 24),
            _buildSnakeIconButton(
              color: const Color(0xFF1877F2),
              tooltip: 'Facebook',
              icon: FontAwesomeIcons.facebook,
              onTap: () => _launchURL('https://www.facebook.com/your_page'),
            ),
            const SizedBox(width: 24),
            _buildSnakeIconButton(
              color: Colors.black,
              tooltip: 'X',
              icon: FontAwesomeIcons.xTwitter,
              onTap: () => _launchURL('https://www.x.com/your_handle'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSnakeIconButton({
    required FaIconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 60,
      height: 60,
      child: GlowSnakeBorder(
        glowColor: color.withValues(alpha: 0.95),
        thickness: 4,
        borderRadius: 30,
        snakeSpeed: 2,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          child: Tooltip(
            message: tooltip,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.25),
                    color.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 10,
                    spreadRadius: 1,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: onTap,
                icon: FaIcon(icon, color: color, size: 28),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
