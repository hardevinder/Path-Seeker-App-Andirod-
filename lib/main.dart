// lib/main.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:oktoast/oktoast.dart';
import 'package:http/http.dart' as http;

import 'firebase_options.dart';
import 'constants/constants.dart'; // ✅ single source of truth (LIVE baseUrl)

// auth / base screens
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart' as dashboard;

// student screens
import 'screens/contact_list_screen.dart';
import 'screens/student_fee_screen.dart';
import 'screens/student_assignments_screen.dart';
import 'screens/student_timetable_screen.dart';
import 'screens/student_attendance_screen.dart';
import 'screens/student_circulars_screen.dart';
import 'screens/leave_page.dart';
import 'screens/student_diary_screen.dart';
import 'screens/student_messages_screen.dart';

// teacher screens
import 'screens/teacher/teacher_dashboard.dart';
import 'screens/teacher/mark_attendance.dart';
import 'screens/teacher/teacher_circulars_screen.dart';
import 'screens/teacher/teacher_timetable_display.dart';
import 'screens/teacher/substitution_listing.dart';
import 'screens/teacher/substituted_listing.dart';
import 'screens/teacher/teacher_leave_requests.dart';
import 'screens/teacher/teacher_digital_diary_screen.dart';
import 'screens/teacher/teacher_messages_screen.dart';

// ✅ NEW: My Attendance Calendar screen
import 'screens/teacher/my_attendance_calendar.dart';

// ✅ NEW: Teacher self leave screen (apply + status)
import 'screens/teacher/teacher_my_leave_requests_screen.dart';

import 'services/notification_service.dart';
import 'services/api_service.dart';

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

  // ✅ Register background handler
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

  // ✅ Init notifications + sync token to backend using authenticated register-device route
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
  final activeRole =
      (prefs.getString('activeRole') ?? '').toLowerCase();

  final initialRoute = authToken == null
      ? '/login'
      : (activeRole == 'teacher' ? '/teacher' : '/dashboard');

  runApp(StudentApp(initialRoute: initialRoute));
}

/// Save token locally + send to backend
/// ✅ Backend route: POST {baseUrl}/api/notifications/register-device
/// Body: { token, platform, deviceName, systemVersion }
/// Auth: Bearer {authToken}
Future<void> _persistAndSendToken({
  required SharedPreferences prefs,
  required String baseUrl,
  required String fcmToken,
}) async {
  try {
    await prefs.setString('fcmToken', fcmToken);

    final authToken =
        prefs.getString('authToken') ?? prefs.getString('token');

    if (authToken == null || authToken.trim().isEmpty) {
      debugPrint(
        '⚠️ FCM token generated but auth token not found. Token saved locally only.',
      );
      await prefs.setBool('fcmTokenSynced', false);
      return;
    }

    final cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');

    // Constants.apiBase in your app appears to be domain/root based (not /api-prefixed)
    // so register-device should go to /api/notifications/register-device.
    final uri = Uri.parse('$cleanBase/api/notifications/register-device');

    final payload = {
      'token': fcmToken,
      'platform': Platform.isAndroid ? 'android' : 'ios',
      'deviceName': 'Student App',
      'systemVersion': Platform.operatingSystemVersion,
    };

    debugPrint('📡 Registering device token to backend: $uri');

    final resp = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $authToken',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      debugPrint('✅ Device registered successfully');
      debugPrint('register-device body: ${resp.body}');
      await prefs.setBool('fcmTokenSynced', true);
    } else {
      debugPrint(
        '⚠️ register-device failed. Status=${resp.statusCode} Body=${resp.body}',
      );
      await prefs.setBool('fcmTokenSynced', false);
    }
  } catch (e, st) {
    debugPrint('⚠️ _persistAndSendToken failed: $e\n$st');
    await prefs.setBool('fcmTokenSynced', false);
  }
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
          '/dashboard': (context) => dashboard.DashboardScreen(),

          // Teacher
          '/teacher': (context) => const TeacherDashboard(),
          '/teacher/attendance': (context) => const MarkAttendanceScreen(),

          // ✅ Teacher: approve/reject STUDENT leave requests
          '/teacher/leave-requests': (context) =>
              const TeacherLeaveRequestsScreen(),

          // ✅ Teacher: apply for OWN leave + view status
          '/teacher/my-leaves': (context) =>
              const TeacherMyLeaveRequestsScreen(),

          '/teacher/circulars': (context) => const TeacherCircularsScreen(),
          '/teacher-timetable-display': (context) =>
              const TeacherTimetableDisplayScreen(),
          '/teacher/substitutions': (context) =>
              const TeacherSubstitutionListing(),
          '/teacher/substituted': (context) =>
              const TeacherSubstitutedListing(),
          '/teacher/diary': (context) => const TeacherDigitalDiaryScreen(),
          '/teacher/messages': (context) => const TeacherMessagesScreen(),

          // ✅ NEW: My Attendance Calendar (Teacher)
          '/my-attendance-calendar': (context) =>
              const MyAttendanceCalendarScreen(),

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
          '/messages': (context) => const StudentMessagesScreen(),

          // ❌ REMOVED COMPLETELY:
          // '/chat': (context) => ChatScreen(...)
        },

        // ✅ Optional: handle old routes + notification deep-link routes safely
        onGenerateRoute: (settings) {
          int? extractThreadId(Object? args) {
            if (args is int) return args;
            if (args is String) return int.tryParse(args);
            if (args is Map) {
              final raw = args['threadId'] ?? args['thread_id'];
              return raw is int ? raw : int.tryParse('${raw ?? ''}');
            }
            return null;
          }

          if (settings.name == '/chat') {
            return MaterialPageRoute(
              builder: (_) => dashboard.DashboardScreen(),
            );
          }

          if (settings.name == '/messages/thread') {
            final threadId = extractThreadId(settings.arguments);
            return MaterialPageRoute(
              builder: (_) => StudentMessagesScreen(openThreadId: threadId),
            );
          }

          if (settings.name == '/teacher/messages/thread') {
            final threadId = extractThreadId(settings.arguments);
            return MaterialPageRoute(
              builder: (_) => TeacherMessagesScreen(openThreadId: threadId),
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