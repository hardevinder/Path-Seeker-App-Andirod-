import 'dart:convert';

import 'package:flutter/material.dart';

import '../widgets/admin_module_widgets.dart';
import 'api_service.dart';

class RoleDashboardApi {
  static const List<String> _collectionAmountKeys = [
    'grandTotal',
    'totalCollection',
    'total_collection',
    'totalCollected',
    'total_collected',
    'totalPaid',
    'total_paid',
    'paid',
    'paidAmount',
    'paid_amount',
    'Fee_Recieved',
    'fee_received',
    'feeReceived',
    'Amount',
    'amount',
    'TotalAmount',
    'totalAmount',
  ];

  static const List<String> _dueAmountKeys = [
    'totalDue',
    'total_due',
    'due',
    'dueAmount',
    'due_amount',
    'pending',
    'pendingAmount',
    'pending_amount',
    'remaining',
    'remainingAmount',
    'remaining_amount',
    'effectiveFeeDue',
    'effective_fee_due',
    'finalAmountDue',
    'final_amount_due',
    'balance',
    'outstanding',
    'totalOutstanding',
  ];

  static const List<String> _concessionAmountKeys = [
    'concession',
    'Concession',
    'concessionAmount',
    'concession_amount',
    'totalConcession',
    'total_concession',
    'totalConcessionReceived',
    'total_concession_received',
  ];

  static Future<AdminDashboardPayload> superadmin() async {
    final today = _today();
    final results = await Future.wait([
      _list('/sessions'),
      _list('/classes'),
      _list('/sections'),
      _list('/users'),
    ]);

    final sessions = results[0];
    final classes = results[1];
    final sections = results[2];
    final users = results[3];

    final activeSession = _activeSessionName(sessions);
    final sessionId = _rowId(_activeSession(sessions));
    final feeResults = await Future.wait<dynamic>([
      _json(_withQuery('/transactions/summary/day-summary', {
        'session_id': sessionId,
      })),
      _list(_withQuery('/reports/student-total-due', {
        'session_id': sessionId,
        'tillDate': today,
      })),
    ]);

    final daySummary = feeResults[0];
    final dayRows = _resolveList(daySummary);
    final dueRows = feeResults[1] as List<Map<String, dynamic>>;
    final dayCollection = _amountFromPayload(
      daySummary,
      _collectionAmountKeys,
    );
    final dueAmount = _sumAmount(dueRows, _dueAmountKeys);

    return AdminDashboardPayload(
      metrics: [
        AdminMetric(
          label: 'Session',
          value: activeSession,
          helper: 'Active academic year',
          icon: Icons.calendar_today_rounded,
          color: const Color(0xFFD97706),
        ),
        AdminMetric(
          label: 'Classes',
          value: _count(classes),
          helper: 'Class master',
          icon: Icons.class_rounded,
          color: const Color(0xFF2563EB),
        ),
        AdminMetric(
          label: 'Users',
          value: _count(users),
          helper: 'Login accounts',
          icon: Icons.manage_accounts_rounded,
          color: const Color(0xFF7C3AED),
        ),
        AdminMetric(
          label: 'Day Collection',
          value: _formatMoney(dayCollection),
          helper: today,
          icon: Icons.payments_rounded,
          color: const Color(0xFF16A34A),
        ),
        AdminMetric(
          label: 'Fee Due',
          value: dueAmount > 0 ? _formatMoney(dueAmount) : _count(dueRows),
          helper: dueAmount > 0 ? 'Outstanding amount' : 'Due records',
          icon: Icons.receipt_long_rounded,
          color: const Color(0xFFE11D48),
        ),
      ],
      highlights: [
        AdminFeedItem(
          title: activeSession == '-'
              ? 'Session data unavailable'
              : 'Active session: $activeSession',
          subtitle:
              'Sessions, classes and sections are available for mobile review.',
          meta: 'Live',
          icon: Icons.cloud_done_rounded,
          color: const Color(0xFF2563EB),
        ),
        AdminFeedItem(
          title: '${_count(classes)} classes, ${_count(sections)} sections',
          subtitle:
              'Academic structure is synced from PITS class and section masters.',
          meta: 'Setup',
          icon: Icons.account_tree_rounded,
          color: const Color(0xFF0F766E),
        ),
        AdminFeedItem(
          title: 'Today collection: ${_formatMoney(dayCollection)}',
          subtitle: dayRows.isEmpty
              ? 'No receipts were returned for today yet.'
              : '${dayRows.length} receipt rows are available for accounts review.',
          meta: 'Fees',
          icon: Icons.currency_rupee_rounded,
          color: const Color(0xFF16A34A),
        ),
      ],
      timeline: [
        AdminFeedItem(
          title:
              users.isEmpty ? 'No users found' : '${users.length} users found',
          subtitle:
              'User and role management can use this live count for access review.',
          meta: 'RBAC',
          icon: Icons.verified_user_rounded,
          color: const Color(0xFF7C3AED),
        ),
        AdminFeedItem(
          title: dueAmount > 0
              ? 'Fee due: ${_formatMoney(dueAmount)}'
              : '${dueRows.length} due records loaded',
          subtitle:
              'Outstanding fee details are visible for Super Admin and Accounts.',
          meta: 'Due',
          icon: Icons.receipt_long_rounded,
          color: const Color(0xFFE11D48),
        ),
      ],
    );
  }

