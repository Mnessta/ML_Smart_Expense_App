import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/logger.dart';
import 'ai_notification_service.dart';

class LocalNotificationService {
  LocalNotificationService._internal();

  static final LocalNotificationService _instance = LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const String _channelId = 'ai_insights_channel';
  static const String _channelName = 'AI Insights & Alerts';
  static const String _channelDescription = 'Budget alerts and smart spending insights';

  Future<void> initialize() async {
    if (_initialized) return;

    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const WindowsInitializationSettings windowsSettings =
        WindowsInitializationSettings(
          appName: 'ML Smart Expense',
          appUserModelId: 'com.mlsmartexpense.app',
          guid: '6c6a39f8-8fbb-4e4c-98f0-7e5bb4f55aa7',
        );

    final InitializationSettings settings = const InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      windows: windowsSettings,
    );

    try {
      await _plugin.initialize(settings);
      await _ensurePermissions();
      _initialized = true;
      AppLogger.i('Local notifications initialized');
    } catch (e, stackTrace) {
      AppLogger.e('Failed to initialize notifications: $e', e, stackTrace);
    }
  }

  Future<void> _ensurePermissions() async {
    if (kIsWeb) {
      return;
    }

    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImpl =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl == null) return;
      final bool? granted = await androidImpl.areNotificationsEnabled();
      if (granted == false) {
        await androidImpl.requestNotificationsPermission();
      }
    } else if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  Future<void> showNotification(NotificationMessage message) async {
    if (!_initialized) {
      await initialize();
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    final NotificationDetails details = const NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _plugin.show(
        message.hashCode & 0x7fffffff,
        message.title,
        message.message,
        details,
      );
    } catch (e, stackTrace) {
      AppLogger.e('Failed to show notification: $e', e, stackTrace);
    }
  }

  Future<void> showNotifications(List<NotificationMessage> messages) async {
    for (final NotificationMessage message in messages) {
      await showNotification(message);
    }
  }
}











