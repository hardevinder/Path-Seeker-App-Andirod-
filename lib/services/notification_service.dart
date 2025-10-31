// lib/services/notification_service.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../firebase_options.dart';
import '../main.dart'; // for navigatorKey

class NotificationService {
  static bool _firebaseEnsured = false;

  /// Ensure Firebase is initialized. Safe to call multiple times.
  static Future<void> ensureFirebaseInitialized() async {
    if (_firebaseEnsured) return;

    try {
      // If any Firebase app is already initialized, mark as ensured.
      if (Firebase.apps.isNotEmpty) {
        _firebaseEnsured = true;
        debugPrint('✅ Firebase already initialized (NotificationService)');
        return;
      }

      // Initialize with generated options (flutterfire)
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      _firebaseEnsured = true;
      debugPrint('✅ Firebase initialized by NotificationService');
    } catch (e, st) {
      debugPrint('⚠️ NotificationService.ensureFirebaseInitialized failed: $e\n$st');
      // Do not rethrow — callers will handle missing Firebase gracefully.
    }
  }

  /// Initialize messaging listeners and attempt to fetch token.
  static Future<void> initialize() async {
    // Make sure Firebase exists before using any Firebase APIs.
    await ensureFirebaseInitialized();

    try {
      final messaging = FirebaseMessaging.instance;

      // Check support (some platforms may not support FCM)
      bool supported = true;
      try {
        supported = await messaging.isSupported();
      } catch (_) {
        // If isSupported fails, proceed — some older plugin versions may not implement it.
        supported = true;
      }

      if (!supported) {
        debugPrint('⚠️ Firebase Messaging not supported on this device.');
        return;
      }

      // Request runtime permission (Android 13+, iOS)
      try {
        final settings = await messaging.requestPermission();
        debugPrint('🔐 Notification permission: ${settings.authorizationStatus}');
      } catch (e) {
        debugPrint('⚠️ requestPermission failed: $e');
      }

      // Try to fetch token (with retries)
      final token = await getTokenSafe();
      if (token != null) {
        debugPrint('✅ FCM Token (initialize): $token');
        // Optionally: send token to backend here if you want
      } else {
        debugPrint('❌ FCM Token not available (initialize)');
      }

      // Foreground message handler
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('📩 Foreground Notification: ${message.notification?.title}');

        final context = navigatorKey.currentContext;
        if (context != null) {
          try {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: Text(message.notification?.title ?? 'New Message'),
                content: Text(message.notification?.body ?? ''),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          } catch (e) {
            debugPrint('⚠️ Failed to show dialog for notification: $e');
          }
        } else {
          debugPrint('⚠️ Notification received but no active context to show dialog.');
        }
      });
    } catch (e, st) {
      debugPrint('🚨 NotificationService.initialize caught: $e\n$st');
      // Swallow errors to avoid blocking app startup.
    }
  }

  /// Attempts to get an FCM token with limited retries. Returns null on failure.
  static Future<String?> getTokenSafe({int maxRetries = 4, Duration retryDelay = const Duration(seconds: 2)}) async {
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
        // If it's a SERVICE_NOT_AVAILABLE, wait and retry.
      }
      await Future.delayed(retryDelay);
    }

    debugPrint('❌ getTokenSafe: failed after $maxRetries attempts');
    return null;
  }
}
