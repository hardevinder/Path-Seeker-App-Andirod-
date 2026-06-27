import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../services/api_service.dart';

class CoordinatorSyllabusApprovalScreen extends StatefulWidget {
  const CoordinatorSyllabusApprovalScreen({super.key});

  @override
  State<CoordinatorSyllabusApprovalScreen> createState() =>
      _CoordinatorSyllabusApprovalScreenState();
}

class _CoordinatorSyllabusApprovalScreenState
    extends State<CoordinatorSyllabusApprovalScreen> {
  static const String _base = '/syllabus-breakdowns';

  final DateFormat _dateTimeFormat = DateFormat('dd MMM yyyy, hh:mm a');
  final TextEditingController _classFilter = TextEditingController();
  final TextEditingController _subjectFilter = TextEditingController();
  final TextEditingController _teacherFilter = TextEditingController();
  final TextEditingController _sessionFilter = TextEditingController();
  final TextEditingController _termFilter = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  bool _fetching = false;
  String? _error;
  Timer? _pollTimer;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _fetchPending();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 7),
      (_) {
        if (mounted && !_busy) _fetchPending(showLoading: false);
      },
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _classFilter.dispose();
    _subjectFilter.dispose();
    _teacherFilter.dispose();
    _sessionFilter.dispose();
    _termFilter.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredRows {
    final classQuery = _classFilter.text.trim().toLowerCase();
    final subjectQuery = _subjectFilter.text.trim().toLowerCase();
    final teacherQuery = _teacherFilter.text.trim().toLowerCase();
    final sessionQuery = _sessionFilter.text.trim().toLowerCase();
    final termQuery = _termFilter.text.trim().toLowerCase();

    return _rows.where((row) {
      return _className(row).toLowerCase().contains(classQuery) &&
          _subjectName(row).toLowerCase().contains(subjectQuery) &&
          _teacherName(row).toLowerCase().contains(teacherQuery) &&
          _safe(row['academicSession']).toLowerCase().contains(sessionQuery) &&
          _safe(row['term']).toLowerCase().contains(termQuery);
    }).toList();
  }

  int get _submittedCount =>
      _rows.where((row) => _statusOf(row) == 'SUBMITTED').length;

  int get _approvedCount =>
      _rows.where((row) => _statusOf(row) == 'APPROVED').length;

  Future<void> _fetchPending({bool showLoading = true}) async {
    if (_fetching) return;
    _fetching = true;
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final response = await ApiService.rawGet('$_base/pending');
      if (!_ok(response.statusCode)) {
        throw Exception(
          _extractError(response.body, 'Failed to fetch pending syllabus.'),
        );
      }
      final rows = _extractRows(jsonDecode(response.body));
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cleanError(e));
    } finally {
      _fetching = false;
      if (mounted && showLoading) setState(() => _loading = false);
    }
  }

  Future<Map<String, dynamic>?> _fetchById(dynamic id) async {
    try {
      final response = await ApiService.rawGet('$_base/$id');
      if (!_ok(response.statusCode)) {
        _showSnack(_extractError(response.body, 'Failed to open breakdown.'));
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final data = decoded['data'] ?? decoded;
        if (data is Map) return Map<String, dynamic>.from(data);
      }
    } catch (e) {
      _showSnack(_cleanError(e));
    }
    return null;
  }

  Future<void> _openPreview(Map<String, dynamic> row) async {
    setState(() => _busy = true);
    final full = await _fetchById(row['id']);
    if (mounted) setState(() => _busy = false);
    if (full == null || !mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SyllabusPreviewSheet(
        row: full,
        dateTimeFormat: _dateTimeFormat,
        onOpenPdf: () => _openPdf(row['id']),
      ),
    );
  }

  Future<void> _openPdf(dynamic id) async {
    setState(() => _busy = true);
    try {
      final response = await ApiService.rawGet(
        '$_base/$id/pdf',
        extraHeaders: const {'Accept': 'application/pdf'},
      );
      final bytes = response.bodyBytes;
      final isPdf = bytes.length > 4 &&
          bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46;
      if (!_ok(response.statusCode) || !isPdf) {
        _showSnack(_extractError(response.body, 'Failed to open PDF.'));
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/syllabus_breakdown_$id.pdf');
      await file.writeAsBytes(bytes, flush: true);
      await OpenFilex.open(file.path);
    } catch (e) {
      _showSnack(_cleanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(Map<String, dynamic> row) async {
    if (_statusOf(row) == 'APPROVED') {
      _showSnack('Already approved.');
      return;
    }

    bool publish = _asBool(row['publish']);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Approve Syllabus?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dialogLine('Class', _className(row)),
                _dialogLine('Subject', _subjectName(row)),
                _dialogLine('Teacher', _teacherName(row)),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Publish after approval'),
                  value: publish,
                  onChanged: (value) =>
                      setDialogState(() => publish = value ?? false),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Approve'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final response = await ApiService.rawPost('$_base/${row['id']}/approve', {
        'publish': publish,
      });
      if (!_ok(response.statusCode)) {
        _showSnack(_extractError(response.body, 'Failed to approve.'));
        return;
      }
      _showSnack('Syllabus breakdown approved.');
      await _fetchPending(showLoading: false);
    } catch (e) {
      _showSnack(_cleanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _returnToTeacher(Map<String, dynamic> row) async {
    if (_statusOf(row) == 'APPROVED') {
      _showSnack('Approved breakdown cannot be returned.');
      return;
    }

    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Return to Teacher'),
          content: TextField(
            controller: reasonController,
            minLines: 3,
            maxLines: 6,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Reason *',
              hintText: 'Write what needs to be corrected...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final clean = reasonController.text.trim();
                if (clean.isEmpty) return;
                Navigator.pop(context, clean);
              },
              child: const Text('Return'),
            ),
          ],
        );
      },
    );
    reasonController.dispose();
    if (reason == null || reason.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      final response = await ApiService.rawPost(
        '$_base/${row['id']}/return',
        {'reason': reason.trim()},
      );
      if (!_ok(response.statusCode)) {
        _showSnack(_extractError(response.body, 'Failed to return.'));
        return;
      }
      _showSnack('Sent back to teacher with reason.');
      await _fetchPending(showLoading: false);
    } catch (e) {
      _showSnack(_cleanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Syllabus Approvals'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _busy ? null : _fetchPending,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _state(
                      Icons.warning_rounded,
                      'Could not load approvals',
                      _error!,
                      actionLabel: 'Retry',
                      onAction: _fetchPending,
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchPending,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                        children: [
                          _hero(rows.length),
                          const SizedBox(height: 12),
                          _filters(),
                          const SizedBox(height: 12),
                          if (rows.isEmpty)
                            _state(
                              Icons.fact_check_rounded,
                              'No pending syllabus breakdowns',
                              'Submitted breakdowns will appear here for coordinator review.',
                            )
                          else
                            ...rows.map(_approvalCard),
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

  Widget _hero(int shownCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF047857), Color(0xFF2563EB)],
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
              Icon(Icons.fact_check_rounded, color: Colors.white, size: 36),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Syllabus Approval',
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
              _heroStat('Shown', '$shownCount'),
              _heroStat('Submitted', '$_submittedCount'),
              _heroStat('Approved', '$_approvedCount'),
            ],
          ),
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
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
          TextField(
            controller: _classFilter,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search Class',
              prefixIcon: Icon(Icons.school_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _subjectFilter,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search Subject',
              prefixIcon: Icon(Icons.menu_book_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _teacherFilter,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search Teacher',
              prefixIcon: Icon(Icons.person_search_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _sessionFilter,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Session',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _termFilter,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Term',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _approvalCard(Map<String, dynamic> row) {
    final status = _statusOf(row);
    final isApproved = status == 'APPROVED';
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
                        _subjectName(row),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_className(row)} • ${_teacherName(row)}',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                _statusChip(status),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _infoChip(Icons.calendar_today_rounded,
                    _safe(row['academicSession'], '-')),
                _infoChip(Icons.segment_rounded, _safe(row['term'], '-')),
                _infoChip(
                  Icons.schedule_rounded,
                  _fmtDateTime(row['submittedAt'] ?? row['updatedAt']),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _openPreview(row),
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text('View'),
                ),
                FilledButton.icon(
                  onPressed: isApproved || _busy ? null : () => _approve(row),
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('Approve'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      isApproved || _busy ? null : () => _returnToTeacher(row),
                  icon: const Icon(Icons.reply_rounded, size: 18),
                  label: const Text('Return'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _openPdf(row['id']),
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                  label: const Text('PDF'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final color = status == 'APPROVED'
        ? const Color(0xFF16A34A)
        : status == 'RETURNED'
            ? const Color(0xFFDC2626)
            : status == 'SUBMITTED'
                ? const Color(0xFFD97706)
                : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF475569)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _state(
    IconData icon,
    String title,
    String body, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: Colors.grey.shade500),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ],
        ),
      ),
    );
  }

  String _fmtDateTime(dynamic value) {
    final text = _safe(value);
    if (text.isEmpty) return '-';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return text;
    return _dateTimeFormat.format(parsed.toLocal());
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _SyllabusPreviewSheet extends StatelessWidget {
  const _SyllabusPreviewSheet({
    required this.row,
    required this.dateTimeFormat,
    required this.onOpenPdf,
  });

  final Map<String, dynamic> row;
  final DateFormat dateTimeFormat;
  final VoidCallback onOpenPdf;

  @override
  Widget build(BuildContext context) {
    final items = _itemsOf(row);
    final shownItems = items.take(12).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Syllabus Breakdown Preview',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  children: [
                    _summaryGrid(),
                    if (_safe(row['bookReference']).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _textBlock('Book/Reference', _safe(row['bookReference'])),
                    ],
                    if (_safe(row['objectives']).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _textBlock('Objectives', _safe(row['objectives'])),
                    ],
                    const SizedBox(height: 12),
                    const Text(
                      'Breakdown Items',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    if (shownItems.isEmpty)
                      _emptyItems()
                    else
                      ...shownItems.asMap().entries.map(
                            (entry) => _itemCard(entry.key, entry.value),
                          ),
                    if (items.length > 12) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Showing first 12 items. Open PDF for full view.',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: onOpenPdf,
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                        label: const Text('Open PDF'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _summaryGrid() {
    final rows = [
      ('Class', _className(row)),
      ('Subject', _subjectName(row)),
      ('Teacher', _teacherName(row)),
      ('Status', _statusOf(row)),
      ('Session', _safe(row['academicSession'], '-')),
      ('Term', _safe(row['term'], '-')),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: rows
          .map(
            (item) => Container(
              width: 160,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withOpacity(0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.$1,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.$2,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _textBlock(String title, String body) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(body),
        ],
      ),
    );
  }

  Widget _itemCard(int index, Map<String, dynamic> item) {
    final sequence = _safe(item['sequence'] ?? item['seq_no'], '${index + 1}');
    final unitNumber = _safe(item['unitNumber'] ?? item['unit_no']);
    final unitTitle = _safe(item['unitTitle'] ?? item['unit_title']);
    final unit = [unitNumber, unitTitle].where((v) => v.isNotEmpty).join(' ');
    final topics = _safe(item['topics'], '-');
    final subtopics = _safe(item['subtopics']);
    final periods = _safe(item['periods'], '-');
    final plannedMonth =
        _safe(item['plannedMonth'] ?? item['planned_month'], '-');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '#$sequence • ${unit.isEmpty ? '-' : unit}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text('P: $periods'),
              ],
            ),
            const SizedBox(height: 6),
            Text(topics),
            if (subtopics.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtopics,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'Month: $plannedMonth',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyItems() {
    return Container(
      padding: const EdgeInsets.all(18),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text('No items'),
    );
  }
}

List<Map<String, dynamic>> _extractRows(dynamic decoded) {
  final raw = decoded is List
      ? decoded
      : decoded is Map
          ? (decoded['data'] ?? decoded['rows'] ?? decoded['items'] ?? [])
          : [];
  if (raw is! List) return <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

List<Map<String, dynamic>> _itemsOf(Map<String, dynamic> row) {
  final raw = row['Items'] ?? row['items'] ?? [];
  if (raw is! List) return <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

String _className(Map<String, dynamic> row) {
  final nested = row['Class'];
  if (nested is Map) {
    return _safe(nested['class_name'] ?? nested['name'], '-');
  }
  return _safe(row['class_name'] ?? row['classId'], '-');
}

String _subjectName(Map<String, dynamic> row) {
  final nested = row['Subject'];
  if (nested is Map) {
    return _safe(nested['subject_name'] ?? nested['name'], '-');
  }
  return _safe(row['subject_name'] ?? row['subjectId'], '-');
}

String _teacherName(Map<String, dynamic> row) {
  final nested = row['Teacher'];
  if (nested is Map) return _safe(nested['name'], '-');
  return _safe(row['teacher_name'] ?? row['teacherId'], '-');
}

String _statusOf(Map<String, dynamic> row) =>
    _safe(row['status'], 'DRAFT').toUpperCase();

String _safe(dynamic value, [String fallback = '']) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = _safe(value).toLowerCase();
  return text == 'true' || text == '1' || text == 'yes';
}

bool _ok(int statusCode) => statusCode >= 200 && statusCode < 300;

String _cleanError(Object error) =>
    error.toString().replaceFirst('Exception: ', '');

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
