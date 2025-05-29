import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../main.dart'; // ⬅️ Import to access navigatorKey

class NotificationService {
  static Future<void> initialize() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // 🔐 Request permission (Android 13+ requires this)
    NotificationSettings settings = await messaging.requestPermission();
    print('🔐 Permission: ${settings.authorizationStatus}');

    // 🪪 Fetch and log the device token
    final token = await messaging.getToken();
    debugPrint("📲 FCM Token: $token");

    // 🔔 Handle messages when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("📩 Foreground Notification: ${message.notification?.title}");

      final context = navigatorKey.currentContext;

      if (context != null) {
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
      } else {
        debugPrint("❗ Notification received but no valid context for dialog.");
      }
    });
  }
}
