import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/role_manager.dart';
import '../services/api_service.dart';
import 'role_switcher.dart';

class RoleDashboardDrawer extends StatelessWidget {
  final String activeRole;

  const RoleDashboardDrawer({super.key, required this.activeRole});

  Future<Map<String, String>> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final name =
        prefs.getString('name') ?? prefs.getString('username') ?? 'User';
    final email = prefs.getString('email') ?? '';
    return {'name': name, 'email': email};
  }

  void _showWebNotice(BuildContext context, String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title is available on the web portal.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

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

  List<Map<String, dynamic>> _dashboardItems() {
    switch (AppRoles.normalize(activeRole)) {
      case AppRoles.superadmin:
        return [
          {
            'icon': Icons.shield_rounded,
            'title': 'Manage School Settings',
            'route': '/superadmin/school-settings',
          },
          {
            'icon': Icons.group_rounded,
            'title': 'User & Role Management',
            'route': '/superadmin/user-management',
          },
          {
            'icon': Icons.bar_chart_rounded,
            'title': 'School Reports',
            'route': '/superadmin/school-reports',
          },
          {
            'icon': Icons.account_balance_wallet_rounded,
            'title': 'Accounts Dashboard',
            'route': '/accounts',
          },
          {
            'icon': Icons.payments_rounded,
            'title': 'Day Collection',
            'route': '/accounts/day-collection',
          },
          {
            'icon': Icons.receipt_long_rounded,
            'title': 'Fee Due Report',
            'route': '/accounts/fee-due',
          },
          {
            'icon': Icons.query_stats_rounded,
            'title': 'Session Summary',
            'route': '/accounts/session-summary',
          },
          {
            'icon': Icons.verified_user_rounded,
            'title': 'Role Permissions',
            'route': '/superadmin/permissions',
          },
          {
            'icon': Icons.calendar_month_rounded,
            'title': 'Academic Year',
            'route': '/superadmin/academic-year',
          },
          {
            'icon': Icons.account_tree_rounded,
            'title': 'Classes & Sections',
            'route': '/superadmin/classes-sections',
          },
          {
            'icon': Icons.manage_search_rounded,
            'title': 'User Tracking',
            'route': '/superadmin/user-tracking',
          },
          {
            'icon': Icons.account_balance_wallet_rounded,
            'title': 'Bank Accounts',
            'route': '/superadmin/bank-accounts',
          },
          {
            'icon': Icons.auto_awesome_rounded,
            'title': 'AI Settings',
            'route': '/superadmin/ai-settings',
          },
        ];
      case AppRoles.accounts:
        return [
          {
            'icon': Icons.currency_rupee_rounded,
            'title': 'Collect Fee',
            'route': '/accounts/collect-fee',
          },
          {
            'icon': Icons.calendar_today_rounded,
            'title': 'Day Collection',
            'route': '/accounts/day-collection',
          },
          {
            'icon': Icons.receipt_long_rounded,
            'title': 'Fee Due Report',
            'route': '/accounts/fee-due',
          },
          {
            'icon': Icons.query_stats_rounded,
            'title': 'Session Summary',
            'route': '/accounts/session-summary',
          },
          {
            'icon': Icons.stacked_bar_chart_rounded,
            'title': 'Fee Head Collection',
            'route': '/accounts/fee-head-collection',
          },
          {
            'icon': Icons.cancel_rounded,
            'title': 'Cancelled Receipts',
            'route': '/accounts/cancelled-receipts',
          },
          {
            'icon': Icons.summarize_rounded,
            'title': 'Concession Report',
            'route': '/accounts/concession-report',
          },
          {
            'icon': Icons.directions_bus_rounded,
            'title': 'Transport Fee',
            'route': '/accounts/transport-fee',
          },
          {
            'icon': Icons.account_balance_rounded,
            'title': 'Opening Balances',
            'route': '/accounts/opening-balances',
          },
          {
            'icon': Icons.account_tree_rounded,
            'title': 'Fee Structure',
            'route': '/accounts/fee-structure',
          },
          {
            'icon': Icons.bookmark_rounded,
            'title': 'Fee Headings',
            'route': '/accounts/fee-headings',
          },
          {
            'icon': Icons.category_rounded,
            'title': 'Fee Category',
            'route': '/accounts/fee-category',
          },
          {
            'icon': Icons.local_offer_rounded,
            'title': 'Concessions',
            'route': '/accounts/concessions',
          },
          {
            'icon': Icons.account_balance_wallet_rounded,
            'title': 'Modes & Banks',
            'route': '/accounts/payment-setup',
          },
        ];
      case AppRoles.hr:
        return [
          {
            'icon': Icons.badge_rounded,
            'title': 'Employee Directory',
            'route': '/hr/employees',
          },
          {
            'icon': Icons.event_note_rounded,
            'title': 'Leave & Attendance',
            'route': '/hr/leave-attendance',
          },
          {
            'icon': Icons.login_rounded,
            'title': 'Staff Onboarding',
            'route': '/hr/onboarding',
          },
          {
            'icon': Icons.fact_check_rounded,
            'title': 'Leave Requests',
            'route': '/hr/leave-requests',
          },
          {
            'icon': Icons.calendar_view_month_rounded,
            'title': 'Attendance Calendar',
            'route': '/hr/attendance-calendar',
          },
          {
            'icon': Icons.calendar_month_rounded,
            'title': 'Academic Calendar',
            'route': '/hr/academic-calendar',
          },
          {
            'icon': Icons.chat_bubble_rounded,
            'title': 'Messages',
            'route': '/hr/messages',
          },
          {
            'icon': Icons.apartment_rounded,
            'title': 'Departments',
            'route': '/hr/departments',
          },
          {
            'icon': Icons.manage_accounts_rounded,
            'title': 'Employee Accounts',
            'route': '/hr/employee-accounts',
          },
        ];
      case AppRoles.transport:
        return [
          {
            'icon': Icons.directions_bus_rounded,
            'title': 'Route Management',
            'route': '/transport/routes',
          },
          {
            'icon': Icons.people_rounded,
            'title': 'Pickup Tracking',
            'route': '/transport/pickup-tracking',
          },
          {
            'icon': Icons.map_rounded,
            'title': 'Vehicle Status',
            'route': '/transport/vehicle-status',
          },
          {
            'icon': Icons.directions_bus_rounded,
            'title': 'Buses',
            'route': '/transport/buses',
          },
          {
            'icon': Icons.person_pin_circle_rounded,
            'title': 'Student Assignments',
            'route': '/transport/student-assignments',
          },
          {
            'icon': Icons.badge_rounded,
            'title': 'Transport Staff',
            'route': '/transport/staff',
          },
          {
            'icon': Icons.check_circle_rounded,
            'title': 'Mark Attendance',
            'route': '/transport/attendance',
          },
          {
            'icon': Icons.assessment_rounded,
            'title': 'Attendance Report',
            'route': '/transport/attendance-report',
          },
          {
            'icon': Icons.payments_rounded,
            'title': 'Fee Overrides',
            'route': '/transport/fee-overrides',
          },
        ];
      case AppRoles.examination:
        return [
          {
            'icon': Icons.event_rounded,
            'title': 'Exam Schedule',
            'route': '/examination/schedule',
          },
          {
            'icon': Icons.grade_rounded,
            'title': 'Result Moderation',
            'route': '/examination/result-moderation',
          },
          {
            'icon': Icons.assignment_turned_in_rounded,
            'title': 'Exam Reports',
            'route': '/examination/reports',
          },
          {
            'icon': Icons.edit_calendar_rounded,
            'title': 'Manage Exams',
            'route': '/examination/exams',
          },
          {
            'icon': Icons.schema_rounded,
            'title': 'Exam Schemes',
            'route': '/examination/schemes',
          },
          {
            'icon': Icons.edit_note_rounded,
            'title': 'Marks Entry',
            'route': '/examination/marks-entry',
          },
          {
            'icon': Icons.extension_rounded,
            'title': 'Co-Scholastic',
            'route': '/examination/co-scholastic',
          },
          {
            'icon': Icons.rate_review_rounded,
            'title': 'Remarks',
            'route': '/examination/remarks',
          },
          {
            'icon': Icons.school_rounded,
            'title': 'Promotion',
            'route': '/examination/promotion',
          },
          {
            'icon': Icons.emoji_events_rounded,
            'title': 'Final Result',
            'route': '/examination/final-result',
          },
          {
            'icon': Icons.picture_as_pdf_rounded,
            'title': 'Report Cards',
            'route': '/examination/report-cards',
          },
        ];
      default:
        return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = AppRoles.label(activeRole);
    return Drawer(
      child: Column(
        children: [
          FutureBuilder<Map<String, String>>(
            future: _loadProfile(),
            builder: (ctx, snapshot) {
              final data = snapshot.data ?? {'name': 'User', 'email': ''};
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
                              data['name'] ?? 'User',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              roleLabel,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              data['email'] ?? '',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
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
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const SizedBox(height: 8),
                _tile(
                  context: context,
                  icon: Icons.dashboard_rounded,
                  title: 'Dashboard',
                  color: const Color(0xFF00C6FF),
                  routeName: AppRoles.dashboardRoute(activeRole),
                  replaceAll: true,
                ),
                _tile(
                  context: context,
                  icon: Icons.switch_account_rounded,
                  title: 'Switch Role',
                  color: const Color(0xFF111827),
                  extraAction: () => RoleSwitcher.show(context),
                ),
                const Divider(height: 0),
                ..._dashboardItems().map((item) {
                  return _tile(
                    context: context,
                    icon: item['icon'] as IconData,
                    title: item['title'] as String,
                    color: const Color(0xFF6C63FF),
                    routeName: item['route'] as String?,
                    extraAction: item['route'] == null
                        ? () => _showWebNotice(context, item['title'] as String)
                        : null,
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          ),
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
        ],
      ),
    );
  }

  Widget _tile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Color color,
    String? routeName,
    bool replaceAll = false,
    VoidCallback? extraAction,
  }) {
    final String? current = ModalRoute.of(context)?.settings.name;
    final selected = routeName != null && current == routeName;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withAlpha((0.95 * 255).round()),
              color.withAlpha((0.7 * 255).round()),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Color.fromARGB((0.06 * 255).round(), 0, 0, 0),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: selected ? Colors.deepPurple : Colors.black87,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check_circle, color: Colors.deepPurple)
          : const Icon(Icons.chevron_right_rounded),
      tileColor:
          selected ? Colors.deepPurple.withAlpha((0.06 * 255).round()) : null,
      onTap: () {
        if (extraAction != null) {
          extraAction();
          return;
        }
        Navigator.of(context).pop();
        if (routeName == null) {
          _showWebNotice(context, title);
          return;
        }
        if (replaceAll) {
          Navigator.of(context)
              .pushNamedAndRemoveUntil(routeName, (route) => false);
        } else {
          if (current != routeName) Navigator.of(context).pushNamed(routeName);
        }
      },
    );
  }
}