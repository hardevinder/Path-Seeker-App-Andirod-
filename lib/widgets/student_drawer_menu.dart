// lib/widgets/student_drawer_menu.dart
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'role_switcher.dart';

class StudentDrawerMenu extends StatelessWidget {
  const StudentDrawerMenu({super.key});

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
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 3))
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
      title: Text(title,
          style: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? Colors.deepPurple : Colors.black87)),
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
                        Text(studentName,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800)),
                        SizedBox(height: 6),
                        Text(studentEmail,
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13)),
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
                  routeName: '/choose-role',
                  icon: Icons.switch_account_rounded,
                  title: 'Switch Role',
                  color: const Color(0xFF111827),
                  extraAction: () => RoleSwitcher.show(context),
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
                  routeName: '/student/bus-live',
                  icon: Icons.directions_bus_rounded,
                  title: 'My Bus Live',
                  color: const Color(0xFF16A34A),
                  subtitle: 'Track your assigned school bus',
                ),
                _tile(
                  context: context,
                  routeName: '/student/exam-seat',
                  icon: Icons.event_seat_rounded,
                  title: 'My Exam Seat',
                  color: const Color(0xFF7C3AED),
                  subtitle: 'Room, seat and exam attendance',
                ),
                _tile(
                  context: context,
                  routeName: '/student/answer-script-status',
                  icon: Icons.description_rounded,
                  title: 'Answer Script Status',
                  color: const Color(0xFFB45309),
                  subtitle: 'Checking and rechecking updates',
                ),
                _tile(
                  context: context,
                  routeName: '/student/activities-achievements',
                  icon: Icons.emoji_events_rounded,
                  title: 'Activities & Achievements',
                  color: const Color(0xFFD97706),
                  subtitle: 'Competitions, positions and certificates',
                ),
                _tile(
                  context: context,
                  routeName: '/student/leadership',
                  icon: Icons.workspace_premium_rounded,
                  title: 'My Leadership',
                  color: const Color(0xFF4F46E5),
                  subtitle: 'Council position, duties & leadership history',
                ),
                _tile(
                  context: context,
                  routeName: '/house-duty',
                  icon: Icons.flag_outlined,
                  title: 'My House Duties & Assembly',
                  color: const Color(0xFFB45309),
                  subtitle: 'My assigned House duties and performance',
                ), // HOUSE_DUTY_V15 // STUDENT_LEADERSHIP_V13
                _tile(
                  context: context,
                  routeName: '/parent-consents',
                  icon: Icons.draw_rounded,
                  title: 'Parent Consent',
                  color: const Color(0xFF4F46E5),
                  subtitle: 'Consent, acknowledgement & signed form scan',
                ),
                _tile(
                  context: context,
                  routeName: '/document-vault',
                  icon: Icons.shield_outlined,
                  title: 'My Documents',
                  color: const Color(0xFF1D4ED8),
                  subtitle: 'DOB, Aadhaar, previous school & certificates',
                ),
                _tile(
                  context: context,
                  routeName: '/student-health',
                  icon: Icons.health_and_safety_rounded,
                  title: 'My Health & Growth',
                  color: const Color(0xFF0F766E),
                  subtitle: 'Height, weight, screenings & health profile',
                ),
                _tile(
                  context: context,
                  routeName: '/anecdotal-records',
                  icon: Icons.auto_awesome_outlined,
                  title: 'My Growth & Recognition',
                  color: const Color(0xFF7C3AED),
                  subtitle: 'Shared observations and school recognition',
                ),
                _tile(
                  context: context,
                  routeName: '/daily-readiness',
                  icon: Icons.check_circle_outline_rounded,
                  title: 'My Daily Readiness',
                  color: const Color(0xFF0E7490),
                  subtitle: 'Shared uniform, hygiene & tiffin record',
                ),
                _tile(
                  context: context,
                  routeName: '/lost-found',
                  icon: Icons.search_rounded,
                  title: 'Lost & Found',
                  color: const Color(0xFF7C3AED),
                  subtitle: 'View found items, report lost & submit a claim',
                ),
                _tile(
                  context: context,
                  routeName: '/student/lesson-plans',
                  icon: Icons.auto_stories_rounded,
                  title: 'Lesson Plans',
                  color: const Color(0xFF4F46E5),
                  subtitle: 'Published weekly plans',
                ),
                _tile(
                  context: context,
                  routeName: '/online-classes',
                  icon: Icons.video_call_rounded,
                  title: 'Online Classes',
                  color: const Color(0xFF2D8CFF),
                  subtitle: 'View and join Zoom classes',
                ),
                _tile(
                  context: context,
                  routeName: '/assessments',
                  icon: Icons.assignment_turned_in_rounded,
                  title: 'Tests & Results',
                  color: const Color(0xFF4F46E5),
                  subtitle: 'Attempt tests and upload answer sheets',
                ),
                _tile(
                  context: context,
                  routeName: '/student/library',
                  icon: Icons.local_library_rounded,
                  title: 'Library',
                  color: const Color(0xFF1D4ED8),
                  subtitle: 'Issued books & dues',
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
                  child: Text('Quick actions',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, color: Colors.black54)),
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
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
            child: Text('App version 1.0.0',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
