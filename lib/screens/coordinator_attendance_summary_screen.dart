import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';

class CoordinatorAttendanceSummaryScreen extends StatefulWidget {
  const CoordinatorAttendanceSummaryScreen({super.key});

  @override
  State<CoordinatorAttendanceSummaryScreen> createState() =>
      _CoordinatorAttendanceSummaryScreenState();
}

class _CoordinatorAttendanceSummaryScreenState
    extends State<CoordinatorAttendanceSummaryScreen> {
  final DateFormat _apiDate = DateFormat('yyyy-MM-dd');
  final DateFormat _displayDate = DateFormat('dd MMM yyyy');

  DateTime _selectedDate = DateTime.now();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  String get _selectedDateString => _apiDate.format(_selectedDate);

  List<Map<String, dynamic>> get _sections {
    final rows = _summary?['summary'];
    if (rows is! List) return [];
    return rows
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  int get _totalStudents =>
      _sections.fold(0, (sum, item) => sum + _asInt(item['total']));

  int get _absentStudents =>
      _sections.fold(0, (sum, item) => sum + _asInt(item['absent']));

  int get _leaveStudents =>
      _sections.fold(0, (sum, item) => sum + _asInt(item['leave']));

  int get _presentStudents =>
      (_totalStudents - _absentStudents - _leaveStudents)
          .clamp(0, 1 << 31)
          .toInt();

  Future<void> _loadSummary() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response =
          await ApiService.rawGet('/attendance/summary/$_selectedDateString');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_extractError(response.body, 'Failed to load'));
      }

      final decoded = jsonDecode(response.body);
      if (!mounted) return;
      setState(() {
        _summary = decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _summary = null;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shiftDay(int delta) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: delta)));
    _loadSummary();
  }

  void _goToday() {
    setState(() => _selectedDate = DateTime.now());
    _loadSummary();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    _loadSummary();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  int _percentage(int value, int total) {
    if (total <= 0) return 0;
    return ((value / total) * 100).round();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Summary'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadSummary,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadSummary,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            _hero(),
            const SizedBox(height: 12),
            _dateControls(),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 34),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _stateCard(
                Icons.warning_rounded,
                'Failed to load attendance',
                _error!,
                actionLabel: 'Retry',
                onAction: _loadSummary,
              )
            else if (_summary == null || _sections.isEmpty)
              _stateCard(
                Icons.info_rounded,
                'No summary available',
                'No attendance summary is available for $_selectedDateString.',
                actionLabel: 'Refresh',
                onAction: _loadSummary,
              )
            else ...[
              _overview(),
              const SizedBox(height: 14),
              _sectionHeader(),
              const SizedBox(height: 10),
              ..._sections.map(_breakdownCard),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.fact_check_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Class Wise Attendance',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Review present, absent and leave counts by class-section for ${_displayDate.format(_selectedDate)}.',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateControls() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => _shiftDay(-1),
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('Prev'),
          ),
          OutlinedButton.icon(
            onPressed: _goToday,
            icon: const Icon(Icons.today_rounded),
            label: const Text('Today'),
          ),
          OutlinedButton.icon(
            onPressed: () => _shiftDay(1),
            icon: const Icon(Icons.chevron_right_rounded),
            label: const Text('Next'),
          ),
          ElevatedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month_rounded),
            label: Text(_displayDate.format(_selectedDate)),
          ),
        ],
      ),
    );
  }

  Widget _overview() {
    final total = _totalStudents;
    final present = _presentStudents;
    final absent = _absentStudents;
    final leave = _leaveStudents;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 720;
        final metrics = Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _metricCard(
                    title: 'Total Students',
                    value: total,
                    subtitle: 'All class-section records',
                    color: const Color(0xFF64748B),
                    icon: Icons.groups_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metricCard(
                    title: 'Present',
                    value: present,
                    subtitle: '${_percentage(present, total)}% of total',
                    color: const Color(0xFF16A34A),
                    icon: Icons.check_circle_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _metricCard(
                    title: 'Absent',
                    value: absent,
                    subtitle: '${_percentage(absent, total)}% of total',
                    color: const Color(0xFFDC2626),
                    icon: Icons.cancel_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metricCard(
                    title: 'Leaves',
                    value: leave,
                    subtitle: '${_percentage(leave, total)}% of total',
                    color: const Color(0xFFD97706),
                    icon: Icons.event_busy_rounded,
                  ),
                ),
              ],
            ),
          ],
        );

        final chart = _attendanceChart(total, present, absent, leave);

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: metrics),
              const SizedBox(width: 12),
              Expanded(child: chart),
            ],
          );
        }

        return Column(
          children: [
            metrics,
            const SizedBox(height: 12),
            chart,
          ],
        );
      },
    );
  }

  Widget _metricCard({
    required String title,
    required int value,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$value',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _attendanceChart(int total, int present, int absent, int leave) {
    return Container(
      height: 274,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overall Attendance - $_selectedDateString',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: total <= 0
                ? const Center(child: Text('No attendance data'))
                : PieChart(
                    PieChartData(
                      centerSpaceRadius: 48,
                      sectionsSpace: 2,
                      sections: [
                        PieChartSectionData(
                          value: present.toDouble(),
                          color: const Color(0xFF22C55E),
                          title: '${_percentage(present, total)}%',
                          radius: 52,
                          titleStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                        PieChartSectionData(
                          value: absent.toDouble(),
                          color: const Color(0xFFEF4444),
                          title: '${_percentage(absent, total)}%',
                          radius: 52,
                          titleStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                        PieChartSectionData(
                          value: leave.toDouble(),
                          color: const Color(0xFFF59E0B),
                          title: '${_percentage(leave, total)}%',
                          radius: 52,
                          titleStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: const [
              _LegendDot(color: Color(0xFF22C55E), label: 'Present'),
              _LegendDot(color: Color(0xFFEF4444), label: 'Absent'),
              _LegendDot(color: Color(0xFFF59E0B), label: 'Leaves'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Class & Section Breakdown',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 2),
              Text(
                'Detailed attendance progress for each class-section',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ),
        ),
        _chip('${_sections.length} sections'),
      ],
    );
  }

  Widget _breakdownCard(Map<String, dynamic> item) {
    final total = _asInt(item['total']);
    final absent = _asInt(item['absent']);
    final leave = _asInt(item['leave']);
    final present = (total - absent - leave).clamp(0, 1 << 31).toInt();
    final presentPct = _percentage(present, total);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Class ${item['class_name'] ?? '-'} - Section ${item['section_name'] ?? '-'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Total Students: $total',
                      style:
                          const TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _chip('$presentPct% Present'),
            ],
          ),
          const SizedBox(height: 12),
          _progressStat('Present', present, total, const Color(0xFF16A34A)),
          _progressStat('Absent', absent, total, const Color(0xFFDC2626)),
          _progressStat('Leaves', leave, total, const Color(0xFFD97706)),
        ],
      ),
    );
  }

  Widget _progressStat(String label, int value, int total, Color color) {
    final pct = _percentage(value, total);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                '$value ($pct%)',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: total <= 0 ? 0 : value / total,
              color: color,
              backgroundColor: color.withOpacity(0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stateCard(
    IconData icon,
    String title,
    String message, {
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2563EB), size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(message, style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
