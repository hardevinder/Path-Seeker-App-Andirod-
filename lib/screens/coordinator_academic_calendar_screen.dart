import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../services/api_service.dart';

const List<String> _eventTypes = [
  'HOLIDAY',
  'VACATION',
  'EXAM',
  'PTM',
  'ACTIVITY',
  'EVENT',
  'TRAINING',
  'SYLLABUS_DEADLINE',
  'RESULT',
  'OTHER',
];

class CoordinatorAcademicCalendarScreen extends StatefulWidget {
  const CoordinatorAcademicCalendarScreen({super.key});

  @override
  State<CoordinatorAcademicCalendarScreen> createState() =>
      _CoordinatorAcademicCalendarScreenState();
}

class _CoordinatorAcademicCalendarScreenState
    extends State<CoordinatorAcademicCalendarScreen> {
  final DateFormat _displayDate = DateFormat('dd MMM yyyy');
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _sessionController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _schools = [];
  List<Map<String, dynamic>> _calendars = [];

  String _schoolId = '';
  String _status = '';

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _sessionController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _loadSchools(),
        _loadCalendars(),
      ]);
      if (!mounted) return;
      setState(() {
        _schools = results[0];
        _calendars = results[1];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshCalendars() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _loadCalendars();
      if (!mounted) return;
      setState(() => _calendars = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadSchools() async {
    final response = await ApiService.rawGet('/schools?limit=5000');
    if (!_ok(response.statusCode)) return <Map<String, dynamic>>[];
    return _extractRows(jsonDecode(response.body));
  }

  Future<List<Map<String, dynamic>>> _loadCalendars() async {
    final params = <String, String>{};
    if (_schoolId.isNotEmpty) params['school_id'] = _schoolId;
    if (_sessionController.text.trim().isNotEmpty) {
      params['academic_session'] = _sessionController.text.trim();
    }
    if (_status.isNotEmpty) params['status'] = _status;
    if (_searchController.text.trim().isNotEmpty) {
      params['q'] = _searchController.text.trim();
    }
    final query = Uri(queryParameters: params).query;
    final response = await ApiService.rawGet(
        '/academic-calendars${query.isEmpty ? '' : '?$query'}');
    if (!_ok(response.statusCode)) {
      throw Exception(
          _extractError(response.body, 'Failed to fetch calendars'));
    }
    return _extractRows(jsonDecode(response.body));
  }

  Future<void> _openCalendarEditor({Map<String, dynamic>? calendar}) async {
    final isPublished = _statusOf(calendar) == 'PUBLISHED';
    final schoolId = _safe(calendar?['school_id']).isEmpty
        ? ''
        : _safe(calendar?['school_id']);
    final session = TextEditingController(
      text: _safe(calendar?['academic_session']),
    );
    final title = TextEditingController(text: _safe(calendar?['title']));
    final totalWorkingDays = TextEditingController(
      text: calendar?['total_working_days'] == null
          ? ''
          : _safe(calendar?['total_working_days']),
    );
    final weeklyOff = TextEditingController(
      text: calendar?['weekly_off'] == null
          ? ''
          : const JsonEncoder.withIndent('  ').convert(calendar?['weekly_off']),
    );
    final remarks = TextEditingController(text: _safe(calendar?['remarks']));
    DateTime? startDate = _parseDate(calendar?['start_date']);
    DateTime? endDate = _parseDate(calendar?['end_date']);
    String selectedSchool = schoolId;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sheetHeader(
                    calendar == null
                        ? 'Create Academic Calendar'
                        : 'Edit Academic Calendar',
                    isPublished
                        ? 'Published calendars must be unpublished before editing.'
                        : 'Set the academic session, dates and working day details.',
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: selectedSchool,
                    decoration: const InputDecoration(
                      labelText: 'School',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Optional - Select School'),
                      ),
                      ..._schools.map(
                        (school) => DropdownMenuItem(
                          value: _safe(school['id']),
                          child: Text(_schoolName(school)),
                        ),
                      ),
                    ],
                    onChanged: isPublished
                        ? null
                        : (value) =>
                            setSheetState(() => selectedSchool = value ?? ''),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: session,
                    enabled: !isPublished,
                    decoration: const InputDecoration(
                      labelText: 'Academic Session *',
                      hintText: 'e.g. 2026-27',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: title,
                    enabled: !isPublished,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      hintText: 'Academic Calendar 2026-27',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _dateButton(
                          label: 'Start Date *',
                          value: startDate,
                          enabled: !isPublished,
                          onPick: (date) =>
                              setSheetState(() => startDate = date),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dateButton(
                          label: 'End Date *',
                          value: endDate,
                          enabled: !isPublished,
                          onPick: (date) => setSheetState(() => endDate = date),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: totalWorkingDays,
                    enabled: !isPublished,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Total Working Days',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: weeklyOff,
                    enabled: !isPublished,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Weekly Off JSON',
                      hintText:
                          '{"sun": true, "second_sat": true, "fourth_sat": false}',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: remarks,
                    enabled: !isPublished,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Remarks',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: isPublished || _saving
                          ? null
                          : () async {
                              final ok = await _saveCalendar(
                                calendar: calendar,
                                schoolId: selectedSchool,
                                session: session.text,
                                title: title.text,
                                startDate: startDate,
                                endDate: endDate,
                                weeklyOffJson: weeklyOff.text,
                                totalWorkingDays: totalWorkingDays.text,
                                remarks: remarks.text,
                              );
                              if (ok && context.mounted) {
                                Navigator.pop(context, true);
                              }
                            },
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(calendar == null ? 'Create' : 'Save Changes'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    for (final controller in [
      session,
      title,
      totalWorkingDays,
      weeklyOff,
      remarks,
    ]) {
      controller.dispose();
    }
    if (saved == true) await _refreshCalendars();
  }

  Future<bool> _saveCalendar({
    required Map<String, dynamic>? calendar,
    required String schoolId,
    required String session,
    required String title,
    required DateTime? startDate,
    required DateTime? endDate,
    required String weeklyOffJson,
    required String totalWorkingDays,
    required String remarks,
  }) async {
    final cleanSession = session.trim();
    if (cleanSession.isEmpty) {
      _showSnack('Academic session is required.');
      return false;
    }
    if (startDate == null || endDate == null) {
      _showSnack('Start date and end date are required.');
      return false;
    }
    if (startDate.isAfter(endDate)) {
      _showSnack('Start date cannot be after end date.');
      return false;
    }

    dynamic weeklyOff;
    if (weeklyOffJson.trim().isNotEmpty) {
      try {
        weeklyOff = jsonDecode(weeklyOffJson);
      } catch (_) {
        _showSnack('Weekly off JSON is invalid.');
        return false;
      }
    }

    setState(() => _saving = true);
    try {
      final payload = {
        'school_id': schoolId.isEmpty ? null : int.tryParse(schoolId),
        'academic_session': cleanSession,
        'title': title.trim().isEmpty ? null : title.trim(),
        'start_date': _inputDate(startDate),
        'end_date': _inputDate(endDate),
        'weekly_off': weeklyOff,
        'total_working_days': totalWorkingDays.trim().isEmpty
            ? null
            : int.tryParse(totalWorkingDays.trim()),
        'remarks': remarks.trim().isEmpty ? null : remarks.trim(),
      };
      final response = calendar == null
          ? await ApiService.rawPost('/academic-calendars', payload)
          : await ApiService.rawPut(
              '/academic-calendars/${calendar['id']}',
              payload,
            );
      if (!_ok(response.statusCode)) {
        _showSnack(_extractError(response.body, 'Failed to save calendar.'));
        return false;
      }
      _showSnack(calendar == null
          ? 'Academic calendar created.'
          : 'Academic calendar updated.');
      return true;
    } catch (e) {
      _showSnack(_cleanError(e));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _calendarAction(
    Map<String, dynamic> calendar, {
    required String title,
    required String message,
    required String endpoint,
    required String method,
    required String success,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final response = method == 'delete'
          ? await ApiService.rawDelete(endpoint)
          : await ApiService.rawPost(endpoint, const {});
      if (!_ok(response.statusCode)) {
        _showSnack(_extractError(response.body, 'Action failed.'));
        return;
      }
      _showSnack(success);
      await _refreshCalendars();
    } catch (e) {
      _showSnack(_cleanError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openCalendarPdf(Map<String, dynamic> calendar) async {
    setState(() => _saving = true);
    try {
      final response = await ApiService.rawGet(
        '/academic-calendars/${calendar['id']}/pdf',
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
      final fileName =
          'AcademicCalendar_${_safe(calendar['academic_session'], _safe(calendar['id']))}.pdf'
              .replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      await OpenFilex.open(file.path);
    } catch (e) {
      _showSnack(_cleanError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openEvents(Map<String, dynamic> calendar) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CalendarEventsSheet(
        calendar: calendar,
        displayDate: _displayDate,
        onMessage: _showSnack,
        onCalendarChanged: _refreshCalendars,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Academic Calendar'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refreshCalendars,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : () => _openCalendarEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Create'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _state(
                  Icons.warning_rounded,
                  'Could not load academic calendars',
                  _error!,
                  actionLabel: 'Retry',
                  onAction: _loadInitial,
                )
              : RefreshIndicator(
                  onRefresh: _refreshCalendars,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
                    children: [
                      _hero(),
                      const SizedBox(height: 12),
                      _filters(),
                      const SizedBox(height: 12),
                      if (_calendars.isEmpty)
                        _state(
                          Icons.calendar_month_rounded,
                          'No calendars found',
                          'Create a calendar or change the filters.',
                        )
                      else
                        ..._calendars.map(_calendarCard),
                    ],
                  ),
                ),
    );
  }

  Widget _hero() {
    final published =
        _calendars.where((cal) => _statusOf(cal) == 'PUBLISHED').length;
    final drafts = _calendars.where((cal) => _statusOf(cal) == 'DRAFT').length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D4ED8), Color(0xFF0F766E)],
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
              Icon(Icons.calendar_month_rounded, color: Colors.white, size: 36),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Academic Calendar',
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
              _heroStat('Shown', '${_calendars.length}'),
              _heroStat('Published', '$published'),
              _heroStat('Draft', '$drafts'),
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
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _refreshCalendars(),
            decoration: const InputDecoration(
              labelText: 'Search title / session',
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _sessionController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _refreshCalendars(),
            decoration: const InputDecoration(
              labelText: 'Academic Session',
              hintText: '2026-27',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _schoolId,
            decoration: const InputDecoration(
              labelText: 'School',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('All Schools')),
              ..._schools.map(
                (school) => DropdownMenuItem(
                  value: _safe(school['id']),
                  child: Text(_schoolName(school)),
                ),
              ),
            ],
            onChanged: (value) => setState(() => _schoolId = value ?? ''),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _status,
            decoration: const InputDecoration(
              labelText: 'Status',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: '', child: Text('All Status')),
              DropdownMenuItem(value: 'DRAFT', child: Text('DRAFT')),
              DropdownMenuItem(value: 'PUBLISHED', child: Text('PUBLISHED')),
              DropdownMenuItem(value: 'ARCHIVED', child: Text('ARCHIVED')),
            ],
            onChanged: (value) => setState(() => _status = value ?? ''),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _refreshCalendars,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Apply Filters'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _calendarCard(Map<String, dynamic> calendar) {
    final status = _statusOf(calendar);
    final isPublished = status == 'PUBLISHED';
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
                        _safe(calendar['title'], 'Academic Calendar'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_safe(calendar['academic_session'], '-')} • ${_schoolNameById(calendar['school_id'])}',
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
                _infoChip(
                  Icons.date_range_rounded,
                  '${_pretty(calendar['start_date'])} - ${_pretty(calendar['end_date'])}',
                ),
                _infoChip(
                  Icons.work_history_rounded,
                  'Working: ${_safe(calendar['total_working_days'], '-')}',
                ),
              ],
            ),
            if (_safe(calendar['remarks']).isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _safe(calendar['remarks']),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade800),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _openCalendarPdf(calendar),
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                  label: const Text('PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _openEvents(calendar),
                  icon: const Icon(Icons.event_note_rounded, size: 18),
                  label: const Text('Events'),
                ),
                FilledButton.icon(
                  onPressed: isPublished || _saving
                      ? null
                      : () => _openCalendarEditor(calendar: calendar),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Edit'),
                ),
                OutlinedButton.icon(
                  onPressed: isPublished || _saving
                      ? null
                      : () => _calendarAction(
                            calendar,
                            title: 'Publish calendar?',
                            message:
                                'After publish, editing will be blocked until it is unpublished.',
                            endpoint:
                                '/academic-calendars/${calendar['id']}/publish',
                            method: 'post',
                            success: 'Calendar published.',
                          ),
                  icon: const Icon(Icons.publish_rounded, size: 18),
                  label: const Text('Publish'),
                ),
                OutlinedButton.icon(
                  onPressed: !isPublished || _saving
                      ? null
                      : () => _calendarAction(
                            calendar,
                            title: 'Unpublish calendar?',
                            message:
                                'This will move it back to draft so edits are allowed.',
                            endpoint:
                                '/academic-calendars/${calendar['id']}/unpublish',
                            method: 'post',
                            success: 'Calendar moved to draft.',
                          ),
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: const Text('Unpublish'),
                ),
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _calendarAction(
                            calendar,
                            title: 'Delete calendar?',
                            message:
                                'This will also delete all events inside this calendar.',
                            endpoint: '/academic-calendars/${calendar['id']}',
                            method: 'delete',
                            success: 'Calendar deleted.',
                          ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateButton({
    required String label,
    required DateTime? value,
    required bool enabled,
    required ValueChanged<DateTime> onPick,
  }) {
    return OutlinedButton.icon(
      onPressed: enabled
          ? () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? now,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
              );
              if (picked != null) onPick(picked);
            }
          : null,
      icon: const Icon(Icons.calendar_today_rounded, size: 18),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          value == null ? label : _displayDate.format(value),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _sheetHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
      ],
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

  Widget _statusChip(String status) {
    final color = status == 'PUBLISHED'
        ? const Color(0xFF16A34A)
        : status == 'ARCHIVED'
            ? const Color(0xFF64748B)
            : const Color(0xFF2563EB);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
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

  String _schoolNameById(dynamic id) {
    if (_safe(id).isEmpty) return '-';
    final match = _schools.where((school) => _safe(school['id']) == _safe(id));
    return match.isEmpty ? 'School #$id' : _schoolName(match.first);
  }

  String _schoolName(Map<String, dynamic> school) =>
      _safe(school['name'], 'School ${_safe(school['id'])}');

  String _pretty(dynamic value) {
    final date = _parseDate(value);
    return date == null ? '-' : _displayDate.format(date);
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

class _CalendarEventsSheet extends StatefulWidget {
  const _CalendarEventsSheet({
    required this.calendar,
    required this.displayDate,
    required this.onMessage,
    required this.onCalendarChanged,
  });

  final Map<String, dynamic> calendar;
  final DateFormat displayDate;
  final ValueChanged<String> onMessage;
  final Future<void> Function() onCalendarChanged;

  @override
  State<_CalendarEventsSheet> createState() => _CalendarEventsSheetState();
}

class _CalendarEventsSheetState extends State<_CalendarEventsSheet> {
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String _typeFilter = '';
  String? _error;
  List<Map<String, dynamic>> _events = [];

  bool get _isPublished => _statusOf(widget.calendar) == 'PUBLISHED';

  List<Map<String, dynamic>> get _filteredEvents {
    final query = _searchController.text.trim().toLowerCase();
    return _events.where((event) {
      if (_typeFilter.isNotEmpty && _safe(event['type']) != _typeFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      final haystack = [
        event['title'],
        event['description'],
        event['type'],
        event['exam_name'],
        event['class_scope'],
      ].map(_safe).join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiService.rawGet(
          '/academic-calendars/${widget.calendar['id']}/events');
      if (!_ok(response.statusCode)) {
        throw Exception(_extractError(response.body, 'Failed to fetch events'));
      }
      final rows = _extractRows(jsonDecode(response.body));
      if (!mounted) return;
      setState(() => _events = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEventEditor({Map<String, dynamic>? event}) async {
    final title = TextEditingController(text: _safe(event?['title']));
    final description =
        TextEditingController(text: _safe(event?['description']));
    final scope = TextEditingController(
      text: _safe(event?['class_scope'], 'ALL'),
    );
    final startTime = TextEditingController(text: _safe(event?['start_time']));
    final endTime = TextEditingController(text: _safe(event?['end_time']));
    final examName = TextEditingController(text: _safe(event?['exam_name']));
    final meta = TextEditingController(
      text: event?['meta'] == null
          ? ''
          : const JsonEncoder.withIndent('  ').convert(event?['meta']),
    );

    String type = _eventTypes.contains(_safe(event?['type']))
        ? _safe(event?['type'])
        : 'OTHER';
    bool isWorkingDay = event?['is_working_day'] == null
        ? true
        : _asBool(event?['is_working_day']);
    bool isPublicHoliday = _asBool(event?['is_public_holiday']);
    DateTime? startDate = _parseDate(event?['start_date']) ??
        _parseDate(widget.calendar['start_date']);
    DateTime? endDate = _parseDate(event?['end_date']) ??
        _parseDate(widget.calendar['start_date']);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event == null ? 'Add Event' : 'Edit Event',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      border: OutlineInputBorder(),
                    ),
                    items: _eventTypes
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setSheetState(() => type = value ?? 'OTHER'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: scope,
                    decoration: const InputDecoration(
                      labelText: 'Scope',
                      hintText: 'ALL / CLASS_1 / CLASS_1,CLASS_2',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: description,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _dateButton(
                          context,
                          label: 'Start Date *',
                          value: startDate,
                          displayDate: widget.displayDate,
                          onPick: (date) => setSheetState(() {
                            startDate = date;
                            endDate ??= date;
                          }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dateButton(
                          context,
                          label: 'End Date',
                          value: endDate,
                          displayDate: widget.displayDate,
                          onPick: (date) => setSheetState(() => endDate = date),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startTime,
                          decoration: const InputDecoration(
                            labelText: 'Start Time',
                            hintText: 'HH:mm',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: endTime,
                          decoration: const InputDecoration(
                            labelText: 'End Time',
                            hintText: 'HH:mm',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Working Day'),
                    value: isWorkingDay,
                    onChanged: (value) =>
                        setSheetState(() => isWorkingDay = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Public Holiday'),
                    value: isPublicHoliday,
                    onChanged: (value) =>
                        setSheetState(() => isPublicHoliday = value),
                  ),
                  TextField(
                    controller: examName,
                    decoration: const InputDecoration(
                      labelText: 'Exam Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: meta,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Meta JSON',
                      hintText: '{"venue":"Auditorium"}',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              final ok = await _saveEvent(
                                event: event,
                                type: type,
                                title: title.text,
                                description: description.text,
                                startDate: startDate,
                                endDate: endDate,
                                startTime: startTime.text,
                                endTime: endTime.text,
                                scope: scope.text,
                                isWorkingDay: isWorkingDay,
                                isPublicHoliday: isPublicHoliday,
                                examName: examName.text,
                                metaJson: meta.text,
                              );
                              if (ok && context.mounted) {
                                Navigator.pop(context, true);
                              }
                            },
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(event == null ? 'Add Event' : 'Save Event'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    for (final controller in [
      title,
      description,
      scope,
      startTime,
      endTime,
      examName,
      meta,
    ]) {
      controller.dispose();
    }
    if (saved == true) await _loadEvents();
  }

  Future<bool> _saveEvent({
    required Map<String, dynamic>? event,
    required String type,
    required String title,
    required String description,
    required DateTime? startDate,
    required DateTime? endDate,
    required String startTime,
    required String endTime,
    required String scope,
    required bool isWorkingDay,
    required bool isPublicHoliday,
    required String examName,
    required String metaJson,
  }) async {
    if (title.trim().isEmpty) {
      widget.onMessage('Event title is required.');
      return false;
    }
    if (startDate == null) {
      widget.onMessage('Start date is required.');
      return false;
    }
    final resolvedEndDate = endDate ?? startDate;
    if (startDate.isAfter(resolvedEndDate)) {
      widget.onMessage('Start date cannot be after end date.');
      return false;
    }

    dynamic meta;
    if (metaJson.trim().isNotEmpty) {
      try {
        meta = jsonDecode(metaJson);
      } catch (_) {
        widget.onMessage('Meta JSON is invalid.');
        return false;
      }
    }

    setState(() => _saving = true);
    try {
      final payload = {
        'type': type,
        'title': title.trim(),
        'description': description.trim().isEmpty ? null : description.trim(),
        'start_date': _inputDate(startDate),
        'end_date': _inputDate(resolvedEndDate),
        'start_time': startTime.trim().isEmpty ? null : startTime.trim(),
        'end_time': endTime.trim().isEmpty ? null : endTime.trim(),
        'class_scope': scope.trim().isEmpty ? 'ALL' : scope.trim(),
        'is_working_day': isWorkingDay,
        'is_public_holiday': isPublicHoliday,
        'exam_name': examName.trim().isEmpty ? null : examName.trim(),
        'meta': meta,
      };
      final response = event == null
          ? await ApiService.rawPost(
              '/academic-calendars/${widget.calendar['id']}/events',
              payload,
            )
          : await ApiService.rawPut(
              '/academic-calendars/events/${event['id']}',
              payload,
            );
      if (!_ok(response.statusCode)) {
        widget.onMessage(_extractError(response.body, 'Failed to save event.'));
        return false;
      }
      widget.onMessage(event == null ? 'Event added.' : 'Event updated.');
      return true;
    } catch (e) {
      widget.onMessage(_cleanError(e));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteEvent(Map<String, dynamic> event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete event?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final response = await ApiService.rawDelete(
          '/academic-calendars/events/${event['id']}');
      if (!_ok(response.statusCode)) {
        widget
            .onMessage(_extractError(response.body, 'Failed to delete event.'));
        return;
      }
      widget.onMessage('Event deleted.');
      await _loadEvents();
    } catch (e) {
      widget.onMessage(_cleanError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        final rows = _filteredEvents;
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Calendar Events',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${_safe(widget.calendar['title'], 'Academic Calendar')} • ${_safe(widget.calendar['academic_session'], '-')}',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ],
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
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        children: [
                          TextField(
                            controller: _searchController,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Search events',
                              prefixIcon: Icon(Icons.search_rounded),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            value: _typeFilter,
                            decoration: const InputDecoration(
                              labelText: 'Type',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('All Types'),
                              ),
                              ..._eventTypes.map(
                                (type) => DropdownMenuItem(
                                  value: type,
                                  child: Text(type),
                                ),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => _typeFilter = value ?? ''),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _isPublished || _saving
                                      ? null
                                      : () => _openEventEditor(),
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('Add Event'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              IconButton.filledTonal(
                                tooltip: 'Refresh',
                                onPressed: _loadEvents,
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                            ],
                          ),
                          if (_isPublished) ...[
                            const SizedBox(height: 10),
                            _notice(
                              'This calendar is published. Unpublish it to add, edit or delete events.',
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            _notice(_error!),
                          ] else if (rows.isEmpty) ...[
                            const SizedBox(height: 36),
                            _emptyEvents(),
                          ] else ...[
                            const SizedBox(height: 12),
                            ...rows.map(_eventCard),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _eventCard(Map<String, dynamic> event) {
    final working = _asBool(event['is_working_day']);
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
                  child: Text(
                    _safe(event['title'], 'Untitled Event'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _typeChip(_safe(event['type'], 'OTHER')),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _eventDateLabel(event),
              style: TextStyle(color: Colors.grey.shade700),
            ),
            if (_safe(event['exam_name']).isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Exam: ${_safe(event['exam_name'])}'),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _miniChip(Icons.group_work_rounded,
                    _safe(event['class_scope'], 'ALL')),
                _miniChip(
                  working ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  working ? 'Working day' : 'Non-working',
                ),
                if (_asBool(event['is_public_holiday']))
                  _miniChip(Icons.flag_rounded, 'Public holiday'),
              ],
            ),
            if (_safe(event['description']).isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _safe(event['description']),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isPublished || _saving
                        ? null
                        : () => _openEventEditor(event: event),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isPublished || _saving
                        ? null
                        : () => _deleteEvent(event),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyEvents() {
    return Column(
      children: [
        Icon(Icons.event_note_rounded, size: 42, color: Colors.grey.shade500),
        const SizedBox(height: 10),
        const Text(
          'No events found',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          'Add holidays, exams, PTMs and other calendar events.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700),
        ),
      ],
    );
  }

  Widget _notice(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFF1E3A8A))),
    );
  }

  Widget _typeChip(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB).withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        type,
        style: const TextStyle(
          color: Color(0xFF1D4ED8),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _miniChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  String _eventDateLabel(Map<String, dynamic> event) {
    final start = _parseDate(event['start_date']);
    final end = _parseDate(event['end_date']);
    final startText = start == null ? '-' : widget.displayDate.format(start);
    final endText = end == null ? '' : widget.displayDate.format(end);
    final range = endText.isNotEmpty && endText != startText
        ? '$startText - $endText'
        : startText;
    final time = [
      _safe(event['start_time']),
      _safe(event['end_time']),
    ].where((value) => value.isNotEmpty).join(' - ');
    return time.isEmpty ? range : '$range • $time';
  }
}

Widget _dateButton(
  BuildContext context, {
  required String label,
  required DateTime? value,
  required DateFormat displayDate,
  required ValueChanged<DateTime> onPick,
}) {
  return OutlinedButton.icon(
    onPressed: () async {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: value ?? now,
        firstDate: DateTime(2020),
        lastDate: DateTime(2035),
      );
      if (picked != null) onPick(picked);
    },
    icon: const Icon(Icons.calendar_today_rounded, size: 18),
    label: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        value == null ? label : displayDate.format(value),
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}

List<Map<String, dynamic>> _extractRows(dynamic decoded) {
  if (decoded is List) {
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
  if (decoded is Map) {
    for (final key in ['rows', 'data', 'items', 'results', 'schools']) {
      final value = decoded[key];
      if (value is List) return _extractRows(value);
    }
  }
  return <Map<String, dynamic>>[];
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

bool _ok(int statusCode) => statusCode >= 200 && statusCode < 300;

String _cleanError(Object error) =>
    error.toString().replaceFirst('Exception: ', '');

String _safe(dynamic value, [String fallback = '']) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

String _statusOf(Map<String, dynamic>? calendar) =>
    _safe(calendar?['status'], 'DRAFT').toUpperCase();

DateTime? _parseDate(dynamic value) {
  final text = _safe(value);
  if (text.isEmpty) return null;
  final normalized = text.length >= 10 ? text.substring(0, 10) : text;
  return DateTime.tryParse(normalized);
}

String _inputDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

bool _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = _safe(value).toLowerCase();
  return text == 'true' || text == '1' || text == 'yes';
}
