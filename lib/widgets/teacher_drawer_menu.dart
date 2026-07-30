// lib/widgets/teacher_drawer_menu.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/role_manager.dart';
import '../services/api_service.dart';
import 'role_switcher.dart';

class TeacherDrawerMenu extends StatelessWidget {
  final String? activeRole;

  const TeacherDrawerMenu({super.key, this.activeRole});

  Future<void> _logout(BuildContext ctx) async {
    await ApiService.clearLocalSession();

    if (!ctx.mounted) return;

    Navigator.of(ctx).pop();
    Navigator.of(ctx).pushNamedAndRemoveUntil('/login', (route) => false);
    ScaffoldMessenger.of(ctx).clearSnackBars();
    ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(
        content: Text('👋 Logged out successfully'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _leadingIcon(IconData icon, Color color) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.95), color.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }

  Widget _tile({
    required BuildContext context,
    required String routeName,
    required IconData icon,
    required String title,
    Color color = const Color(0xFF6C63FF),
    String? subtitle,
    bool replaceAll = false,
    VoidCallback? extraAction,
  }) {
    final String? current = ModalRoute.of(context)?.settings.name;
    final selected = current == routeName;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: _leadingIcon(icon, color),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: selected ? Colors.deepPurple : Colors.black87,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: selected
          ? const Icon(Icons.check_circle, color: Colors.deepPurple)
          : const Icon(Icons.chevron_right_rounded),
      tileColor: selected ? Colors.deepPurple.withOpacity(0.06) : null,
      onTap: () {
        if (extraAction != null) {
          extraAction();
          return;
        }
        Navigator.of(context).pop(); // close drawer first
        if (replaceAll) {
          Navigator.of(context)
              .pushNamedAndRemoveUntil(routeName, (route) => false);
        } else {
          // avoid pushing same route again
          if (current != routeName) Navigator.of(context).pushNamed(routeName);
        }
      },
    );
  }

