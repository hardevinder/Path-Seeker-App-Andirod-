// lib/main.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:oktoast/oktoast.dart';
import 'package:http/http.dart' as http;

import 'firebase_options.dart';
import 'constants/constants.dart'; // ✅ single source of truth (LIVE baseUrl)

import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
// ❌ REMOVED: chat_screen.dart
import 'screens/contact_list_screen.dart';
import 'screens/student_fee_screen.dart';
import 'screens/student_assignments_screen.dart';
import 'screens/student_timetable_screen.dart';
import 'screens/student_attendance_screen.dart';
import 'screens/student_circulars_screen.dart';
import 'screens/leave_page.dart';
import 'screens/student_diary_screen.dart';

// teacher screens
import 'screens/teacher/teacher_dashboard.dart';
import 'screens/teacher/mark_attendance.dart';
import 'screens/teacher/teacher_circulars_screen.dart';
import 'screens/teacher/teacher_timetable_display.dart';
import 'screens/teacher/substitution_listing.dart';
import 'screens/teacher/substituted_listing.dart';
import 'screens/teacher/teacher_leave_requests.dart';
import 'screens/teacher/teacher_digital_diary_screen.dart';

import 'services/notification_service.dart';
import 'services/api_service.dart';

// NOTE: If you already have a separate file widgets/student_app_bar.dart
// and you use it elsewhere, keep that file. This main.dart doesn't need it.

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// ✅ REQUIRED: background handler (fixes "no onBackgroundMessage handler")
/// Must be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('📩 BG message id=${message.messageId} data=${message.data}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Init Firebase (required before onBackgroundMessage registration on some setups)
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    debugPrint('✅ Firebase initialized successfully');
  } catch (e, st) {
    debugPrint('❌ Firebase.initializeApp() failed: $e\n$st');
  }

  // ✅ Register background handler (fix your warning)
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  final prefs = await SharedPreferences.getInstance();

  // ✅ Force LIVE API base from constants.dart
  final String apiBase = Constants.apiBase;
  debugPrint('🌐 API Base (forced): $apiBase');

  // ✅ Set ApiService host (support both patterns)
  try {
    ApiService.baseUrl = apiBase;
  } catch (_) {
    try {
      ApiService.setBaseUrl(apiBase);
    } catch (_) {
      debugPrint(
        'ApiService: please expose static baseUrl or setBaseUrl method to set host dynamically.',
      );
    }
  }

  // ✅ Init notifications + sync token to backend
  // NotificationService should also setup foreground listeners + local notifications.
  try {
    await NotificationService.initialize(
      onToken: (fcmToken) async {
        await _persistAndSendToken(
          prefs: prefs,
          baseUrl: apiBase,
          fcmToken: fcmToken,
        );
      },
    );
  } catch (e, st) {
    debugPrint('⚠️ NotificationService.initialize() failed: $e\n$st');
  }

  final authToken = prefs.getString('authToken');
  final activeRole = (prefs.getString('activeRole') ?? '').toLowerCase();

  final initialRoute = authToken == null
      ? '/login'
      : (activeRole == 'teacher' ? '/teacher' : '/dashboard');

  runApp(StudentApp(initialRoute: initialRoute));
}

/// Save token locally + send to backend
/// ✅ Backend route: POST {baseUrl}/fcm/save-token
/// Body: { userId, fcmToken }
Future<void> _persistAndSendToken({
  required SharedPreferences prefs,
  required String baseUrl,
  required String fcmToken,
}) async {
  try {
    await prefs.setString('fcmToken', fcmToken);

    final userId = _resolveUserIdFromPrefs(prefs);

    if (userId.isEmpty) {
      debugPrint(
        '⚠️ FCM token generated but userId not found in prefs. Token saved locally only.',
      );
      return;
    }

    // ✅ IMPORTANT FIX: route matches your backend fcmRoutes
    final uri = Uri.parse(
      '${baseUrl.replaceAll(RegExp(r"/+$"), "")}/fcm/save-token',
    );

    final payload = {
      "userId": userId, // ✅ admission number preferred
      "fcmToken": fcmToken,
    };

    debugPrint('📡 Saving FCM token to backend: $uri for userId=$userId');

    final resp = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            // If your backend protects this route with JWT, uncomment:
            // 'Authorization': 'Bearer ${prefs.getString('authToken') ?? ""}',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      debugPrint('✅ FCM token saved to backend successfully');
      await prefs.setBool('fcmTokenSynced', true);
    } else {
      debugPrint(
        '⚠️ Failed to save FCM token. Status=${resp.statusCode} Body=${resp.body}',
      );
      await prefs.setBool('fcmTokenSynced', false);
    }
  } catch (e, st) {
    debugPrint('⚠️ _persistAndSendToken failed: $e\n$st');
    await prefs.setBool('fcmTokenSynced', false);
  }
}

