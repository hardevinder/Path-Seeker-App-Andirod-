// lib/widgets/teacher_app_bar.dart
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'role_switcher.dart';

class TeacherAppBar extends StatelessWidget implements PreferredSizeWidget {
  final BuildContext? parentContext;
  final VoidCallback? onLogout;
  final String? teacherName;
  final String roleLabel;
  final GlobalKey<ScaffoldState>? scaffoldKey;

  const TeacherAppBar({
    super.key,
    this.parentContext,
    this.onLogout,
    this.teacherName,
    this.roleLabel = 'Teacher',
    this.scaffoldKey,
  });

  Future<void> _defaultLogout(BuildContext ctx) async {
    await ApiService.clearLocalSession();

    if (!ctx.mounted) return;

    ScaffoldMessenger.of(ctx).clearSnackBars();
    ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(
        content: Text('👋 Logged out successfully'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    Navigator.of(ctx).pushNamedAndRemoveUntil('/login', (route) => false);
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
    // Preferred: use scaffoldKey if provided
    if (scaffoldKey?.currentState != null) {
      scaffoldKey!.currentState!.openDrawer();
      return;
    }

    // Fallback: use Scaffold.maybeOf to find nearest ScaffoldState
    final scaffold = Scaffold.maybeOf(ctx);
    if (scaffold != null) {
      scaffold.openDrawer();
      return;
    }

    // Last resort: call Scaffold.of (may throw if context isn't inside a Scaffold subtree)
    try {
      Scaffold.of(ctx).openDrawer();
    } catch (_) {
      // ignore - can't open
    }
  }

  void _openEndDrawer(BuildContext ctx) {
    if (scaffoldKey?.currentState != null) {
      scaffoldKey!.currentState!.openEndDrawer();
      return;
    }
    final scaffold = Scaffold.maybeOf(ctx);
    if (scaffold != null) {
      scaffold.openEndDrawer();
      return;
    }
    try {
      Scaffold.of(ctx).openEndDrawer();
    } catch (_) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    // Display teacher name or fallback; used only for personalization if you want it later.
    final display = (teacherName ?? '').trim();
    final firstName = display.isNotEmpty ? display.split(' ').first : '';

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
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 14,
                offset: Offset(0, 6))
          ],
        ),
      ),
      titleSpacing: 0,
      centerTitle: true,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'The Pathseekers International School',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
          ),
          if (firstName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '$roleLabel • Welcome, $firstName',
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 26),
          onPressed: () => _openDrawer(ctx),
          tooltip: 'Menu',
        ),
      ),
      actions: [
        FutureBuilder<List<String>>(
          future: RoleSwitcher.loadSupportedRoles(),
          builder: (context, snapshot) {
            final roles = snapshot.data ?? const <String>[];
            if (roles.length <= 1) return const SizedBox.shrink();

            return IconButton(
              icon: const Icon(
                Icons.switch_account_rounded,
                color: Colors.white,
                size: 25,
              ),
              onPressed: () => RoleSwitcher.show(parentContext ?? context),
              tooltip: 'Switch Role',
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.notifications_rounded,
              color: Colors.white, size: 26),
          onPressed: () => _openEndDrawer(parentContext ?? context),
          tooltip: 'Notifications',
        ),
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 26),
          onPressed: () => _handleLogout(parentContext ?? context),
          tooltip: 'Logout',
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(70);
}
