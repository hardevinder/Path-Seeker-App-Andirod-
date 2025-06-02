import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudentAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String studentName;
  final BuildContext parentContext; // ✅ Added this

  const StudentAppBar({
    super.key,
    required this.studentName,
    required this.parentContext, // ✅ Added this
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
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu, color: Colors.white, size: 26),
          onPressed: () {
            Scaffold.of(ctx).openDrawer(); // ✅ Opens Drawer from internal context
          },
        ),
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