  static Future<AdminDashboardPayload> accounts() async {
    final today = _today();
    final sessions = await _list('/sessions');
    final activeSession = _activeSession(sessions);
    final sessionId = _rowId(activeSession);
    final sessionName = activeSession == null
        ? '-'
        : '${activeSession['name'] ?? activeSession['session'] ?? activeSession['SessionName'] ?? activeSession['title'] ?? '-'}';

    final results = await Future.wait<dynamic>([
      _json(_withQuery('/transactions/summary/day-summary', {
        'session_id': sessionId,
      })),
      _list(_withQuery('/transactions', {
        'session_id': sessionId,
      })),
      _list(_withQuery('/reports/student-total-due', {
        'session_id': sessionId,
        'tillDate': today,
      })),
      _list(_withQuery('/feedue/school-fee-summary', {
        'session_id': sessionId,
      })),
      _list('/transactions/cancelled'),
      _list('/concessions'),
    ]);

    final daySummary = results[0];
    final transactions = results[1] as List<Map<String, dynamic>>;
    final dueRows = results[2] as List<Map<String, dynamic>>;
    final summaryRows = results[3] as List<Map<String, dynamic>>;
    final cancelledRows = results[4] as List<Map<String, dynamic>>;
    final concessions = results[5] as List<Map<String, dynamic>>;

    final dayRows = _resolveList(daySummary);
    final dayCollection = _amountFromPayload(
      daySummary,
      _collectionAmountKeys,
    );
    final sessionCollection = _sumAmount(
      transactions,
      _collectionAmountKeys,
    );
    final dueAmount = _sumAmount(dueRows, _dueAmountKeys);
    final concessionAmount = _sumAmount(
      summaryRows,
      _concessionAmountKeys,
    );
    final recentRows = dayRows.isNotEmpty
        ? dayRows.take(6).toList()
        : transactions.take(6).toList();

    return AdminDashboardPayload(
      metrics: [
        AdminMetric(
          label: 'Day Collection',
          value: _formatMoney(dayCollection),
          helper: today,
          icon: Icons.payments_rounded,
          color: const Color(0xFF16A34A),
        ),
        AdminMetric(
          label: 'Receipts',
          value:
              dayRows.isNotEmpty ? '${dayRows.length}' : _count(transactions),
          helper: dayRows.isNotEmpty ? 'Today' : 'Session records',
          icon: Icons.receipt_rounded,
          color: const Color(0xFF2563EB),
        ),
        AdminMetric(
          label: 'Fee Due',
          value: dueAmount > 0 ? _formatMoney(dueAmount) : _count(dueRows),
          helper: dueAmount > 0 ? 'Outstanding amount' : 'Due records',
          icon: Icons.receipt_long_rounded,
          color: const Color(0xFFE11D48),
        ),
        AdminMetric(
          label: 'Session',
          value: sessionCollection > 0
              ? _formatMoney(sessionCollection)
              : sessionName,
          helper: sessionCollection > 0 ? 'Collection total' : 'Active session',
          icon: Icons.calendar_month_rounded,
          color: const Color(0xFFD97706),
        ),
      ],
      highlights: [
        AdminFeedItem(
          title: 'Today collection: ${_formatMoney(dayCollection)}',
          subtitle: dayRows.isEmpty
              ? 'No day collection rows were returned for today yet.'
              : '${dayRows.length} receipt rows are ready for checking.',
          meta: 'Today',
          icon: Icons.currency_rupee_rounded,
          color: const Color(0xFF16A34A),
        ),
        AdminFeedItem(
          title: dueAmount > 0
              ? 'Outstanding fees: ${_formatMoney(dueAmount)}'
              : '${dueRows.length} due records available',
          subtitle:
              'Fee due, total due and opening balance reports are grouped in this role.',
          meta: 'Due',
          icon: Icons.account_balance_wallet_rounded,
          color: const Color(0xFFE11D48),
        ),
        AdminFeedItem(
          title: concessionAmount > 0
              ? 'Concessions: ${_formatMoney(concessionAmount)}'
              : '${concessions.length} concession setups',
          subtitle:
              'Concession master and concession reports are available for Accounts review.',
          meta: 'Concession',
          icon: Icons.percent_rounded,
          color: const Color(0xFF7C3AED),
        ),
      ],
      timeline: recentRows.isEmpty
          ? [
              const AdminFeedItem(
                title: 'No receipt activity yet',
                subtitle:
                    'Collection rows will appear here after receipts are created.',
                meta: 'Receipts',
                icon: Icons.inbox_rounded,
                color: Color(0xFFD97706),
              ),
              AdminFeedItem(
                title: '${cancelledRows.length} cancelled receipts',
                subtitle:
                    'Cancelled receipts are available from the Accounts reports area.',
                meta: 'Cancel',
                icon: Icons.cancel_rounded,
                color: const Color(0xFFE11D48),
              ),
            ]
          : recentRows
              .map(
                (row) => AdminFeedItem(
                  title: _rowTitle(row),
                  subtitle: _rowSubtitle(row),
                  meta: _rowMeta(row),
                  icon: Icons.receipt_rounded,
                  color: const Color(0xFF2563EB),
                ),
              )
              .toList(),
    );
  }

