// lib/widgets/teacher_drawer_menu.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TeacherDrawerMenu extends StatelessWidget {
  const TeacherDrawerMenu({super.key});

  Future<void> _logout(BuildContext ctx) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('authToken');
    await prefs.remove('activeRole');
    // close drawer first
    Navigator.of(ctx).pop();
    // then navigate to login and remove all previous routes
    Navigator.of(ctx).pushNamedAndRemoveUntil('/login', (route) => false);
    ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(content: Text('👋 Logged out successfully')),
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
        Navigator.of(context).pop(); // close drawer first
        if (extraAction != null) extraAction();
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
    return {'name': name, 'email': email, 'school': school};
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          // Header with teacher info
          FutureBuilder<Map<String, String>>(
            future: _loadProfile(),
            builder: (ctx, snap) {
              final data =
                  snap.data ?? {'name': 'Teacher Name', 'email': '', 'school': ''};
              final displayName =
                  (data['name'] ?? '').isNotEmpty ? data['name']! : 'Teacher';
              final displayEmail = (data['email'] ?? '').isNotEmpty
                  ? data['email']!
                  : 'teacher@example.com';

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
                        child: Icon(Icons.person, color: Colors.white, size: 36),
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
                  routeName: '/teacher',
                  icon: Icons.dashboard_rounded,
                  title: 'Dashboard',
                  color: const Color(0xFF00C6FF),
                  replaceAll: true,
                ),

                _tile(
                  context: context,
                  routeName: '/teacher/attendance',
                  icon: Icons.check_box_outlined,
                  title: 'Mark Attendance',
                  color: const Color(0xFF6C63FF),
                ),

                _tile(
                  context: context,
                  routeName: '/teacher-timetable-display',
                  icon: Icons.table_chart,
                  title: 'Timetable',
                  color: const Color(0xFF38EF7D),
                ),

                _tile(
                  context: context,
                  routeName: '/teacher/substitutions',
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
                  routeName: '/view-circulars',
                  icon: Icons.campaign,
                  title: 'Circulars',
                  color: const Color(0xFF8E2DE2),
                ),

                _tile(
                  context: context,
                  routeName: '/employee-leave-request',
                  icon: Icons.beach_access,
                  title: 'Leave Requests',
                  color: const Color(0xFF4A90E2),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Quick actions',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.black54,
                    ),
                  ),
                ),

                _tile(
                  context: context,
                  routeName: '/notifications',
                  icon: Icons.notifications_active_rounded,
                  title: 'Notifications',
                  color: const Color(0xFF00BFA6),
                  subtitle: 'Unread alerts',
                ),

                _tile(
                  context: context,
                  routeName: '/profile',
                  icon: Icons.person_rounded,
                  title: 'Profile',
                  color: const Color(0xFF7ED957),
                ),

                _tile(
                  context: context,
                  routeName: '/settings',
                  icon: Icons.settings_rounded,
                  title: 'Settings',
                  color: const Color(0xFF9C27B0),
                ),

                _tile(
                  context: context,
                  routeName: '/help',
                  icon: Icons.help_rounded,
                  title: 'Help & Support',
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
            padding:
                const EdgeInsets.only(bottom: 12, left: 16, right: 16),
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
