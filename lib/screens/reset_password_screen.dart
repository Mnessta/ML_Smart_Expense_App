import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../app_router.dart';
import '../services/auth_service.dart';
import '../utils/supabase_guard.dart';
import '../utils/validators.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String? accessToken;
  final String? refreshToken;
  final String? email;
  final String? mode;

  const ResetPasswordScreen({
    super.key,
    this.accessToken,
    this.refreshToken,
    this.email,
    this.mode,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  bool _sessionInitialized = false;
  String? _userEmail;
  bool _otpVerified = false;
  bool _isOtpFlow = false;
  String? _verifiedOtp;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.email ?? '';
    _initializeSession();
  }

  Future<void> _initializeSession() async {
    _isOtpFlow = widget.mode == 'otp';
    if (!isSupabaseInitialized()) {
      setState(() {
        _userEmail = widget.email ?? _emailController.text.trim();
        _sessionInitialized = true;
      });
      return;
    }

    // Supabase automatically handles recovery sessions from URL hash
    final user = AuthService().currentUser;
    if (!_isOtpFlow &&
        user == null &&
        widget.accessToken == null &&
        widget.refreshToken == null) {
      _isOtpFlow = true;
    }
    setState(() {
      _userEmail = user?.email ?? widget.email ?? _emailController.text.trim();
      _sessionInitialized = true;
    });
  }

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    final String email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email first.')),
      );
      return;
    }
    setState(() {
      _isLoading = true;
      _verifiedOtp = null;
      _otpVerified = false;
    });
    try {
      await AuthService().requestPasswordResetOtp(email);
      if (!mounted) return;
      _otpController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('A 6-digit reset code was sent to $email.'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final String error = e.toString().toLowerCase();
      String message = 'Could not send OTP: ${e.toString()}';
      if (error.contains('no account found') ||
          error.contains('user-not-found')) {
        message = 'No account found with this email address.';
      } else if (error.contains('invalid email') ||
          error.contains('invalid-email')) {
        message = 'Please enter a valid email address.';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtp() async {
    final String email = _emailController.text.trim();
    final String otp = _otpController.text.trim();
    if (email.isEmpty || otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email and 6-digit OTP.')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final bool verified = await AuthService().verifyPasswordResetOtp(
        email: email,
        otp: otp,
      );
      if (!mounted) return;
      if (!verified) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid or expired OTP.')),
        );
        return;
      }
      setState(() {
        _otpVerified = true;
        _verifiedOtp = otp;
        _userEmail = email;
      });
      _otpController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OTP verified. You can set a new password.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final String error = e.toString().toLowerCase();
      String message = 'OTP verification failed: ${e.toString()}';
      if (error.contains('no otp found') ||
          error.contains('invalid otp') ||
          error.contains('expired')) {
        message = 'Invalid or expired OTP. Please request a new code.';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final String newPassword = _passwordController.text.trim();
    final String confirmPassword = _confirmPasswordController.text.trim();

    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match. Please try again.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isOtpFlow) {
        final String otp = _verifiedOtp ?? _otpController.text.trim();
        if (otp.isEmpty) {
          throw Exception(
            'OTP is missing. Please verify your reset code again.',
          );
        }
        await AuthService().resetPasswordWithOtp(
          email: _emailController.text.trim(),
          otp: otp,
          newPassword: newPassword,
        );
      } else {
        // Link/recovery session flow
        await AuthService().updatePasswordFromReset(newPassword);
      }

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password reset successfully! You can now login with your new password.',
          ),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate to login after a short delay
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      context.go(AppRoutes.login);
    } catch (e) {
      if (!mounted) return;
      String errorMessage = 'Failed to reset password';

      if (e.toString().contains('token') || e.toString().contains('expired')) {
        errorMessage =
            'This password reset link has expired or is invalid. Please request a new one.';
      } else {
        errorMessage = 'Failed to reset password: ${e.toString()}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          duration: const Duration(seconds: 4),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while initializing session
    if (!_sessionInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reset Password')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset Password'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.login),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Icon(
                  Icons.lock_reset,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  _isOtpFlow && !_otpVerified
                      ? 'Verify Reset Code'
                      : 'Create New Password',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _isOtpFlow && !_otpVerified
                      ? 'Enter your email and 6-digit code to continue.'
                      : _userEmail != null
                      ? 'Enter a new password for $_userEmail'
                      : widget.email != null
                      ? 'Enter a new password for ${widget.email}'
                      : 'Enter your new password below',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (_isOtpFlow && !_otpVerified) ...[
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'name@example.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '6-digit OTP',
                      hintText: '123456',
                      prefixIcon: Icon(Icons.pin_outlined),
                      counterText: '',
                    ),
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isLoading ? null : _requestOtp,
                          child: const Text('Send OTP'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _verifyOtp,
                          child: const Text('Verify OTP'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (!_isOtpFlow || _otpVerified) ...[
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      hintText: 'Enter your new password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    validator: (value) =>
                        Validators.password(value, minLength: 6),
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'Confirm New Password',
                      hintText: 'Re-enter your new password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please confirm your password';
                      }
                      if (value != _passwordController.text.trim()) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _resetPassword,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
                        : const Text(
                            'Reset Password',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ],
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => context.go(AppRoutes.login),
                  child: const Text('Back to Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
