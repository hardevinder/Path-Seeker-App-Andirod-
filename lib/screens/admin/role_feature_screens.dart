import 'package:flutter/material.dart';

import '../../auth/role_manager.dart';
import '../../services/role_dashboard_api.dart';
import '../../widgets/admin_module_widgets.dart';

class SuperadminPermissionsScreen extends StatelessWidget {
  const SuperadminPermissionsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      buildSuperadminFeatureScreen('permissions');
}

class SuperadminAcademicYearScreen extends StatelessWidget {
  const SuperadminAcademicYearScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      buildSuperadminFeatureScreen('academicYear');
}

class SuperadminClassesSectionsScreen extends StatelessWidget {
  const SuperadminClassesSectionsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      buildSuperadminFeatureScreen('classesSections');
}

class SuperadminUserTrackingScreen extends StatelessWidget {
  const SuperadminUserTrackingScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      buildSuperadminFeatureScreen('userTracking');
}

class SuperadminBankAccountsScreen extends StatelessWidget {
  const SuperadminBankAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      buildSuperadminFeatureScreen('bankAccounts');
}

class SuperadminAiSettingsScreen extends StatelessWidget {
  const SuperadminAiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      buildSuperadminFeatureScreen('aiSettings');
}

class HrLeaveRequestsScreen extends StatelessWidget {
  const HrLeaveRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) => buildHrFeatureScreen('leaveRequests');
}

class HrAttendanceCalendarScreen extends StatelessWidget {
  const HrAttendanceCalendarScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      buildHrFeatureScreen('attendanceCalendar');
}

class HrDepartmentsScreen extends StatelessWidget {
  const HrDepartmentsScreen({super.key});

  @override
  Widget build(BuildContext context) => buildHrFeatureScreen('departments');
}

class HrEmployeeAccountsScreen extends StatelessWidget {
  const HrEmployeeAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      buildHrFeatureScreen('employeeAccounts');
}

class HrMessagesScreen extends StatelessWidget {
  const HrMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) => buildHrFeatureScreen('messages');
}

class TransportBusesScreen extends StatelessWidget {
  const TransportBusesScreen({super.key});

  @override
  Widget build(BuildContext context) => buildTransportFeatureScreen('buses');
}

class TransportStudentAssignmentsScreen extends StatelessWidget {
  const TransportStudentAssignmentsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      buildTransportFeatureScreen('assignments');
}

class TransportStaffScreen extends StatelessWidget {
  const TransportStaffScreen({super.key});

  @override
  Widget build(BuildContext context) => buildTransportFeatureScreen('staff');
}

class TransportAttendanceScreen extends StatelessWidget {
  const TransportAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      buildTransportFeatureScreen('attendance');
}

class TransportAttendanceReportScreen extends StatelessWidget {
  const TransportAttendanceReportScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      buildTransportFeatureScreen('attendanceReport');
}

class TransportFeeOverridesScreen extends StatelessWidget {
  const TransportFeeOverridesScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      buildTransportFeatureScreen('feeOverrides');
}

class ExaminationManageExamsScreen extends StatelessWidget {
  const ExaminationManageExamsScreen({super.key});

  @override
  Widget build(BuildContext context) => buildExaminationFeatureScreen('exams');
}

class ExaminationSchemesScreen extends StatelessWidget {
  const ExaminationSchemesScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      buildExaminationFeatureScreen('schemes');
}

class ExaminationMarksEntryScreen extends StatelessWidget {
  const ExaminationMarksEntryScreen({super.key});

  @override
  Widget build(BuildContext context) => buildExaminationFeatureScreen('marks');
}

class ExaminationCoScholasticScreen extends StatelessWidget {
  const ExaminationCoScholasticScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      buildExaminationFeatureScreen('coScholastic');
}

class ExaminationRemarksScreen extends StatelessWidget {
  const ExaminationRemarksScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      buildExaminationFeatureScreen('remarks');
}

class ExaminationPromotionScreen extends StatelessWidget {
  const ExaminationPromotionScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      buildExaminationFeatureScreen('promotion');
}

class ExaminationReportCardsScreen extends StatelessWidget {
  const ExaminationReportCardsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      buildExaminationFeatureScreen('reportCards');
}

class ExaminationFinalResultScreen extends StatelessWidget {
  const ExaminationFinalResultScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      buildExaminationFeatureScreen('finalResult');
}

AdminFeatureScreen buildSuperadminFeatureScreen(String key) {
  final spec = _superadminSpecs[key] ?? _superadminSpecs['schoolSettings']!;
  final endpoints = _superadminFeatureEndpoints(key);
  return AdminFeatureScreen(
    activeRole: AppRoles.superadmin,
    title: spec.title,
    fallbackName: 'Super Admin',
    summary: spec.summary,
    icon: spec.icon,
    accent: spec.accent,
    metrics: spec.metrics,
    actions: spec.actions,
    checklist: spec.checklist,
    records: spec.records,
    checklistTitle: spec.checklistTitle,
    recordsTitle: spec.recordsTitle,
    dataLoader: _loaderFor(spec, endpoints),
  );
}

AdminFeatureScreen buildHrFeatureScreen(String key) {
  final spec = _hrSpecs[key] ?? _hrSpecs['employees']!;
  final endpoints = _hrFeatureEndpoints(key);
  return AdminFeatureScreen(
    activeRole: AppRoles.hr,
    title: spec.title,
    fallbackName: 'HR',
    summary: spec.summary,
    icon: spec.icon,
    accent: spec.accent,
    metrics: spec.metrics,
    actions: spec.actions,
    checklist: spec.checklist,
    records: spec.records,
    checklistTitle: spec.checklistTitle,
    recordsTitle: spec.recordsTitle,
    dataLoader: _loaderFor(spec, endpoints),
  );
}

AdminFeatureScreen buildTransportFeatureScreen(String key) {
  final spec = _transportSpecs[key] ?? _transportSpecs['routes']!;
  final endpoints = _transportFeatureEndpoints(key);
  return AdminFeatureScreen(
    activeRole: AppRoles.transport,
    title: spec.title,
    fallbackName: 'Transport',
    summary: spec.summary,
    icon: spec.icon,
    accent: spec.accent,
    metrics: spec.metrics,
    actions: spec.actions,
    checklist: spec.checklist,
    records: spec.records,
    checklistTitle: spec.checklistTitle,
    recordsTitle: spec.recordsTitle,
    dataLoader: _loaderFor(spec, endpoints),
  );
}

AdminFeatureScreen buildExaminationFeatureScreen(String key) {
  final spec = _examinationSpecs[key] ?? _examinationSpecs['schedule']!;
  final endpoints = _examinationFeatureEndpoints(key);
  return AdminFeatureScreen(
    activeRole: AppRoles.examination,
    title: spec.title,
    fallbackName: 'Examination',
    summary: spec.summary,
    icon: spec.icon,
    accent: spec.accent,
    metrics: spec.metrics,
    actions: spec.actions,
    checklist: spec.checklist,
    records: spec.records,
    checklistTitle: spec.checklistTitle,
    recordsTitle: spec.recordsTitle,
    dataLoader: _loaderFor(spec, endpoints),
  );
}

AdminFeatureScreen buildAccountsFeatureScreen(String key) {
  final spec = _accountsSpec(key);
  final endpoints = _accountsFeatureEndpoints(key);
  return AdminFeatureScreen(
    activeRole: AppRoles.accounts,
    title: spec.title,
    fallbackName: 'Accounts',
    summary: spec.summary,
    icon: spec.icon,
    accent: spec.accent,
    metrics: spec.metrics,
    actions: spec.actions,
    checklist: spec.checklist,
    records: spec.records,
    checklistTitle: spec.checklistTitle,
    recordsTitle: spec.recordsTitle,
    dataLoader: _loaderFor(spec, endpoints),
  );
}

Future<AdminDashboardPayload> Function()? _loaderFor(
  _FeatureSpec spec,
  List<String> endpoints,
) {
  if (endpoints.isEmpty) return null;
  return () => RoleDashboardApi.module(
        title: spec.title,
        endpoints: endpoints,
        icon: spec.icon,
        color: spec.accent,
      );
}

class _FeatureSpec {
  final String title;
  final String summary;
  final IconData icon;
  final Color accent;
  final List<AdminMetric> metrics;
  final List<AdminAction> actions;
  final List<AdminFeedItem> checklist;
  final List<AdminFeedItem> records;
  final String checklistTitle;
  final String recordsTitle;

  const _FeatureSpec({
    required this.title,
    required this.summary,
    required this.icon,
    required this.accent,
    required this.metrics,
    required this.actions,
    required this.checklist,
    required this.records,
    this.checklistTitle = 'Workflow',
    this.recordsTitle = 'Focus Items',
  });
}

class _AccountSpecInfo {
  final String title;
  final String summary;
  final IconData icon;
  final Color accent;
  final String group;

  const _AccountSpecInfo({
    required this.title,
    required this.summary,
    required this.icon,
    required this.accent,
    required this.group,
  });
}

const _blue = Color(0xFF2563EB);
const _indigo = Color(0xFF4F46E5);
const _purple = Color(0xFF7C3AED);
const _green = Color(0xFF16A34A);
const _teal = Color(0xFF0F766E);
const _cyan = Color(0xFF0891B2);
const _amber = Color(0xFFD97706);
const _rose = Color(0xFFE11D48);
const _slate = Color(0xFF334155);

List<String> _superadminFeatureEndpoints(String key) {
  switch (key) {
    case 'schoolSettings':
      return ['/schools', '/sessions', '/academic-years'];
    case 'userManagement':
      return ['/users/all', '/users', '/roles'];
    case 'schoolReports':
      return [
        '/reports/class-wise-student-count',
        '/reports/session/day-wise',
        '/student-caste-report/caste-gender-report',
      ];
    case 'permissions':
      return ['/roles', '/permissions'];
    case 'academicYear':
      return ['/academic-years', '/sessions', '/terms'];
    case 'classesSections':
      return ['/classes?withSections=true', '/sections'];
    case 'userTracking':
      return ['/users/sessions', '/users/student-login-activity'];
    case 'bankAccounts':
      return ['/school-bank-accounts'];
    case 'aiSettings':
      return ['/ai-settings'];
    default:
      return const [];
  }
}

List<String> _accountsFeatureEndpoints(String key) {
  final today = _today();
  switch (key) {
    case 'collectFee':
      return [
        '/transactions',
        '/transactions/summary/day-summary',
        '/mode-of-transactions',
        '/school-bank-accounts?active_only=true',
      ];
    case 'dayCollection':
      return [
        '/transactions/summary/day-summary',
        '/reports/day-wise?startDate=$today&endDate=$today&includeCancelled=true',
      ];
    case 'feeDue':
      return [
        '/reports/student-total-due?tillDate=$today',
        '/feedue/school-fee-summary',
      ];
    case 'sessionSummary':
      return ['/feedue/school-fee-summary', '/sessions', '/opening-balances'];
    case 'feeHeadCollection':
      return ['/student-fee-head-collection', '/fee-headings'];
    case 'bulkConcessions':
      return ['/concessions', '/students'];
    case 'cancelledReceipts':
      return ['/transactions/cancelled'];
    case 'concessionReport':
      return ['/feedue/concession-report', '/concessions'];
    case 'transportFee':
      return [
        '/feedue/van-fee-detailed-report',
        '/student-transport-fee-head-amounts',
      ];
    case 'openingBalances':
      return ['/opening-balances'];
    case 'feeStructure':
      return ['/fee-structures', '/classes', '/sessions'];
    case 'studentFeeStructure':
      return ['/student-fee-structures', '/students', '/sessions'];
    case 'feeHeadings':
      return ['/fee-headings', '/fee_categories'];
    case 'feeCategory':
      return ['/fee_categories'];
    case 'concessions':
      return ['/concessions'];
    case 'paymentSetup':
      return [
        '/mode-of-transactions',
        '/school-bank-accounts?active_only=true'
      ];
    case 'messages':
      return ['/api/messages/me', '/api/messages/recipients'];
    default:
      return const [];
  }
}

