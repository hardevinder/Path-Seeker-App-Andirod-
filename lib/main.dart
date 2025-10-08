// File: lib/main.dart
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
// removed missing import: screens/fee_details_screen.dart
import 'screens/student_fee_screen.dart'; // <-- New: the converted fee screen
import 'screens/student_assignments_screen.dart';
import 'screens/student_timetable_screen.dart';
import 'screens/student_attendance_screen.dart';
import 'screens/student_circulars_screen.dart';
import 'screens/leave_page.dart';
import 'screens/student_diary_screen.dart'; // <-- Single-file diary screen (list + inline detail)
import 'widgets/student_app_bar.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Check login session
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken');

  runApp(StudentApp(initialRoute: token != null ? '/dashboard' : '/login'));
}

class StudentApp extends StatelessWidget {
  final String initialRoute;
  const StudentApp({super.key, required this.initialRoute});

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
        builder: (context, child) {
          // Ensure NotificationService.initialize is called once after first frame.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              NotificationService.initialize();
            } catch (e) {
              // ignore any initialization error here; optional logging can be added
            }
          });
          return child ?? const SizedBox.shrink();
        },
        routes: {
          '/login': (context) => const LoginScreen(),
          '/dashboard': (context) => const DashboardScreen(),
          '/contacts': (context) => const ContactListScreen(),
          // point fee-details to the Flutter fee screen to avoid missing file error
          '/fee-details': (context) => const StudentFeeScreen(),
          '/fees': (context) => const StudentFeeScreen(), // alternate route
          '/assignments': (context) => const StudentAssignmentsScreen(),
          '/timetable': (context) => const StudentTimetableScreen(),
          '/attendance': (context) => const StudentAttendanceScreen(),
          '/circulars': (context) => const StudentCircularsScreen(),
          '/leave': (context) => LeavePage(),
          // register both route names to be safe — dashboard uses '/student-diary'
          '/diaries': (context) => const StudentDiaryScreen(),
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

// If you already have widgets/student_app_bar.dart, keep that file and remove this class.
// This copy is safe to leave here if you want self-contained main.dart.
class StudentAppBar extends StatelessWidget implements PreferredSizeWidget {
  final BuildContext parentContext;
  final String? studentName;

  // defaultName is set to the user's name (Hardevinder Singh)
  static const String defaultName = 'Hardevinder Singh';

  const StudentAppBar({
    super.key,
    required this.parentContext,
    this.studentName,
  });

  Future<void> handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('authToken');
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
      leading: Builder(builder: (innerCtx) {
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
      }),
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
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(60);
}
