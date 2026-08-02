import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/online_class_models.dart';
import '../services/online_class_api.dart';

class OnlineClassAttendanceScreen extends StatefulWidget {
  final OnlineClass onlineClass;
  final bool canManage;

  const OnlineClassAttendanceScreen({
    super.key,
    required this.onlineClass,
    required this.canManage,
  });

  @override
  State<OnlineClassAttendanceScreen> createState() =>
      _OnlineClassAttendanceScreenState();
}

class _OnlineClassAttendanceScreenState
    extends State<OnlineClassAttendanceScreen> {
  bool _loading = true;
  String? _error;
  String? _busyKey;
  OnlineClassAttendanceReport? _report;
  final Map<int, int?> _selectedStudents = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _loading = true);
    try {
      final report = await OnlineClassApi.attendance(widget.onlineClass.id);
      if (!mounted) return;
      setState(() {
        _report = report;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        ),
      );
  }

  Future<void> _recalculate() async {
    setState(() => _busyKey = 'recalculate');
    try {
      final report =
          await OnlineClassApi.recalculateAttendance(widget.onlineClass.id);
      if (!mounted) return;
      setState(() => _report = report);
      _message('Attendance recalculated.');
    } catch (error) {
      _message(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _updateStatus(
    OnlineClassAttendanceRow row,
    String value,
  ) async {
    final key = 'status-${row.student.id}';
    setState(() => _busyKey = key);
    try {
      await OnlineClassApi.updateAttendanceStatus(
        onlineClassId: widget.onlineClass.id,
        studentId: row.student.id,
        status: value == 'automatic' ? null : value,
        resetAutomatic: value == 'automatic',
      );
      _message(value == 'automatic'
          ? 'Automatic attendance restored.'
          : 'Attendance updated.');
      await _load(showLoader: false);
    } catch (error) {
      _message(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _matchSession(OnlineClassAttendanceSession session) async {
    final studentId = _selectedStudents[session.id];
    if (studentId == null || studentId <= 0) {
      _message('Select the correct student first.', error: true);
      return;
    }
    final key = 'match-${session.id}';
    setState(() => _busyKey = key);
    try {
      await OnlineClassApi.matchAttendanceSession(
        onlineClassId: widget.onlineClass.id,
        sessionId: session.id,
        studentId: studentId,
      );
      _message('Zoom participant matched with the student.');
      await _load(showLoader: false);
    } catch (error) {
      _message(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  String _duration(int seconds) {
    final total = seconds < 0 ? 0 : seconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final secs = total % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m ${secs.toString().padLeft(2, '0')}s';
  }

  String _date(DateTime? value) =>
      value == null ? '—' : DateFormat('d MMM, h:mm a').format(value);

  Color _statusColor(String value) {
    switch (value) {
      case 'present':
        return Colors.green;
      case 'partial':
        return Colors.orange;
      case 'absent':
        return Colors.red;
      case 'excused':
        return Colors.blue;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.canManage ? 'Class Attendance' : 'My Attendance'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _load(showLoader: false),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(showLoader: false),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  _classHeader(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _errorCard(_error!),
                  ],
                  if (report != null) ...[
                    const SizedBox(height: 16),
                    if (widget.canManage) _summary(report.summary),
                    if (widget.canManage) const SizedBox(height: 16),
                    _rulesCard(report.rules),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.canManage
                                ? 'Student attendance'
                                : 'Your attendance',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (widget.canManage)
                          OutlinedButton.icon(
                            onPressed:
                                _busyKey == 'recalculate' ? null : _recalculate,
                            icon: _busyKey == 'recalculate'
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.calculate_outlined),
                            label: const Text('Recalculate'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (report.rows.isEmpty)
                      _emptyCard('Attendance is not available yet.')
                    else
                      ...report.rows.map(_attendanceCard),
                    if (widget.canManage &&
                        report.unmatchedSessions.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Needs teacher review',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'These Zoom participants could not be matched confidently. Match each one with the correct student once.',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 10),
                      ...report.unmatchedSessions.map(_unmatchedCard),
                    ],
                  ],
                ],
              ),
      ),
    );
  }

  Widget _classHeader() => Card(
        elevation: 0,
        color: const Color(0xFFEFF6FF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFBFDBFE)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF2D8CFF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child:
                    const Icon(Icons.fact_check_outlined, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.onlineClass.title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.onlineClass.className}${widget.onlineClass.sectionName.isEmpty ? '' : ' – ${widget.onlineClass.sectionName}'} · ${widget.onlineClass.subjectName}',
                      style: const TextStyle(color: Color(0xFF475569)),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      DateFormat('EEE, d MMM · h:mm a')
                          .format(widget.onlineClass.startTime),
                      style: const TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _summary(OnlineClassAttendanceSummary summary) {
    final items = [
      ('Students', summary.total, Colors.blue),
      ('Present', summary.present, Colors.green),
      ('Partial', summary.partial, Colors.orange),
      ('Absent', summary.absent, Colors.red),
      ('Review', summary.needsReview, Colors.blueGrey),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: item.$3.withOpacity(.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: item.$3.withOpacity(.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.$1,
                            style: const TextStyle(color: Color(0xFF64748B))),
                        const SizedBox(height: 4),
                        Text('${item.$2}',
                            style: TextStyle(
                                fontSize: 24,
                                color: item.$3,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _rulesCard(OnlineClassAttendanceRules rules) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          'Automatic rule: Present at ${rules.presentPercent}% or more, Partial from ${rules.partialPercent}%, and Late after ${rules.lateMinutes} minutes. Unclear Basic-account identities stay under teacher review.',
          style: const TextStyle(color: Color(0xFF475569)),
        ),
      );

  Widget _attendanceCard(OnlineClassAttendanceRow row) {
    final color = _statusColor(row.status);
    final busy = _busyKey == 'status-${row.student.id}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(15),
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
                      Text(row.student.name,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      if (row.student.admissionNumber.isNotEmpty)
                        Text(
                          row.student.admissionNumber,
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                    ],
                  ),
                ),
                _badge(row.status, color),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                _info(Icons.login_rounded, 'Joined', _date(row.firstJoinedAt)),
                _info(Icons.timer_outlined, 'Duration',
                    _duration(row.totalDurationSeconds)),
                _info(Icons.percent_rounded, 'Covered',
                    '${row.attendancePercentage.toStringAsFixed(1)}%'),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (row.isLate) _badge('late', Colors.orange),
                _badge(
                  '${row.matchingStatus} ${row.matchConfidence}%',
                  row.matchingStatus == 'confirmed' ||
                          row.matchingStatus == 'manual'
                      ? Colors.green
                      : row.matchingStatus == 'likely'
                          ? Colors.orange
                          : Colors.blueGrey,
                ),
                if (row.manualOverride) _badge('manual', Colors.deepPurple),
              ],
            ),
            if (widget.canManage) ...[
              const Divider(height: 24),
              Row(
                children: [
                  const Expanded(
                    child: Text('Teacher override',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  if (busy)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    PopupMenuButton<String>(
                      tooltip: 'Change attendance',
                      onSelected: (value) => _updateStatus(row, value),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'automatic', child: Text('Automatic')),
                        PopupMenuItem(value: 'present', child: Text('Present')),
                        PopupMenuItem(value: 'partial', child: Text('Partial')),
                        PopupMenuItem(value: 'absent', child: Text('Absent')),
                        PopupMenuItem(value: 'excused', child: Text('Excused')),
                      ],
                      child: const Chip(
                        avatar: Icon(Icons.edit_outlined, size: 18),
                        label: Text('Change'),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _unmatchedCard(OnlineClassAttendanceSession session) {
    final report = _report;
    final students = report?.rows.map((row) => row.student).toList() ?? [];
    final busy = _busyKey == 'match-${session.id}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: const Color(0xFFFFFBEB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFFDE68A)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.participantName,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              session.zoomEmail?.trim().isNotEmpty == true
                  ? session.zoomEmail!
                  : 'Zoom email unavailable',
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 10),
            Text(
              'Joined ${_date(session.joinedAt)} · ${_duration(session.durationSeconds)}',
              style: const TextStyle(color: Color(0xFF475569)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _selectedStudents[session.id],
              decoration: const InputDecoration(
                labelText: 'Match with student',
                border: OutlineInputBorder(),
              ),
              isExpanded: true,
              items: students
                  .map(
                    (student) => DropdownMenuItem(
                      value: student.id,
                      child: Text(
                        student.admissionNumber.isEmpty
                            ? student.name
                            : '${student.name} (${student.admissionNumber})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (value) => setState(
                        () => _selectedStudents[session.id] = value,
                      ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: busy ? null : () => _matchSession(session),
              icon: busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.link_rounded),
              label: Text(busy ? 'Matching…' : 'Confirm match'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _info(IconData icon, String label, String value) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: const Color(0xFF64748B)),
          const SizedBox(width: 5),
          Text('$label: $value'),
        ],
      );

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w700, fontSize: 12),
        ),
      );

  Widget _errorCard(String text) => Card(
        color: const Color(0xFFFEF2F2),
        child: ListTile(
          leading: const Icon(Icons.error_outline, color: Colors.red),
          title: Text(text),
          trailing: TextButton(
              onPressed: () => _load(), child: const Text('Try again')),
        ),
      );

  Widget _emptyCard(String text) => Card(
        elevation: 0,
        color: const Color(0xFFF8FAFC),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          child: Center(
            child: Text(text, style: const TextStyle(color: Color(0xFF64748B))),
          ),
        ),
      );
}
