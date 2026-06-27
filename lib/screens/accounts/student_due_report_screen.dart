import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/api_service.dart';

class AccountsStudentDueReportScreen extends StatefulWidget {
  const AccountsStudentDueReportScreen({super.key});

  @override
  State<AccountsStudentDueReportScreen> createState() =>
      _AccountsStudentDueReportScreenState();
}

class _AccountsStudentDueReportScreenState
    extends State<AccountsStudentDueReportScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _loadingMasters = true;
  bool _loadingMain = false;
  bool _loadingPrev = false;
  bool _busy = false;
  String? _error;

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _students = [];
  List<String> _feeHeadings = [];
  Map<int, num> _previousBalances = {};
  Map<String, dynamic>? _school;

  int? _classId;
  int? _sessionId;

  @override
  void initState() {
    super.initState();
    _loadMasters();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredStudents {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _students;
    return _students.where((student) {
      final text = [
        _studentName(student),
        _admissionNo(student),
      ].join(' ').toLowerCase();
      return text.contains(q);
    }).toList();
  }

  Map<String, _DueSummary> get _headSummary {
    final summary = <String, _DueSummary>{};
    for (final student in _students) {
      for (final fee in _feeDetails(student)) {
        final heading = _safe(fee['fee_heading']);
        if (heading.isEmpty) continue;
        final current = summary[heading] ?? const _DueSummary();
        summary[heading] = current +
            _DueSummary(
              originalFeeDue: _num(fee['originalFeeDue']),
              effectiveFeeDue: _num(fee['effectiveFeeDue']),
              finalAmountDue: _num(fee['finalAmountDue']),
              totalFeeReceived: _num(fee['totalFeeReceived']),
              totalVanFeeReceived: _num(fee['totalVanFeeReceived']),
              totalConcessionReceived: _num(fee['totalConcessionReceived']),
            );
      }
    }
    return summary;
  }

  _DueSummary get _grandSummary {
    return _headSummary.values.fold(
      const _DueSummary(),
      (acc, item) => acc + item,
    );
  }

  num get _totalPreviousBalance =>
      _previousBalances.values.fold<num>(0, (sum, value) => sum + value);

  Future<void> _loadMasters() async {
    setState(() {
      _loadingMasters = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _getList('/classes'),
        _getList('/sessions'),
        _getList('/schools'),
      ]);
      final sessions = results[1];
      if (!mounted) return;
      setState(() {
        _classes = results[0];
        _sessions = sessions;
        _school = results[2].isNotEmpty ? results[2].first : null;
        _sessionId = _toInt(
              sessions.firstWhere(
                (row) => row['is_active'] == true || row['isActive'] == true,
                orElse: () => sessions.isNotEmpty ? sessions.first : {},
              )['id'],
            ) ??
            (sessions.isNotEmpty ? _toInt(sessions.first['id']) : null);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingMasters = false);
    }
  }

  Future<List<Map<String, dynamic>>> _getList(String endpoint) async {
    final response = await ApiService.rawGet(endpoint);
    if (!_ok(response.statusCode)) {
      throw Exception(_apiError(response.body, 'Failed to load data.'));
    }
    return _extractRows(jsonDecode(response.body));
  }

  Future<void> _loadDueData() async {
    if (_classId == null) {
      _showSnack('Please select a class.');
      return;
    }
    if (_sessionId == null) {
      _showSnack('Please select an academic session.');
      return;
    }

    setState(() {
      _loadingMain = true;
      _error = null;
      _students = [];
      _feeHeadings = [];
      _previousBalances = {};
    });

    try {
      final response = await ApiService.rawGet(
        '/feedue/class/$_classId/fees?session_id=$_sessionId',
      );
      if (!_ok(response.statusCode)) {
        throw Exception(
          _apiError(response.body, 'Could not fetch fee data.'),
        );
      }
      final rows = _extractRows(jsonDecode(response.body));
      final headings = <String>{};
      for (final student in rows) {
        for (final fee in _feeDetails(student)) {
          final heading = _safe(fee['fee_heading']);
          if (heading.isNotEmpty) headings.add(heading);
        }
      }
      if (!mounted) return;
      setState(() {
        _students = rows;
        _feeHeadings = headings.toList()..sort();
      });
      await _loadPreviousBalances(rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingMain = false);
    }
  }

  Future<void> _loadPreviousBalances(List<Map<String, dynamic>> rows) async {
    if (_sessionId == null || rows.isEmpty) return;
    setState(() => _loadingPrev = true);
    try {
      final futures = rows.map((student) async {
        final id = _studentId(student);
        if (id == null) return MapEntry(0, 0);
        try {
          final response = await ApiService.rawGet(
            '/opening-balances/outstanding?student_id=$id&session_id=$_sessionId',
          );
          if (!_ok(response.statusCode)) return MapEntry(id, 0);
          final decoded = jsonDecode(response.body);
          final amount = decoded is Map
              ? _num(
                  decoded['data'] is Map
                      ? decoded['data']['outstanding']
                      : decoded['outstanding'] ?? decoded['totalOutstanding'],
                )
              : 0;
          return MapEntry(id, amount);
        } catch (_) {
          return MapEntry(id, 0);
        }
      }).toList();
      final entries = await Future.wait(futures);
      if (!mounted) return;
      setState(() {
        _previousBalances = {
          for (final entry in entries)
            if (entry.key != 0) entry.key: entry.value,
        };
      });
    } finally {
      if (mounted) setState(() => _loadingPrev = false);
    }
  }

  Future<void> _exportCsv() async {
    if (_students.isEmpty) {
      _showSnack('Please select a class with data first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final rows = <List<dynamic>>[
        ['Class Name', _selectedClassName],
        ['Session', _sessionLabel],
        if (_school != null) ['School', _safe(_school!['name'])],
        [],
        ['Admission No.', 'Student Name', 'Previous Balance', ..._feeHeadings],
        ..._students.map((student) {
          final feeMap = {
            for (final fee in _feeDetails(student))
              _safe(fee['fee_heading']): _num(fee['finalAmountDue']),
          };
          return [
            _admissionNo(student),
            _studentName(student),
            _previousBalances[_studentId(student)] ?? 0,
            ..._feeHeadings.map((heading) => feeMap[heading] ?? 0),
          ];
        }),
        [],
        ['Headwise Summary'],
        [
          'Fee Heading',
          'Original Fee Due',
          'Effective Fee Due',
          'Final Due',
          'Received',
          'Van Fee Received',
          'Concession Given',
        ],
        ..._headSummary.entries.map((entry) => [
              entry.key,
              entry.value.originalFeeDue,
              entry.value.effectiveFeeDue,
              entry.value.finalAmountDue,
              entry.value.totalFeeReceived,
              entry.value.totalVanFeeReceived,
              entry.value.totalConcessionReceived,
            ]),
        [],
        ['Grand Summary'],
        ['Original Fee Due', _grandSummary.originalFeeDue],
        ['Effective Fee Due', _grandSummary.effectiveFeeDue],
        ['Final Due', _grandSummary.finalAmountDue],
        ['Received', _grandSummary.totalFeeReceived],
        ['Van Fee Received', _grandSummary.totalVanFeeReceived],
        ['Concession Given', _grandSummary.totalConcessionReceived],
        ['Previous Balance', _totalPreviousBalance],
      ];

      final csv = const ListToCsvConverter().convert(rows);
      final dir = await getTemporaryDirectory();
      final fileName =
          'StudentDue_${_selectedClassName}_${_sessionLabel}'.replaceAll(
        RegExp(r'[^A-Za-z0-9_.-]+'),
        '_',
      );
      final file = File('${dir.path}/$fileName.csv');
      await file.writeAsString(csv, flush: true);
      await OpenFilex.open(file.path);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _selectedClassName {
    final match = _classes.where((row) => _toInt(row['id']) == _classId);
    if (match.isEmpty) return _classId?.toString() ?? '-';
    return _safe(
        match.first['class_name'] ?? match.first['name'], 'Class $_classId');
  }

  String get _sessionLabel {
    final match = _sessions.where((row) => _toInt(row['id']) == _sessionId);
    if (match.isEmpty) return _sessionId?.toString() ?? '-';
    return _safe(match.first['name'] ?? match.first['label'], '$_sessionId');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fee Due Report'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: _students.isEmpty || _busy ? null : _exportCsv,
            icon: const Icon(Icons.download_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadingMain ? null : _loadDueData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          _loadingMasters
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadDueData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                    children: [
                      _hero(),
                      const SizedBox(height: 12),
                      _filters(),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        _notice(_error!, Colors.red.shade700),
                      ],
                      if (_loadingMain) ...[
                        const SizedBox(height: 24),
                        const Center(child: CircularProgressIndicator()),
                      ] else if (_students.isEmpty) ...[
                        const SizedBox(height: 24),
                        _emptyState(),
                      ] else ...[
                        const SizedBox(height: 12),
                        _grandSummaryCard(),
                        const SizedBox(height: 12),
                        _headSummaryCard(),
                        const SizedBox(height: 12),
                        _studentList(),
                      ],
                    ],
                  ),
                ),
          if (_busy)
            Container(
              color: Colors.black.withOpacity(0.08),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE11D48), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_rounded, color: Colors.white, size: 34),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Student Due Amounts',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _heroStat('Students', '${_filteredStudents.length}'),
              _heroStat('Final Due', _money(_grandSummary.finalAmountDue)),
              _heroStat('Prev Bal', _money(_totalPreviousBalance)),
            ],
          ),
          if (_school != null) ...[
            const SizedBox(height: 10),
            Text(
              _safe(_school!['name']),
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
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
          DropdownButtonFormField<int>(
            value: _classId,
            decoration: const InputDecoration(
              labelText: 'Select Class',
              border: OutlineInputBorder(),
            ),
            items: _classes
                .map(
                  (row) => DropdownMenuItem(
                    value: _toInt(row['id']),
                    child: Text(_safe(row['class_name'] ?? row['name'])),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() => _classId = value);
              _loadDueData();
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: _sessionId,
            decoration: const InputDecoration(
              labelText: 'Academic Session',
              border: OutlineInputBorder(),
            ),
            items: _sessions
                .map(
                  (row) => DropdownMenuItem(
                    value: _toInt(row['id']),
                    child:
                        Text(_safe(row['name'] ?? row['label'] ?? row['id'])),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() => _sessionId = value);
              _loadDueData();
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchController,
            enabled: _students.isNotEmpty,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Search name / admission no.',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loadingMain ? null : _loadDueData,
              icon: const Icon(Icons.analytics_rounded),
              label: Text(
                  _loadingMain ? 'Fetching fee data...' : 'Load Due Report'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grandSummaryCard() {
    final grand = _grandSummary;
    return _sectionCard(
      title: 'Grand Summary',
      subtitle:
          'Previous balance is shown separately and is not part of headwise totals.',
      child: Column(
        children: [
          _metricRow('Original Fee Due', grand.originalFeeDue),
          _metricRow('Effective Fee Due', grand.effectiveFeeDue),
          _metricRow('Final Due', grand.finalAmountDue, strong: true),
          _metricRow('Received', grand.totalFeeReceived),
          _metricRow('Van Fee Received', grand.totalVanFeeReceived),
          _metricRow('Concession Given', grand.totalConcessionReceived),
          _metricRow('Previous Balance', _totalPreviousBalance, danger: true),
        ],
      ),
    );
  }

  Widget _headSummaryCard() {
    final entries = _headSummary.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return _sectionCard(
      title: 'Headwise Summary',
      subtitle: '${entries.length} fee headings',
      child: Column(
        children: entries
            .map(
              (entry) => ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  entry.key,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle:
                    Text('Final due: ${_money(entry.value.finalAmountDue)}'),
                children: [
                  _metricRow('Original Fee Due', entry.value.originalFeeDue),
                  _metricRow('Effective Fee Due', entry.value.effectiveFeeDue),
                  _metricRow('Final Due', entry.value.finalAmountDue,
                      strong: true),
                  _metricRow('Received', entry.value.totalFeeReceived),
                  _metricRow(
                      'Van Fee Received', entry.value.totalVanFeeReceived),
                  _metricRow(
                    'Concession Given',
                    entry.value.totalConcessionReceived,
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _studentList() {
    final students = _filteredStudents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Student Dues',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        if (students.isEmpty)
          _notice(
            'No student data matches your search.',
            Colors.grey.shade700,
          )
        else
          ...students.map(_studentCard),
      ],
    );
  }

  Widget _studentCard(Map<String, dynamic> student) {
    final id = _studentId(student);
    final prevBalance = id == null ? 0 : (_previousBalances[id] ?? 0);
    final feeMap = {
      for (final fee in _feeDetails(student)) _safe(fee['fee_heading']): fee,
    };
    final totalDue = _feeHeadings.fold<num>(
      0,
      (sum, heading) => sum + _num(feeMap[heading]?['finalAmountDue']),
    );

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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _studentName(student),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Admission ${_admissionNo(student)}',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                _dueChip(totalDue + prevBalance),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _miniAmount('Final Due', totalDue, true),
                _miniAmount(
                  _loadingPrev ? 'Prev (...)' : 'Previous',
                  prevBalance,
                  false,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._feeHeadings.map((heading) {
              final fee = feeMap[heading];
              final finalDue = _num(fee?['finalAmountDue']);
              if (finalDue == 0) return const SizedBox.shrink();
              return ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(heading),
                subtitle: Text('Final due: ${_money(finalDue)}'),
                children: [
                  _metricRow('Original', _num(fee?['originalFeeDue'])),
                  _metricRow('Effective', _num(fee?['effectiveFeeDue'])),
                  _metricRow('Received', _num(fee?['totalFeeReceived'])),
                  _metricRow('Van Fee', _num(fee?['totalVanFeeReceived'])),
                  _metricRow(
                    'Concession',
                    _num(fee?['totalConcessionReceived']),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _dueChip(num value) {
    final color = value > 0 ? const Color(0xFFE11D48) : const Color(0xFF16A34A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value > 0 ? _money(value) : 'Clear',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _miniAmount(String label, num value, bool strong) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: strong ? const Color(0xFFFFF1F2) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 11)),
            Text(
              _money(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _metricRow(
    String label,
    num value, {
    bool strong = false,
    bool danger = false,
  }) {
    final color = danger && value > 0 ? const Color(0xFFE11D48) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            _money(value),
            style: TextStyle(
              color: color,
              fontWeight: strong || danger ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice(String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: color)),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(Icons.receipt_long_rounded,
              size: 46, color: Colors.grey.shade500),
          const SizedBox(height: 10),
          const Text(
            'Select a class to view due amounts',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            _classId == null
                ? 'Choose class and session, then load the due report.'
                : 'No student data found for this class/session.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _DueSummary {
  const _DueSummary({
    this.originalFeeDue = 0,
    this.effectiveFeeDue = 0,
    this.finalAmountDue = 0,
    this.totalFeeReceived = 0,
    this.totalVanFeeReceived = 0,
    this.totalConcessionReceived = 0,
  });

  final num originalFeeDue;
  final num effectiveFeeDue;
  final num finalAmountDue;
  final num totalFeeReceived;
  final num totalVanFeeReceived;
  final num totalConcessionReceived;

  _DueSummary operator +(_DueSummary other) {
    return _DueSummary(
      originalFeeDue: originalFeeDue + other.originalFeeDue,
      effectiveFeeDue: effectiveFeeDue + other.effectiveFeeDue,
      finalAmountDue: finalAmountDue + other.finalAmountDue,
      totalFeeReceived: totalFeeReceived + other.totalFeeReceived,
      totalVanFeeReceived: totalVanFeeReceived + other.totalVanFeeReceived,
      totalConcessionReceived:
          totalConcessionReceived + other.totalConcessionReceived,
    );
  }
}

List<Map<String, dynamic>> _extractRows(dynamic decoded) {
  if (decoded is List) {
    return decoded
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
  if (decoded is Map) {
    for (final key in [
      'data',
      'rows',
      'results',
      'items',
      'classes',
      'sessions'
    ]) {
      final value = decoded[key];
      if (value is List) return _extractRows(value);
    }
  }
  return <Map<String, dynamic>>[];
}

List<Map<String, dynamic>> _feeDetails(Map<String, dynamic> student) {
  final raw = student['feeDetails'];
  if (raw is! List) return <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}

String _studentName(Map<String, dynamic> student) =>
    _safe(student['name'] ?? student['student_name'], '-');

String _admissionNo(Map<String, dynamic> student) => _safe(
      student['AdmissionNumber'] ??
          student['admission_number'] ??
          student['admissionNo'] ??
          student['admission_no'] ??
          student['id'],
      '-',
    );

int? _studentId(Map<String, dynamic> student) {
  final nested = student['Student'];
  return _toInt(student['id'] ??
      student['student_id'] ??
      student['Student_ID'] ??
      student['StudentId'] ??
      (nested is Map ? nested['id'] : null));
}

num _num(dynamic value) {
  if (value is num) return value;
  final text = _safe(value);
  if (text.isEmpty) return 0;
  return num.tryParse(text.replaceAll(',', '')) ?? 0;
}

int? _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(_safe(value));
}

String _money(dynamic value) {
  final amount = _num(value);
  if (amount == 0) return '-';
  return NumberFormat.currency(
    locale: 'en_IN',
    symbol: '',
    decimalDigits: 2,
  ).format(amount);
}

String _safe(dynamic value, [String fallback = '']) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

bool _ok(int statusCode) => statusCode >= 200 && statusCode < 300;

String _apiError(String body, String fallback) {
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
