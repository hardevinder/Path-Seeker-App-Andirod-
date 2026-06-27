import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';

class CoordinatorSubstitutionsScreen extends StatefulWidget {
  const CoordinatorSubstitutionsScreen({super.key});

  @override
  State<CoordinatorSubstitutionsScreen> createState() =>
      _CoordinatorSubstitutionsScreenState();
}

class _CoordinatorSubstitutionsScreenState
    extends State<CoordinatorSubstitutionsScreen> {
  final DateFormat _apiDate = DateFormat('yyyy-MM-dd');
  final DateFormat _displayDate = DateFormat('dd MMM yyyy');

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  DateTime? _filterDate;
  String? _coveringTeacher;
  String? _regularTeacher;
  String? _classFilter;
  String? _periodFilter;
  String? _subjectFilter;

  @override
  void initState() {
    super.initState();
    _loadSubstitutions();
  }

  Future<void> _loadSubstitutions() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await ApiService.rawGet('/substitutions');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_extractError(response.body, 'Failed to load'));
      }

      final decoded = jsonDecode(response.body);
      final raw = decoded is List
          ? decoded
          : decoded is Map
              ? (decoded['data'] ??
                  decoded['rows'] ??
                  decoded['items'] ??
                  decoded['substitutions'] ??
                  [])
              : [];

      final rows = raw is List
          ? raw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .map(_normalizeRow)
              .toList()
          : <Map<String, dynamic>>[];

      rows.sort((a, b) => _safe(b['_date']).compareTo(_safe(a['_date'])));

      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _normalizeRow(Map<String, dynamic> row) {
    final normalized = Map<String, dynamic>.from(row);
    normalized['_date'] = _dateOnly(row['date']);
    normalized['_coveringTeacherName'] = _coveringTeacherName(row);
    normalized['_regularTeacherName'] = _regularTeacherName(row);
    normalized['_classLabel'] = _classLabel(row);
    normalized['_periodName'] = _periodName(row);
    normalized['_subjectName'] = _subjectName(row);
    return normalized;
  }

  List<Map<String, dynamic>> get _filteredRows {
    return _rows.where((row) {
      final dateOk = _filterDate == null ||
          row['_date'] == _apiDate.format(_filterDate!);
      final coveringOk = _coveringTeacher == null ||
          row['_coveringTeacherName'] == _coveringTeacher;
      final regularOk = _regularTeacher == null ||
          row['_regularTeacherName'] == _regularTeacher;
      final classOk =
          _classFilter == null || row['_classLabel'] == _classFilter;
      final periodOk =
          _periodFilter == null || row['_periodName'] == _periodFilter;
      final subjectOk =
          _subjectFilter == null || row['_subjectName'] == _subjectFilter;
      return dateOk &&
          coveringOk &&
          regularOk &&
          classOk &&
          periodOk &&
          subjectOk;
    }).toList();
  }

  List<String> get _coveringOptions =>
      _uniqueSorted(_rows.map((row) => _safe(row['_coveringTeacherName'])));
  List<String> get _regularOptions =>
      _uniqueSorted(_rows.map((row) => _safe(row['_regularTeacherName'])));
  List<String> get _classOptions =>
      _uniqueSorted(_rows.map((row) => _safe(row['_classLabel'])));
  List<String> get _periodOptions =>
      _uniqueSorted(_rows.map((row) => _safe(row['_periodName'])));
  List<String> get _subjectOptions =>
      _uniqueSorted(_rows.map((row) => _safe(row['_subjectName'])));

  List<String> _uniqueSorted(Iterable<String> values) {
    final set = values
        .where((value) => value.isNotEmpty && value != '-')
        .toSet();
    return set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() => _filterDate = picked);
  }

  void _resetFilters() {
    setState(() {
      _filterDate = null;
      _coveringTeacher = null;
      _regularTeacher = null;
      _classFilter = null;
      _periodFilter = null;
      _subjectFilter = null;
    });
  }

  int get _todayCount {
    final today = _apiDate.format(DateTime.now());
    return _rows.where((row) => row['_date'] == today).length;
  }

  int get _weekCount {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final saturday = monday.add(const Duration(days: 5));
    return _rows.where((row) {
      final parsed = DateTime.tryParse(_safe(row['_date']));
      if (parsed == null) return false;
      return !parsed.isBefore(monday) && !parsed.isAfter(saturday);
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Substitutions'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadSubstitutions,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadSubstitutions,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            _hero(),
            const SizedBox(height: 12),
            _stats(rows.length),
            const SizedBox(height: 12),
            _filters(),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 34),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _state(
                Icons.warning_rounded,
                'Could not load substitutions',
                _error!,
              )
            else if (rows.isEmpty)
              _state(
                Icons.swap_horiz_rounded,
                'No substitutions found',
                'Try changing filters or pull down to refresh.',
              )
            else
              ...rows.map(_substitutionCard),
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
          colors: [Color(0xFF0F766E), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        children: [
          Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 36),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Substitution Listing',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Review covering teachers, regular teachers, class, period and subject.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stats(int filteredCount) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = constraints.maxWidth > 640 ? 4 : 2;
        return GridView.count(
          crossAxisCount: count,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.85,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _statCard('Filtered', '$filteredCount', Icons.filter_alt_rounded),
            _statCard('Total', '${_rows.length}', Icons.list_alt_rounded),
            _statCard('Today', '$_todayCount', Icons.today_rounded),
            _statCard('This Week', '$_weekCount', Icons.date_range_rounded),
          ],
        );
      },
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF0F766E)),
          const SizedBox(width: 9),
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
                  style: const TextStyle(color: Colors.black54, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month_rounded),
              label: Text(
                _filterDate == null
                    ? 'All Dates'
                    : _displayDate.format(_filterDate!),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _dropdown(
            label: 'Covering Teacher',
            value: _coveringTeacher,
            options: _coveringOptions,
            emptyLabel: 'All Covering Teachers',
            onChanged: (value) => setState(() => _coveringTeacher = value),
          ),
          const SizedBox(height: 10),
          _dropdown(
            label: 'Regular Teacher',
            value: _regularTeacher,
            options: _regularOptions,
            emptyLabel: 'All Regular Teachers',
            onChanged: (value) => setState(() => _regularTeacher = value),
          ),
          const SizedBox(height: 10),
          _dropdown(
            label: 'Class',
            value: _classFilter,
            options: _classOptions,
            emptyLabel: 'All Classes',
            onChanged: (value) => setState(() => _classFilter = value),
          ),
          const SizedBox(height: 10),
          _dropdown(
            label: 'Period',
            value: _periodFilter,
            options: _periodOptions,
            emptyLabel: 'All Periods',
            onChanged: (value) => setState(() => _periodFilter = value),
          ),
          const SizedBox(height: 10),
          _dropdown(
            label: 'Subject',
            value: _subjectFilter,
            options: _subjectOptions,
            emptyLabel: 'All Subjects',
            onChanged: (value) => setState(() => _subjectFilter = value),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reset Filters'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown({
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

  Widget _substitutionCard(Map<String, dynamic> row) {
    final isToday = row['_date'] == _apiDate.format(DateTime.now());
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF0F766E).withOpacity(0.12),
                  child: const Icon(
                    Icons.swap_horiz_rounded,
                    color: Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row['_periodName']} • ${row['_subjectName']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_niceDate(row['_date'])} • ${row['_classLabel']}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                if (isToday) _pill('Today'),
              ],
            ),
            const SizedBox(height: 12),
            _teacherLine(
              'Covering',
              _safe(row['_coveringTeacherName'], '-'),
              const Color(0xFF16A34A),
            ),
            const SizedBox(height: 7),
            _teacherLine(
              'Regular',
              _safe(row['_regularTeacherName'], '-'),
              const Color(0xFFDC2626),
            ),
          ],
        ),
      ),
    );
  }

  Widget _teacherLine(String label, String name, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        Expanded(
          child: Text(name, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _state(IconData icon, String title, String message) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: const Color(0xFF64748B)),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFDF7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }

  String _coveringTeacherName(Map<String, dynamic> row) {
    final teacher = _mapOf(row['Teacher'] ?? row['CoveringTeacher']);
    final employee = _mapOf(row['CoveringEmployee']);
    final nestedTeacher = _mapOf(row['teacher']);
    return _safe(
      teacher['name'] ??
          employee['name'] ??
          row['teacherName'] ??
          nestedTeacher['name'] ??
          _mapOf(nestedTeacher['userAccount'])['name'] ??
          row['teacher_name'],
      '-',
    );
  }

  String _regularTeacherName(Map<String, dynamic> row) {
    final teacher = _mapOf(row['OriginalTeacher'] ?? row['RegularTeacher']);
    final employee = _mapOf(row['OriginalEmployee']);
    final nestedTeacher = _mapOf(row['originalTeacher']);
    return _safe(
      teacher['name'] ??
          employee['name'] ??
          row['regularTeacherName'] ??
          row['originalTeacherName'] ??
          nestedTeacher['name'] ??
          _mapOf(nestedTeacher['userAccount'])['name'],
      '-',
    );
  }

  String _classLabel(Map<String, dynamic> row) {
    final classObj = _mapOf(row['Class'] ?? row['class']);
    final sectionObj = _mapOf(row['Section'] ?? row['section']);
    final className = _safe(
      classObj['class_name'] ??
          classObj['name'] ??
          row['className'] ??
          row['class_name'] ??
          row['classId'] ??
          row['class_id'],
      '-',
    );
    final sectionName = _safe(
      sectionObj['section_name'] ??
          sectionObj['name'] ??
          row['sectionName'] ??
          row['section_name'],
    );
    return sectionName.isEmpty ? className : '$className - $sectionName';
  }

  String _periodName(Map<String, dynamic> row) {
    final period = _mapOf(row['Period'] ?? row['period']);
    return _safe(
      period['period_name'] ??
          period['name'] ??
          row['periodName'] ??
          row['period_name'] ??
          row['periodId'] ??
          row['period_id'],
      '-',
    );
  }

  String _subjectName(Map<String, dynamic> row) {
    final subject = _mapOf(row['Subject'] ?? row['subject']);
    return _safe(
      subject['name'] ??
          row['subjectName'] ??
          row['subject_name'] ??
          row['subject'],
      '-',
    );
  }

  String _dateOnly(dynamic value) {
    final raw = _safe(value);
    if (raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw.length >= 10 ? raw.substring(0, 10) : raw;
    return _apiDate.format(parsed);
  }

  String _niceDate(dynamic value) {
    final parsed = DateTime.tryParse(_safe(value));
    return parsed == null ? _safe(value, '-') : _displayDate.format(parsed);
  }

  Map<String, dynamic> _mapOf(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
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
