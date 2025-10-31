// lib/widgets/student_drawer_menu.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudentDrawerMenu extends StatelessWidget {
  const StudentDrawerMenu({super.key});

  Future<void> _logout(BuildContext ctx) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('authToken');
    // close drawer first
    Navigator.of(ctx).pop();
    // then navigate to login and remove all previous routes
    Navigator.of(ctx).pushNamedAndRemoveUntil('/login', (route) => false);
    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('👋 Logged out successfully')));
  }

  Widget _leadingIcon(IconData icon, Color color) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withOpacity(0.95), color.withOpacity(0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 3))],
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
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: selected ? Colors.deepPurple : Colors.black87)),
      subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: selected ? const Icon(Icons.check_circle, color: Colors.deepPurple) : const Icon(Icons.chevron_right_rounded),
      tileColor: selected ? Colors.deepPurple.withOpacity(0.06) : null,
      onTap: () {
        Navigator.of(context).pop(); // close drawer first
        if (extraAction != null) extraAction();
        if (replaceAll) {
          Navigator.of(context).pushNamedAndRemoveUntil(routeName, (route) => false);
        } else {
          // avoid pushing same route again
          if (current != routeName) Navigator.of(context).pushNamed(routeName);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // You can pass real user info by modifying this widget to accept parameters.
    const studentName = 'Student Name';
    const studentEmail = 'student@example.com';

    return Drawer(
      child: Column(
        children: [
          Container(
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
                      children: const [
                        Text(studentName, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                        SizedBox(height: 6),
                        Text(studentEmail, style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Menu items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const SizedBox(height: 8),
                _tile(
                  context: context,
                  routeName: '/dashboard',
                  icon: Icons.dashboard_rounded,
                  title: 'Dashboard',
                  color: const Color(0xFF00C6FF),
                  replaceAll: true,
                ),
                _tile(
                  context: context,
                  routeName: '/assignments',
                  icon: Icons.assignment_rounded,
                  title: 'Assignments',
                  color: const Color(0xFF6C63FF),
                ),
                _tile(
                  context: context,
                  routeName: '/timetable',
                  icon: Icons.calendar_today_rounded,
                  title: 'Time Table',
                  color: const Color(0xFF38EF7D),
                ),
                _tile(
                  context: context,
                  routeName: '/fee-details',
                  icon: Icons.account_balance_wallet_rounded,
                  title: 'Fee Details',
                  color: const Color(0xFFFFA726),
                ),
                _tile(
                  context: context,
                  routeName: '/circulars',
                  icon: Icons.notifications_rounded,
                  title: 'Circulars',
                  color: const Color(0xFFEF5350),
                  subtitle: 'School notices & updates',
                ),
                _tile(
                  context: context,
                  routeName: '/attendance',
                  icon: Icons.access_time_rounded,
                  title: 'Attendance',
                  color: const Color(0xFF8E2DE2),
                ),
                _tile(
                  context: context,
                  routeName: '/leave',
                  icon: Icons.event_note_rounded,
                  title: 'Leave Requests',
                  color: const Color(0xFF4A90E2),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('Quick actions', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black54)),
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
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
            child: Text('App version 1.0.0', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
