import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/splash_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/reset_password_screen.dart';
import 'auth_page.dart';
import 'utils/supabase_guard.dart';

class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String home = '/home';
  static const String resetPassword = '/reset-password';
}

GoRouter createRouter(GlobalKey<NavigatorState> key) {
  return GoRouter(
    navigatorKey: key,
    initialLocation: AppRoutes.splash,
    redirect: (BuildContext context, GoRouterState state) async {
      final bool isAuthenticated =
          isSupabaseInitialized() &&
          Supabase.instance.client.auth.currentUser != null;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool isGuestMode = prefs.getBool('isGuestMode') ?? false;
      
      // Allow access to auth pages without authentication
      final bool isAuthPage = state.matchedLocation == AppRoutes.login || 
                              state.matchedLocation == AppRoutes.signup ||
                              state.matchedLocation == AppRoutes.splash ||
                              state.matchedLocation == AppRoutes.resetPassword;
      
      // Don't redirect away from reset password page - allow recovery sessions
      if (state.matchedLocation == AppRoutes.resetPassword) {
        return null; // Allow access
      }
      
      // If on auth page and already authenticated (not guest), go to home
      if (isAuthPage && isAuthenticated && !isGuestMode) {
        return AppRoutes.home;
      }
      
      // If trying to access protected routes without auth (and not guest mode), redirect to login
      if (!isAuthPage && !isAuthenticated && !isGuestMode) {
        return AppRoutes.login;
      }
      
      // Allow guest mode or authenticated users to access home
      if (state.matchedLocation == AppRoutes.home && (isAuthenticated || isGuestMode)) {
        return null; // Allow access
      }
      
      return null; // No redirect needed
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        pageBuilder: (BuildContext context, GoRouterState state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SplashScreen(),
          transitionsBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (BuildContext context, GoRouterState state) => CustomTransitionPage(
          key: state.pageKey,
          child: const AuthPage(),
          transitionDuration: const Duration(milliseconds: 400),
          transitionsBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
            // Card flip animation - flips like a card (180 degrees on Y-axis) without mirroring
            return AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final double angle = animation.value * 3.14159; // 180 degrees in radians
                final bool isFlipped = animation.value > 0.5;
                
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001) // Perspective for 3D effect
                    ..rotateY(angle),
                  child: isFlipped
                      ? Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..rotateY(3.14159), // Flip back to prevent mirroring
                          child: child,
                        )
                      : child,
                );
              },
              child: child,
            );
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.signup,
        pageBuilder: (BuildContext context, GoRouterState state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SignupScreen(),
          transitionDuration: const Duration(milliseconds: 400),
          transitionsBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
            // Card flip animation - flips like a card (180 degrees on Y-axis) without mirroring
            return AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final double angle = animation.value * 3.14159; // 180 degrees in radians
                final bool isFlipped = animation.value > 0.5;
                
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001) // Perspective for 3D effect
                    ..rotateY(angle),
                  child: isFlipped
                      ? Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..rotateY(3.14159), // Flip back to prevent mirroring
                          child: child,
                        )
                      : child,
                );
              },
              child: child,
            );
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.home,
        pageBuilder: (BuildContext context, GoRouterState state) => CustomTransitionPage(
          key: state.pageKey,
          child: const HomeScreen(),
          transitionsBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
            final Animation<double> scale = Tween<double>(begin: 0.9, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic),
            );
            return ScaleTransition(scale: scale, child: FadeTransition(opacity: animation, child: child));
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        pageBuilder: (BuildContext context, GoRouterState state) {
          // Extract tokens and email from query parameters
          final accessToken = state.uri.queryParameters['access_token'];
          final refreshToken = state.uri.queryParameters['refresh_token'];
          final email = state.uri.queryParameters['email'] ?? 
                       (state.uri.queryParameters['type'] == 'recovery' 
                       ? state.uri.queryParameters['email'] 
                       : null);
          
          return CustomTransitionPage(
            key: state.pageKey,
            child: ResetPasswordScreen(
              accessToken: accessToken,
              refreshToken: refreshToken,
              email: email,
            ),
            transitionsBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
              return FadeTransition(opacity: animation, child: child);
            },
          );
        },
      ),
    ],
  );
}

class CustomTransitionPage<T> extends Page<T> {
  final Widget child;
  final Widget Function(BuildContext, Animation<double>, Animation<double>, Widget) transitionsBuilder;
  final Duration transitionDuration;

  const CustomTransitionPage({
    required super.key,
    required this.child,
    required this.transitionsBuilder,
    this.transitionDuration = const Duration(milliseconds: 300),
  });

  @override
  Route<T> createRoute(BuildContext context) {
    return PageRouteBuilder<T>(
      settings: this,
      pageBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) => child,
      transitionDuration: transitionDuration,
      transitionsBuilder: transitionsBuilder,
    );
  }
}






