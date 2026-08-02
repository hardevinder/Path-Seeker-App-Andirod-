import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/role_manager.dart';
import '../models/assessment_models.dart';
import '../services/assessment_api.dart';
import 'assessment_attempt_screen.dart';
import 'assessment_offline_submission_screen.dart';
import 'assessment_submissions_screen.dart';
import 'teacher_assessment_builder_screen.dart';

class AssessmentsScreen extends StatefulWidget {
  final int? onlineClassId;
  final String? assessmentType;
  const AssessmentsScreen({
    super.key,
    this.onlineClassId,
    this.assessmentType,
  });

  @override
  State<AssessmentsScreen> createState() => _AssessmentsScreenState();
}

class _AssessmentsScreenState extends State<AssessmentsScreen> {
  List<Assessment> _rows = [];
  bool _loading = true;
  bool _canManage = false;
  bool _isStudent = false;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadRoleAndData();
  }

  Future<void> _loadRoleAndData() async {
    final prefs = await SharedPreferences.getInstance();
    final roles = <String>{};
    for (final key in ['activeRole', 'selectedRole', 'role', 'userRole']) {
      final value = AppRoles.normalize(prefs.getString(key));
      if (value.isNotEmpty) roles.add(value);
    }
    final raw = prefs.getString('roles');
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          roles.addAll(decoded.map((e) => AppRoles.normalize(e.toString())));
        }
      } catch (_) {
        roles.addAll(raw
            .split(',')
            .map(AppRoles.normalize)
            .where((e) => e.isNotEmpty));
      }
    }
    _isStudent = roles.contains('student');
    _canManage = roles.any({
      'teacher',
      'admin',
      'superadmin',
      'super_admin',
      'academic_coordinator',
      'coordinator',
      'principal',
    }.contains);
    await _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      _rows = await AssessmentApi.list(
        onlineClassId: widget.onlineClassId,
        assessmentType: widget.assessmentType,
      );
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  List<Assessment> get _filtered => _filter == 'all'
      ? _rows
      : _rows.where((row) => row.mode == _filter).toList();

  Future<void> _createOrEdit({Assessment? assessment}) async {
    Assessment? full = assessment;
    if (assessment != null && assessment.questions.isEmpty) {
      try {
        full = await AssessmentApi.detail(assessment.id);
      } catch (e) {
        _snack(e.toString());
        return;
      }
    }
    if (!mounted) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TeacherAssessmentBuilderScreen(
          existing: full,
          onlineClassId: widget.onlineClassId,
          initialAssessmentType: widget.assessmentType,
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _action(Assessment row, String action) async {
    try {
      await AssessmentApi.action(row.id, action);
      _snack(action == 'results/publish'
          ? 'Results published.'
          : action == 'publish'
              ? 'Assessment published.'
              : 'Assessment closed.');
      await _load();
    } catch (e) {
      _snack(e.toString());
    }
  }

  Future<void> _cancel(Assessment row) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Cancel assessment?'),
            content: Text('Cancel “${row.title}”?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('No')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Cancel Assessment')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await AssessmentApi.cancel(row.id);
      _snack('Assessment cancelled.');
      await _load();
    } catch (e) {
      _snack(e.toString());
    }
  }

  Future<void> _attempt(Assessment row) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => AssessmentAttemptScreen(assessment: row)),
    );
    if (changed == true) _load();
  }

  Future<void> _submitOffline(Assessment row) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => AssessmentOfflineSubmissionScreen(assessment: row)),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.assessmentType == 'assignment'
            ? 'Assignments'
            : widget.onlineClassId == null
                ? 'Tests & Assessments'
                : 'Class Tests'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('All')),
                      ButtonSegment(
                          value: 'online',
                          label: Text('Online'),
                          icon: Icon(Icons.laptop)),
                      ButtonSegment(
                          value: 'offline',
                          label: Text('Written'),
                          icon: Icon(Icons.description_outlined)),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (value) =>
                        setState(() => _filter = value.first),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? _EmptyAssessmentState(
                        assignmentOnly: widget.assessmentType == 'assignment',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 100),
                          itemCount: _filtered.length,
                          itemBuilder: (context, index) =>
                              _assessmentCard(_filtered[index]),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: () => _createOrEdit(),
              icon: const Icon(Icons.add),
              label: Text(widget.assessmentType == 'assignment'
                  ? 'Create Assignment'
                  : 'Create Test'),
            )
          : null,
    );
  }

  Widget _assessmentCard(Assessment row) {
    final enrollment = row.enrollment;
    final resultVisible = row.resultVisible;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _pill(row.mode == 'online' ? 'ONLINE' : 'WRITTEN',
                    row.mode == 'online' ? Colors.indigo : Colors.orange),
                const SizedBox(width: 7),
                _pill(row.assessmentType.toUpperCase(), Colors.deepPurple),
                const SizedBox(width: 7),
                _pill(row.status.replaceAll('_', ' ').toUpperCase(),
                    _statusColor(row.status)),
                const Spacer(),
                Text('${row.totalMarks.g} marks',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            Text(row.title,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 3),
            Text(
              '${row.className}${row.sectionName.isNotEmpty ? ' – ${row.sectionName}' : ''} · ${row.subjectName}',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 7,
              children: [
                if (row.startsAt != null)
                  _meta(Icons.event_available,
                      'Opens ${DateFormat('dd MMM, hh:mm a').format(row.startsAt!)}'),
                if (row.endsAt != null)
                  _meta(Icons.timer_off_outlined,
                      'Due ${DateFormat('dd MMM, hh:mm a').format(row.endsAt!)}'),
                if (row.durationMinutes != null)
                  _meta(Icons.timer_outlined, '${row.durationMinutes} min'),
                _meta(Icons.person_outline, row.teacherName),
              ],
            ),
            if (!_canManage && enrollment != null) ...[
              const Divider(height: 26),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: resultVisible
                      ? const Color(0xFFE7F8EF)
                      : const Color(0xFFF2F4F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: resultVisible
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Result: ${enrollment.obtainedMarks ?? 0}/${row.totalMarks.g} · Grade ${enrollment.grade ?? '—'}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF087443)),
                          ),
                          if ((enrollment.feedback ?? '').isNotEmpty)
                            Text(enrollment.feedback!),
                        ],
                      )
                    : Text(
                        'Status: ${enrollment.status.replaceAll('_', ' ')}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              if (resultVisible &&
                  enrollment.latestAttempt?.files.any(
                        (file) => file.kind == 'corrected_submission',
                      ) ==
                      true) ...[
                const SizedBox(height: 8),
                ...enrollment.latestAttempt!.files
                    .where((file) => file.kind == 'corrected_submission')
                    .map((file) => OutlinedButton.icon(
                          onPressed: () => AssessmentApi.downloadAndOpen(
                            '/api/assessments/${row.id}/files/${file.id}',
                            file.name,
                          ),
                          icon: const Icon(Icons.rate_review_outlined),
                          label: const Text('Teacher Feedback File'),
                        )),
              ],
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => AssessmentApi.downloadAndOpen(
                      '/api/assessments/${row.id}/pdf', '${row.title}.pdf'),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Question Paper'),
                ),
                ...row.files
                    .where((file) => const [
                          'question_paper',
                          'supporting_material',
                        ].contains(file.kind))
                    .map((file) => OutlinedButton.icon(
                          onPressed: () => AssessmentApi.downloadAndOpen(
                              '/api/assessments/${row.id}/files/${file.id}',
                              file.name),
                          icon: const Icon(Icons.download),
                          label: Text(file.kind == 'question_paper'
                              ? 'Attached Paper'
                              : file.name),
                        )),
                if (_isStudent && row.canAttempt && row.mode == 'online')
                  FilledButton.icon(
                    onPressed: () => _attempt(row),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(row.assessmentType == 'assignment'
                        ? 'Open Assignment'
                        : 'Attempt Test'),
                  ),
                if (_isStudent && row.canAttempt && row.mode == 'offline')
                  FilledButton.icon(
                    onPressed: () => _submitOffline(row),
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: Text(row.assessmentType == 'assignment'
                        ? 'Scan & Upload Work'
                        : 'Scan & Submit'),
                  ),
                if (row.canManage &&
                    const ['draft', 'scheduled'].contains(row.status)) ...[
                  OutlinedButton.icon(
                    onPressed: () => _createOrEdit(assessment: row),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _action(row, 'publish'),
                    icon: const Icon(Icons.publish),
                    label: const Text('Publish'),
                  ),
                ],
                if (row.canManage && row.status == 'published')
                  OutlinedButton.icon(
                    onPressed: () => _action(row, 'close'),
                    icon: const Icon(Icons.lock_clock_outlined),
                    label: const Text('Close'),
                  ),
                if (row.canManage &&
                    !const ['draft', 'scheduled', 'cancelled']
                        .contains(row.status))
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AssessmentSubmissionsScreen(assessment: row),
                      ),
                    ).then((_) => _load()),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Submissions'),
                  ),
                if (row.canManage &&
                    !const ['cancelled', 'result_published']
                        .contains(row.status))
                  TextButton.icon(
                    onPressed: () => _cancel(row),
                    icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                    label: const Text('Cancel',
                        style: TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
            color: color.withOpacity(.12),
            borderRadius: BorderRadius.circular(30)),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w800)),
      );

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: Colors.indigo),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12.5)),
        ],
      );

  Color _statusColor(String status) {
    switch (status) {
      case 'published':
      case 'result_published':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'scheduled':
        return Colors.amber.shade800;
      case 'closed':
      case 'evaluated':
        return Colors.blue;
      default:
        return Colors.deepPurple;
    }
  }
}

class _EmptyAssessmentState extends StatelessWidget {
  final bool assignmentOnly;
  const _EmptyAssessmentState({this.assignmentOnly = false});

  @override
  Widget build(BuildContext context) => ListView(
        children: [
          const SizedBox(height: 100),
          const Icon(Icons.assignment_turned_in_outlined,
              size: 74, color: Colors.black26),
          const SizedBox(height: 16),
          Text(assignmentOnly
              ? 'No assignments available'
              : 'No assessments available',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(assignmentOnly
              ? 'Published assignments will appear here.'
              : 'Published tests and written papers will appear here.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54)),
        ],
      );
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
