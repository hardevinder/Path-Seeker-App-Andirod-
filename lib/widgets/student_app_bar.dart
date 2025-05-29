import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      // backgroundColor: const Color(0xFF1976D2), // Beautiful blue f6740c
      backgroundColor: const Color(0xFF1976D2), // Beautiful blue f6740c
      elevation: 6,
      shadowColor: Colors.black.withOpacity(0.3),
      leading: IconButton(
        icon: const Icon(Icons.notifications_none, color: Colors.white, size: 26),
        onPressed: () {
          Navigator.of(context).pushNamed('/notifications');
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
