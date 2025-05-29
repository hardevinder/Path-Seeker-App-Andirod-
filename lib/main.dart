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


// ✅ Global navigator key for push notification alerts
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔥 Firebase Initialization
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 🎯 Load saved login token
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken');

  runApp(StudentApp(initialRoute: token != null ? '/contacts' : '/login'));
}

class StudentApp extends StatelessWidget {
  final String initialRoute;

  const StudentApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return OKToast(
      child: MaterialApp(
        title: 'Student App',
        navigatorKey: navigatorKey, // ✅ Needed for push-based dialogs
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          scaffoldBackgroundColor: Colors.white,
        ),
        initialRoute: initialRoute,
        builder: (context, child) {
          // ✅ Initialize push notification service
          WidgetsBinding.instance.addPostFrameCallback((_) {
            NotificationService.initialize(); // No context needed
          });
          return child!;
        },
        routes: {
          '/login': (context) => const WonderfulLoginScreen(),
          '/dashboard': (context) => const DashboardScreen(),
          '/contacts': (context) => const ContactListScreen(),
          '/fee-details': (context) => const FeeDetailsScreen(),
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
