import 'package:flutter/material.dart';

import '../../auth/role_manager.dart';
import '../../services/role_dashboard_api.dart';
import '../../widgets/admin_module_widgets.dart';

class AccountsDashboardScreen extends StatelessWidget {
  const AccountsDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminDashboardScaffold(
      activeRole: AppRoles.accounts,
      title: 'Accounts Dashboard',
      fallbackName: 'Accounts',
      heroTitle: 'Fee & Collection Desk',
      heroSubtitle:
          'Review collections, dues, receipts, concessions, opening balances and fee setup from one mobile workspace.',
      heroIcon: Icons.account_balance_wallet_rounded,
      accent: const Color(0xFF0F766E),
      dataLoader: RoleDashboardApi.accounts,
      metrics: const [
        AdminMetric(
          label: 'Collection',
          value: 'Today',
          helper: 'Daily receipts',
          icon: Icons.payments_rounded,
          color: Color(0xFF16A34A),
        ),
        AdminMetric(
          label: 'Fee Due',
          value: 'Live',
          helper: 'Outstanding review',
          icon: Icons.receipt_long_rounded,
          color: Color(0xFFE11D48),
        ),
        AdminMetric(
          label: 'Receipts',
          value: 'Session',
          helper: 'Collected records',
          icon: Icons.receipt_rounded,
          color: Color(0xFF2563EB),
        ),
        AdminMetric(
          label: 'Setup',
          value: 'Fees',
          helper: 'Heads and structure',
          icon: Icons.tune_rounded,
          color: Color(0xFFD97706),
        ),
      ],
      primaryActionTitle: 'Fee Work',
      primaryActions: const [
        AdminAction(
          title: 'Collect Fee',
          subtitle: 'Receipts, students and payment modes',
          icon: Icons.currency_rupee_rounded,
          color: Color(0xFF16A34A),
          routeName: '/accounts/collect-fee',
        ),
        AdminAction(
          title: 'Day Collection',
          subtitle: 'Today collection and receipt summary',
          icon: Icons.calendar_today_rounded,
          color: Color(0xFF2563EB),
          routeName: '/accounts/day-collection',
        ),
        AdminAction(
          title: 'Fee Due Report',
          subtitle: 'Student dues and pending balances',
          icon: Icons.receipt_long_rounded,
          color: Color(0xFFE11D48),
          routeName: '/accounts/fee-due',
        ),
        AdminAction(
          title: 'Session Summary',
          subtitle: 'School fee summary by session',
          icon: Icons.query_stats_rounded,
          color: Color(0xFF7C3AED),
          routeName: '/accounts/session-summary',
        ),
        AdminAction(
          title: 'Fee Head Collection',
          subtitle: 'Head-wise collection report',
          icon: Icons.stacked_bar_chart_rounded,
          color: Color(0xFF0F766E),
          routeName: '/accounts/fee-head-collection',
        ),
        AdminAction(
          title: 'Bulk Concessions',
          subtitle: 'Apply student concessions',
          icon: Icons.percent_rounded,
          color: Color(0xFFD97706),
          routeName: '/accounts/bulk-concessions',
        ),
      ],
      highlightsTitle: 'Collection Snapshot',
      highlights: const [
        AdminFeedItem(
          title: 'Daily close focus',
          subtitle:
              'Day collection, cancelled receipts and payment modes stay together for accounts checking.',
          meta: 'Today',
          icon: Icons.task_alt_rounded,
          color: Color(0xFF16A34A),
        ),
        AdminFeedItem(
          title: 'Due and concession review',
          subtitle:
              'Outstanding fee, concession report and opening balances are available from this role.',
          meta: 'Due',
          icon: Icons.account_balance_rounded,
          color: Color(0xFFE11D48),
        ),
      ],
      secondaryActionTitle: 'Reports & Setup',
      secondaryActions: const [
        AdminAction(
          title: 'Cancelled Receipts',
          subtitle: 'Cancelled and restored receipts',
          icon: Icons.cancel_rounded,
          color: Color(0xFFE11D48),
          routeName: '/accounts/cancelled-receipts',
        ),
        AdminAction(
          title: 'Concession Report',
          subtitle: 'Class and student concessions',
          icon: Icons.summarize_rounded,
          color: Color(0xFF7C3AED),
          routeName: '/accounts/concession-report',
        ),
        AdminAction(
          title: 'Transport Fee',
          subtitle: 'Van fee detailed report',
          icon: Icons.directions_bus_rounded,
          color: Color(0xFF0891B2),
          routeName: '/accounts/transport-fee',
        ),
        AdminAction(
          title: 'Opening Balances',
          subtitle: 'Previous balance entries',
          icon: Icons.account_balance_rounded,
          color: Color(0xFF334155),
          routeName: '/accounts/opening-balances',
        ),
        AdminAction(
          title: 'Fee Structure',
          subtitle: 'Class fee setup',
          icon: Icons.account_tree_rounded,
          color: Color(0xFFD97706),
          routeName: '/accounts/fee-structure',
        ),
        AdminAction(
          title: 'Fee Headings',
          subtitle: 'Fee head master',
          icon: Icons.bookmark_rounded,
          color: Color(0xFF2563EB),
          routeName: '/accounts/fee-headings',
        ),
        AdminAction(
          title: 'Fee Category',
          subtitle: 'Fee category master',
          icon: Icons.category_rounded,
          color: Color(0xFF0F766E),
          routeName: '/accounts/fee-category',
        ),
        AdminAction(
          title: 'Concessions',
          subtitle: 'Concession master',
          icon: Icons.local_offer_rounded,
          color: Color(0xFF7C3AED),
          routeName: '/accounts/concessions',
        ),
        AdminAction(
          title: 'Modes & Banks',
          subtitle: 'Payment modes and bank accounts',
          icon: Icons.account_balance_wallet_rounded,
          color: Color(0xFF16A34A),
          routeName: '/accounts/payment-setup',
        ),
      ],
      timelineTitle: 'Close The Day',
      timeline: const [
        AdminFeedItem(
          title: 'Before day closing',
          subtitle:
              'Check cash, bank, online receipts, cancelled entries and concession totals.',
          meta: 'Close',
          icon: Icons.fact_check_rounded,
          color: Color(0xFF0F766E),
        ),
      ],
    );
  }
}
