import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/api_service.dart';

class AccountsFeeHeadCollectionReportScreen extends StatefulWidget {
  const AccountsFeeHeadCollectionReportScreen({super.key});

  @override
  State<AccountsFeeHeadCollectionReportScreen> createState() =>
      _AccountsFeeHeadCollectionReportScreenState();
}

class _AccountsFeeHeadCollectionReportScreenState
    extends State<AccountsFeeHeadCollectionReportScreen> {
  final DateFormat _apiDate = DateFormat('yyyy-MM-dd');
  final TextEditingController _searchController = TextEditingController();

  bool _loadingMasters = true;
  bool _loading = false;
  bool _downloading = false;
  String? _error;

  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _sections = [];
  Map<String, dynamic>? _school;
  Map<String, dynamic>? _report;

  String _sessionId = '';
  String _classId = '';
  String _sectionId = '';
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _feeHeads => _asMapList(_report?['feeHeads']);

  List<Map<String, dynamic>> get _rows => _asMapList(_report?['rows']);

  List<Map<String, dynamic>> get _filteredRows {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows.where((row) {
      final text = [
        row['studentName'],
        row['admissionNumber'],
        row['className'],
        row['sectionName'],
      ].map(_safe).join(' ').toLowerCase();
      return text.contains(q);
    }).toList();
  }

  Map<String, dynamic> get _reportTotals {
    final raw = _report?['reportTotals'];
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  bool get _showVanColumns => _asBool(_report?['showVanColumns']);
  bool get _showFine => _report?['showFine'] != false;
  bool get _hasData => _rows.isNotEmpty;

  List<Map<String, dynamic>> get _visibleSections {
    if (_classId.isEmpty) return _sections;
    return _sections.where((section) {
      final classId = section['class_id'] ??
          section['classId'] ??
          section['Class_ID'] ??
          (section['class'] is Map ? section['class']['id'] : null);
      if (_safe(classId).isEmpty) return true;
      return _safe(classId) == _classId;
    }).toList();
  }

  String get _selectedClassName {
    if (_classId.isEmpty) return 'All Classes';
    final match = _classes.where((row) => _safe(row['id']) == _classId);
    if (match.isEmpty) return _classId;
    return _safe(
      match.first['class_name'] ??
          match.first['className'] ??
          match.first['name'],
      _classId,
    );
  }

  String get _selectedSessionName {
    final match = _sessions.where((row) => _safe(row['id']) == _sessionId);
    if (match.isEmpty) return _sessionId;
    return _safe(match.first['name'] ?? match.first['label'], _sessionId);
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loadingMasters = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _getList('/schools'),
        _getList('/sessions'),
        _getList('/classes'),
        _getList('/sections'),
      ]);
      final sessions = results[1];
      final active = sessions.firstWhere(
        (row) => row['is_active'] == true || row['is_active'] == 1,
        orElse: () =>
            sessions.isNotEmpty ? sessions.first : <String, dynamic>{},
      );
      if (!mounted) return;
      setState(() {
        _school = results[0].isNotEmpty ? results[0].first : null;
        _sessions = sessions;
        _classes = results[2];
        _sections = results[3];
        _sessionId = _safe(active['id']);
      });
      if (_sessionId.isNotEmpty) await _fetchReport();
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
      return <Map<String, dynamic>>[];
    }
    return _extractRows(jsonDecode(response.body));
  }

  Future<void> _fetchReport() async {
    if (_sessionId.isEmpty) {
      setState(() => _error = 'Please select academic session.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiService.rawGet(
        _endpoint('/student-fee-head-collection'),
      );
      if (!_ok(response.statusCode)) {
        throw Exception(_apiError(response.body, 'Could not fetch report.'));
      }
      final decoded = jsonDecode(response.body);
      if (!mounted) return;
      setState(() {
        _report = decoded is Map ? Map<String, dynamic>.from(decoded) : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _report = null;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download(String type) async {
    if (_sessionId.isEmpty) {
      _showSnack('Please select session first.');
      return;
    }
    final isExcel = type == 'excel';
    setState(() => _downloading = true);
    try {
      final response = await ApiService.rawGet(
        _endpoint(
          isExcel
              ? '/student-fee-head-collection/excel'
              : '/student-fee-head-collection/pdf',
        ),
        extraHeaders: {
          'Accept': isExcel
              ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
              : 'application/pdf',
        },
      );
      if (!_ok(response.statusCode) || response.bodyBytes.isEmpty) {
        _showSnack(_apiError(response.body, 'Could not download report.'));
        return;
      }
      final dir = await getTemporaryDirectory();
      final ext = isExcel ? 'xlsx' : 'pdf';
      final file = File('${dir.path}/student_fee_head_collection.$ext');
      await file.writeAsBytes(response.bodyBytes, flush: true);
      await OpenFilex.open(file.path);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  String _endpoint(String path) {
    final params = <String, String>{
      if (_sessionId.isNotEmpty) 'session_id': _sessionId,
      if (_classId.isNotEmpty) 'class_id': _classId,
      if (_sectionId.isNotEmpty) 'section_id': _sectionId,
      if (_fromDate != null) 'from_date': _apiDate.format(_fromDate!),
      if (_toDate != null) 'to_date': _apiDate.format(_toDate!),
    };
    final query = Uri(queryParameters: params).query;
    return query.isEmpty ? path : '$path?$query';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fee Head Collection'),
        actions: [
          IconButton(
            tooltip: 'Excel',
            onPressed:
                _hasData && !_downloading ? () => _download('excel') : null,
            icon: const Icon(Icons.table_chart_rounded),
          ),
          IconButton(
            tooltip: 'PDF',
            onPressed:
                _hasData && !_downloading ? () => _download('pdf') : null,
            icon: const Icon(Icons.picture_as_pdf_rounded),
          ),
        ],
      ),
      body: _loadingMasters
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchReport,
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
                  const SizedBox(height: 12),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (!_hasData)
                    _emptyState()
                  else ...[
                    _searchAndActions(),
                    const SizedBox(height: 12),
                    _studentList(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _hero() {
    final totals = _reportTotals;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF101828), Color(0xFF344054)],
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
              Icon(Icons.stacked_bar_chart_rounded,
                  color: Colors.white, size: 34),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Student Fee Head Collection',
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
              _heroStat('Students', '${_rows.length}'),
              _heroStat('Received', _money(totals['totalReceived'])),
              _heroStat('Grand', _money(totals['grandTotal'])),
            ],
          ),
          if (_school != null && _safe(_school!['name']).isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_safe(_school!['name']),
                style: const TextStyle(color: Colors.white70)),
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
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _filters() {
    return _panel(
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: _sessionId,
            decoration: const InputDecoration(
              labelText: 'Session',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('Select Session')),
              ..._sessions.map(
                (session) => DropdownMenuItem(
                  value: _safe(session['id']),
                  child: Text(_safe(session['name'] ?? session['label'])),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() => _sessionId = value ?? '');
              _fetchReport();
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _classId,
            decoration: const InputDecoration(
              labelText: 'Class',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('All Classes')),
              ..._classes.map(
                (cls) => DropdownMenuItem(
                  value: _safe(cls['id']),
                  child: Text(
                    _safe(cls['class_name'] ?? cls['className'] ?? cls['name']),
                  ),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _classId = value ?? '';
                _sectionId = '';
              });
              _fetchReport();
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _sectionId,
            decoration: const InputDecoration(
              labelText: 'Section',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('All Sections')),
              ..._visibleSections.map(
                (section) => DropdownMenuItem(
                  value: _safe(section['id']),
                  child: Text(
                    _safe(section['section_name'] ??
                        section['sectionName'] ??
                        section['name']),
                  ),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() => _sectionId = value ?? '');
              _fetchReport();
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _dateButton(
                  'From Date',
                  _fromDate,
                  (date) {
                    setState(() => _fromDate = date);
                    _fetchReport();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dateButton(
                  'To Date',
                  _toDate,
                  (date) {
                    setState(() => _toDate = date);
                    _fetchReport();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading || _sessionId.isEmpty ? null : _fetchReport,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_loading ? 'Loading...' : 'Refresh'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateButton(
    String label,
    DateTime? value,
    ValueChanged<DateTime?> onChanged,
  ) {
    return OutlinedButton.icon(
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
        );
        onChanged(picked);
      },
      icon: const Icon(Icons.calendar_month_rounded, size: 18),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          value == null ? label : DateFormat('dd MMM yyyy').format(value),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _searchAndActions() {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Search student',
              hintText: 'Name, admission no, class or section',
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
          Row(
            children: [
              Expanded(child: _smallInfo('Class', _selectedClassName)),
              const SizedBox(width: 8),
              Expanded(child: _smallInfo('Session', _selectedSessionName)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _downloading ? null : () => _download('excel'),
                  icon: const Icon(Icons.table_chart_rounded),
                  label: const Text('Excel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _downloading ? null : () => _download('pdf'),
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text('PDF'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _smallInfo(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 11)),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _studentList() {
    final rows = _filteredRows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Showing ${rows.length} of ${_rows.length} students',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          _notice('No student matches your search.', Colors.grey.shade700)
        else
          ...rows.map(_studentCard),
      ],
    );
  }

  Widget _studentCard(Map<String, dynamic> row) {
    final totals = row['totals'] is Map
        ? Map<String, dynamic>.from(row['totals'])
        : <String, dynamic>{};
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
                        _safe(row['studentName'], '-'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_safe(row['admissionNumber'], '-')} • ${_safe(row['className'], '-')} ${_safe(row['sectionName'], '')}',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                _amountChip(_money(totals['grandTotal'])),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _amountBox('Received', totals['totalReceived']),
                _amountBox('Concession', totals['totalConcession']),
                _amountBox('Grand', totals['grandTotal'], strong: true),
              ],
            ),
            const SizedBox(height: 8),
            ..._feeHeads.map((head) => _feeHeadTile(row, head)),
            if (_showVanColumns) _vanTile(row),
          ],
        ),
      ),
    );
  }

  Widget _feeHeadTile(Map<String, dynamic> row, Map<String, dynamic> head) {
    final feeHeads = row['feeHeads'] is Map
        ? Map<String, dynamic>.from(row['feeHeads'])
        : <String, dynamic>{};
    final headId = _safe(head['id']);
    final value = feeHeads[headId] is Map
        ? Map<String, dynamic>.from(feeHeads[headId])
        : <String, dynamic>{};
    final paid = _num(value['paid']);
    final concession = _num(value['concession']);
    final fine = _num(value['fine']);
    if (paid == 0 && concession == 0 && fine == 0) {
      return const SizedBox.shrink();
    }
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(_safe(head['name'], 'Fee Head')),
      subtitle: Text('Paid: ${_money(paid)}'),
      children: [
        _line('Paid', paid),
        _line('Concession', concession),
        if (_showFine) _line('Fine', fine),
      ],
    );
  }

  Widget _vanTile(Map<String, dynamic> row) {
    final van = row['van'] is Map
        ? Map<String, dynamic>.from(row['van'])
        : <String, dynamic>{};
    final received = _num(van['received']);
    final concession = _num(van['concession']);
    final fine = _num(van['fine']);
    if (received == 0 && concession == 0 && fine == 0) {
      return const SizedBox.shrink();
    }
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Van Fee'),
      subtitle: Text('Received: ${_money(received)}'),
      children: [
        _line('Received', received),
        _line('Concession', concession),
        if (_showFine) _line('Fine', fine),
      ],
    );
  }

  Widget _line(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(_money(value),
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _amountBox(String label, dynamic value, {bool strong = false}) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: strong ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
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
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB).withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF1D4ED8),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: child,
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
          Icon(Icons.currency_rupee_rounded,
              size: 46, color: Colors.grey.shade500),
          const SizedBox(height: 10),
          const Text(
            'No report data found',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Select session and filters to view student fee head wise collection.',
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

List<Map<String, dynamic>> _extractRows(dynamic decoded) {
  if (decoded is List) {
    return decoded
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
  if (decoded is Map) {
    for (final key in ['data', 'rows', 'results', 'items']) {
      final value = decoded[key];
      if (value is List) return _extractRows(value);
    }
  }
  return <Map<String, dynamic>>[];
}

List<Map<String, dynamic>> _asMapList(dynamic raw) {
  if (raw is! List) return <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}

bool _ok(int statusCode) => statusCode >= 200 && statusCode < 300;

num _num(dynamic value) {
  if (value is num) return value;
  return num.tryParse(_safe(value).replaceAll(',', '')) ?? 0;
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = _safe(value).toLowerCase();
  return text == 'true' || text == '1' || text == 'yes';
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
