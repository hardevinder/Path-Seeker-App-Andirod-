import 'package:flutter/material.dart';

import '../../auth/role_manager.dart';
import '../../services/role_dashboard_api.dart';
import '../../widgets/admin_module_widgets.dart';

class SuperadminDashboardScreen extends StatelessWidget {
  const SuperadminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminDashboardScaffold(
      activeRole: AppRoles.superadmin,
      title: 'Super Admin Dashboard',
      fallbackName: 'Super Admin',
      heroTitle: 'School Command Center',
      heroSubtitle:
          'Run setup, users, reports, fee transactions, permissions and academic structure from one mobile control surface.',
      heroIcon: Icons.admin_panel_settings_rounded,
      accent: const Color(0xFF4F46E5),
      dataLoader: RoleDashboardApi.superadmin,
      metrics: const [
        AdminMetric(
          label: 'Session',
          value: '2026-27',
          helper: 'Active academic year',
          icon: Icons.calendar_today_rounded,
          color: Color(0xFFD97706),
        ),
        AdminMetric(
          label: 'Roles',
          value: '7+',
          helper: 'Mobile role dashboards',
          icon: Icons.groups_rounded,
          color: Color(0xFF2563EB),
        ),
        AdminMetric(
          label: 'Fees',
          value: 'Live',
          helper: 'Transactions & collection',
          icon: Icons.receipt_long_rounded,
          color: Color(0xFF0891B2),
        ),
        AdminMetric(
          label: 'Access',
          value: 'RBAC',
          helper: 'Permission driven',
          icon: Icons.verified_user_rounded,
          color: Color(0xFF7C3AED),
        ),
      ],
      primaryActions: const [],
      actionSections: const [
        AdminActionSection(
          title: 'Fee Section',
          actions: [
            AdminAction(
              title: 'Collect Fee',
              subtitle: 'Student fee collection',
              icon: Icons.currency_rupee_rounded,
              color: Color(0xFF16A34A),
              routeName: '/accounts/collect-fee',
            ),
            AdminAction(
              title: 'Direct Payment',
              subtitle: 'Payment link page',
              icon: Icons.credit_card_rounded,
              color: Color(0xFF0369A1),
            ),
            AdminAction(
              title: 'Fee Due Report',
              subtitle: 'Student due list',
              icon: Icons.receipt_long_rounded,
              color: Color(0xFFE11D48),
              routeName: '/accounts/fee-due',
            ),
            AdminAction(
              title: 'Pending Due',
              subtitle: 'School fee summary',
              icon: Icons.checklist_rtl_rounded,
              color: Color(0xFF2563EB),
              routeName: '/accounts/session-summary',
            ),
            AdminAction(
              title: 'Fee Head Collection',
              subtitle: 'Collection matrix',
              badge: 'NEW',
              icon: Icons.table_chart_rounded,
              color: Color(0xFF7C3AED),
              routeName: '/accounts/fee-head-collection',
            ),
            AdminAction(
              title: 'Day Summary',
              subtitle: 'Day-wise fee report',
              icon: Icons.calendar_today_rounded,
              color: Color(0xFFD97706),
              routeName: '/accounts/day-collection',
            ),
            AdminAction(
              title: 'Transport / Van Fee',
              subtitle: 'Van fee report',
              icon: Icons.directions_bus_rounded,
              color: Color(0xFF0891B2),
              routeName: '/accounts/transport-fee',
            ),
            AdminAction(
              title: 'Transactions',
              subtitle: 'Search receipts and manage records',
              icon: Icons.receipt_rounded,
              color: Color(0xFF0F766E),
              routeName: '/superadmin/transactions',
            ),
          ],
        ),
        AdminActionSection(
          title: 'Students',
          actions: [
            AdminAction(
              title: 'Student List',
              subtitle: 'Search and manage students',
              icon: Icons.groups_rounded,
              color: Color(0xFF7C3AED),
            ),
            AdminAction(
              title: 'Student I-Cards',
              subtitle: 'Generate ID cards',
              badge: 'NEW',
              icon: Icons.badge_rounded,
              color: Color(0xFF0F766E),
            ),
            AdminAction(
              title: 'Bulk Concessions',
              subtitle: 'Apply concession',
              badge: 'NEW',
              icon: Icons.local_offer_rounded,
              color: Color(0xFFD97706),
              routeName: '/accounts/bulk-concessions',
            ),
            AdminAction(
              title: 'House Summary',
              subtitle: 'House-wise stats',
              badge: 'NEW',
              icon: Icons.stacked_bar_chart_rounded,
              color: Color(0xFF0369A1),
              routeName: '/superadmin/school-reports',
            ),
          ],
        ),
        AdminActionSection(
          title: 'Reports',
          actions: [
            AdminAction(
              title: 'School Reports',
              subtitle: 'Strength, fees and MIS summaries',
              icon: Icons.query_stats_rounded,
              color: Color(0xFF16A34A),
              routeName: '/superadmin/school-reports',
            ),
            AdminAction(
              title: 'Caste & Gender',
              subtitle: 'Demographics',
              icon: Icons.diversity_3_rounded,
              color: Color(0xFFDC2626),
              routeName: '/superadmin/school-reports',
            ),
            AdminAction(
              title: 'Religion & Gender',
              subtitle: 'Demographics',
              icon: Icons.account_tree_rounded,
              color: Color(0xFF0369A1),
              routeName: '/superadmin/school-reports',
            ),
          ],
        ),
        AdminActionSection(
          title: 'Communication & Admin',
          actions: [
            AdminAction(
              title: 'Enquiries',
              subtitle: 'Admission enquiries',
              icon: Icons.person_search_rounded,
              color: Color(0xFFEA580C),
            ),
            AdminAction(
              title: 'Messages',
              subtitle: 'Fee reminders and chat',
              badge: 'NEW',
              icon: Icons.chat_bubble_rounded,
              color: Color(0xFF2563EB),
              routeName: '/accounts/messages',
            ),
            AdminAction(
              title: 'Role Permissions',
              subtitle: 'Assign role access',
              badge: 'ADMIN',
              icon: Icons.shield_rounded,
              color: Color(0xFF334155),
              routeName: '/superadmin/permissions',
            ),
            AdminAction(
              title: 'Users & Roles',
              subtitle: 'Accounts, roles and access control',
              icon: Icons.manage_accounts_rounded,
              color: Color(0xFF2563EB),
              routeName: '/superadmin/user-management',
            ),
          ],
        ),
        AdminActionSection(
          title: 'School Setup',
          compact: true,
          actions: [
            AdminAction(
              title: 'School Settings',
              subtitle: 'Academic year, policies and calendar',
              icon: Icons.settings_rounded,
              color: Color(0xFF4F46E5),
              routeName: '/superadmin/school-settings',
            ),
            AdminAction(
              title: 'Academic Year',
              subtitle: 'Sessions, terms and holidays',
              icon: Icons.calendar_month_rounded,
              color: Color(0xFFD97706),
              routeName: '/superadmin/academic-year',
            ),
            AdminAction(
              title: 'Classes & Sections',
              subtitle: 'Class master, sections and roll setup',
              icon: Icons.account_tree_rounded,
              color: Color(0xFF0F766E),
              routeName: '/superadmin/classes-sections',
            ),
            AdminAction(
              title: 'Bank Accounts',
              subtitle: 'Receipt and certificate setup',
              icon: Icons.account_balance_wallet_rounded,
              color: Color(0xFF16A34A),
              routeName: '/superadmin/bank-accounts',
            ),
            AdminAction(
              title: 'User Tracking',
              subtitle: 'Audit user activity',
              icon: Icons.manage_search_rounded,
              color: Color(0xFF334155),
              routeName: '/superadmin/user-tracking',
            ),
            AdminAction(
              title: 'AI Settings',
              subtitle: 'Assistant and automation setup',
              icon: Icons.auto_awesome_rounded,
              color: Color(0xFF7C3AED),
              routeName: '/superadmin/ai-settings',
            ),
          ],
        ),
      ],
      highlights: const [
        AdminFeedItem(
          title: 'Transaction control added',
          subtitle:
              'Super Admin can open the mobile transaction view for receipts, payment modes, collection records and cancelled entries.',
          meta: 'Fees',
          icon: Icons.receipt_long_rounded,
          color: Color(0xFF0891B2),
        ),
        AdminFeedItem(
          title: 'Role-aware navigation',
          subtitle:
              'PITS roles now land on matching mobile dashboards for Superadmin, Accounts, HR, Transport and Examination.',
          meta: 'Mobile',
          icon: Icons.switch_account_rounded,
          color: Color(0xFF2563EB),
        ),
        AdminFeedItem(
          title: 'Fee office visibility',
          subtitle:
              'Super Admin can review day collection, dues, session summary and accounts setup directly.',
          meta: 'Fees',
          icon: Icons.account_balance_wallet_rounded,
          color: Color(0xFF16A34A),
        ),
        AdminFeedItem(
          title: 'Academic setup',
          subtitle:
              'Session, classes, sections and calendars stay grouped for school-wide readiness.',
          meta: 'Setup',
          icon: Icons.event_available_rounded,
          color: Color(0xFFD97706),
        ),
      ],
      secondaryActions: const [],
      timeline: const [
        AdminFeedItem(
          title: 'Review permissions before rollout',
          subtitle:
              'Keep fee, HR, exam and transport access tied to the correct staff roles.',
          meta: 'RBAC',
          icon: Icons.shield_rounded,
          color: Color(0xFF7C3AED),
        ),
      ],
    );
  }
}
