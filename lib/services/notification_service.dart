// lib/services/notification_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// If you want to send token to backend:
// import 'package:http/http.dart' as http;
// import 'dart:convert';

import '../firebase_options.dart';
import '../main.dart'; // navigatorKey

class NotificationService {
  static bool _firebaseEnsured = false;

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'high_importance_channel', // MUST match backend channelId
    'High Importance Notifications',
    description: 'Used for important notifications (Diary, Alerts)',
    importance: Importance.high,
  );

  /// Ensure Firebase is initialized. Safe to call multiple times.
  static Future<void> ensureFirebaseInitialized() async {
    if (_firebaseEnsured) return;

    try {
      if (Firebase.apps.isNotEmpty) {
        _firebaseEnsured = true;
        debugPrint('✅ Firebase already initialized (NotificationService)');
        return;
      }

      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _firebaseEnsured = true;
      debugPrint('✅ Firebase initialized by NotificationService');
    } catch (e, st) {
      debugPrint('⚠️ ensureFirebaseInitialized failed: $e\n$st');
    }
  }

  /// Call this once (e.g., in main after Firebase init).
  static Future<void> initialize({
    required Future<void> Function(String token) onToken, // ✅ pass backend save function
  }) async {
    await ensureFirebaseInitialized();

    try {
      final messaging = FirebaseMessaging.instance;

      // Support check
      bool supported = true;
      try {
        supported = await messaging.isSupported();
      } catch (_) {
        supported = true;
      }
      if (!supported) {
        debugPrint('⚠️ Firebase Messaging not supported on this device.');
        return;
      }

      // ✅ Request runtime permission (Android 13+, iOS)
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('🔐 Notification permission: ${settings.authorizationStatus}');

      // ✅ Create Android channel (recommended)
      await _initLocalNotificationsChannel();

      // ✅ Get token and save it
      final token = await getTokenSafe();
      if (token != null) {
        debugPrint('✅ FCM Token: $token');
        await onToken(token); // ✅ send to backend / save
      } else {
        debugPrint('❌ FCM Token not available');
      }

      // ✅ Handle token refresh automatically
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        debugPrint('🔄 FCM Token refreshed: $newToken');
        await onToken(newToken);
      });

      // ✅ Foreground messages → show local notification (better than dialog)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        debugPrint('📩 Foreground message: ${message.notification?.title}');
        await _showLocalNotification(message);
      });

      // ✅ When user taps notification (app in background)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('👉 Notification tapped: ${message.data}');
        _handleNotificationTap(message.data);
      });

      // ✅ When app launched from terminated by notification
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        debugPrint('🚀 Opened from terminated notification: ${initial.data}');
        _handleNotificationTap(initial.data);
      }
    } catch (e, st) {
      debugPrint('🚨 NotificationService.initialize caught: $e\n$st');
    }
  }

  static Future<void> _initLocalNotificationsChannel() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings =
        InitializationSettings(android: androidInit);

    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        // You can parse payload if you set it
      },
    );

    if (Platform.isAndroid) {
      final androidImpl = _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(_androidChannel);
    }
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final title = message.notification?.title ?? 'New Message';
    final body = message.notification?.body ?? '';

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );

    const NotificationDetails details =
        NotificationDetails(android: androidDetails);

    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }

  static void _handleNotificationTap(Map<String, dynamic> data) {
    // Example: backend sends { screen: 'DiaryScreen', diaryId: '12' }
    final screen = (data['screen'] ?? '').toString();
    final diaryId = (data['diaryId'] ?? '').toString();

    if (screen == 'DiaryScreen' && diaryId.isNotEmpty) {
      navigatorKey.currentState?.pushNamed('/diary', arguments: diaryId);
    }
  }

  /// Attempts to get an FCM token with limited retries. Returns null on failure.
  static Future<String?> getTokenSafe({
    int maxRetries = 4,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    await ensureFirebaseInitialized();

    final messaging = FirebaseMessaging.instance;
    String? token;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        token = await messaging.getToken();
        if (token != null && token.isNotEmpty) {
          debugPrint('✅ getTokenSafe success (attempt $attempt)');
          return token;
        }
      } catch (e) {
        debugPrint('⚠️ getTokenSafe attempt $attempt failed: $e');
      }
      await Future.delayed(retryDelay);
    }

    debugPrint('❌ getTokenSafe: failed after $maxRetries attempts');
    return null;
  }
}