List<String> _hrFeatureEndpoints(String key) {
  final today = _today();
  switch (key) {
    case 'employees':
      return ['/employees'];
    case 'leaveAttendance':
      return ['/employee-attendance?date=$today', '/employees'];
    case 'onboarding':
      return ['/employees'];
    case 'leaveRequests':
      return [
        '/employee-leave-requests/all?status=pending',
        '/employee-leave-types',
      ];
    case 'attendanceCalendar':
      return ['/employee-attendance?date=$today', '/employees'];
    case 'departments':
      return ['/departments', '/departments/trashed'];
    case 'employeeAccounts':
      return ['/users/employees', '/employees'];
    case 'messages':
      return ['/api/messages/me', '/api/messages/recipients'];
    default:
      return const [];
  }
}

List<String> _transportFeatureEndpoints(String key) {
  final today = _today();
  switch (key) {
    case 'routes':
      return ['/transportations'];
    case 'pickup':
      return [
        '/transport-attendance/bus-summary-all?date=$today',
        '/student-transport-assignments?active=true',
      ];
    case 'vehicle':
      return ['/buses', '/transport-staff'];
    case 'buses':
      return ['/buses', '/transport-staff'];
    case 'assignments':
      return [
        '/student-transport-assignments?active=true',
        '/transportations',
        '/buses',
      ];
    case 'staff':
      return ['/transport-staff'];
    case 'attendance':
      return [
        '/transport-attendance/bus-summary-all?date=$today',
        '/student-transport-assignments?active=true',
      ];
    case 'attendanceReport':
      return ['/transport-attendance/bus-summary-all?date=$today'];
    case 'feeOverrides':
      return ['/student-transport-fee-head-amounts'];
    default:
      return const [];
  }
}

List<String> _examinationFeatureEndpoints(String key) {
  switch (key) {
    case 'schedule':
      return ['/exam-schedules', '/exams'];
    case 'moderation':
      return ['/marks/pending-summary', '/exams'];
    case 'reports':
      return ['/report-card-formats', '/exams/class-exam-subjects'];
    case 'exams':
      return ['/exams', '/terms'];
    case 'schemes':
      return [
        '/exam-schemes',
        '/combined-exam-schemes',
        '/assessment-components'
      ];
    case 'marks':
      return ['/marks-entry', '/exams/class-exam-subjects'];
    case 'coScholastic':
      return [
        '/coscholastic-evaluations/assigned-classes',
        '/co-scholastic-grades',
        '/coscholastic-evaluations',
      ];
    case 'remarks':
      return ['/student-remarks', '/classes'];
    case 'promotion':
      return ['/student-promotion-decisions', '/classes'];
    case 'reportCards':
      return ['/report-card-formats', '/report-card-formats/assigned-classes'];
    case 'finalResult':
      return ['/report-card-formats', '/exams', '/grade-schemes'];
    default:
      return const [];
  }
}

String _today() {
  final now = DateTime.now();
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return '${now.year}-$month-$day';
}

const _accountMetrics = [
  AdminMetric(
    label: 'Collection',
    value: 'Live',
    helper: 'Fee receipts',
    icon: Icons.payments_rounded,
    color: _green,
  ),
  AdminMetric(
    label: 'Due',
    value: 'Review',
    helper: 'Outstanding fees',
    icon: Icons.receipt_long_rounded,
    color: _rose,
  ),
  AdminMetric(
    label: 'Reports',
    value: 'Ready',
    helper: 'Day and session',
    icon: Icons.query_stats_rounded,
    color: _blue,
  ),
  AdminMetric(
    label: 'Setup',
    value: 'Masters',
    helper: 'Heads and modes',
    icon: Icons.tune_rounded,
    color: _amber,
  ),
];

const _accountsWorkActions = [
  AdminAction(
    title: 'Collect Fee',
    subtitle: 'Receipt entry and payment modes',
    icon: Icons.currency_rupee_rounded,
    color: _green,
    routeName: '/accounts/collect-fee',
  ),
  AdminAction(
    title: 'Day Collection',
    subtitle: 'Daily collection and receipts',
    icon: Icons.calendar_today_rounded,
    color: _blue,
    routeName: '/accounts/day-collection',
  ),
  AdminAction(
    title: 'Fee Due Report',
    subtitle: 'Student outstanding fees',
    icon: Icons.receipt_long_rounded,
    color: _rose,
    routeName: '/accounts/fee-due',
  ),
  AdminAction(
    title: 'Session Summary',
    subtitle: 'School fee session summary',
    icon: Icons.query_stats_rounded,
    color: _purple,
    routeName: '/accounts/session-summary',
  ),
];

const _accountsReportActions = [
  AdminAction(
    title: 'Fee Head Collection',
    subtitle: 'Head-wise collection report',
    icon: Icons.stacked_bar_chart_rounded,
    color: _teal,
    routeName: '/accounts/fee-head-collection',
  ),
  AdminAction(
    title: 'Cancelled Receipts',
    subtitle: 'Cancelled fee receipts',
    icon: Icons.cancel_rounded,
    color: _rose,
    routeName: '/accounts/cancelled-receipts',
  ),
  AdminAction(
    title: 'Concession Report',
    subtitle: 'Concession summary',
    icon: Icons.summarize_rounded,
    color: _purple,
    routeName: '/accounts/concession-report',
  ),
  AdminAction(
    title: 'Transport Fee',
    subtitle: 'Van fee report',
    icon: Icons.directions_bus_rounded,
    color: _cyan,
    routeName: '/accounts/transport-fee',
  ),
];

const _accountsSetupActions = [
  AdminAction(
    title: 'Opening Balances',
    subtitle: 'Previous balance entries',
    icon: Icons.account_balance_rounded,
    color: _slate,
    routeName: '/accounts/opening-balances',
  ),
  AdminAction(
    title: 'Fee Structure',
    subtitle: 'Class fee setup',
    icon: Icons.account_tree_rounded,
    color: _amber,
    routeName: '/accounts/fee-structure',
  ),
  AdminAction(
    title: 'Fee Headings',
    subtitle: 'Fee head master',
    icon: Icons.bookmark_rounded,
    color: _blue,
    routeName: '/accounts/fee-headings',
  ),
  AdminAction(
    title: 'Fee Category',
    subtitle: 'Fee category master',
    icon: Icons.category_rounded,
    color: _teal,
    routeName: '/accounts/fee-category',
  ),
  AdminAction(
    title: 'Concessions',
    subtitle: 'Concession master',
    icon: Icons.local_offer_rounded,
    color: _purple,
    routeName: '/accounts/concessions',
  ),
  AdminAction(
    title: 'Modes & Banks',
    subtitle: 'Payment modes and banks',
    icon: Icons.account_balance_wallet_rounded,
    color: _green,
    routeName: '/accounts/payment-setup',
  ),
];

const Map<String, _AccountSpecInfo> _accountsInfo = {
  'collectFee': _AccountSpecInfo(
    title: 'Collect Fee',
    summary:
        'Review receipt records, payment modes, bank accounts and recent fee activity.',
    icon: Icons.currency_rupee_rounded,
    accent: _green,
    group: 'work',
  ),
  'dayCollection': _AccountSpecInfo(
    title: 'Day Collection',
    summary:
        'Check today collection, receipt rows, cancelled entries and payment totals.',
    icon: Icons.calendar_today_rounded,
    accent: _blue,
    group: 'work',
  ),
  'feeDue': _AccountSpecInfo(
    title: 'Fee Due Report',
    summary:
        'Review student outstanding fees, pending balances and follow-up records.',
    icon: Icons.receipt_long_rounded,
    accent: _rose,
    group: 'work',
  ),
  'sessionSummary': _AccountSpecInfo(
    title: 'Session Summary',
    summary:
        'Review school fee totals, session summaries, opening balances and fee heads.',
    icon: Icons.query_stats_rounded,
    accent: _purple,
    group: 'work',
  ),
  'feeHeadCollection': _AccountSpecInfo(
    title: 'Fee Head Collection',
    summary:
        'Check fee-head-wise collection details across receipts and selected periods.',
    icon: Icons.stacked_bar_chart_rounded,
    accent: _teal,
    group: 'report',
  ),
  'bulkConcessions': _AccountSpecInfo(
    title: 'Bulk Concessions',
    summary:
        'Review concession setup and student concession activity for account approval.',
    icon: Icons.percent_rounded,
    accent: _amber,
    group: 'work',
  ),
  'cancelledReceipts': _AccountSpecInfo(
    title: 'Cancelled Receipts',
    summary:
        'Track cancelled receipt rows and keep reversal activity visible for review.',
    icon: Icons.cancel_rounded,
    accent: _rose,
    group: 'report',
  ),
  'concessionReport': _AccountSpecInfo(
    title: 'Concession Report',
    summary:
        'Review concession report data grouped for class, student and fee head checks.',
    icon: Icons.summarize_rounded,
    accent: _purple,
    group: 'report',
  ),
  'transportFee': _AccountSpecInfo(
    title: 'Transport Fee',
    summary:
        'Review van fee details, transport concessions and pending transport amounts.',
    icon: Icons.directions_bus_rounded,
    accent: _cyan,
    group: 'report',
  ),
  'openingBalances': _AccountSpecInfo(
    title: 'Opening Balances',
    summary:
        'Review previous balance entries carried into the active fee session.',
    icon: Icons.account_balance_rounded,
    accent: _slate,
    group: 'setup',
  ),
  'feeStructure': _AccountSpecInfo(
    title: 'Fee Structure',
    summary:
        'Review class-wise fee structure rows, sessions and linked fee heads.',
    icon: Icons.account_tree_rounded,
    accent: _amber,
    group: 'setup',
  ),
  'studentFeeStructure': _AccountSpecInfo(
    title: 'Student Fee Structure',
    summary:
        'Review student-specific fee structure rows and session assignments.',
    icon: Icons.person_pin_rounded,
    accent: _indigo,
    group: 'setup',
  ),
  'feeHeadings': _AccountSpecInfo(
    title: 'Fee Headings',
    summary: 'Review fee heading master data and linked fee categories.',
    icon: Icons.bookmark_rounded,
    accent: _blue,
    group: 'setup',
  ),
  'feeCategory': _AccountSpecInfo(
    title: 'Fee Category',
    summary: 'Review fee category master data used across fee headings.',
    icon: Icons.category_rounded,
    accent: _teal,
    group: 'setup',
  ),
  'concessions': _AccountSpecInfo(
    title: 'Concessions',
    summary: 'Review concession master rows and concession policy names.',
    icon: Icons.local_offer_rounded,
    accent: _purple,
    group: 'setup',
  ),
  'paymentSetup': _AccountSpecInfo(
    title: 'Modes & Banks',
    summary:
        'Review payment mode setup and active bank accounts used for receipts.',
    icon: Icons.account_balance_wallet_rounded,
    accent: _green,
    group: 'setup',
  ),
  'messages': _AccountSpecInfo(
    title: 'Accounts Messages',
    summary: 'Review account office communication and fee reminder threads.',
    icon: Icons.chat_bubble_rounded,
    accent: _blue,
    group: 'work',
  ),
};

_FeatureSpec _accountsSpec(String key) {
  final info = _accountsInfo[key] ?? _accountsInfo['collectFee']!;
  return _FeatureSpec(
    title: info.title,
    summary: info.summary,
    icon: info.icon,
    accent: info.accent,
    metrics: _accountMetrics,
    actions: _accountsActionsFor(info.group),
    checklistTitle: 'Review',
    recordsTitle: 'Live Records',
    checklist: [
      AdminFeedItem(
        title: '${info.title} records',
        subtitle:
            'Latest available records are shown below after the screen syncs.',
        meta: 'Live',
        icon: info.icon,
        color: info.accent,
      ),
      const AdminFeedItem(
        title: 'Accounts follow-up',
        subtitle:
            'Use related actions to move between collection, dues, reports and setup.',
        meta: 'Desk',
        icon: Icons.rule_rounded,
        color: _slate,
      ),
    ],
    records: [
      AdminFeedItem(
        title: 'Pull down to refresh',
        subtitle:
            'The screen updates from the latest backend data when refreshed.',
        meta: 'Refresh',
        icon: Icons.refresh_rounded,
        color: info.accent,
      ),
    ],
  );
}

