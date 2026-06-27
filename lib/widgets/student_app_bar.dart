// lib/widgets/student_app_bar.dart
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'role_switcher.dart';

class StudentAppBar extends StatelessWidget implements PreferredSizeWidget {
  final BuildContext? parentContext;
  final VoidCallback? onLogout;
  final String title;
  final GlobalKey<ScaffoldState>? scaffoldKey;

  const StudentAppBar({
    super.key,
    this.parentContext,
    this.onLogout,
    this.title = "The Pathseekers International\nSchool",
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

    Navigator.of(ctx).pushNamedAndRemoveUntil(
      '/login',
      (route) => false,
    );
  }

  void _handleLogout(BuildContext ctx) {
    if (onLogout != null) {
      onLogout!();
      return;
    }

    final logoutContext = parentContext ?? ctx;
    _defaultLogout(logoutContext);
  }

  void _openDrawer(BuildContext ctx) {
    if (scaffoldKey?.currentState != null) {
      scaffoldKey!.currentState!.openDrawer();
      return;
    }

    final scaffold = Scaffold.maybeOf(ctx);
    if (scaffold != null) {
      scaffold.openDrawer();
      return;
    }

    try {
      Scaffold.of(ctx).openDrawer();
    } catch (_) {
      // Drawer not available in current context
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
            colors: [
              Color(0xFF6C63FF),
              Color(0xFF9B8CFF),
              Color(0xFF6EC6FF),
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
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          height: 1.18,
          shadows: [
            Shadow(
              color: Colors.black26,
              offset: Offset(0, 1),
              blurRadius: 2,
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
      leading: Builder(
        builder: (ctx) {
          return IconButton(
            icon: const Icon(
              Icons.menu_rounded,
              color: Colors.white,
              size: 26,
            ),
            onPressed: () => _openDrawer(ctx),
            tooltip: 'Menu',
          );
        },
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
          icon: const Icon(
            Icons.logout_rounded,
            color: Colors.white,
            size: 26,
          ),
          onPressed: () => _handleLogout(parentContext ?? context),
          tooltip: 'Logout',
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(70);
}
