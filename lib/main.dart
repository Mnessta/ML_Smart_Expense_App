import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'utils/theme.dart';
import 'utils/logger.dart';
import 'app_router.dart';
import 'providers/theme_provider.dart';
import 'providers/expense_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/currency_provider.dart';
import 'services/sync_service.dart';
import 'services/db_service.dart';
import 'widgets/app_lock_wrapper.dart';
import 'config/supabase_config.dart';
import 'services/local_notification_service.dart';

final SyncService syncService = SyncService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env file
  try {
    await dotenv.load(fileName: '.env');
    AppLogger.i('Environment variables loaded successfully');
  } catch (e) {
    AppLogger.w('Warning: Could not load .env file: $e');
    AppLogger.w('Please ensure .env file exists in the project root');
    AppLogger.w('Copy .env.example to .env and update with your credentials');
    // Continue - will show configuration warning later
  }

  // Initialize Supabase
  try {
    if (!SupabaseConfig.isConfigured) {
      AppLogger.w('WARNING: ${SupabaseConfig.statusMessage}');
      AppLogger.w(
        'Please copy .env.example to .env and update with your Supabase credentials',
      );
      AppLogger.w('The app will continue but Supabase features will not work');
    } else {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
      );
      AppLogger.i('Supabase initialized successfully');
    }
  } catch (e, stackTrace) {
    AppLogger.e('Error initializing Supabase: $e', e, stackTrace);
    AppLogger.w(
      'Please check your .env file and ensure SUPABASE_URL and SUPABASE_ANON_KEY are set correctly',
    );
    AppLogger.w('The app will continue but Supabase features will not work');
    // Don't rethrow - allow app to continue without Supabase
  }

  await LocalNotificationService().initialize();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _rootKey = GlobalKey<NavigatorState>();
  late final GoRouter _router = createRouter(_rootKey);

  @override
  void initState() {
    super.initState();
    // Listen to auth state changes and start/stop sync service
    Supabase.instance.client.auth.onAuthStateChange.listen((event) async {
      if (event.event == AuthChangeEvent.passwordRecovery) {
        _router.go(AppRoutes.resetPassword);
        return;
      }

      if (event.session != null) {
        // User logged in - clear guest mode data and save preferences
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          final SharedPreferences prefs = await SharedPreferences.getInstance();

          // Clear guest mode flag and data
          await prefs.setBool('isGuestMode', false);
          await prefs.setBool('isLoggedIn', true);

          // Clear guest data from database
          try {
            await DbService().clearGuestData();
          } catch (_) {
            // Continue even if clearing fails
          }

          // Only clear guest-specific data - preserve logged-in user's saved preferences
          // Don't remove userName or displayUsername - they are user preferences that should persist

          // Determine auth provider
          final provider = user.appMetadata['provider'] as String? ?? 'email';
          await prefs.setString('authProvider', provider);

          // Save user email if available
          if (user.email != null) {
            await prefs.setString('userEmail', user.email!);
          }

          // Only update userName from Supabase if user hasn't set a custom one
          // This preserves user's custom preferences - once saved, stays saved
          final String? currentUserName = prefs.getString('userName');
          if (currentUserName == null || currentUserName.isEmpty) {
            // Only set from Supabase if user hasn't set a custom name
            final name = user.userMetadata?['name'] as String?;
            if (name != null && name.isNotEmpty) {
              await prefs.setString('userName', name);
            }
          }
          // Note: displayUsername is never overwritten - it stays until user changes it

          // Restore profile image URL from Supabase user metadata
          // This ensures the image persists across logout/login
          final String? profileImageUrl =
              user.userMetadata?['profile_image_url'] as String?;
          if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
            // Save profile image URL to SharedPreferences so it persists
            await prefs.setString('profileImageUrl', profileImageUrl);
            await prefs.setString('profileImagePath', profileImageUrl);
          } else {
            // If no URL in metadata, check if we have a saved URL in SharedPreferences
            // This handles the case where image was saved but metadata wasn't updated
            final String? savedUrl = prefs.getString('profileImageUrl');
            if (savedUrl != null &&
                savedUrl.isNotEmpty &&
                (savedUrl.startsWith('http://') ||
                    savedUrl.startsWith('https://'))) {
              // Keep the saved URL - it's still valid
              await prefs.setString('profileImagePath', savedUrl);
            }
          }
        }

        // Start sync service
        syncService.start();
        // Initial pull from server
        syncService.syncNow().catchError((e, stackTrace) {
          AppLogger.e('Initial sync error: $e', e, stackTrace);
        });
      } else {
        // User logged out - stop sync service
        syncService.dispose();
      }
    });

    // Check if user is already logged in
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser != null) {
      syncService.start();
      syncService.syncNow().catchError((e, stackTrace) {
        AppLogger.e('Initial sync error: $e', e, stackTrace);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <ChangeNotifierProvider<dynamic>>[
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<ExpenseProvider>(
          create: (_) => ExpenseProvider(),
        ),
        ChangeNotifierProvider<ConnectivityProvider>(
          create: (_) => ConnectivityProvider(),
        ),
        ChangeNotifierProvider<CurrencyProvider>(
          create: (_) => CurrencyProvider(),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder:
            (BuildContext context, ThemeProvider themeProvider, Widget? child) {
              return AppLockWrapper(
                child: MaterialApp.router(
                  key: _rootKey,
                  title: 'ML Smart Expense',
                  theme: AppTheme.light(themeProvider.accentColor),
                  darkTheme: AppTheme.dark(themeProvider.accentColor),
                  themeMode: themeProvider.themeMode,
                  routerConfig: _router,
                ),
              );
            },
      ),
    );
  }

  @override
  void dispose() {
    syncService.dispose();
    super.dispose();
  }
}