List<AdminAction> _accountsActionsFor(String group) {
  switch (group) {
    case 'report':
      return _accountsReportActions;
    case 'setup':
      return _accountsSetupActions;
    case 'work':
    default:
      return _accountsWorkActions;
  }
}

const _superadminActions = [
  AdminAction(
    title: 'School Settings',
    subtitle: 'Academic year, policy and calendar setup',
    icon: Icons.settings_rounded,
    color: _indigo,
    routeName: '/superadmin/school-settings',
  ),
  AdminAction(
    title: 'Users & Roles',
    subtitle: 'Accounts, roles and access control',
    icon: Icons.manage_accounts_rounded,
    color: _blue,
    routeName: '/superadmin/user-management',
  ),
  AdminAction(
    title: 'Permissions',
    subtitle: 'Role permissions and module visibility',
    icon: Icons.verified_user_rounded,
    color: _purple,
    routeName: '/superadmin/permissions',
  ),
  AdminAction(
    title: 'School Reports',
    subtitle: 'Strength, fee, caste and gender analytics',
    icon: Icons.query_stats_rounded,
    color: _green,
    routeName: '/superadmin/school-reports',
  ),
  AdminAction(
    title: 'Day Collection',
    subtitle: 'Daily fee collection review',
    icon: Icons.payments_rounded,
    color: _green,
    routeName: '/accounts/day-collection',
  ),
  AdminAction(
    title: 'Fee Due Report',
    subtitle: 'Outstanding fee details',
    icon: Icons.receipt_long_rounded,
    color: _rose,
    routeName: '/accounts/fee-due',
  ),
  AdminAction(
    title: 'Academic Year',
    subtitle: 'Sessions, terms and working calendars',
    icon: Icons.calendar_month_rounded,
    color: _amber,
    routeName: '/superadmin/academic-year',
  ),
  AdminAction(
    title: 'Classes & Sections',
    subtitle: 'Class structure, sections and roll setup',
    icon: Icons.account_tree_rounded,
    color: _teal,
    routeName: '/superadmin/classes-sections',
  ),
];

const _hrActions = [
  AdminAction(
    title: 'Employee Directory',
    subtitle: 'Staff profiles, codes and departments',
    icon: Icons.badge_rounded,
    color: _green,
    routeName: '/hr/employees',
  ),
  AdminAction(
    title: 'Leave & Attendance',
    subtitle: 'Daily status, absentees and leave summary',
    icon: Icons.event_note_rounded,
    color: _blue,
    routeName: '/hr/leave-attendance',
  ),
  AdminAction(
    title: 'Leave Requests',
    subtitle: 'Pending approvals and remarks',
    icon: Icons.fact_check_rounded,
    color: _amber,
    routeName: '/hr/leave-requests',
  ),
  AdminAction(
    title: 'Attendance Calendar',
    subtitle: 'Employee month-wise attendance view',
    icon: Icons.calendar_view_month_rounded,
    color: _teal,
    routeName: '/hr/attendance-calendar',
  ),
  AdminAction(
    title: 'Messages',
    subtitle: 'HR reminders and staff communication',
    icon: Icons.chat_bubble_rounded,
    color: _purple,
    routeName: '/hr/messages',
  ),
  AdminAction(
    title: 'Onboarding',
    subtitle: 'Joining pipeline and document readiness',
    icon: Icons.login_rounded,
    color: _rose,
    routeName: '/hr/onboarding',
  ),
];

const _transportActions = [
  AdminAction(
    title: 'Routes',
    subtitle: 'Transportations, villages and fine rules',
    icon: Icons.signpost_rounded,
    color: _cyan,
    routeName: '/transport/routes',
  ),
  AdminAction(
    title: 'Buses',
    subtitle: 'Fleet, driver and conductor assignment',
    icon: Icons.directions_bus_rounded,
    color: _green,
    routeName: '/transport/buses',
  ),
  AdminAction(
    title: 'Assign Students',
    subtitle: 'Student route and stop assignment',
    icon: Icons.person_pin_circle_rounded,
    color: _indigo,
    routeName: '/transport/student-assignments',
  ),
  AdminAction(
    title: 'Staff',
    subtitle: 'Drivers, conductors and linked users',
    icon: Icons.badge_rounded,
    color: _rose,
    routeName: '/transport/staff',
  ),
  AdminAction(
    title: 'Mark Attendance',
    subtitle: 'Pickup and drop mobile marking',
    icon: Icons.check_circle_rounded,
    color: _amber,
    routeName: '/transport/attendance',
  ),
  AdminAction(
    title: 'Attendance Report',
    subtitle: 'Bus-wise present and absent report',
    icon: Icons.assessment_rounded,
    color: _teal,
    routeName: '/transport/attendance-report',
  ),
];

const _examinationManageActions = [
  AdminAction(
    title: 'Manage Exams',
    subtitle: 'Create, edit and lock exams',
    icon: Icons.edit_calendar_rounded,
    color: _blue,
    routeName: '/examination/exams',
  ),
  AdminAction(
    title: 'Exam Schedule',
    subtitle: 'Dates, sessions and invigilation plan',
    icon: Icons.event_rounded,
    color: _cyan,
    routeName: '/examination/schedule',
  ),
  AdminAction(
    title: 'Exam Schemes',
    subtitle: 'Components, weightage and terms',
    icon: Icons.schema_rounded,
    color: _purple,
    routeName: '/examination/schemes',
  ),
  AdminAction(
    title: 'Report Formats',
    subtitle: 'Report card layouts and templates',
    icon: Icons.article_rounded,
    color: _green,
    routeName: '/examination/report-cards',
  ),
];

const _examinationEntryActions = [
  AdminAction(
    title: 'Marks Entry',
    subtitle: 'Enter and update subject marks',
    icon: Icons.edit_note_rounded,
    color: _blue,
    badge: 'ENTRY',
    routeName: '/examination/marks-entry',
  ),
  AdminAction(
    title: 'Co-Scholastic',
    subtitle: 'Grades, areas and mapping',
    icon: Icons.extension_rounded,
    color: _teal,
    badge: 'ENTRY',
    routeName: '/examination/co-scholastic',
  ),
  AdminAction(
    title: 'Remarks',
    subtitle: 'Student comments and class remarks',
    icon: Icons.rate_review_rounded,
    color: _amber,
    badge: 'ENTRY',
    routeName: '/examination/remarks',
  ),
  AdminAction(
    title: 'Promotion',
    subtitle: 'Promotion decisions and class movement',
    icon: Icons.school_rounded,
    color: _indigo,
    badge: 'ENTRY',
    routeName: '/examination/promotion',
  ),
];

const _examinationReportActions = [
  AdminAction(
    title: 'Final Result',
    subtitle: 'Class-wise totals, grades and toppers',
    icon: Icons.emoji_events_rounded,
    color: _amber,
    badge: 'REPORT',
    routeName: '/examination/final-result',
  ),
  AdminAction(
    title: 'Result Moderation',
    subtitle: 'Review and approve student results',
    icon: Icons.grade_rounded,
    color: _rose,
    routeName: '/examination/result-moderation',
  ),
  AdminAction(
    title: 'Exam Reports',
    subtitle: 'Summaries, analytics and exports',
    icon: Icons.assignment_turned_in_rounded,
    color: _green,
    routeName: '/examination/reports',
  ),
  AdminAction(
    title: 'Report Cards',
    subtitle: 'Generate student-wise report cards',
    icon: Icons.picture_as_pdf_rounded,
    color: _slate,
    badge: 'PDF',
    routeName: '/examination/report-cards',
  ),
];

