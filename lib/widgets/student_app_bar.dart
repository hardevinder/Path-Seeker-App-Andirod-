// lib/widgets/student_app_bar.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudentAppBar extends StatelessWidget implements PreferredSizeWidget {
  final BuildContext parentContext;

  const StudentAppBar({
    super.key,
    required this.parentContext,
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
      automaticallyImplyLeading: false,
      // keep the AppBar itself transparent and paint with flexibleSpace gradient
      backgroundColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF6C63FF), // purple
              Color(0xFF9B8CFF), // lighter purple
              Color(0xFF6EC6FF), // soft cyan accent (subtle)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
      ),
      titleSpacing: 0,
      centerTitle: true,
      title: const Text(
        "The Pathseekers International\nSchool",
        style: TextStyle(
          color: Colors.white,
          fontSize: 16.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          height: 1.18,
          shadows: [
            Shadow(color: Colors.black26, offset: Offset(0, 1), blurRadius: 2)
          ],
        ),
        textAlign: TextAlign.center,
      ),
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 26),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
          tooltip: 'Menu',
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 26),
          onPressed: handleLogout,
          tooltip: 'Logout',
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(70);
}