  Future<Map<String, String>> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('name') ??
        prefs.getString('teacherName') ??
        prefs.getString('username') ??
        'Teacher';
    final email =
        prefs.getString('email') ?? prefs.getString('teacherEmail') ?? '';
    final school = prefs.getString('schoolName') ?? '';
    final role = AppRoles.normalize(prefs.getString('activeRole'));
    return {'name': name, 'email': email, 'school': school, 'role': role};
  }

  @override
  Widget build(BuildContext context) {
    final dashboardRoute = activeRole != null
        ? AppRoles.dashboardRoute(activeRole!)
        : (ModalRoute.of(context)?.settings.name == '/coordinator')
            ? '/coordinator'
            : '/teacher';
    final isCoordinatorDrawer = activeRole == AppRoles.coordinator ||
        ModalRoute.of(context)?.settings.name == '/coordinator';
    final diaryRoute =
        isCoordinatorDrawer ? '/coordinator/digital-diary' : '/teacher/diary';
    final diaryTitle =
        isCoordinatorDrawer ? 'View Digital Diaries' : 'Digital Diary';
    final attendanceRoute = isCoordinatorDrawer
        ? '/coordinator/attendance-summary'
        : '/teacher/attendance';
    final attendanceTitle =
        isCoordinatorDrawer ? 'Attendance Summary' : 'Mark Attendance';
    final timetableRoute = isCoordinatorDrawer
        ? '/coordinator/timetable'
        : '/teacher-timetable-display';
    final substitutionsRoute = isCoordinatorDrawer
        ? '/coordinator/substitution-assignment'
        : '/teacher/substitutions';
    final circularsRoute =
        isCoordinatorDrawer ? '/coordinator/circulars' : '/teacher/circulars';
    final circularsTitle =
        isCoordinatorDrawer ? 'Circular Management' : 'Circulars';

    return Drawer(
      child: Column(
        children: [
          // Header with teacher info
          FutureBuilder<Map<String, String>>(
            future: _loadProfile(),
            builder: (ctx, snap) {
              final data = snap.data ??
                  {'name': 'Teacher Name', 'email': '', 'school': ''};
              final displayName =
                  (data['name'] ?? '').isNotEmpty ? data['name']! : 'Teacher';
              final displayEmail = (data['email'] ?? '').isNotEmpty
                  ? data['email']!
                  : 'teacher@example.com';
              final roleLabel =
                  AppRoles.label(data['role'] ?? AppRoles.teacher);

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF9B8CFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.white24,
                        child:
                            Icon(Icons.person, color: Colors.white, size: 36),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              displayEmail,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              roleLabel,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Menu items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const SizedBox(height: 8),
                _tile(
                  context: context,
                  routeName: dashboardRoute,
                  icon: Icons.dashboard_rounded,
                  title: 'Dashboard',
                  color: const Color(0xFF00C6FF),
                  replaceAll: true,
                ),
                _tile(
                  context: context,
                  routeName: '/choose-role',
                  icon: Icons.switch_account_rounded,
                  title: 'Switch Role',
                  color: const Color(0xFF111827),
                  extraAction: () => RoleSwitcher.show(context),
                ),
                _tile(
                  context: context,
                  routeName: '/my-visitors',
                  icon: Icons.badge_rounded,
                  title: 'My Visitors',
                  color: const Color(0xFF2563EB),
                ),
                _tile(
                  context: context,
                  routeName: attendanceRoute,
                  icon: Icons.check_box_outlined,
                  title: attendanceTitle,
                  color: const Color(0xFF6C63FF),
                ),
                _tile(
                  context: context,
                  routeName: '/teacher/ptm',
                  icon: Icons.groups_2_rounded,
                  title: isCoordinatorDrawer ? 'PTM Management' : 'PTM Feedback',
                  color: const Color(0xFF7C3AED),
                  subtitle: isCoordinatorDrawer
                      ? 'Class-wise PTM progress'
                      : 'Scan forms and mark attendance',
                ),
                if (isCoordinatorDrawer)
                  _tile(
                    context: context,
                    routeName: '/coordinator/students',
                    icon: Icons.school_rounded,
                    title: 'Students View',
                    color: const Color(0xFF0F766E),
                  ),
                if (isCoordinatorDrawer)
                  _tile(
                    context: context,
                    routeName: '/coordinator/academic-calendar',
                    icon: Icons.calendar_month_rounded,
                    title: 'Academic Calendar',
                    color: const Color(0xFF1D4ED8),
                  ),
                if (!isCoordinatorDrawer)
                  _tile(
                    context: context,
                    routeName: '/teacher/academic-calendar',
                    icon: Icons.calendar_month_rounded,
                    title: 'Academic Calendar',
                    color: const Color(0xFF1D4ED8),
                  ),
                _tile(
                  context: context,
                  routeName: timetableRoute,
                  icon: Icons.table_chart,
                  title: 'Timetable',
                  color: const Color(0xFF38EF7D),
                ),
                if (isCoordinatorDrawer)
                  _tile(
                    context: context,
                    routeName: '/coordinator/incharge-assignment',
                    icon: Icons.supervisor_account_rounded,
                    title: 'Incharge Assignment',
                    color: const Color(0xFF2563EB),
                  ),
                if (isCoordinatorDrawer)
                  _tile(
                    context: context,
                    routeName: '/coordinator/subjects',
                    icon: Icons.menu_book_rounded,
                    title: 'Subjects',
                    color: const Color(0xFFB45309),
                  ),
                if (isCoordinatorDrawer)
                  _tile(
                    context: context,
                    routeName: '/coordinator/syllabus-approvals',
                    icon: Icons.fact_check_rounded,
                    title: 'Syllabus Approvals',
                    color: const Color(0xFF047857),
                  ),
                _tile(
                  context: context,
                  routeName: substitutionsRoute,
                  icon: Icons.swap_horiz,
                  title: 'Substitutions',
                  color: const Color(0xFFFFA726),
                ),
                _tile(
                  context: context,
                  routeName: '/teacher/substituted',
                  icon: Icons.person_off,
                  title: 'Substituted (Me)',
                  color: const Color(0xFFEF5350),
                ),
                _tile(
                  context: context,
                  routeName: circularsRoute,
                  icon: Icons.campaign,
                  title: circularsTitle,
                  color: const Color(0xFF8E2DE2),
                ),
                _tile(
                  context: context,
                  routeName: '/teacher/leave-requests',
                  icon: Icons.beach_access,
                  title: 'Student Leave Requests',
                  color: const Color(0xFF4A90E2),
                ),
                _tile(
                  context: context,
                  routeName: '/teacher/my-leaves',
                  icon: Icons.event_note,
                  title: 'My Leave',
                  color: const Color(0xFF00BFA6),
                ),
                _tile(
                  context: context,
                  routeName: diaryRoute,
                  icon: Icons.book,
                  title: diaryTitle,
                  color: const Color(0xFF7ED957),
                ),
                _tile(
                  context: context,
                  routeName: '/teacher/messages',
                  icon: Icons.forum_rounded,
                  title: 'Messages',
                  color: const Color(0xFF9C27B0),
                ),
                _tile(
                  context: context,
                  routeName: '/teacher/marks-entry',
                  icon: Icons.edit_note_rounded,
                  title: 'Marks Entry',
                  color: const Color(0xFF2563EB),
                ),
                _tile(
                  context: context,
                  routeName: '/teacher/lesson-plan',
                  icon: Icons.menu_book_rounded,
                  title: 'Lesson Plan',
                  color: const Color(0xFF0F766E),
                ),
                _tile(
                  context: context,
                  routeName: '/teacher/library',
                  icon: Icons.local_library_rounded,
                  title: 'Library',
                  color: const Color(0xFF1D4ED8),
                  subtitle: 'Issued books & dues',
                ),
                _tile(
                  context: context,
                  routeName: '/teacher/bus-live',
                  icon: Icons.directions_bus_filled_rounded,
                  title: 'My Bus Route',
                  color: const Color(0xFF0F766E),
                  subtitle: 'Assigned route & live bus',
                ),
                _tile(
                  context: context,
                  routeName: '/my-attendance-calendar',
                  icon: Icons.calendar_today,
                  title: 'My Attendance',
                  color: const Color(0xFF4A90E2),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          // Logout & version
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _logout(context),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Logout'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
            child: Text(
              'App version 1.0.0',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