const Map<String, _FeatureSpec> _superadminSpecs = {
  'schoolSettings': _FeatureSpec(
    title: 'School Settings',
    summary:
        'Configure the school-wide academic setup, policy defaults and operational preferences.',
    icon: Icons.settings_rounded,
    accent: _indigo,
    metrics: [
      AdminMetric(
          label: 'Session',
          value: '2026-27',
          helper: 'Active academic year',
          icon: Icons.calendar_today_rounded,
          color: _indigo),
      AdminMetric(
          label: 'Setup',
          value: 'Live',
          helper: 'School profile ready',
          icon: Icons.verified_rounded,
          color: _green),
      AdminMetric(
          label: 'Modules',
          value: '12+',
          helper: 'ERP areas connected',
          icon: Icons.apps_rounded,
          color: _purple),
      AdminMetric(
          label: 'Calendar',
          value: 'Open',
          helper: 'Holidays and terms',
          icon: Icons.event_available_rounded,
          color: _amber),
    ],
    actions: _superadminActions,
    checklist: [
      AdminFeedItem(
          title: 'Academic session',
          subtitle:
              'Session, term windows and working calendar remain the first setup checkpoint.',
          meta: 'Core',
          icon: Icons.date_range_rounded,
          color: _indigo),
      AdminFeedItem(
          title: 'School profile',
          subtitle:
              'Institution identity, contact details, certificates and print headers stay aligned.',
          meta: 'Profile',
          icon: Icons.account_balance_rounded,
          color: _blue),
      AdminFeedItem(
          title: 'Module access',
          subtitle:
              'Dashboard access follows role permission setup from the PITS web portal.',
          meta: 'RBAC',
          icon: Icons.lock_person_rounded,
          color: _purple),
    ],
    records: [
      AdminFeedItem(
          title: 'Holiday marking',
          subtitle:
              'Review academic calendar before enabling attendance for the next cycle.',
          meta: 'Today',
          icon: Icons.beach_access_rounded,
          color: _amber),
      AdminFeedItem(
          title: 'School bank accounts',
          subtitle:
              'Fee receipts and certificates use the configured account details.',
          meta: 'Finance',
          icon: Icons.account_balance_wallet_rounded,
          color: _green),
    ],
  ),
  'userManagement': _FeatureSpec(
    title: 'User & Role Management',
    summary:
        'Create users, map employees and students, and control mobile or portal access.',
    icon: Icons.manage_accounts_rounded,
    accent: _blue,
    metrics: [
      AdminMetric(
          label: 'Roles',
          value: '7+',
          helper: 'Mobile supported roles',
          icon: Icons.groups_rounded,
          color: _blue),
      AdminMetric(
          label: 'Access',
          value: 'RBAC',
          helper: 'Role permission model',
          icon: Icons.security_rounded,
          color: _purple),
      AdminMetric(
          label: 'Staff',
          value: 'Linked',
          helper: 'Employee user accounts',
          icon: Icons.badge_rounded,
          color: _green),
      AdminMetric(
          label: 'Students',
          value: 'Linked',
          helper: 'Student user accounts',
          icon: Icons.school_rounded,
          color: _amber),
    ],
    actions: [
      ..._superadminActions,
      AdminAction(
          title: 'Employee Accounts',
          subtitle: 'Staff login account mapping',
          icon: Icons.badge_rounded,
          color: _green,
          routeName: '/hr/employee-accounts'),
    ],
    checklist: [
      AdminFeedItem(
          title: 'Role assignment',
          subtitle: 'Assign only the role needed for each user workflow.',
          meta: 'Access',
          icon: Icons.assignment_ind_rounded,
          color: _blue),
      AdminFeedItem(
          title: 'Status cleanup',
          subtitle:
              'Disable inactive users and verify linked employee or student records.',
          meta: 'Audit',
          icon: Icons.rule_rounded,
          color: _amber),
      AdminFeedItem(
          title: 'Role switch',
          subtitle: 'Multi-role users can switch from the mobile app drawer.',
          meta: 'Mobile',
          icon: Icons.switch_account_rounded,
          color: _purple),
    ],
    records: [
      AdminFeedItem(
          title: 'Permissions review',
          subtitle:
              'PITS web permission groups are now reflected in the mobile role dashboard paths.',
          meta: 'RBAC',
          icon: Icons.admin_panel_settings_rounded,
          color: _purple),
    ],
  ),
  'schoolReports': _FeatureSpec(
    title: 'School Reports',
    summary:
        'Track school strength, category reports, transport, fee and operational summaries.',
    icon: Icons.query_stats_rounded,
    accent: _green,
    metrics: [
      AdminMetric(
          label: 'Strength',
          value: 'Live',
          helper: 'Class-wise rollup',
          icon: Icons.groups_rounded,
          color: _green),
      AdminMetric(
          label: 'Fees',
          value: 'Due',
          helper: 'Summary and collection',
          icon: Icons.payments_rounded,
          color: _amber),
      AdminMetric(
          label: 'Transport',
          value: 'Mapped',
          helper: 'Routes and assignments',
          icon: Icons.directions_bus_rounded,
          color: _cyan),
      AdminMetric(
          label: 'Reports',
          value: 'PDF',
          helper: 'Portal exports ready',
          icon: Icons.picture_as_pdf_rounded,
          color: _rose),
    ],
    actions: _superadminActions,
    checklist: [
      AdminFeedItem(
          title: 'Student strength',
          subtitle:
              'Class, gender, caste and religion summaries match the PITS web reports.',
          meta: 'MIS',
          icon: Icons.diversity_3_rounded,
          color: _green),
      AdminFeedItem(
          title: 'Fee analytics',
          subtitle:
              'Use due, concession and collection report paths for finance follow-up.',
          meta: 'Fees',
          icon: Icons.receipt_long_rounded,
          color: _amber),
      AdminFeedItem(
          title: 'Transport summary',
          subtitle:
              'Transport assignments and van fee summaries are grouped for review.',
          meta: 'Bus',
          icon: Icons.alt_route_rounded,
          color: _cyan),
    ],
    records: [
      AdminFeedItem(
          title: 'Final result link',
          subtitle:
              'Exam analytics are available from the Examination dashboard.',
          meta: 'Exam',
          icon: Icons.emoji_events_rounded,
          color: _purple),
    ],
  ),
  'permissions': _FeatureSpec(
    title: 'Role Permissions',
    summary:
        'Review role permissions, module groups and dashboard visibility for school users.',
    icon: Icons.verified_user_rounded,
    accent: _purple,
    metrics: [
      AdminMetric(
          label: 'Mode',
          value: 'RBAC',
          helper: 'Permission driven',
          icon: Icons.lock_rounded,
          color: _purple),
      AdminMetric(
          label: 'Modules',
          value: 'Grouped',
          helper: 'Role-wise access',
          icon: Icons.dashboard_customize_rounded,
          color: _blue),
      AdminMetric(
          label: 'Audit',
          value: 'Ready',
          helper: 'Review access',
          icon: Icons.fact_check_rounded,
          color: _green),
      AdminMetric(
          label: 'Mobile',
          value: 'Synced',
          helper: 'Supported roles',
          icon: Icons.phone_android_rounded,
          color: _amber),
    ],
    actions: _superadminActions,
    checklist: [
      AdminFeedItem(
          title: 'Permission groups',
          subtitle: 'Keep sensitive finance, exam and HR modules role-bound.',
          meta: 'RBAC',
          icon: Icons.shield_rounded,
          color: _purple),
      AdminFeedItem(
          title: 'Mobile visibility',
          subtitle: 'Only mobile-supported roles appear in role selection.',
          meta: 'App',
          icon: Icons.mobile_friendly_rounded,
          color: _blue),
    ],
    records: [
      AdminFeedItem(
          title: 'Superadmin override',
          subtitle: 'Superadmin remains the complete access and recovery role.',
          meta: 'Admin',
          icon: Icons.key_rounded,
          color: _rose),
    ],
  ),
  'academicYear': _FeatureSpec(
    title: 'Academic Year',
    summary:
        'Manage sessions, terms, working days, holidays and academic calendar setup.',
    icon: Icons.calendar_month_rounded,
    accent: _amber,
    metrics: [
      AdminMetric(
          label: 'Session',
          value: '2026-27',
          helper: 'Current cycle',
          icon: Icons.event_rounded,
          color: _amber),
      AdminMetric(
          label: 'Terms',
          value: 'Ready',
          helper: 'Term setup',
          icon: Icons.timeline_rounded,
          color: _blue),
      AdminMetric(
          label: 'Holidays',
          value: 'Mark',
          helper: 'Calendar updates',
          icon: Icons.event_busy_rounded,
          color: _rose),
      AdminMetric(
          label: 'Attendance',
          value: 'Linked',
          helper: 'Working days',
          icon: Icons.how_to_reg_rounded,
          color: _green),
    ],
    actions: _superadminActions,
    checklist: [
      AdminFeedItem(
          title: 'Session rollover',
          subtitle:
              'Confirm classes, sections and fee structures before opening new session work.',
          meta: 'Year',
          icon: Icons.update_rounded,
          color: _amber),
      AdminFeedItem(
          title: 'Holiday marking',
          subtitle:
              'Holiday dates affect student, teacher and employee attendance views.',
          meta: 'Calendar',
          icon: Icons.beach_access_rounded,
          color: _rose),
    ],
    records: [
      AdminFeedItem(
          title: 'Term windows',
          subtitle: 'Exam schemes and report cards depend on clean term setup.',
          meta: 'Exam',
          icon: Icons.schema_rounded,
          color: _purple),
    ],
  ),
  'classesSections': _FeatureSpec(
    title: 'Classes & Sections',
    summary:
        'Maintain classes, sections, houses, roll numbers and student promotion structure.',
    icon: Icons.account_tree_rounded,
    accent: _teal,
    metrics: [
      AdminMetric(
          label: 'Classes',
          value: 'Open',
          helper: 'Class master',
          icon: Icons.class_rounded,
          color: _teal),
      AdminMetric(
          label: 'Sections',
          value: 'Open',
          helper: 'Section master',
          icon: Icons.view_module_rounded,
          color: _blue),
      AdminMetric(
          label: 'Roll Nos.',
          value: 'Ready',
          helper: 'Roll management',
          icon: Icons.format_list_numbered_rounded,
          color: _amber),
      AdminMetric(
          label: 'Promotion',
          value: 'Linked',
          helper: 'Next class flow',
          icon: Icons.school_rounded,
          color: _green),
    ],
    actions: _superadminActions,
    checklist: [
      AdminFeedItem(
          title: 'Class structure',
          subtitle:
              'Keep class and section records clean before timetable, fees and exams.',
          meta: 'Setup',
          icon: Icons.account_tree_rounded,
          color: _teal),
      AdminFeedItem(
          title: 'Roll number management',
          subtitle:
              'Roll numbers drive attendance sheets and report card ordering.',
          meta: 'Roster',
          icon: Icons.pin_rounded,
          color: _amber),
    ],
    records: [
      AdminFeedItem(
          title: 'Promotion history',
          subtitle:
              'Promotion decisions from Examination flow can feed the next session.',
          meta: 'Result',
          icon: Icons.moving_rounded,
          color: _green),
    ],
  ),
  'userTracking': _FeatureSpec(
    title: 'User Tracking',
    summary:
        'Review login activity, user actions and operational accountability snapshots.',
    icon: Icons.manage_search_rounded,
    accent: _slate,
    metrics: [
      AdminMetric(
          label: 'Activity',
          value: 'Live',
          helper: 'Portal tracking',
          icon: Icons.track_changes_rounded,
          color: _slate),
      AdminMetric(
          label: 'Users',
          value: 'Mapped',
          helper: 'Role audit',
          icon: Icons.people_alt_rounded,
          color: _blue),
      AdminMetric(
          label: 'Risk',
          value: 'Review',
          helper: 'Access cleanup',
          icon: Icons.warning_rounded,
          color: _amber),
      AdminMetric(
          label: 'Logs',
          value: 'Portal',
          helper: 'Detailed history',
          icon: Icons.history_rounded,
          color: _purple),
    ],
    actions: _superadminActions,
    checklist: [
      AdminFeedItem(
          title: 'Audit trail',
          subtitle:
              'Use tracking to review sensitive school, fee, HR and exam changes.',
          meta: 'Audit',
          icon: Icons.history_edu_rounded,
          color: _slate),
      AdminFeedItem(
          title: 'Inactive cleanup',
          subtitle:
              'Disable stale accounts and verify role mappings regularly.',
          meta: 'Access',
          icon: Icons.person_off_rounded,
          color: _rose),
    ],
    records: [
      AdminFeedItem(
          title: 'Role switch events',
          subtitle:
              'Multi-role activity should be checked when investigating access concerns.',
          meta: 'Roles',
          icon: Icons.switch_account_rounded,
          color: _blue),
    ],
  ),
  'bankAccounts': _FeatureSpec(
    title: 'School Bank Accounts',
    summary:
        'Manage bank details used in receipts, certificates and finance communication.',
    icon: Icons.account_balance_wallet_rounded,
    accent: _green,
    metrics: [
      AdminMetric(
          label: 'Receipts',
          value: 'Linked',
          helper: 'Fee print setup',
          icon: Icons.receipt_rounded,
          color: _green),
      AdminMetric(
          label: 'Gateway',
          value: 'Ready',
          helper: 'Payment settings',
          icon: Icons.payments_rounded,
          color: _blue),
      AdminMetric(
          label: 'Certificates',
          value: 'Linked',
          helper: 'Print templates',
          icon: Icons.workspace_premium_rounded,
          color: _amber),
      AdminMetric(
          label: 'Status',
          value: 'Review',
          helper: 'Account details',
          icon: Icons.rule_rounded,
          color: _rose),
    ],
    actions: _superadminActions,
    checklist: [
      AdminFeedItem(
          title: 'Receipt footer',
          subtitle:
              'Bank details appear on fee communication and receipt templates.',
          meta: 'Fees',
          icon: Icons.receipt_long_rounded,
          color: _green),
      AdminFeedItem(
          title: 'Payment gateway',
          subtitle: 'Gateway settings should match the active school account.',
          meta: 'Pay',
          icon: Icons.credit_card_rounded,
          color: _blue),
    ],
    records: [
      AdminFeedItem(
          title: 'Certificate print',
          subtitle:
              'Bonafide and fee certificates use school identity details.',
          meta: 'Print',
          icon: Icons.print_rounded,
          color: _amber),
    ],
  ),
  'aiSettings': _FeatureSpec(
    title: 'AI Settings',
    summary:
        'Configure AI features, assistant availability and school-level automation settings.',
    icon: Icons.auto_awesome_rounded,
    accent: _purple,
    metrics: [
      AdminMetric(
          label: 'Assistant',
          value: 'Ready',
          helper: 'AI module',
          icon: Icons.smart_toy_rounded,
          color: _purple),
      AdminMetric(
          label: 'Safety',
          value: 'Review',
          helper: 'Usage controls',
          icon: Icons.shield_rounded,
          color: _blue),
      AdminMetric(
          label: 'Prompts',
          value: 'School',
          helper: 'Institution context',
          icon: Icons.tune_rounded,
          color: _green),
      AdminMetric(
          label: 'Access',
          value: 'Role',
          helper: 'Permission driven',
          icon: Icons.lock_rounded,
          color: _amber),
    ],
    actions: _superadminActions,
    checklist: [
      AdminFeedItem(
          title: 'Assistant access',
          subtitle:
              'Keep AI settings tied to school policy and staff permissions.',
          meta: 'AI',
          icon: Icons.auto_awesome_rounded,
          color: _purple),
      AdminFeedItem(
          title: 'Context quality',
          subtitle:
              'School profile and module data should stay updated for useful responses.',
          meta: 'Data',
          icon: Icons.data_object_rounded,
          color: _blue),
    ],
    records: [
      AdminFeedItem(
          title: 'Role visibility',
          subtitle: 'Only approved staff roles should see automation tools.',
          meta: 'RBAC',
          icon: Icons.verified_user_rounded,
          color: _green),
    ],
  ),
};

