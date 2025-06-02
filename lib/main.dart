import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:oktoast/oktoast.dart';

import 'firebase_options.dart';
import 'screens/wonderful_login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/contact_list_screen.dart';
import 'services/notification_service.dart';
import 'screens/fee_details_screen.dart';
import 'screens/student_assignments_screen.dart';
import 'screens/timetable_screen.dart';
import 'screens/attendance_screen.dart';
import 'screens/student_circulars_screen.dart';
import 'widgets/student_app_bar.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
        theme: ThemeData(primarySwatch: Colors.indigo),
        initialRoute: initialRoute,
        builder: (context, child) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            NotificationService.initialize();
          });
          return child!;
        },
        routes: {
          '/login': (context) => const WonderfulLoginScreen(),
          '/dashboard': (context) => const DashboardScreen(),
          '/contacts': (context) => const ContactListScreen(),
          '/fee-details': (context) => const FeeDetailsScreen(),
          '/assignments': (context) => const StudentAssignmentsScreen(),
          '/timetable': (context) => const TimeTableScreen(),
          '/attendance': (context) => const AttendanceScreen(),
          '/circulars': (context) => const StudentCircularsScreen(),
          '/chat': (context) {
            final args = ModalRoute.of(context)!.settings.arguments as Map;
            return ChatScreen(
              currentUserId: args['currentUserId'],
              contactId: args['contactId'],
              currentUserName: args['currentUserName'],
              contactName: args['contactName'],
            );
          },
        },
      ),
    );
  }
}

// ✅ Updated StudentAppBar with Drawer menu icon
typedef LogoutCallback = Future<void> Function();

class StudentAppBar extends StatelessWidget implements PreferredSizeWidget {
  final BuildContext parentContext;
  final String studentName;

  const StudentAppBar({
    super.key,
    required this.parentContext,
    required this.studentName,
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
    return AppBar(
      backgroundColor: const Color(0xFF1976D2),
      elevation: 6,
      shadowColor: Colors.black.withOpacity(0.3),
      leading: IconButton(
        icon: const Icon(Icons.menu, color: Colors.white, size: 26),
        onPressed: () {
          Scaffold.of(parentContext).openDrawer();
        },
      ),
      centerTitle: true,
      title: Text(
        'Welcome $studentName',
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
