import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/api_service.dart';

const List<String> _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

class CoordinatorTimetableScreen extends StatefulWidget {
  const CoordinatorTimetableScreen({super.key});

  @override
  State<CoordinatorTimetableScreen> createState() =>
      _CoordinatorTimetableScreenState();
}

class _CoordinatorTimetableScreenState
    extends State<CoordinatorTimetableScreen> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _periods = [];
  List<Map<String, dynamic>> _classRows = [];
  List<Map<String, dynamic>> _teacherRows = [];

  String? _classFilter;
  String? _sectionFilter;
  String? _classDayFilter;
  String? _teacherFilter;
  String? _teacherDayFilter;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final periods = await _loadListFromCandidates(['/periods']);
      final classRows = await _loadListFromCandidates([
        '/period-class-teacher-subject/timetable',
        '/period-class-teacher-subject',
        '/period-class-teacher-subject/all',
      ]);
      final teacherRows = await _loadListFromCandidates([
        '/period-class-teacher-subject/timetable-teacher',
        '/period-class-teacher-subject/teacher-timetable',
      ]);

      if (!mounted) return;
      setState(() {
        _periods = periods;
        _teacherRows =
            _normalizeRows(classRows.isNotEmpty ? classRows : teacherRows);
        _classRows =
            _normalizeRows(classRows.isNotEmpty ? classRows : teacherRows);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadListFromCandidates(
    List<String> endpoints,
  ) async {
    String? lastError;

    for (final endpoint in endpoints) {
      try {
        final response = await ApiService.rawGet(endpoint);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          lastError = _extractError(response.body, 'Failed: $endpoint');
          continue;
        }

        final decoded = jsonDecode(response.body);
        final rows = _extractRows(decoded);
        if (rows.isNotEmpty || endpoints.length == 1) return rows;
      } catch (e) {
        lastError = e.toString().replaceFirst('Exception: ', '');
      }
    }

    if (endpoints.length == 1) {
      throw Exception(lastError ?? 'Failed to load ${endpoints.first}');
    }
    return [];
  }

  List<Map<String, dynamic>> _extractRows(dynamic decoded) {
    final raw = decoded is List
        ? decoded
        : decoded is Map
            ? (decoded['timetable'] ??
                decoded['data'] ??
                decoded['rows'] ??
                decoded['items'] ??
                decoded['periods'] ??
                [])
            : [];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<Map<String, dynamic>> _normalizeRows(List<Map<String, dynamic>> rows) {
    return rows
        .map((item) {
          final row = Map<String, dynamic>.from(item);
          row['_dayShort'] =
              _normalizeDay(row['day'] ?? row['Day'] ?? row['weekday']);
          row['_periodId'] = _periodId(row);
          return row;
        })
        .where((row) =>
            _safe(row['_dayShort']).isNotEmpty && row['_periodId'] != null)
        .toList()
      ..sort(_compareRows);
  }

  int _compareRows(Map<String, dynamic> a, Map<String, dynamic> b) {
    final dayA = _days.indexOf(_safe(a['_dayShort']));
    final dayB = _days.indexOf(_safe(b['_dayShort']));
    final byDay = (dayA < 0 ? 99 : dayA) - (dayB < 0 ? 99 : dayB);
    if (byDay != 0) return byDay;

    final pA = int.tryParse('${a['_periodId']}') ?? 9999;
    final pB = int.tryParse('${b['_periodId']}') ?? 9999;
    return pA.compareTo(pB);
  }

  List<Map<String, dynamic>> get _filteredClassRows {
    return _classRows.where((row) {
      final classValue = _className(row);
      final sectionValue = _sectionName(row);
      final dayValue = _safe(row['_dayShort']);
      final classOk = _classFilter == null || _classFilter == classValue;
      final sectionOk =
          _sectionFilter == null || _sectionFilter == sectionValue;
      final dayOk = _classDayFilter == null || _classDayFilter == dayValue;
      return classOk && sectionOk && dayOk;
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredTeacherRows {
    return _teacherRows.where((row) {
      final teacherValue = _teacherName(row);
      final dayValue = _safe(row['_dayShort']);
      final teacherOk =
          _teacherFilter == null || _teacherFilter == teacherValue;
      final dayOk = _teacherDayFilter == null || _teacherDayFilter == dayValue;
      return teacherOk && dayOk;
    }).toList();
  }

  List<String> get _classOptions => _uniqueSorted(_classRows.map(_className));
  List<String> get _sectionOptions =>
      _uniqueSorted(_classRows.map(_sectionName));
  List<String> get _teacherOptions =>
      _uniqueSorted(_teacherRows.map(_teacherName));

  List<String> _uniqueSorted(Iterable<String> values) {
    final set = values.where((v) => v.trim().isNotEmpty && v != '-').toSet();
    return set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Timetable Assignment'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.groups_rounded), text: 'Class Wise'),
              Tab(icon: Icon(Icons.co_present_rounded), text: 'Teacher Wise'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _loadAll,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _state(
                    Icons.warning_rounded,
                    'Could not load timetable',
                    _error!,
                    actionLabel: 'Retry',
                    onAction: _loadAll,
                  )
                : TabBarView(
                    children: [
                      RefreshIndicator(
                        onRefresh: _loadAll,
                        child: _classWiseView(),
                      ),
                      RefreshIndicator(
                        onRefresh: _loadAll,
                        child: _teacherWiseView(),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _classWiseView() {
    final rows = _filteredClassRows;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        _hero(
          icon: Icons.groups_rounded,
          title: 'Class Wise Timetable',
          subtitle: 'Review periods assigned to each class and section.',
          color: const Color(0xFF2563EB),
        ),
        const SizedBox(height: 12),
        _filters(
          children: [
            _textDropdown(
              label: 'Class',
              value: _classFilter,
              options: _classOptions,
              emptyLabel: 'All Classes',
              onChanged: (value) => setState(() => _classFilter = value),
            ),
            _textDropdown(
              label: 'Section',
              value: _sectionFilter,
              options: _sectionOptions,
              emptyLabel: 'All Sections',
              onChanged: (value) => setState(() => _sectionFilter = value),
            ),
            _textDropdown(
              label: 'Day',
              value: _classDayFilter,
              options: _days,
              emptyLabel: 'All Days',
              onChanged: (value) => setState(() => _classDayFilter = value),
            ),
          ],
          onReset: () => setState(() {
            _classFilter = null;
            _sectionFilter = null;
            _classDayFilter = null;
          }),
        ),
        const SizedBox(height: 12),
        _summaryStrip([
          _summaryItem(
              'Assignments', '${rows.length}', Icons.event_note_rounded),
          _summaryItem(
              'Classes', '${_classOptions.length}', Icons.class_rounded),
          _summaryItem(
              'Sections', '${_sectionOptions.length}', Icons.account_tree_rounded),
        ]),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          _empty('No class timetable found for selected filters.')
        else
          ..._groupedRows(rows).entries.map((entry) {
            return _daySection(entry.key, entry.value, showTeacher: true);
          }),
      ],
    );
  }

  Widget _teacherWiseView() {
    final rows = _filteredTeacherRows;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        _hero(
          icon: Icons.co_present_rounded,
          title: 'Teacher Wise Timetable',
          subtitle: 'Review teacher workload and assigned periods.',
          color: const Color(0xFF7C3AED),
        ),
        const SizedBox(height: 12),
        _filters(
          children: [
            _textDropdown(
              label: 'Teacher',
              value: _teacherFilter,
              options: _teacherOptions,
              emptyLabel: 'All Teachers',
              onChanged: (value) => setState(() => _teacherFilter = value),
            ),
            _textDropdown(
              label: 'Day',
              value: _teacherDayFilter,
              options: _days,
              emptyLabel: 'All Days',
              onChanged: (value) => setState(() => _teacherDayFilter = value),
            ),
          ],
          onReset: () => setState(() {
            _teacherFilter = null;
            _teacherDayFilter = null;
          }),
        ),
        const SizedBox(height: 12),
        _summaryStrip([
          _summaryItem(
              'Assignments', '${rows.length}', Icons.event_note_rounded),
          _summaryItem(
              'Teachers', '${_teacherOptions.length}', Icons.person_rounded),
          _summaryItem(
              'Periods', '${_periods.length}', Icons.schedule_rounded),
        ]),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          _empty('No teacher timetable found for selected filters.')
        else
          ..._groupedRows(rows).entries.map((entry) {
            return _daySection(entry.key, entry.value, showTeacher: false);
          }),
      ],
    );
  }

  Widget _hero({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color, const Color(0xFF0F172A)]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters({
    required List<Widget> children,
    required VoidCallback onReset,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          ...children.expand((child) => [child, const SizedBox(height: 10)]),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reset Filters'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _textDropdown({
    required String label,
    required String? value,
    required List<String> options,
    required String emptyLabel,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: options.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem<String>(value: null, child: Text(emptyLabel)),
        ...options.map(
          (option) => DropdownMenuItem<String>(
            value: option,
            child: Text(option, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _summaryStrip(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = constraints.maxWidth > 640 ? children.length : 1;
        return GridView.count(
          crossAxisCount: count,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: count == 1 ? 4.2 : 2.3,
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          children: children,
        );
      },
    );
  }

  Widget _summaryItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2563EB)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> _groupedRows(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final day in _days) {
      final dayRows = rows.where((row) => row['_dayShort'] == day).toList();
      if (dayRows.isNotEmpty) grouped[day] = dayRows;
    }
    return grouped;
  }

  Widget _daySection(
    String day,
    List<Map<String, dynamic>> rows, {
    required bool showTeacher,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
          child: Row(
            children: [
              Text(
                day,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 8),
              _pill('${rows.length} periods'),
            ],
          ),
        ),
        ...rows.map((row) => _assignmentCard(row, showTeacher: showTeacher)),
      ],
    );
  }

  Widget _assignmentCard(
    Map<String, dynamic> row, {
    required bool showTeacher,
  }) {
    final period = _periodName(row['_periodId']);
    final classSection =
        [_className(row), _sectionName(row)].where((x) => x != '-').join(' - ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFF2563EB).withOpacity(0.10),
              child: Text(
                _periodInitial(period),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    period,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    showTeacher ? classSection : _teacherName(row),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _pill(_subjectName(row)),
                      if (showTeacher) _pill(_teacherName(row)),
                      if (!showTeacher)
                        _pill(classSection.isEmpty ? '-' : classSection),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(String message) {
    return _state(
      Icons.event_busy_rounded,
      'No Timetable',
      message,
      actionLabel: 'Refresh',
      onAction: _loadAll,
    );
  }

  Widget _state(
    IconData icon,
    String title,
    String message, {
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: const Color(0xFF64748B)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.isEmpty ? '-' : label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  dynamic _periodId(Map<String, dynamic> row) {
    final period = _mapOf(row['period'] ?? row['Period']);
    return row['periodId'] ??
        row['period_id'] ??
        row['PeriodId'] ??
        period['id'] ??
        row['id'];
  }

  String _periodName(dynamic periodId) {
    for (final period in _periods) {
      final id = period['id'] ?? period['periodId'] ?? period['period_id'];
      if ('$id' == '$periodId') {
        return _safe(
          period['period_name'] ??
              period['name'] ??
              period['label'] ??
              'Period $periodId',
        );
      }
    }
    return 'Period ${_safe(periodId, '-')}';
  }

  String _periodInitial(String period) {
    final number = RegExp(r'\d+').firstMatch(period)?.group(0);
    if (number != null) return 'P$number';
    return period.isEmpty ? 'P' : period[0].toUpperCase();
  }

  String _className(Map<String, dynamic> row) {
    final classObj = _mapOf(row['Class'] ?? row['class']);
    return _safe(
      classObj['class_name'] ??
          classObj['name'] ??
          row['className'] ??
          row['class_name'] ??
          row['classId'],
      '-',
    );
  }

  String _sectionName(Map<String, dynamic> row) {
    final sectionObj = _mapOf(row['Section'] ?? row['section']);
    return _safe(
      sectionObj['section_name'] ??
          sectionObj['name'] ??
          row['sectionName'] ??
          row['section_name'] ??
          row['sectionId'],
      '-',
    );
  }

  String _subjectName(Map<String, dynamic> row) {
    final subject = _mapOf(row['Subject'] ?? row['subject']);
    return _safe(
      subject['name'] ??
          row['subjectName'] ??
          row['subject_name'] ??
          row['subjectId'],
      'Subject',
    );
  }

  String _teacherName(Map<String, dynamic> row) {
    final teacher = _mapOf(row['Teacher'] ?? row['teacher'] ?? row['User']);
    final employee = _mapOf(row['employee'] ?? row['Employee']);
    final staff = _mapOf(row['staff'] ?? row['Staff']);
    return _safe(
      teacher['name'] ??
          teacher['full_name'] ??
          employee['name'] ??
          employee['full_name'] ??
          staff['name'] ??
          staff['full_name'] ??
          row['teacherName'] ??
          row['teacher_name'] ??
          row['employeeName'] ??
          row['employee_name'] ??
          row['staffName'] ??
          row['staff_name'] ??
          row['userName'] ??
          row['user_name'] ??
          row['teacherId'],
      '-',
    );
  }

  Map<String, dynamic> _mapOf(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  String _normalizeDay(dynamic value) {
    final raw = _safe(value).toLowerCase();
    const map = {
      'mon': 'Mon',
      'monday': 'Mon',
      'tue': 'Tue',
      'tues': 'Tue',
      'tuesday': 'Tue',
      'wed': 'Wed',
      'weds': 'Wed',
      'wednesday': 'Wed',
      'thu': 'Thu',
      'thur': 'Thu',
      'thurs': 'Thu',
      'thursday': 'Thu',
      'fri': 'Fri',
      'friday': 'Fri',
      'sat': 'Sat',
      'saturday': 'Sat',
    };
    return map[raw] ?? '';
  }

  String _safe(dynamic value, [String fallback = '']) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  String _extractError(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final message =
            decoded['message'] ?? decoded['error'] ?? decoded['sqlMessage'];
        if (message != null && message.toString().trim().isNotEmpty) {
          return message.toString();
        }
      }
    } catch (_) {}
    return fallback;
  }
}