const Map<String, _FeatureSpec> _hrSpecs = {
  'employees': _FeatureSpec(
    title: 'Employee Directory',
    summary:
        'Browse staff profiles, departments, designations and linked user accounts.',
    icon: Icons.badge_rounded,
    accent: _green,
    metrics: [
      AdminMetric(
          label: 'Profiles',
          value: 'Active',
          helper: 'Enabled staff',
          icon: Icons.badge_rounded,
          color: _green),
      AdminMetric(
          label: 'Departments',
          value: 'Mapped',
          helper: 'Department master',
          icon: Icons.apartment_rounded,
          color: _blue),
      AdminMetric(
          label: 'Users',
          value: 'Linked',
          helper: 'Login accounts',
          icon: Icons.person_rounded,
          color: _purple),
      AdminMetric(
          label: 'Status',
          value: 'Review',
          helper: 'Disabled staff',
          icon: Icons.rule_rounded,
          color: _amber),
    ],
    actions: _hrActions,
    checklist: [
      AdminFeedItem(
          title: 'Profile completeness',
          subtitle:
              'Employee code, department, designation and contact details should be complete.',
          meta: 'Staff',
          icon: Icons.assignment_ind_rounded,
          color: _green),
      AdminFeedItem(
          title: 'Account mapping',
          subtitle:
              'Teacher and HR login access depends on linked employee user accounts.',
          meta: 'Users',
          icon: Icons.link_rounded,
          color: _blue),
    ],
    records: [
      AdminFeedItem(
          title: 'Directory search',
          subtitle:
              'Use department and role filters before attendance or leave follow-up.',
          meta: 'HR',
          icon: Icons.search_rounded,
          color: _purple),
    ],
  ),
  'leaveAttendance': _FeatureSpec(
    title: 'Leave & Attendance',
    summary:
        'Review daily staff attendance, absentees, leave categories and unmarked records.',
    icon: Icons.event_note_rounded,
    accent: _blue,
    metrics: [
      AdminMetric(
          label: 'Present',
          value: 'Today',
          helper: 'Marked staff',
          icon: Icons.check_circle_rounded,
          color: _green),
      AdminMetric(
          label: 'Absent',
          value: 'Track',
          helper: 'Follow-up list',
          icon: Icons.cancel_rounded,
          color: _rose),
      AdminMetric(
          label: 'Leave',
          value: 'Pending',
          helper: 'Requests and approvals',
          icon: Icons.pending_actions_rounded,
          color: _amber),
      AdminMetric(
          label: 'Unmarked',
          value: 'Audit',
          helper: 'Daily cleanup',
          icon: Icons.edit_calendar_rounded,
          color: _blue),
    ],
    actions: _hrActions,
    checklist: [
      AdminFeedItem(
          title: 'Date review',
          subtitle:
              'Move across dates and compare marked, absent, leave and unmarked staff.',
          meta: 'Daily',
          icon: Icons.today_rounded,
          color: _blue),
      AdminFeedItem(
          title: 'Teacher absentee list',
          subtitle:
              'Teacher absences should be checked with substitutions and timetable impact.',
          meta: 'Academic',
          icon: Icons.school_rounded,
          color: _purple),
      AdminFeedItem(
          title: 'Leave status',
          subtitle:
              'Pending leave requests need approval, rejection or remarks before payroll review.',
          meta: 'Leave',
          icon: Icons.fact_check_rounded,
          color: _amber),
    ],
    records: [
      AdminFeedItem(
          title: 'Short leave',
          subtitle:
              'Short leave and half-day records are tracked separately from full-day leave.',
          meta: 'Policy',
          icon: Icons.timer_rounded,
          color: _teal),
    ],
  ),
  'onboarding': _FeatureSpec(
    title: 'Staff Onboarding',
    summary:
        'Track recruitment, joining details, document collection and account readiness.',
    icon: Icons.login_rounded,
    accent: _rose,
    metrics: [
      AdminMetric(
          label: 'Joining',
          value: 'Queue',
          helper: 'New staff',
          icon: Icons.person_add_rounded,
          color: _rose),
      AdminMetric(
          label: 'Documents',
          value: 'Check',
          helper: 'Pending files',
          icon: Icons.description_rounded,
          color: _amber),
      AdminMetric(
          label: 'Accounts',
          value: 'Create',
          helper: 'User access',
          icon: Icons.manage_accounts_rounded,
          color: _blue),
      AdminMetric(
          label: 'Induction',
          value: 'Plan',
          helper: 'Department handoff',
          icon: Icons.handshake_rounded,
          color: _green),
    ],
    actions: _hrActions,
    checklist: [
      AdminFeedItem(
          title: 'Joining record',
          subtitle:
              'Create employee profile before account, attendance and payroll mapping.',
          meta: 'Start',
          icon: Icons.person_add_alt_1_rounded,
          color: _rose),
      AdminFeedItem(
          title: 'Department handoff',
          subtitle:
              'Assign department, designation, reporting role and timetable needs.',
          meta: 'Dept',
          icon: Icons.apartment_rounded,
          color: _blue),
      AdminFeedItem(
          title: 'Access setup',
          subtitle:
              'Create linked user account only after role and status are confirmed.',
          meta: 'Login',
          icon: Icons.key_rounded,
          color: _purple),
    ],
    records: [
      AdminFeedItem(
          title: 'Policy acknowledgment',
          subtitle:
              'Attendance, leave and communication rules should be shared during onboarding.',
          meta: 'HR',
          icon: Icons.rule_folder_rounded,
          color: _green),
    ],
  ),
  'leaveRequests': _FeatureSpec(
    title: 'HR Leave Requests',
    summary:
        'Review pending employee leaves, dates, reasons, paid status and approval remarks.',
    icon: Icons.fact_check_rounded,
    accent: _amber,
    metrics: [
      AdminMetric(
          label: 'Pending',
          value: 'Open',
          helper: 'Needs action',
          icon: Icons.pending_actions_rounded,
          color: _amber),
      AdminMetric(
          label: 'Approved',
          value: 'Track',
          helper: 'Leave ledger',
          icon: Icons.task_alt_rounded,
          color: _green),
      AdminMetric(
          label: 'Rejected',
          value: 'Audit',
          helper: 'With remarks',
          icon: Icons.cancel_rounded,
          color: _rose),
      AdminMetric(
          label: 'WOP',
          value: 'Check',
          helper: 'Without pay',
          icon: Icons.money_off_rounded,
          color: _slate),
    ],
    actions: _hrActions,
    checklist: [
      AdminFeedItem(
          title: 'Latest request first',
          subtitle:
              'PITS highlights the newest pending request for fast approval.',
          meta: 'Queue',
          icon: Icons.new_releases_rounded,
          color: _amber),
      AdminFeedItem(
          title: 'Remarks required',
          subtitle:
              'Approval or rejection should include clear HR remarks when needed.',
          meta: 'Review',
          icon: Icons.rate_review_rounded,
          color: _blue),
    ],
    records: [
      AdminFeedItem(
          title: 'Paid vs without pay',
          subtitle: 'Check WOP flag before payroll or salary processing.',
          meta: 'Payroll',
          icon: Icons.payments_rounded,
          color: _green),
    ],
  ),
  'attendanceCalendar': _FeatureSpec(
    title: 'Employee Attendance Calendar',
    summary:
        'Inspect employee month calendars with present, absent, leave and holiday markers.',
    icon: Icons.calendar_view_month_rounded,
    accent: _teal,
    metrics: [
      AdminMetric(
          label: 'Month',
          value: 'Open',
          helper: 'Calendar view',
          icon: Icons.calendar_month_rounded,
          color: _teal),
      AdminMetric(
          label: 'Present',
          value: 'Count',
          helper: 'Monthly total',
          icon: Icons.check_circle_rounded,
          color: _green),
      AdminMetric(
          label: 'Leave',
          value: 'Count',
          helper: 'Approved leave',
          icon: Icons.event_busy_rounded,
          color: _amber),
      AdminMetric(
          label: 'Absent',
          value: 'Count',
          helper: 'Unapproved absence',
          icon: Icons.cancel_rounded,
          color: _rose),
    ],
    actions: _hrActions,
    checklist: [
      AdminFeedItem(
          title: 'Employee selection',
          subtitle:
              'Select employee and month before reviewing attendance exceptions.',
          meta: 'Filter',
          icon: Icons.person_search_rounded,
          color: _teal),
      AdminFeedItem(
          title: 'Holiday overlay',
          subtitle:
              'Calendar output depends on school holiday and working-day setup.',
          meta: 'Calendar',
          icon: Icons.event_available_rounded,
          color: _amber),
    ],
    records: [
      AdminFeedItem(
          title: 'Monthly summary',
          subtitle: 'Use month totals for HR review and payroll handoff.',
          meta: 'Payroll',
          icon: Icons.summarize_rounded,
          color: _green),
    ],
  ),
  'departments': _FeatureSpec(
    title: 'Departments',
    summary:
        'Manage department names and keep staff grouped for attendance and reporting.',
    icon: Icons.apartment_rounded,
    accent: _blue,
    metrics: [
      AdminMetric(
          label: 'Departments',
          value: 'Open',
          helper: 'Department master',
          icon: Icons.apartment_rounded,
          color: _blue),
      AdminMetric(
          label: 'Teaching',
          value: 'Group',
          helper: 'Academic staff',
          icon: Icons.school_rounded,
          color: _green),
      AdminMetric(
          label: 'Non-Teaching',
          value: 'Group',
          helper: 'Admin staff',
          icon: Icons.business_center_rounded,
          color: _amber),
      AdminMetric(
          label: 'Reports',
          value: 'Filter',
          helper: 'Department-wise',
          icon: Icons.filter_alt_rounded,
          color: _purple),
    ],
    actions: _hrActions,
    checklist: [
      AdminFeedItem(
          title: 'Clean naming',
          subtitle:
              'Consistent department names improve HR filters and reports.',
          meta: 'Master',
          icon: Icons.edit_note_rounded,
          color: _blue),
      AdminFeedItem(
          title: 'Teacher detection',
          subtitle:
              'Academic and faculty departments influence absentee spotlights.',
          meta: 'Academic',
          icon: Icons.school_rounded,
          color: _green),
    ],
    records: [
      AdminFeedItem(
          title: 'Attendance filter',
          subtitle: 'Department filters help HR review absentees faster.',
          meta: 'Daily',
          icon: Icons.filter_list_rounded,
          color: _amber),
    ],
  ),
  'employeeAccounts': _FeatureSpec(
    title: 'Employee User Accounts',
    summary:
        'Create, link and review staff login accounts for portal and mobile access.',
    icon: Icons.manage_accounts_rounded,
    accent: _purple,
    metrics: [
      AdminMetric(
          label: 'Linked',
          value: 'Users',
          helper: 'Employee accounts',
          icon: Icons.link_rounded,
          color: _purple),
      AdminMetric(
          label: 'Teacher',
          value: 'Access',
          helper: 'Teaching role',
          icon: Icons.school_rounded,
          color: _green),
      AdminMetric(
          label: 'HR',
          value: 'Access',
          helper: 'HR role',
          icon: Icons.badge_rounded,
          color: _blue),
      AdminMetric(
          label: 'Disabled',
          value: 'Audit',
          helper: 'Inactive users',
          icon: Icons.person_off_rounded,
          color: _rose),
    ],
    actions: _hrActions,
    checklist: [
      AdminFeedItem(
          title: 'Account linkage',
          subtitle:
              'Each staff login should point to the correct employee profile.',
          meta: 'Users',
          icon: Icons.link_rounded,
          color: _purple),
      AdminFeedItem(
          title: 'Role cleanup',
          subtitle: 'Remove old roles from transferred or inactive staff.',
          meta: 'Access',
          icon: Icons.rule_rounded,
          color: _amber),
    ],
    records: [
      AdminFeedItem(
          title: 'Mobile support',
          subtitle:
              'Teacher, HR, Transport and Examination roles open native dashboards.',
          meta: 'App',
          icon: Icons.phone_android_rounded,
          color: _blue),
    ],
  ),
  'messages': _FeatureSpec(
    title: 'HR Messages',
    summary:
        'Open staff conversations, reminders and HR communication follow-up.',
    icon: Icons.chat_bubble_rounded,
    accent: _purple,
    metrics: [
      AdminMetric(
          label: 'Inbox',
          value: 'Open',
          helper: 'Conversations',
          icon: Icons.inbox_rounded,
          color: _purple),
      AdminMetric(
          label: 'Unread',
          value: 'Track',
          helper: 'Needs reply',
          icon: Icons.mark_email_unread_rounded,
          color: _amber),
      AdminMetric(
          label: 'Reminders',
          value: 'Send',
          helper: 'Follow-up notes',
          icon: Icons.notifications_active_rounded,
          color: _blue),
      AdminMetric(
          label: 'Staff',
          value: 'Reach',
          helper: 'Employee contacts',
          icon: Icons.people_rounded,
          color: _green),
    ],
    actions: _hrActions,
    checklist: [
      AdminFeedItem(
          title: 'Leave follow-up',
          subtitle:
              'Use messages to clarify leave requests and missing documents.',
          meta: 'HR',
          icon: Icons.sms_rounded,
          color: _purple),
      AdminFeedItem(
          title: 'Attendance reminder',
          subtitle:
              'Follow up with staff for unmarked or exception attendance.',
          meta: 'Daily',
          icon: Icons.notifications_rounded,
          color: _amber),
    ],
    records: [
      AdminFeedItem(
          title: 'Conversation context',
          subtitle:
              'Keep message threads attached to staff and role workflows.',
          meta: 'Inbox',
          icon: Icons.forum_rounded,
          color: _blue),
    ],
  ),
};

