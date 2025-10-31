// lib/widgets/student_app_bar.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudentAppBar extends StatelessWidget implements PreferredSizeWidget {
  final BuildContext? parentContext;
  final VoidCallback? onLogout;
  final String title;
  final GlobalKey<ScaffoldState>? scaffoldKey; // NEW optional

  const StudentAppBar({
    super.key,
    this.parentContext,
    this.onLogout,
    this.title = "The Pathseekers International\nSchool",
    this.scaffoldKey,
  });

  Future<void> _defaultLogout(BuildContext ctx) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('authToken');
    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('👋 Logged out successfully')));
    Navigator.of(ctx).pushReplacementNamed('/login');
  }

  void _handleLogout(BuildContext ctx) {
    if (onLogout != null) {
      onLogout!();
      return;
    }
    if (parentContext != null) {
      _defaultLogout(parentContext!);
      return;
    }
    _defaultLogout(ctx);
  }

  void _openDrawer(BuildContext ctx) {
    // preferred: use scaffoldKey if provided
    if (scaffoldKey?.currentState != null) {
      scaffoldKey!.currentState!.openDrawer();
      return;
    }

    // fallback: use context (Builder ensures context is inside Scaffold subtree)
    final scaffold = Scaffold.maybeOf(ctx);
    if (scaffold != null) {
      scaffold.openDrawer();
      return;
    }

    // last resort: try Navigator context fallback (rare)
    try {
      Scaffold.of(ctx).openDrawer();
    } catch (_) {
      // fail silently; drawer will not open
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6C63FF), Color(0xFF9B8CFF), Color(0xFF6EC6FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 14, offset: Offset(0, 6))],
        ),
      ),
      titleSpacing: 0,
      centerTitle: true,
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          height: 1.18,
          shadows: [Shadow(color: Colors.black26, offset: Offset(0, 1), blurRadius: 2)],
        ),
        textAlign: TextAlign.center,
      ),
      leading: Builder(
        builder: (ctx) {
          return IconButton(
            icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 26),
            onPressed: () => _openDrawer(ctx),
            tooltip: 'Menu',
          );
        },
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 26),
          onPressed: () => _handleLogout(parentContext ?? context),
          tooltip: 'Logout',
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(70);
}
