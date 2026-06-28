import 'package:flutter/material.dart';

import '../../auth/role_manager.dart';
import '../../services/role_dashboard_api.dart';
import '../../widgets/admin_module_widgets.dart';

class HrDashboardScreen extends StatelessWidget {
  const HrDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminDashboardScaffold(
      activeRole: AppRoles.hr,
      title: 'HR Dashboard',
      fallbackName: 'HR',
      heroTitle: 'People & Attendance Desk',
      heroSubtitle:
          'Track staff attendance, pending leaves, employee accounts and HR communication with a mobile-first layout.',
      heroIcon: Icons.badge_rounded,
      accent: const Color(0xFF16A34A),
      dataLoader: RoleDashboardApi.hr,
      metrics: const [
        AdminMetric(
          label: 'Attendance',
          value: 'Today',
          helper: 'Daily marking',
          icon: Icons.how_to_reg_rounded,
          color: Color(0xFF16A34A),
        ),
        AdminMetric(
          label: 'Leaves',
          value: 'Pending',
          helper: 'Approval queue',
          icon: Icons.pending_actions_rounded,
          color: Color(0xFFD97706),
        ),
        AdminMetric(
          label: 'Staff',
          value: 'Active',
          helper: 'Employee directory',
          icon: Icons.groups_rounded,
          color: Color(0xFF2563EB),
        ),
        AdminMetric(
          label: 'Messages',
          value: 'Open',
          helper: 'HR follow-up',
          icon: Icons.chat_bubble_rounded,
          color: Color(0xFF7C3AED),
        ),
      ],
      primaryActionTitle: 'HR Actions',
      primaryActions: const [
        AdminAction(
          title: 'Employee Directory',
          subtitle: 'Profiles, departments and contact details',
          icon: Icons.badge_rounded,
          color: Color(0xFF16A34A),
          routeName: '/hr/employees',
        ),
        AdminAction(
          title: 'Leave & Attendance',
          subtitle: 'Daily status and absentee review',
          icon: Icons.event_note_rounded,
          color: Color(0xFF2563EB),
          routeName: '/hr/leave-attendance',
        ),
        AdminAction(
          title: 'Leave Requests',
          subtitle: 'Approve, reject and review remarks',
          icon: Icons.fact_check_rounded,
          color: Color(0xFFD97706),
          routeName: '/hr/leave-requests',
        ),
        AdminAction(
          title: 'Attendance Calendar',
          subtitle: 'Employee month-wise view',
          icon: Icons.calendar_view_month_rounded,
          color: Color(0xFF0F766E),
          routeName: '/hr/attendance-calendar',
        ),
        AdminAction(
          title: 'Academic Calendar',
          subtitle: 'School holidays, exams and event calendar',
          icon: Icons.calendar_month_rounded,
          color: Color(0xFF2563EB),
          routeName: '/hr/academic-calendar',
        ),
        AdminAction(
          title: 'Messages',
          subtitle: 'Staff reminders and conversations',
          icon: Icons.chat_bubble_rounded,
          color: Color(0xFF7C3AED),
          routeName: '/hr/messages',
        ),
        AdminAction(
          title: 'Staff Onboarding',
          subtitle: 'Joining and document readiness',
          icon: Icons.login_rounded,
          color: Color(0xFFE11D48),
          routeName: '/hr/onboarding',
        ),
      ],
      highlights: const [
        AdminFeedItem(
          title: 'Latest leave spotlight',
          subtitle:
              'The HR flow now reflects the PITS web dashboard focus on newest pending leave requests.',
          meta: 'Leave',
          icon: Icons.new_releases_rounded,
          color: Color(0xFFD97706),
        ),
        AdminFeedItem(
          title: 'Teacher absentee impact',
          subtitle:
              'Teaching staff absences can be reviewed alongside substitution and timetable workflows.',
          meta: 'Daily',
          icon: Icons.school_rounded,
          color: Color(0xFF2563EB),
        ),
      ],
      secondaryActionTitle: 'People Setup',
      secondaryActions: const [
        AdminAction(
          title: 'Departments',
          subtitle: 'Department master',
          icon: Icons.apartment_rounded,
          color: Color(0xFF2563EB),
          routeName: '/hr/departments',
        ),
        AdminAction(
          title: 'Employee Accounts',
          subtitle: 'Linked login users',
          icon: Icons.manage_accounts_rounded,
          color: Color(0xFF7C3AED),
          routeName: '/hr/employee-accounts',
        ),
      ],
      timeline: const [
        AdminFeedItem(
          title: 'Daily cleanup',
          subtitle:
              'Review unmarked attendance, pending leave and staff status before closing the day.',
          meta: 'Today',
          icon: Icons.rule_rounded,
          color: Color(0xFF0F766E),
        ),
      ],
    );
  }
}