const Map<String, _FeatureSpec> _transportSpecs = {
  'routes': _FeatureSpec(
    title: 'Route Management',
    summary:
        'Maintain transportations, villages, route fees, fine rules and stop planning.',
    icon: Icons.signpost_rounded,
    accent: _cyan,
    metrics: [
      AdminMetric(
          label: 'Routes',
          value: 'Session',
          helper: 'Active routes',
          icon: Icons.alt_route_rounded,
          color: _cyan),
      AdminMetric(
          label: 'Villages',
          value: 'Unique',
          helper: 'Pickup areas',
          icon: Icons.location_city_rounded,
          color: _green),
      AdminMetric(
          label: 'Fine',
          value: 'Rules',
          helper: 'Late fee setup',
          icon: Icons.percent_rounded,
          color: _amber),
      AdminMetric(
          label: 'Students',
          value: 'Linked',
          helper: 'Assignments',
          icon: Icons.groups_rounded,
          color: _blue),
    ],
    actions: _transportActions,
    checklist: [
      AdminFeedItem(
          title: 'Route master',
          subtitle:
              'Transportations in PITS hold villages, cost and fine configuration.',
          meta: 'Routes',
          icon: Icons.route_rounded,
          color: _cyan),
      AdminFeedItem(
          title: 'Student mapping',
          subtitle:
              'Assignments connect each student to an active route and stop.',
          meta: 'Assign',
          icon: Icons.person_pin_circle_rounded,
          color: _indigo),
    ],
    records: [
      AdminFeedItem(
          title: 'Fee override check',
          subtitle:
              'Student-wise transport fee head amounts can override route defaults.',
          meta: 'Fees',
          icon: Icons.payments_rounded,
          color: _amber),
    ],
  ),
  'pickup': _FeatureSpec(
    title: 'Pickup Tracking',
    summary:
        'Monitor pickup and drop status for route-wise transport attendance.',
    icon: Icons.people_rounded,
    accent: _amber,
    metrics: [
      AdminMetric(
          label: 'Pickup',
          value: 'Mark',
          helper: 'Morning status',
          icon: Icons.check_circle_rounded,
          color: _amber),
      AdminMetric(
          label: 'Drop',
          value: 'Mark',
          helper: 'Afternoon status',
          icon: Icons.how_to_reg_rounded,
          color: _green),
      AdminMetric(
          label: 'Absent',
          value: 'Track',
          helper: 'Not boarded',
          icon: Icons.cancel_rounded,
          color: _rose),
      AdminMetric(
          label: 'Report',
          value: 'Daily',
          helper: 'Bus-wise',
          icon: Icons.assessment_rounded,
          color: _teal),
    ],
    actions: _transportActions,
    checklist: [
      AdminFeedItem(
          title: 'Driver mobile flow',
          subtitle:
              'Driver and conductor roles land directly on mobile attendance marking.',
          meta: 'Mobile',
          icon: Icons.phone_android_rounded,
          color: _amber),
      AdminFeedItem(
          title: 'Bus-wise list',
          subtitle:
              'Mark each assigned student for pickup or drop with date context.',
          meta: 'Bus',
          icon: Icons.directions_bus_rounded,
          color: _green),
    ],
    records: [
      AdminFeedItem(
          title: 'Attendance report',
          subtitle:
              'Transport office can review present and absent status by bus.',
          meta: 'Report',
          icon: Icons.assignment_rounded,
          color: _teal),
    ],
  ),
  'vehicle': _FeatureSpec(
    title: 'Vehicle Status',
    summary:
        'Review fleet readiness, assigned driver, assigned conductor and maintenance notes.',
    icon: Icons.map_rounded,
    accent: _green,
    metrics: [
      AdminMetric(
          label: 'Buses',
          value: 'Fleet',
          helper: 'Total vehicles',
          icon: Icons.directions_bus_rounded,
          color: _green),
      AdminMetric(
          label: 'Drivers',
          value: 'Mapped',
          helper: 'Driver users',
          icon: Icons.person_rounded,
          color: _rose),
      AdminMetric(
          label: 'Conductors',
          value: 'Mapped',
          helper: 'Conductor users',
          icon: Icons.person_pin_rounded,
          color: _amber),
      AdminMetric(
          label: 'Active',
          value: 'Check',
          helper: 'Vehicle status',
          icon: Icons.verified_rounded,
          color: _blue),
    ],
    actions: _transportActions,
    checklist: [
      AdminFeedItem(
          title: 'Driver assignment',
          subtitle: 'Each active bus should have driver and conductor mapping.',
          meta: 'Fleet',
          icon: Icons.badge_rounded,
          color: _green),
      AdminFeedItem(
          title: 'User status',
          subtitle:
              'Disabled transport staff users should be reviewed from staff setup.',
          meta: 'Access',
          icon: Icons.person_off_rounded,
          color: _rose),
    ],
    records: [
      AdminFeedItem(
          title: 'Fleet readiness',
          subtitle:
              'Use vehicle status before opening daily attendance marking.',
          meta: 'Daily',
          icon: Icons.fact_check_rounded,
          color: _blue),
    ],
  ),
  'buses': _FeatureSpec(
    title: 'Buses',
    summary:
        'Manage buses, registration details, activity status and driver or conductor mapping.',
    icon: Icons.directions_bus_rounded,
    accent: _green,
    metrics: [
      AdminMetric(
          label: 'Total',
          value: 'Fleet',
          helper: 'Buses',
          icon: Icons.directions_bus_filled_rounded,
          color: _green),
      AdminMetric(
          label: 'Active',
          value: 'Live',
          helper: 'In service',
          icon: Icons.verified_rounded,
          color: _blue),
      AdminMetric(
          label: 'Driver',
          value: 'Mapped',
          helper: 'Assigned user',
          icon: Icons.person_rounded,
          color: _rose),
      AdminMetric(
          label: 'Conductor',
          value: 'Mapped',
          helper: 'Assigned user',
          icon: Icons.person_pin_rounded,
          color: _amber),
    ],
    actions: _transportActions,
    checklist: [
      AdminFeedItem(
          title: 'Vehicle profile',
          subtitle: 'Keep bus number, status and staff assignment updated.',
          meta: 'Fleet',
          icon: Icons.edit_road_rounded,
          color: _green),
      AdminFeedItem(
          title: 'Attendance readiness',
          subtitle: 'Only mapped staff should mark bus attendance from mobile.',
          meta: 'Mobile',
          icon: Icons.phone_android_rounded,
          color: _amber),
    ],
    records: [
      AdminFeedItem(
          title: 'Inactive buses',
          subtitle:
              'Inactive fleet entries should not be used for new assignments.',
          meta: 'Audit',
          icon: Icons.block_rounded,
          color: _rose),
    ],
  ),
  'assignments': _FeatureSpec(
    title: 'Student Transport Assignments',
    summary:
        'Assign students to active routes and keep session-wise transport service accurate.',
    icon: Icons.person_pin_circle_rounded,
    accent: _indigo,
    metrics: [
      AdminMetric(
          label: 'Students',
          value: 'Mapped',
          helper: 'Transport users',
          icon: Icons.groups_rounded,
          color: _indigo),
      AdminMetric(
          label: 'Session',
          value: 'Active',
          helper: 'Academic session',
          icon: Icons.calendar_today_rounded,
          color: _blue),
      AdminMetric(
          label: 'Route',
          value: 'Linked',
          helper: 'Pickup plan',
          icon: Icons.alt_route_rounded,
          color: _cyan),
      AdminMetric(
          label: 'Fee',
          value: 'Linked',
          helper: 'Transport fee',
          icon: Icons.payments_rounded,
          color: _amber),
    ],
    actions: _transportActions,
    checklist: [
      AdminFeedItem(
          title: 'Active assignment',
          subtitle:
              'One active route assignment should be maintained per transport student.',
          meta: 'Assign',
          icon: Icons.person_pin_circle_rounded,
          color: _indigo),
      AdminFeedItem(
          title: 'Fee sync',
          subtitle:
              'Transport fee calculations depend on the assigned route or override amount.',
          meta: 'Fees',
          icon: Icons.currency_rupee_rounded,
          color: _amber),
    ],
    records: [
      AdminFeedItem(
          title: 'Recent assignments',
          subtitle:
              'PITS dashboard highlights newest route assignments for quick review.',
          meta: 'Recent',
          icon: Icons.history_rounded,
          color: _blue),
    ],
  ),
  'staff': _FeatureSpec(
    title: 'Transport Staff',
    summary:
        'Manage drivers, conductors, staff status and linked user accounts.',
    icon: Icons.badge_rounded,
    accent: _rose,
    metrics: [
      AdminMetric(
          label: 'Drivers',
          value: 'Count',
          helper: 'Driver staff',
          icon: Icons.person_rounded,
          color: _rose),
      AdminMetric(
          label: 'Conductors',
          value: 'Count',
          helper: 'Conductor staff',
          icon: Icons.person_pin_rounded,
          color: _amber),
      AdminMetric(
          label: 'Active',
          value: 'Review',
          helper: 'Working staff',
          icon: Icons.verified_user_rounded,
          color: _green),
      AdminMetric(
          label: 'Disabled',
          value: 'Audit',
          helper: 'User status',
          icon: Icons.person_off_rounded,
          color: _slate),
    ],
    actions: _transportActions,
    checklist: [
      AdminFeedItem(
          title: 'Staff type',
          subtitle:
              'Driver and conductor staff types drive dashboard permissions.',
          meta: 'Role',
          icon: Icons.badge_rounded,
          color: _rose),
      AdminFeedItem(
          title: 'User mapping',
          subtitle:
              'Mobile attendance marking requires linked and active staff user accounts.',
          meta: 'Access',
          icon: Icons.link_rounded,
          color: _blue),
    ],
    records: [
      AdminFeedItem(
          title: 'Inactive staff',
          subtitle:
              'Inactive or disabled staff should be removed from bus assignments.',
          meta: 'Audit',
          icon: Icons.rule_rounded,
          color: _amber),
    ],
  ),
  'attendance': _FeatureSpec(
    title: 'Transport Attendance',
    summary:
        'Driver and conductor mobile marking for student pickup and drop attendance.',
    icon: Icons.check_circle_rounded,
    accent: _amber,
    metrics: [
      AdminMetric(
          label: 'Morning',
          value: 'Pickup',
          helper: 'Boarding status',
          icon: Icons.wb_sunny_rounded,
          color: _amber),
      AdminMetric(
          label: 'Evening',
          value: 'Drop',
          helper: 'Drop status',
          icon: Icons.nightlight_round,
          color: _indigo),
      AdminMetric(
          label: 'Absent',
          value: 'Flag',
          helper: 'Not boarded',
          icon: Icons.cancel_rounded,
          color: _rose),
      AdminMetric(
          label: 'Report',
          value: 'Sync',
          helper: 'Office view',
          icon: Icons.cloud_done_rounded,
          color: _green),
    ],
    actions: _transportActions,
    checklist: [
      AdminFeedItem(
          title: 'Select bus',
          subtitle:
              'Use bus assignment to load the current route student list.',
          meta: 'Bus',
          icon: Icons.directions_bus_rounded,
          color: _amber),
      AdminFeedItem(
          title: 'Mark status',
          subtitle: 'Mark pickup or drop status for each assigned student.',
          meta: 'Mark',
          icon: Icons.check_box_rounded,
          color: _green),
      AdminFeedItem(
          title: 'Review exceptions',
          subtitle:
              'Absent or unmarked students should be checked before route close.',
          meta: 'Daily',
          icon: Icons.warning_rounded,
          color: _rose),
    ],
    records: [
      AdminFeedItem(
          title: 'Office report',
          subtitle: 'Transport office sees bus-wise present and absent report.',
          meta: 'Report',
          icon: Icons.assessment_rounded,
          color: _teal),
    ],
  ),
  'attendanceReport': _FeatureSpec(
    title: 'Transport Attendance Report',
    summary:
        'Review bus-wise and date-wise transport attendance summaries for pickup and drop.',
    icon: Icons.assessment_rounded,
    accent: _teal,
    metrics: [
      AdminMetric(
          label: 'Present',
          value: 'Count',
          helper: 'Boarded students',
          icon: Icons.check_circle_rounded,
          color: _green),
      AdminMetric(
          label: 'Absent',
          value: 'Count',
          helper: 'Not boarded',
          icon: Icons.cancel_rounded,
          color: _rose),
      AdminMetric(
          label: 'Bus',
          value: 'Filter',
          helper: 'Bus-wise view',
          icon: Icons.directions_bus_rounded,
          color: _teal),
      AdminMetric(
          label: 'Date',
          value: 'Filter',
          helper: 'Daily report',
          icon: Icons.today_rounded,
          color: _blue),
    ],
    actions: _transportActions,
    checklist: [
      AdminFeedItem(
          title: 'Daily report',
          subtitle: 'Use date and bus filters for transport office review.',
          meta: 'Daily',
          icon: Icons.today_rounded,
          color: _teal),
      AdminFeedItem(
          title: 'Exception list',
          subtitle:
              'Absent and unmarked lists are useful for parent follow-up.',
          meta: 'Follow-up',
          icon: Icons.list_alt_rounded,
          color: _rose),
    ],
    records: [
      AdminFeedItem(
          title: 'Mobile source',
          subtitle: 'Report data comes from driver and conductor marking flow.',
          meta: 'Mobile',
          icon: Icons.phone_android_rounded,
          color: _blue),
    ],
  ),
  'feeOverrides': _FeatureSpec(
    title: 'Transport Fee Overrides',
    summary:
        'Manage student-wise transport fee head amount overrides for special cases.',
    icon: Icons.payments_rounded,
    accent: _purple,
    metrics: [
      AdminMetric(
          label: 'Overrides',
          value: 'Open',
          helper: 'Student-wise',
          icon: Icons.tune_rounded,
          color: _purple),
      AdminMetric(
          label: 'Fee Head',
          value: 'Linked',
          helper: 'Transport head',
          icon: Icons.receipt_rounded,
          color: _blue),
      AdminMetric(
          label: 'Route Fee',
          value: 'Default',
          helper: 'Route amount',
          icon: Icons.alt_route_rounded,
          color: _cyan),
      AdminMetric(
          label: 'Audit',
          value: 'Review',
          helper: 'Special cases',
          icon: Icons.rule_rounded,
          color: _amber),
    ],
    actions: _transportActions,
    checklist: [
      AdminFeedItem(
          title: 'Override amount',
          subtitle:
              'Use overrides only for approved student-wise transport fee changes.',
          meta: 'Fees',
          icon: Icons.currency_rupee_rounded,
          color: _purple),
      AdminFeedItem(
          title: 'Route default',
          subtitle:
              'Default fee still comes from route or transportation setup.',
          meta: 'Route',
          icon: Icons.route_rounded,
          color: _cyan),
    ],
    records: [
      AdminFeedItem(
          title: 'Finance review',
          subtitle: 'Coordinate overrides with fee collection and due reports.',
          meta: 'Accounts',
          icon: Icons.account_balance_wallet_rounded,
          color: _green),
    ],
  ),
};

