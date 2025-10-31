// lib/main.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:oktoast/oktoast.dart';

import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/contact_list_screen.dart';
import 'services/notification_service.dart';
import 'screens/student_fee_screen.dart';
import 'screens/student_assignments_screen.dart';
import 'screens/student_timetable_screen.dart';
import 'screens/student_attendance_screen.dart';
import 'screens/student_circulars_screen.dart';
import 'screens/leave_page.dart';
import 'screens/student_diary_screen.dart';
import 'widgets/student_app_bar.dart';

// teacher screens
import 'screens/teacher/teacher_dashboard.dart';
import 'screens/teacher/mark_attendance.dart';
import 'screens/teacher/teacher_circulars_screen.dart';
import 'screens/teacher/teacher_timetable_display.dart';
import 'screens/teacher/substitution_listing.dart';
import 'screens/teacher/substituted_listing.dart';
import 'screens/teacher/teacher_leave_requests.dart';
import 'screens/teacher/teacher_digital_diary_screen.dart';

// ApiService
import 'services/api_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Attempt Firebase initialization and remember whether it succeeded.
  var firebaseInitialized = false;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    firebaseInitialized = true;
    debugPrint('✅ Firebase initialized successfully');
  } catch (e, st) {
    // Log full error — do NOT silently swallow in development.
    debugPrint('❌ Firebase.initializeApp() failed: $e\n$st');
    // We do not rethrow here so app can still start, but we will skip FCM calls below.
    // If you want the app to fail loudly during debugging, replace the above with `rethrow`.
  }

  // Initialize NotificationService only if Firebase initialized.
  if (firebaseInitialized) {
    try {
      await NotificationService.initialize();
    } catch (e, st) {
      debugPrint('⚠️ NotificationService.initialize() failed: $e\n$st');
      // swallow - we don't want notification setup to block app startup
    }
  } else {
    debugPrint('⚠️ Skipping NotificationService.initialize() because Firebase init failed.');
  }

  // SharedPreferences and API base URL setup
  final prefs = await SharedPreferences.getInstance();
  final storedHost = prefs.getString('apiHost');

  String defaultHost;
  if (Platform.isAndroid) {
    defaultHost = 'http://10.0.2.2:7100';
  } else if (Platform.isIOS) {
    defaultHost = 'http://localhost:7100';
  } else {
    defaultHost = 'http://localhost:7100';
  }

  final baseUrl = (storedHost != null && storedHost.isNotEmpty) ? storedHost : defaultHost;

  // Try to set ApiService base url (service must expose static baseUrl or setBaseUrl)
  try {
    ApiService.baseUrl = baseUrl;
  } catch (_) {
    try {
      ApiService.setBaseUrl(baseUrl);
    } catch (_) {
      debugPrint('ApiService: please expose static baseUrl or setBaseUrl method to set host dynamically.');
    }
  }

  final token = prefs.getString('authToken');
  final activeRole = (prefs.getString('activeRole') ?? '').toLowerCase();

  final initialRoute = token == null
      ? '/login'
      : (activeRole == 'teacher' ? '/teacher' : '/dashboard');

  runApp(StudentApp(initialRoute: initialRoute));
}

class StudentApp extends StatelessWidget {
  final String initialRoute;
  const StudentApp({Key? key, required this.initialRoute}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return OKToast(
      child: MaterialApp(
        title: 'Student App',
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
        // NOTE: NotificationService is initialized in main() after Firebase init,
        // so we no longer call it here to avoid race conditions.
        builder: (context, child) {
          return child ?? const SizedBox.shrink();
        },
        routes: {
          '/login': (context) => const LoginScreen(),
          '/dashboard': (context) => const DashboardScreen(),
          '/teacher': (context) => const TeacherDashboard(),
          '/teacher/attendance': (context) => const MarkAttendanceScreen(),
          '/teacher/leave-requests': (context) => const TeacherLeaveRequestsScreen(),
          '/contacts': (context) => const ContactListScreen(),
          '/fee-details': (context) => const StudentFeeScreen(),
          '/fees': (context) => const StudentFeeScreen(),
          '/assignments': (context) => const StudentAssignmentsScreen(),
          '/timetable': (context) => const StudentTimetableScreen(),
          '/attendance': (context) => const StudentAttendanceScreen(),
          '/circulars': (context) => const StudentCircularsScreen(),
          '/view-circulars': (context) => const TeacherCircularsScreen(),
          '/teacher/circulars': (context) => const TeacherCircularsScreen(),
          '/teacher-timetable-display': (context) => const TeacherTimetableDisplayScreen(),
          '/teacher/substitutions': (context) => const TeacherSubstitutionListing(),
          '/teacher/substituted': (context) => const TeacherSubstitutedListing(),
          '/leave': (context) => LeavePage(),
          '/diaries': (context) => const StudentDiaryScreen(),
           '/teacher/diary': (context) => const TeacherDigitalDiaryScreen(), // 👈 NEW
          '/student-diary': (context) => const StudentDiaryScreen(),
          '/chat': (context) {
            final args = ModalRoute.of(context)?.settings.arguments;
            final map = (args is Map) ? args : <String, dynamic>{};
            return ChatScreen(
              currentUserId: map['currentUserId'] as String? ?? '',
              contactId: map['contactId'] as String? ?? '',
              currentUserName: map['currentUserName'] as String? ?? '',
              contactName: map['contactName'] as String? ?? '',
            );
          },
        },
      ),
    );
  }
}

class StudentAppBar extends StatelessWidget implements PreferredSizeWidget {
  final BuildContext parentContext;
  final String? studentName;
  static const String defaultName = 'Student';

  const StudentAppBar({Key? key, required this.parentContext, this.studentName}) : super(key: key);

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
    final displayName = (studentName == null || studentName!.trim().isEmpty) ? defaultName : studentName!;
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
                ScaffoldMessenger.of(innerCtx).showSnackBar(const SnackBar(content: Text('No drawer available')));
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