  static Future<AdminDashboardPayload> hr() async {
    final today = _today();
    final results = await Future.wait([
      _list('/employees'),
      _list('/employee-attendance?date=$today'),
      _list('/employee-leave-requests/all?status=pending'),
    ]);

    final employees = results[0];
    final attendance = results[1];
    final pendingLeaves = results[2];
    final statusCounts = _attendanceCounts(attendance);
    final unmarked = employees.length > statusCounts['marked']!
        ? employees.length - statusCounts['marked']!
        : 0;
    final latestLeave = pendingLeaves.isNotEmpty ? pendingLeaves.first : null;

    return AdminDashboardPayload(
      metrics: [
        AdminMetric(
          label: 'Employees',
          value: _count(employees),
          helper: 'Active staff profiles',
          icon: Icons.badge_rounded,
          color: const Color(0xFF16A34A),
        ),
        AdminMetric(
          label: 'Present',
          value: '${statusCounts['present']}',
          helper: 'Marked today',
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF16A34A),
        ),
        AdminMetric(
          label: 'Absent',
          value: '${statusCounts['absent']}',
          helper: 'Needs follow-up',
          icon: Icons.cancel_rounded,
          color: const Color(0xFFE11D48),
        ),
        AdminMetric(
          label: 'Pending Leave',
          value: _count(pendingLeaves),
          helper: 'Approval queue',
          icon: Icons.pending_actions_rounded,
          color: const Color(0xFFD97706),
        ),
      ],
      highlights: [
        AdminFeedItem(
          title: latestLeave == null
              ? 'No pending leave requests'
              : 'Latest leave: ${_employeeName(latestLeave)}',
          subtitle: latestLeave == null
              ? 'The backend did not return any pending employee leave requests.'
              : '${_leaveType(latestLeave)} from ${_shortDate(latestLeave['start_date'])} to ${_shortDate(latestLeave['end_date'])}',
          meta: latestLeave == null ? 'Clear' : 'Pending',
          icon: latestLeave == null
              ? Icons.task_alt_rounded
              : Icons.pending_actions_rounded,
          color: latestLeave == null
              ? const Color(0xFF16A34A)
              : const Color(0xFFD97706),
        ),
        AdminFeedItem(
          title: '$unmarked unmarked attendance records',
          subtitle:
              'Compared employee profile count against today attendance records.',
          meta: today,
          icon: Icons.edit_calendar_rounded,
          color: const Color(0xFF2563EB),
        ),
      ],
      timeline: [
        AdminFeedItem(
          title: '${statusCounts['leave']} staff on leave',
          subtitle:
              'Leave-style statuses are grouped from employee attendance records.',
          meta: 'Today',
          icon: Icons.event_busy_rounded,
          color: const Color(0xFF0F766E),
        ),
      ],
    );
  }

  static Future<AdminDashboardPayload> transport() async {
    final results = await Future.wait([
      _list('/transportations'),
      _list('/buses'),
      _list('/student-transport-assignments?active=true'),
      _list('/transport-staff'),
    ]);

    final routes = results[0];
    final buses = results[1];
    final assignments = results[2];
    final staff = results[3];
    final activeBuses = buses.where((b) => b['active'] != false).length;
    final students = _uniqueCount(assignments, (row) => row['student_id']);
    final drivers = staff
        .where((row) => '${row['staff_type']}'.toLowerCase() == 'driver')
        .length;
    final conductors = staff
        .where((row) => '${row['staff_type']}'.toLowerCase() == 'conductor')
        .length;

    return AdminDashboardPayload(
      metrics: [
        AdminMetric(
          label: 'Routes',
          value: _count(routes),
          helper: 'Transportations',
          icon: Icons.alt_route_rounded,
          color: const Color(0xFF0891B2),
        ),
        AdminMetric(
          label: 'Active Buses',
          value: '$activeBuses',
          helper: '${buses.length} total fleet',
          icon: Icons.directions_bus_filled_rounded,
          color: const Color(0xFF16A34A),
        ),
        AdminMetric(
          label: 'Students',
          value: '$students',
          helper: 'Active route assignments',
          icon: Icons.person_pin_circle_rounded,
          color: const Color(0xFF4F46E5),
        ),
        AdminMetric(
          label: 'Staff',
          value: '${staff.length}',
          helper: '$drivers drivers, $conductors conductors',
          icon: Icons.badge_rounded,
          color: const Color(0xFFE11D48),
        ),
      ],
      highlights: [
        AdminFeedItem(
          title: '$activeBuses active buses',
          subtitle: 'Fleet count is available for transport office review.',
          meta: 'Fleet',
          icon: Icons.directions_bus_rounded,
          color: const Color(0xFF16A34A),
        ),
        AdminFeedItem(
          title: '$students students with transport',
          subtitle:
              'Unique student count comes from active transport assignments.',
          meta: 'Assign',
          icon: Icons.groups_rounded,
          color: const Color(0xFF4F46E5),
        ),
      ],
      timeline: [
        AdminFeedItem(
          title: '$drivers drivers and $conductors conductors',
          subtitle:
              'Transport staff is synced from driver/conductor staff records.',
          meta: 'Staff',
          icon: Icons.badge_rounded,
          color: const Color(0xFFE11D48),
        ),
      ],
    );
  }

  static Future<AdminDashboardPayload> examination() async {
    final results = await Future.wait([
      _list('/exams'),
      _list('/exam-schemes'),
      _list('/report-card-formats'),
      _json('/marks/pending-summary'),
    ]);

    final exams = results[0] as List<Map<String, dynamic>>;
    final schemes = results[1] as List<Map<String, dynamic>>;
    final formats = results[2] as List<Map<String, dynamic>>;
    final pendingPayload = results[3];
    final locked = exams.where(_isLockedExam).length;
    final upcoming = _upcomingExamCount(exams);
    final pendingMarks = _pendingMarks(pendingPayload);

    return AdminDashboardPayload(
      metrics: [
        AdminMetric(
          label: 'Exams',
          value: _count(exams),
          helper: '$upcoming upcoming',
          icon: Icons.edit_calendar_rounded,
          color: const Color(0xFF2563EB),
        ),
        AdminMetric(
          label: 'Locked',
          value: '$locked',
          helper: 'Frozen for editing',
          icon: Icons.lock_rounded,
          color: const Color(0xFF334155),
        ),
        AdminMetric(
          label: 'Schemes',
          value: _count(schemes),
          helper: 'Weightage setup',
          icon: Icons.schema_rounded,
          color: const Color(0xFF7C3AED),
        ),
        AdminMetric(
          label: 'Pending Marks',
          value: pendingMarks,
          helper: '${formats.length} report formats',
          icon: Icons.pending_actions_rounded,
          color: const Color(0xFFD97706),
        ),
      ],
      highlights: [
        AdminFeedItem(
          title: '$upcoming upcoming exams',
          subtitle:
              'Upcoming exams are calculated from exam date fields returned by the backend.',
          meta: 'Exam',
          icon: Icons.upcoming_rounded,
          color: const Color(0xFF2563EB),
        ),
        AdminFeedItem(
          title: '${schemes.length} schemes, ${formats.length} formats',
          subtitle:
              'Exam schemes and report formats are ready for exam workflow review.',
          meta: 'Setup',
          icon: Icons.article_rounded,
          color: const Color(0xFF7C3AED),
        ),
      ],
      timeline: [
        AdminFeedItem(
          title: '$pendingMarks pending marks',
          subtitle:
              'Pending mark summary is shown when the school has pending entry data.',
          meta: 'Entry',
          icon: Icons.edit_note_rounded,
          color: const Color(0xFFD97706),
        ),
      ],
    );
  }

  static Future<AdminDashboardPayload> module({
    required String title,
    required List<String> endpoints,
    required IconData icon,
    required Color color,
  }) async {
    final loaded = <_EndpointRows>[];

    for (final endpoint in endpoints) {
      final rows = await _list(endpoint);
      loaded.add(_EndpointRows(endpoint, rows));
    }

    final nonEmpty = loaded.where((item) => item.rows.isNotEmpty).toList();
    final rows = nonEmpty.isNotEmpty
        ? nonEmpty.expand((item) => item.rows).toList()
        : <Map<String, dynamic>>[];

    final previewRows = rows.take(20).toList();
    final loadedSources = nonEmpty.length;

    return AdminDashboardPayload(
      metrics: [
        AdminMetric(
          label: 'Records',
          value: rows.isEmpty ? '0' : '${rows.length}',
          helper: title,
          icon: icon,
          color: color,
        ),
        AdminMetric(
          label: 'Loaded',
          value: rows.isEmpty ? 'No' : 'Yes',
          helper: rows.isEmpty
              ? 'No module records found'
              : '$loadedSources data source${loadedSources == 1 ? '' : 's'}',
          icon: rows.isEmpty ? Icons.info_rounded : Icons.cloud_done_rounded,
          color: const Color(0xFF2563EB),
        ),
        AdminMetric(
          label: 'Status',
          value: rows.isEmpty ? 'Empty' : 'Live',
          helper:
              rows.isEmpty ? 'Nothing to show yet' : 'Latest backend records',
          icon: rows.isEmpty ? Icons.info_rounded : Icons.cloud_done_rounded,
          color:
              rows.isEmpty ? const Color(0xFFD97706) : const Color(0xFF16A34A),
        ),
        AdminMetric(
          label: 'Preview',
          value: '${previewRows.length}',
          helper: 'Rows shown below',
          icon: Icons.view_list_rounded,
          color: const Color(0xFF7C3AED),
        ),
      ],
      highlights: [
        if (loaded.isEmpty || rows.isEmpty)
          AdminFeedItem(
            title: 'No $title records found',
            subtitle:
                'There is no data to show for this module right now. Pull to refresh after adding records on the web portal.',
            meta: 'Empty',
            icon: Icons.inbox_rounded,
            color: const Color(0xFFD97706),
          )
        else
          AdminFeedItem(
            title: '$title data loaded',
            subtitle:
                'Showing ${previewRows.length} of ${rows.length} live records. Pull down to refresh this list.',
            meta: 'Live',
            icon: Icons.cloud_done_rounded,
            color: const Color(0xFF16A34A),
          ),
      ],
      timeline: previewRows.isEmpty
          ? [
              AdminFeedItem(
                title: 'No records available',
                subtitle:
                    'Once this module has records, they will appear here automatically.',
                meta: title,
                icon: Icons.inbox_rounded,
                color: const Color(0xFFD97706),
              ),
            ]
          : previewRows
              .map(
                (row) => AdminFeedItem(
                  title: _rowTitle(row),
                  subtitle: _rowSubtitle(row),
                  meta: _rowMeta(row),
                  icon: icon,
                  color: color,
                ),
              )
              .toList(),
    );
  }

  static Future<dynamic> _json(String endpoint) async {
    try {
      final response = await ApiService.rawGet(endpoint);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      if (response.body.trim().isEmpty) return null;
      return jsonDecode(response.body);
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> _list(String endpoint) async {
    final data = await _json(endpoint);
    return _resolveList(data);
  }

  static List<Map<String, dynamic>> _resolveList(dynamic data) {
    if (data is List) return data.whereType<Map>().map(_stringKeyed).toList();
    if (data is Map) {
      final map = _stringKeyed(data);
      for (final key in [
        'data',
        'rows',
        'items',
        'results',
        'records',
        'employees',
        'routes',
        'buses',
        'assignments',
        'students',
        'staff',
        'users',
        'classes',
        'sections',
        'sessions',
        'exams',
        'schemes',
        'formats',
        'departments',
        'roles',
        'permissions',
        'academicYears',
        'academic_years',
        'terms',
        'bankAccounts',
        'accounts',
        'transactions',
        'receipts',
        'collections',
        'fees',
        'dues',
        'feeDetails',
        'fee_details',
        'feeHeadings',
        'fee_headings',
        'feeStructures',
        'fee_structures',
        'concessions',
        'openingBalances',
        'opening_balances',
        'cancelledTransactions',
        'cancelled_transactions',
        'headSummary',
        'head_summary',
        'settings',
        'leaveTypes',
        'attendance',
        'summaries',
      ]) {
        final value = map[key];
        if (value is List) {
          return value.whereType<Map>().map(_stringKeyed).toList();
        }
        if (value is Map) {
          final nested = _resolveList(value);
          if (nested.isNotEmpty) return nested;
        }
      }

      final meaningfulKeys = map.keys.where(
        (key) => !{
          'success',
          'ok',
          'message',
          'error',
          'count',
          'total',
        }.contains(key),
      );
      if (meaningfulKeys.isNotEmpty) return [map];
    }
    return [];
  }

  static Map<String, dynamic> _stringKeyed(Map raw) {
    return raw.map((key, value) => MapEntry('$key', value));
  }

  static String _count(List<dynamic> rows) =>
      rows.isEmpty ? '-' : '${rows.length}';

  static int _uniqueCount(
    List<Map<String, dynamic>> rows,
    dynamic Function(Map<String, dynamic>) keyOf,
  ) {
    final keys = <String>{};
    for (final row in rows) {
      final value = keyOf(row);
      if (value != null && '$value'.trim().isNotEmpty) {
        keys.add('$value');
      }
    }
    return keys.length;
  }

  static String _today() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  static String _withQuery(String endpoint, Map<String, Object?> params) {
    final query = params.entries
        .where((entry) =>
            entry.value != null && '${entry.value}'.trim().isNotEmpty)
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent('${entry.value}')}',
        )
        .join('&');
    if (query.isEmpty) return endpoint;
    return '$endpoint${endpoint.contains('?') ? '&' : '?'}$query';
  }

  static dynamic _rowId(Map<String, dynamic>? row) {
    if (row == null) return null;
    return row['id'] ??
        row['session_id'] ??
        row['Session_ID'] ??
        row['SessionId'] ??
        row['value'];
  }

  static double _amountFromPayload(dynamic payload, List<String> keys) {
    if (payload is List) {
      return _sumAmount(_resolveList(payload), keys);
    }
    if (payload is Map) {
      final map = _stringKeyed(payload);
      for (final key in keys) {
        final value = map[key];
        final amount = _amountValue(value);
        if (amount != 0) return amount;
      }

      for (final key in ['summary', 'totals', 'total', 'data']) {
        final nested = map[key];
        if (nested is Map || nested is List) {
          final amount = _amountFromPayload(nested, keys);
          if (amount != 0) return amount;
        }
      }

      return _sumAmount(_resolveList(map), keys);
    }
    return _amountValue(payload);
  }

  static double _sumAmount(
    List<Map<String, dynamic>> rows,
    List<String> keys,
  ) {
    var total = 0.0;
    for (final row in rows) {
      for (final key in keys) {
        if (row.containsKey(key)) {
          total += _amountValue(row[key]);
          break;
        }
      }
    }
    return total;
  }

  static double _amountValue(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    final cleaned = '$value'.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (cleaned.isEmpty || cleaned == '-' || cleaned == '.') return 0;
    return double.tryParse(cleaned) ?? 0;
  }

  static String _formatMoney(double amount) {
    final rounded = amount.round();
    final raw = '$rounded';
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final remaining = raw.length - i;
      buffer.write(raw[i]);
      if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
    }
    return 'Rs ${buffer.toString()}';
  }

  static Map<String, int> _attendanceCounts(
      List<Map<String, dynamic>> records) {
    final leaveStatuses = {
      'leave',
      'full_day_leave',
      'medical_leave',
      'first_half_day_leave',
      'second_half_day_leave',
      'half_day_without_pay',
      'short_leave',
    };
    var present = 0;
    var absent = 0;
    var leave = 0;
    var marked = 0;

    for (final record in records) {
      final status = '${record['status'] ?? ''}'.trim().toLowerCase();
      if (status.isEmpty) continue;
      marked++;
      if (status == 'present') {
        present++;
      } else if (status == 'absent') {
        absent++;
      } else if (leaveStatuses.contains(status)) {
        leave++;
      }
    }

    return {
      'present': present,
      'absent': absent,
      'leave': leave,
      'marked': marked,
    };
  }

  static String _employeeName(Map<String, dynamic> leave) {
    final employee = leave['employee'];
    if (employee is Map) {
      return '${employee['name'] ?? employee['employee_name'] ?? '-'}';
    }
    return '${leave['employee_name'] ?? leave['name'] ?? '-'}';
  }

  static String _leaveType(Map<String, dynamic> leave) {
    final leaveType = leave['leaveType'] ?? leave['leave_type'];
    if (leaveType is Map) return '${leaveType['name'] ?? 'Leave'}';
    return '${leave['leave_type_name'] ?? leave['type'] ?? 'Leave'}';
  }

  static String _shortDate(dynamic value) {
    if (value == null) return '-';
    final raw = '$value';
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
  }

  static String _activeSessionName(List<Map<String, dynamic>> sessions) {
    if (sessions.isEmpty) return '-';
    final row = _activeSession(sessions) ?? sessions.first;
    return '${row['name'] ?? row['session'] ?? row['SessionName'] ?? row['title'] ?? '-'}';
  }

  static Map<String, dynamic>? _activeSession(
    List<Map<String, dynamic>> sessions,
  ) {
    if (sessions.isEmpty) return null;
    return sessions.cast<Map<String, dynamic>?>().firstWhere(
          (row) =>
              row?['active'] == true ||
              row?['is_active'] == true ||
              row?['IsActive'] == true ||
              row?['current'] == true ||
              '${row?['status']}'.toLowerCase() == 'active',
          orElse: () => sessions.first,
        );
  }

  static bool _isLockedExam(Map<String, dynamic> exam) {
    return exam['is_locked'] == true ||
        exam['locked'] == true ||
        '${exam['status']}'.toUpperCase() == 'LOCKED';
  }

  static int _upcomingExamCount(List<Map<String, dynamic>> exams) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    var count = 0;
    for (final exam in exams) {
      final raw = exam['date'] ??
          exam['exam_date'] ??
          exam['start_date'] ??
          exam['examDate'];
      if (raw == null) continue;
      final parsed = DateTime.tryParse('$raw');
      if (parsed != null && !parsed.isBefore(start)) count++;
    }
    return count;
  }

  static String _pendingMarks(dynamic payload) {
    if (payload == null) return '-';
    if (payload is num) return '${payload.round()}';
    if (payload is Map) {
      final map = _stringKeyed(payload);
      final value =
          map['pending'] ?? map['count'] ?? map['total'] ?? map['data'];
      if (value is num) return '${value.round()}';
      if (value is List) return '${value.length}';
      if (value != null && '$value'.trim().isNotEmpty) return '$value';
    }
    return '-';
  }

  static String _rowTitle(Map<String, dynamic> row) {
    for (final key in [
      'name',
      'title',
      'username',
      'email',
      'employee_name',
      'student_name',
      'StudentName',
      'studentName',
      'admission_number',
      'Admission_Number',
      'receipt_no',
      'receiptNo',
      'Receipt_No',
      'slipId',
      'Slip_ID',
      'Serial',
      'fee_heading',
      'FeeHeading',
      'feeHeading',
      'route_name',
      'RouteName',
      'bus_number',
      'BusNumber',
      'exam_name',
      'examName',
      'session',
      'SessionName',
      'class_name',
      'section_name',
      'department_name',
      'code',
      'id',
    ]) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty) return '$value';
    }

    final nestedEmployee = row['employee'];
    if (nestedEmployee is Map && nestedEmployee['name'] != null) {
      return '${nestedEmployee['name']}';
    }
    final nestedStudent = row['student'];
    if (nestedStudent is Map && nestedStudent['name'] != null) {
      return '${nestedStudent['name']}';
    }
    return 'Record';
  }

  static String _rowSubtitle(Map<String, dynamic> row) {
    final parts = <String>[];
    for (final key in [
      'role',
      'status',
      'department_name',
      'designation',
      'employee_id',
      'admission_number',
      'Admission_Number',
      'receipt_no',
      'receiptNo',
      'Slip_ID',
      'Serial',
      'Fee_Recieved',
      'fee_received',
      'amount',
      'Amount',
      'totalAmount',
      'dueAmount',
      'pendingAmount',
      'payment_mode',
      'mode',
      'bank_name',
      'class_name',
      'section_name',
      'Villages',
      'village',
      'staff_type',
      'date',
      'exam_date',
      'start_date',
      'end_date',
      'createdAt',
    ]) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty) {
        parts.add('${_labelize(key)}: ${_trimValue(value)}');
      }
      if (parts.length >= 3) break;
    }

    final employee = row['employee'];
    if (parts.length < 3 && employee is Map && employee['name'] != null) {
      parts.add('Employee: ${employee['name']}');
    }
    final student = row['student'];
    if (parts.length < 3 && student is Map && student['name'] != null) {
      parts.add('Student: ${student['name']}');
    }

    return parts.isEmpty
        ? 'Tap web portal for full details.'
        : parts.join(' · ');
  }

  static String _rowMeta(Map<String, dynamic> row) {
    final value = row['id'] ??
        row['Serial'] ??
        row['receipt_no'] ??
        row['receiptNo'] ??
        row['Slip_ID'] ??
        row['code'] ??
        row['employee_id'] ??
        row['admission_number'] ??
        row['status'];
    if (value == null || '$value'.trim().isEmpty) return 'Live';
    return '#${_trimValue(value)}';
  }

  static String _labelize(String key) {
    return key
        .replaceAll('_', ' ')
        .replaceAll('At', ' at')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  static String _trimValue(dynamic value) {
    final raw = '$value';
    return raw.length > 28 ? '${raw.substring(0, 28)}...' : raw;
  }
}

class _EndpointRows {
  final String endpoint;
  final List<Map<String, dynamic>> rows;

  const _EndpointRows(this.endpoint, this.rows);
}