const Map<String, _FeatureSpec> _examinationSpecs = {
  'schedule': _FeatureSpec(
    title: 'Exam Schedule',
    summary:
        'Plan exam dates, sessions, classes and operational schedule readiness.',
    icon: Icons.event_rounded,
    accent: _cyan,
    metrics: [
      AdminMetric(
          label: 'Exams',
          value: 'Plan',
          helper: 'Upcoming exams',
          icon: Icons.event_note_rounded,
          color: _cyan),
      AdminMetric(
          label: 'Sessions',
          value: 'Set',
          helper: 'Exam slots',
          icon: Icons.schedule_rounded,
          color: _blue),
      AdminMetric(
          label: 'Classes',
          value: 'Mapped',
          helper: 'Class coverage',
          icon: Icons.class_rounded,
          color: _green),
      AdminMetric(
          label: 'Status',
          value: 'Open',
          helper: 'Editable plan',
          icon: Icons.lock_open_rounded,
          color: _amber),
    ],
    actions: [..._examinationManageActions, ..._examinationEntryActions],
    checklist: [
      AdminFeedItem(
          title: 'Exam dates',
          subtitle: 'Schedule each exam with date, session and class scope.',
          meta: 'Plan',
          icon: Icons.event_rounded,
          color: _cyan),
      AdminFeedItem(
          title: 'Scheme check',
          subtitle: 'Confirm exam schemes before marks entry opens.',
          meta: 'Scheme',
          icon: Icons.schema_rounded,
          color: _purple),
      AdminFeedItem(
          title: 'Lock after review',
          subtitle: 'Lock finalized exams before report card processing.',
          meta: 'Lock',
          icon: Icons.lock_rounded,
          color: _slate),
    ],
    records: [
      AdminFeedItem(
          title: 'Upcoming exams',
          subtitle:
              'The PITS web dashboard highlights upcoming exams when dates are stored.',
          meta: 'Next',
          icon: Icons.upcoming_rounded,
          color: _green),
    ],
  ),
  'moderation': _FeatureSpec(
    title: 'Result Moderation',
    summary:
        'Review entered marks, locked exams and result readiness before publication.',
    icon: Icons.grade_rounded,
    accent: _rose,
    metrics: [
      AdminMetric(
          label: 'Pending',
          value: 'Marks',
          helper: 'Needs review',
          icon: Icons.pending_actions_rounded,
          color: _amber),
      AdminMetric(
          label: 'Locked',
          value: 'Exams',
          helper: 'Frozen results',
          icon: Icons.lock_rounded,
          color: _slate),
      AdminMetric(
          label: 'Remarks',
          value: 'Check',
          helper: 'Student comments',
          icon: Icons.rate_review_rounded,
          color: _blue),
      AdminMetric(
          label: 'Final',
          value: 'Ready',
          helper: 'Result summary',
          icon: Icons.emoji_events_rounded,
          color: _green),
    ],
    actions: [..._examinationEntryActions, ..._examinationReportActions],
    checklist: [
      AdminFeedItem(
          title: 'Marks verification',
          subtitle:
              'Check missing or incorrect marks before locking final output.',
          meta: 'Review',
          icon: Icons.fact_check_rounded,
          color: _rose),
      AdminFeedItem(
          title: 'Co-scholastic review',
          subtitle:
              'Grades and remarks should be complete before final report cards.',
          meta: 'Grade',
          icon: Icons.extension_rounded,
          color: _teal),
    ],
    records: [
      AdminFeedItem(
          title: 'Final result summary',
          subtitle:
              'Use class-wise weighted totals and toppers view for moderation.',
          meta: 'Report',
          icon: Icons.emoji_events_rounded,
          color: _amber),
    ],
  ),
  'reports': _FeatureSpec(
    title: 'Exam Reports',
    summary:
        'Generate final result summaries, report cards, grade sheets and analytics exports.',
    icon: Icons.assignment_turned_in_rounded,
    accent: _green,
    metrics: [
      AdminMetric(
          label: 'Final',
          value: 'Summary',
          helper: 'Class-wise',
          icon: Icons.emoji_events_rounded,
          color: _amber),
      AdminMetric(
          label: 'Cards',
          value: 'PDF',
          helper: 'Report cards',
          icon: Icons.picture_as_pdf_rounded,
          color: _rose),
      AdminMetric(
          label: 'Grades',
          value: 'Export',
          helper: 'Grade sheets',
          icon: Icons.table_chart_rounded,
          color: _green),
      AdminMetric(
          label: 'Toppers',
          value: 'Rank',
          helper: 'Ranking sheet',
          icon: Icons.leaderboard_rounded,
          color: _blue),
    ],
    actions: _examinationReportActions,
    checklist: [
      AdminFeedItem(
          title: 'Final result summary',
          subtitle:
              'Class-wise totals, grades, Excel export and toppers ranking.',
          meta: 'Main',
          icon: Icons.emoji_events_rounded,
          color: _amber),
      AdminFeedItem(
          title: 'Report cards',
          subtitle: 'Generate student-wise report cards with selected format.',
          meta: 'PDF',
          icon: Icons.picture_as_pdf_rounded,
          color: _rose),
    ],
    records: [
      AdminFeedItem(
          title: 'Format setup',
          subtitle:
              'Report cards depend on assigned formats and grade scheme setup.',
          meta: 'Setup',
          icon: Icons.article_rounded,
          color: _purple),
    ],
  ),
  'exams': _FeatureSpec(
    title: 'Manage Exams',
    summary: 'Create, edit, lock and review exams across classes and terms.',
    icon: Icons.edit_calendar_rounded,
    accent: _blue,
    metrics: [
      AdminMetric(
          label: 'Total',
          value: 'Exams',
          helper: 'Exam master',
          icon: Icons.event_note_rounded,
          color: _blue),
      AdminMetric(
          label: 'Locked',
          value: 'Track',
          helper: 'Frozen exams',
          icon: Icons.lock_rounded,
          color: _slate),
      AdminMetric(
          label: 'Open',
          value: 'Edit',
          helper: 'Draft exams',
          icon: Icons.lock_open_rounded,
          color: _green),
      AdminMetric(
          label: 'Dates',
          value: 'Plan',
          helper: 'Upcoming exams',
          icon: Icons.upcoming_rounded,
          color: _amber),
    ],
    actions: _examinationManageActions,
    checklist: [
      AdminFeedItem(
          title: 'Exam master',
          subtitle: 'Set exam name, class scope, date and lock state.',
          meta: 'Master',
          icon: Icons.edit_calendar_rounded,
          color: _blue),
      AdminFeedItem(
          title: 'Lock discipline',
          subtitle:
              'Lock exams only after marks and result checks are complete.',
          meta: 'Lock',
          icon: Icons.lock_rounded,
          color: _slate),
    ],
    records: [
      AdminFeedItem(
          title: 'Upcoming list',
          subtitle:
              'Exams with future dates appear in dashboard upcoming exams.',
          meta: 'Next',
          icon: Icons.event_available_rounded,
          color: _green),
    ],
  ),
  'schemes': _FeatureSpec(
    title: 'Exam Schemes',
    summary:
        'Set components, weightage and grading connections used for result calculations.',
    icon: Icons.schema_rounded,
    accent: _purple,
    metrics: [
      AdminMetric(
          label: 'Schemes',
          value: 'Setup',
          helper: 'Exam schemes',
          icon: Icons.schema_rounded,
          color: _purple),
      AdminMetric(
          label: 'Weightage',
          value: 'Map',
          helper: 'Components',
          icon: Icons.percent_rounded,
          color: _blue),
      AdminMetric(
          label: 'Grades',
          value: 'Linked',
          helper: 'Grade schemes',
          icon: Icons.grade_rounded,
          color: _amber),
      AdminMetric(
          label: 'Reports',
          value: 'Use',
          helper: 'Result output',
          icon: Icons.summarize_rounded,
          color: _green),
    ],
    actions: _examinationManageActions,
    checklist: [
      AdminFeedItem(
          title: 'Component setup',
          subtitle:
              'Define assessment components and marks weightage per exam scheme.',
          meta: 'Setup',
          icon: Icons.schema_rounded,
          color: _purple),
      AdminFeedItem(
          title: 'Grade mapping',
          subtitle:
              'Grade scheme setup affects final result summary and report cards.',
          meta: 'Grades',
          icon: Icons.grade_rounded,
          color: _amber),
    ],
    records: [
      AdminFeedItem(
          title: 'Report dependency',
          subtitle: 'Final reports should not run until schemes are verified.',
          meta: 'Result',
          icon: Icons.assignment_rounded,
          color: _green),
    ],
  ),
  'marks': _FeatureSpec(
    title: 'Marks Entry',
    summary:
        'Enter subject marks and keep missing marks visible for exam moderation.',
    icon: Icons.edit_note_rounded,
    accent: _blue,
    metrics: [
      AdminMetric(
          label: 'Entry',
          value: 'Open',
          helper: 'Subject marks',
          icon: Icons.edit_note_rounded,
          color: _blue),
      AdminMetric(
          label: 'Pending',
          value: 'Track',
          helper: 'Missing marks',
          icon: Icons.pending_actions_rounded,
          color: _amber),
      AdminMetric(
          label: 'Classes',
          value: 'Filter',
          helper: 'Class-wise',
          icon: Icons.class_rounded,
          color: _green),
      AdminMetric(
          label: 'Lock',
          value: 'After',
          helper: 'Moderation',
          icon: Icons.lock_rounded,
          color: _slate),
    ],
    actions: [..._examinationEntryActions, ..._examinationReportActions],
    checklist: [
      AdminFeedItem(
          title: 'Select exam',
          subtitle:
              'Marks entry starts with exam, class, section and subject selection.',
          meta: 'Entry',
          icon: Icons.tune_rounded,
          color: _blue),
      AdminFeedItem(
          title: 'Missing marks',
          subtitle:
              'Review pending summary before report cards or final result exports.',
          meta: 'Check',
          icon: Icons.pending_actions_rounded,
          color: _amber),
    ],
    records: [
      AdminFeedItem(
          title: 'Teacher workflow',
          subtitle:
              'Teachers also have marks entry from their dashboard quick actions.',
          meta: 'Teacher',
          icon: Icons.school_rounded,
          color: _green),
    ],
  ),
  'coScholastic': _FeatureSpec(
    title: 'Co-Scholastic Entry',
    summary:
        'Enter co-scholastic grades and maintain class-wise co-scholastic mapping.',
    icon: Icons.extension_rounded,
    accent: _teal,
    metrics: [
      AdminMetric(
          label: 'Areas',
          value: 'Mapped',
          helper: 'Co-scholastic areas',
          icon: Icons.category_rounded,
          color: _teal),
      AdminMetric(
          label: 'Grades',
          value: 'Entry',
          helper: 'Student grades',
          icon: Icons.grade_rounded,
          color: _amber),
      AdminMetric(
          label: 'Classes',
          value: 'Linked',
          helper: 'Class mapping',
          icon: Icons.class_rounded,
          color: _blue),
      AdminMetric(
          label: 'Reports',
          value: 'Shown',
          helper: 'Report cards',
          icon: Icons.article_rounded,
          color: _green),
    ],
    actions: _examinationEntryActions,
    checklist: [
      AdminFeedItem(
          title: 'Area setup',
          subtitle:
              'Co-scholastic area and grade setup should be complete before entry.',
          meta: 'Setup',
          icon: Icons.category_rounded,
          color: _teal),
      AdminFeedItem(
          title: 'Class mapping',
          subtitle:
              'Map co-scholastic areas to classes for clean entry screens.',
          meta: 'Map',
          icon: Icons.account_tree_rounded,
          color: _blue),
    ],
    records: [
      AdminFeedItem(
          title: 'Report card output',
          subtitle: 'Entered grades appear in smart report card formats.',
          meta: 'PDF',
          icon: Icons.picture_as_pdf_rounded,
          color: _green),
    ],
  ),
  'remarks': _FeatureSpec(
    title: 'Student Remarks',
    summary:
        'Record student remarks and teacher comments for report cards and final review.',
    icon: Icons.rate_review_rounded,
    accent: _amber,
    metrics: [
      AdminMetric(
          label: 'Remarks',
          value: 'Entry',
          helper: 'Student comments',
          icon: Icons.rate_review_rounded,
          color: _amber),
      AdminMetric(
          label: 'Class',
          value: 'Filter',
          helper: 'Class-wise',
          icon: Icons.class_rounded,
          color: _blue),
      AdminMetric(
          label: 'Report',
          value: 'Print',
          helper: 'Report cards',
          icon: Icons.article_rounded,
          color: _green),
      AdminMetric(
          label: 'Review',
          value: 'Ready',
          helper: 'Moderation',
          icon: Icons.fact_check_rounded,
          color: _rose),
    ],
    actions: _examinationEntryActions,
    checklist: [
      AdminFeedItem(
          title: 'Class remarks',
          subtitle:
              'Use class and student filters to enter report-card comments.',
          meta: 'Entry',
          icon: Icons.comment_rounded,
          color: _amber),
      AdminFeedItem(
          title: 'Moderation',
          subtitle: 'Review remarks before final report card generation.',
          meta: 'Review',
          icon: Icons.fact_check_rounded,
          color: _rose),
    ],
    records: [
      AdminFeedItem(
          title: 'Teacher support',
          subtitle:
              'Teacher dashboard also includes student remarks entry path.',
          meta: 'Teacher',
          icon: Icons.school_rounded,
          color: _blue),
    ],
  ),
  'promotion': _FeatureSpec(
    title: 'Promotion Decisions',
    summary:
        'Record promoted or not-promoted decisions and prepare next session movement.',
    icon: Icons.school_rounded,
    accent: _indigo,
    metrics: [
      AdminMetric(
          label: 'Decision',
          value: 'Entry',
          helper: 'Promotion status',
          icon: Icons.school_rounded,
          color: _indigo),
      AdminMetric(
          label: 'Result',
          value: 'Based',
          helper: 'Final summary',
          icon: Icons.emoji_events_rounded,
          color: _amber),
      AdminMetric(
          label: 'Next Class',
          value: 'Map',
          helper: 'Session movement',
          icon: Icons.moving_rounded,
          color: _green),
      AdminMetric(
          label: 'History',
          value: 'Track',
          helper: 'Promotion history',
          icon: Icons.history_edu_rounded,
          color: _blue),
    ],
    actions: [..._examinationEntryActions, ..._examinationReportActions],
    checklist: [
      AdminFeedItem(
          title: 'Result review',
          subtitle:
              'Promotion decisions should follow final result summary review.',
          meta: 'Result',
          icon: Icons.emoji_events_rounded,
          color: _amber),
      AdminFeedItem(
          title: 'Class movement',
          subtitle: 'Confirm next class mapping before session rollover.',
          meta: 'Next',
          icon: Icons.moving_rounded,
          color: _green),
    ],
    records: [
      AdminFeedItem(
          title: 'Promotion history',
          subtitle:
              'Keep history clean for student academic record continuity.',
          meta: 'Record',
          icon: Icons.history_edu_rounded,
          color: _blue),
    ],
  ),
  'reportCards': _FeatureSpec(
    title: 'Report Card Generator',
    summary:
        'Generate student-wise PDF report cards using assigned school formats.',
    icon: Icons.picture_as_pdf_rounded,
    accent: _rose,
    metrics: [
      AdminMetric(
          label: 'Formats',
          value: 'Assign',
          helper: 'Report templates',
          icon: Icons.article_rounded,
          color: _rose),
      AdminMetric(
          label: 'Students',
          value: 'Select',
          helper: 'Student-wise PDF',
          icon: Icons.person_search_rounded,
          color: _blue),
      AdminMetric(
          label: 'Marks',
          value: 'Use',
          helper: 'Exam marks',
          icon: Icons.edit_note_rounded,
          color: _green),
      AdminMetric(
          label: 'PDF',
          value: 'Generate',
          helper: 'Print output',
          icon: Icons.picture_as_pdf_rounded,
          color: _amber),
    ],
    actions: _examinationReportActions,
    checklist: [
      AdminFeedItem(
          title: 'Format assignment',
          subtitle: 'Assign report card format to class before generation.',
          meta: 'Format',
          icon: Icons.article_rounded,
          color: _rose),
      AdminFeedItem(
          title: 'Data readiness',
          subtitle:
              'Marks, grades, remarks and health entries should be complete.',
          meta: 'Ready',
          icon: Icons.checklist_rounded,
          color: _green),
    ],
    records: [
      AdminFeedItem(
          title: 'Smart report card',
          subtitle: 'PITS web includes smart report card and designer flows.',
          meta: 'PDF',
          icon: Icons.design_services_rounded,
          color: _purple),
    ],
  ),
  'finalResult': _FeatureSpec(
    title: 'Final Result Summary',
    summary:
        'Review class-wise weighted totals, grades, Excel export and toppers ranking.',
    icon: Icons.emoji_events_rounded,
    accent: _amber,
    metrics: [
      AdminMetric(
          label: 'Totals',
          value: 'Weighted',
          helper: 'Class-wise',
          icon: Icons.calculate_rounded,
          color: _amber),
      AdminMetric(
          label: 'Grades',
          value: 'Ready',
          helper: 'Grade output',
          icon: Icons.grade_rounded,
          color: _green),
      AdminMetric(
          label: 'Excel',
          value: 'Export',
          helper: 'Web portal',
          icon: Icons.table_chart_rounded,
          color: _blue),
      AdminMetric(
          label: 'Toppers',
          value: 'Rank',
          helper: 'Ranking sheet',
          icon: Icons.leaderboard_rounded,
          color: _rose),
    ],
    actions: _examinationReportActions,
    checklist: [
      AdminFeedItem(
          title: 'Weighted result',
          subtitle: 'Final summary uses exam schemes and entered marks.',
          meta: 'Calc',
          icon: Icons.calculate_rounded,
          color: _amber),
      AdminFeedItem(
          title: 'Grade check',
          subtitle: 'Verify grade scheme before publishing report cards.',
          meta: 'Grades',
          icon: Icons.grade_rounded,
          color: _green),
      AdminFeedItem(
          title: 'Ranking sheet',
          subtitle: 'Toppers ranking is reviewed from final result analytics.',
          meta: 'Rank',
          icon: Icons.leaderboard_rounded,
          color: _rose),
    ],
    records: [
      AdminFeedItem(
          title: 'Report cards next',
          subtitle: 'Generate report cards only after final result review.',
          meta: 'PDF',
          icon: Icons.picture_as_pdf_rounded,
          color: _blue),
    ],
  ),
};