/// Prefer admission_number (best match for diary notification mapping).
String _resolveUserIdFromPrefs(SharedPreferences prefs) {
  final candidates = <String>[
    prefs.getString('admission_number') ?? '',
    prefs.getString('admissionNumber') ?? '',
    prefs.getString('username') ?? '',
    prefs.getString('userId') ?? '',
    prefs.getString('studentId') ?? '',
  ];

  for (final v in candidates) {
    final s = v.trim();
    if (s.isNotEmpty) return s;
  }
  return '';
}

class StudentApp extends StatelessWidget {
  final String initialRoute;
  const StudentApp({Key? key, required this.initialRoute}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return OKToast(
      child: MaterialApp(
        title: Constants.appName,
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.indigo,
          scaffoldBackgroundColor: Colors.white,
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1976D2),
            foregroundColor: Colors.white,
            centerTitle: true,
          ),
        ),
        initialRoute: initialRoute,
        builder: (context, child) => child ?? const SizedBox.shrink(),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/dashboard': (context) => const DashboardScreen(),

          // Teacher
          '/teacher': (context) => const TeacherDashboard(),
          '/teacher/attendance': (context) => const MarkAttendanceScreen(),
          '/teacher/leave-requests': (context) =>
              const TeacherLeaveRequestsScreen(),
          '/teacher/circulars': (context) => const TeacherCircularsScreen(),
          '/teacher-timetable-display': (context) =>
              const TeacherTimetableDisplayScreen(),
          '/teacher/substitutions': (context) =>
              const TeacherSubstitutionListing(),
          '/teacher/substituted': (context) => const TeacherSubstitutedListing(),
          '/teacher/diary': (context) => const TeacherDigitalDiaryScreen(),

          // Student
          '/contacts': (context) => const ContactListScreen(),
          '/fee-details': (context) => const StudentFeeScreen(),
          '/fees': (context) => const StudentFeeScreen(),
          '/assignments': (context) => const StudentAssignmentsScreen(),
          '/timetable': (context) => const StudentTimetableScreen(),
          '/attendance': (context) => const StudentAttendanceScreen(),
          '/circulars': (context) => const StudentCircularsScreen(),
          '/leave': (context) => LeavePage(),
          '/diaries': (context) => const StudentDiaryScreen(),
          '/student-diary': (context) => const StudentDiaryScreen(),

          // ❌ REMOVED COMPLETELY:
          // '/chat': (context) => ChatScreen(...)
        },
        // ✅ Optional: if any old code tries to open "/chat", route it safely
        onGenerateRoute: (settings) {
          if (settings.name == '/chat') {
            return MaterialPageRoute(
              builder: (_) => const DashboardScreen(),
            );
          }
          return null;
        },
      ),
    );
  }
}

// Keeping this here only if your project still uses StudentAppBar from main.dart.
// If you already have widgets/student_app_bar.dart, you can delete this class.
class StudentAppBar extends StatelessWidget implements PreferredSizeWidget {
  final BuildContext parentContext;
  final String? studentName;
  static const String defaultName = 'Student';

  const StudentAppBar({Key? key, required this.parentContext, this.studentName})
      : super(key: key);

  Future<void> handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('authToken');
    await prefs.remove('activeRole');
    ScaffoldMessenger.of(parentContext).showSnackBar(
      const SnackBar(content: Text('👋 Logged out successfully')),
    );
    Navigator.of(parentContext).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    final displayName = (studentName == null || studentName!.trim().isEmpty)
        ? defaultName
        : studentName!;
    return AppBar(
      elevation: 6,
      shadowColor: Colors.black.withOpacity(0.3),
      leading: Builder(
        builder: (innerCtx) {
          return IconButton(
            icon: const Icon(Icons.menu, color: Colors.white, size: 26),
            onPressed: () {
              final scaffold = Scaffold.maybeOf(innerCtx);
              if (scaffold != null && scaffold.hasDrawer) {
                scaffold.openDrawer();
              } else {
                ScaffoldMessenger.of(innerCtx).showSnackBar(
                  const SnackBar(content: Text('No drawer available')),
                );
              }
            },
          );
        },
      ),
      title: Text(
        'Welcome $displayName',
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: Colors.white,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white, size: 26),
          onPressed: handleLogout,
          tooltip: 'Logout',
        )
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(60);
}
