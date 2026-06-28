import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class TeacherLessonPlanEvaluationsScreen extends StatefulWidget {
  final int lessonPlanId;
  final Map<String, dynamic>? lessonPlan;

  const TeacherLessonPlanEvaluationsScreen({
    super.key,
    required this.lessonPlanId,
    this.lessonPlan,
  });

  @override
  State<TeacherLessonPlanEvaluationsScreen> createState() =>
      _TeacherLessonPlanEvaluationsScreenState();
}

class _TeacherLessonPlanEvaluationsScreenState
    extends State<TeacherLessonPlanEvaluationsScreen> {
  static const Color _primary = Color(0xFF4F46E5);
  static const Color _green = Color(0xFF16A34A);
  static const Color _orange = Color(0xFFD97706);
  static const Color _muted = Color(0xFF64748B);
  static const Color _bg = Color(0xFFF6F8FF);

  bool _loading = true;
  bool _activeLoading = false;
  bool _studentsLoading = false;
  bool _savingResults = false;
  bool _aiRemarksBusy = false;

  Map<String, dynamic>? _lessonPlan;
  List<Map<String, dynamic>> _evaluations = [];
  Map<String, dynamic>? _activeEval;
  List<Map<String, dynamic>> _students = [];
  Map<String, String> _marks = {};
  Map<String, String> _remarks = {};
  Map<String, dynamic>? _analytics;

  String _search = '';
  String _sectionFilter = '';
  String _remarksLanguage = 'en';

  int? get _activeEvalId => _toInt(_activeEval?['id']);

  @override
  void initState() {
    super.initState();
    _lessonPlan = widget.lessonPlan;
    _loadAll();
  }

  Future<void> _loadAll() async {
    if (mounted) setState(() => _loading = true);
    await Future.wait([
      _loadLessonPlan(),
      _loadEvaluations(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadLessonPlan() async {
    if (_lessonPlan != null && _lessonPlan!.isNotEmpty) return;

    try {
      final response =
          await ApiService.rawGet('/lesson-plans/${widget.lessonPlanId}');
      if (!_ok(response.statusCode)) {
        throw Exception(_error(response.body, 'Failed to load lesson plan'));
      }
      final decoded = _decode(response.body);
      _lessonPlan = _asMap(decoded['lessonPlan'] ?? decoded['data'] ?? decoded);
    } catch (e) {
      _snack(_cleanError(e), error: true);
    }
  }

  Future<void> _loadEvaluations({int? selectId}) async {
    try {
      final response = await ApiService.rawGet(
        '/lesson-plans/${widget.lessonPlanId}/evaluations?includeDraft=1',
      );
      if (!_ok(response.statusCode)) {
        throw Exception(_error(response.body, 'Failed to fetch evaluations'));
      }

      final list = _normalizeList(_decode(response.body));
      if (!mounted) return;
      setState(() => _evaluations = list);

      final targetId = selectId ??
          _activeEvalId ??
          (list.isNotEmpty ? _toInt(list.first['id']) : null);
      if (targetId != null) {
        await _selectEvaluation(targetId);
      } else if (mounted) {
        setState(() => _activeEval = null);
      }
    } catch (e) {
      _snack(_cleanError(e), error: true);
      if (mounted) setState(() => _evaluations = []);
    }
  }

  Future<void> _selectEvaluation(int id) async {
    setState(() {
      _activeLoading = true;
      _analytics = null;
      _students = [];
      _marks = {};
      _remarks = {};
    });

    try {
      final response = await ApiService.rawGet('/lesson-plan-evaluations/$id');
      if (!_ok(response.statusCode)) {
        throw Exception(_error(response.body, 'Failed to load evaluation'));
      }

      final eval = _normalizeEvaluation(_decode(response.body));
      if (!mounted) return;
      setState(() => _activeEval = eval);
      await Future.wait([
        _loadStudents(),
        _loadResults(id),
      ]);
    } catch (e) {
      _snack(_cleanError(e), error: true);
    } finally {
      if (mounted) setState(() => _activeLoading = false);
    }
  }

  Future<void> _loadStudents() async {
    final classId = _toInt(_lessonPlan?['classId']);
    if (classId == null) return;

    setState(() => _studentsLoading = true);
    try {
      final sectionIds = _planSectionIds();
      final params = <String, String>{
        'classId': '$classId',
        'includeDisabled': '0',
        if (sectionIds.isNotEmpty) 'sectionIds': sectionIds.join(','),
      };
      final query = Uri(queryParameters: params).query;
      final response = await ApiService.rawGet(
        '/lesson-plans/${widget.lessonPlanId}/students?$query',
      );

      if (!_ok(response.statusCode)) {
        throw Exception(_error(response.body, 'Failed to load students'));
      }

      final rows = _normalizeStudents(_decode(response.body))
          .where((s) => _pickStudentRef(s).isNotEmpty)
          .toList();
      rows.sort((a, b) {
        final sa = _toInt(a['section_id'] ?? a['sectionId']) ?? 0;
        final sb = _toInt(b['section_id'] ?? b['sectionId']) ?? 0;
        if (sa != sb) return sa.compareTo(sb);
        final ra = _toInt(a['roll_number'] ?? a['rollNumber']) ?? 0;
        final rb = _toInt(b['roll_number'] ?? b['rollNumber']) ?? 0;
        if (ra != rb) return ra.compareTo(rb);
        return _pickStudentName(a).compareTo(_pickStudentName(b));
      });

      if (mounted) setState(() => _students = rows);
    } catch (e) {
      _snack(_cleanError(e), error: true);
      if (mounted) setState(() => _students = []);
    } finally {
      if (mounted) setState(() => _studentsLoading = false);
    }
  }

  Future<void> _loadResults(int evalId) async {
    try {
      dynamic decoded;
      var response =
          await ApiService.rawGet('/lesson-plan-evaluations/$evalId/results');
      if (!_ok(response.statusCode)) {
        response =
            await ApiService.rawGet('/lesson-plan-evaluations/$evalId/result');
      }
      if (!_ok(response.statusCode)) return;
      decoded = _decode(response.body);

      final list = _normalizeList(decoded);
      final marks = <String, String>{};
      final remarks = <String, String>{};
      for (final row in list) {
        final student = _asMap(row['Student'] ?? row['student']);
        final ref = _safeStr(
          row['studentRef'] ??
              student['admission_number'] ??
              student['admission_no'] ??
              student['admissionNumber'],
        );
        if (ref.isEmpty) continue;

        final m = _toNum(row['marksObtained'] ?? row['marks_obtained']);
        if (m != null) marks[ref] = _formatNum(m);

        final remark = _safeStr(row['remark']);
        if (remark.isNotEmpty) remarks[ref] = remark;
      }

      if (mounted) {
        setState(() {
          _marks = marks;
          _remarks = remarks;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadAnalytics() async {
    final id = _activeEvalId;
    if (id == null) return;

    try {
      final response =
          await ApiService.rawGet('/lesson-plan-evaluations/$id/analytics');
      if (!_ok(response.statusCode)) {
        throw Exception(_error(response.body, 'Failed to load analytics'));
      }
      if (mounted) setState(() => _analytics = _decode(response.body));
    } catch (e) {
      _snack(_cleanError(e), error: true);
    }
  }

  Future<void> _publishActive() async {
    final id = _activeEvalId;
    if (id == null) return;

    try {
      final response =
          await ApiService.rawPost('/lesson-plan-evaluations/$id/publish', {});
      if (!_ok(response.statusCode)) {
        throw Exception(_error(response.body, 'Publish failed'));
      }
      _snack('Evaluation published.');
      await _loadEvaluations(selectId: id);
    } catch (e) {
      _snack(_cleanError(e), error: true);
    }
  }

  Future<void> _deleteActive() async {
    final id = _activeEvalId;
    if (id == null) return;

    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete evaluation?'),
        content:
            const Text('This will delete the evaluation and its questions.'),
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
    if (yes != true) return;

    try {
      final response =
          await ApiService.rawDelete('/lesson-plan-evaluations/$id');
      if (!_ok(response.statusCode)) {
        throw Exception(_error(response.body, 'Delete failed'));
      }
      _snack('Evaluation deleted.');
      if (mounted) setState(() => _activeEval = null);
      await _loadEvaluations();
    } catch (e) {
      _snack(_cleanError(e), error: true);
    }
  }

  Future<void> _saveResults() async {
    final id = _activeEvalId;
    if (id == null) {
      _snack('Please select an evaluation first.', error: true);
      return;
    }

    final total = _toNum(_activeEval?['totalMarks']);
    final results = <Map<String, dynamic>>[];
    for (final student in _students) {
      final ref = _pickStudentRef(student);
      if (ref.isEmpty) continue;
      final value = _marks[ref];
      if (value == null || value.trim().isEmpty) continue;
      var marks = num.tryParse(value.trim());
      if (marks == null) continue;
      if (total != null) {
        if (marks < 0) marks = 0;
        if (marks > total) marks = total;
      }
      results.add({
        'studentId': _toInt(student['id']),
        'studentRef': ref,
        'marksObtained': marks,
        'remark': _safeStr(_remarks[ref]).isEmpty ? null : _remarks[ref],
      });
    }

    if (results.isEmpty) {
      _snack('Enter at least one valid mark.', error: true);
      return;
    }

    setState(() => _savingResults = true);
    try {
      final response = await ApiService.rawPost(
        '/lesson-plan-evaluations/$id/results',
        {'results': results},
      );
      if (!_ok(response.statusCode)) {
        throw Exception(_error(response.body, 'Failed to save results'));
      }
      _snack('Saved ${results.length} result(s).');
      await _loadAnalytics();
    } catch (e) {
      _snack(_cleanError(e), error: true);
    } finally {
      if (mounted) setState(() => _savingResults = false);
    }
  }

  Future<void> _generateAiRemarks() async {
    final id = _activeEvalId;
    if (id == null || _activeEval == null) return;

    final totalMarks = _toNum(_activeEval?['totalMarks']) ?? 0;
    final students = <Map<String, dynamic>>[];
    for (final student in _students) {
      final ref = _pickStudentRef(student);
      final marks = num.tryParse(_safeStr(_marks[ref]));
      if (ref.isEmpty || marks == null) continue;
      students.add({
        'studentId': _toInt(student['id']) ?? 0,
        'studentRef': ref,
        'name': _pickStudentName(student),
        'marksObtained': marks,
      });
    }

    if (students.isEmpty) {
      _snack('Fill marks first to generate remarks.', error: true);
      return;
    }

    setState(() => _aiRemarksBusy = true);
    try {
      final response = await ApiService.rawPost(
        '/api/ai/lesson-plan-evaluation/remarks',
        {
          'evaluationId': id,
          'className': _className(),
          'subjectName': _subjectName(),
          'topic': _safeStr(_lessonPlan?['topic']),
          'subtopic': _safeStr(_lessonPlan?['subtopic']),
          'totalMarks': totalMarks,
          'language': _remarksLanguage,
          'students': students,
        },
      );
      if (!_ok(response.statusCode)) {
        throw Exception(_error(response.body, 'AI remarks generation failed'));
      }

      final decoded = _decode(response.body);
      final raw = decoded['remarks'] ??
          decoded['data']?['remarks'] ??
          decoded['result']?['remarks'] ??
          decoded['data']?['result']?['remarks'];
      final list = raw is List ? raw : const [];
      final byId = {
        for (final s in _students)
          if (_toInt(s['id']) != null) _toInt(s['id'])!: _pickStudentRef(s)
      };
      final patch = <String, String>{};
      for (final item in list) {
        final row = _asMap(item);
        final ref = byId[_toInt(row['studentId'])];
        final remark = _safeStr(row['remark']);
        if (ref != null && remark.isNotEmpty) patch[ref] = remark;
      }

      if (patch.isEmpty) {
        _snack('AI returned no usable remarks.', error: true);
        return;
      }

      setState(() => _remarks = {..._remarks, ...patch});
      _snack('Generated remarks for ${patch.length} student(s).');
    } catch (e) {
      _snack(_cleanError(e), error: true);
    } finally {
      if (mounted) setState(() => _aiRemarksBusy = false);
    }
  }

  Future<void> _openEvaluationEditor({Map<String, dynamic>? existing}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EvaluationEditorSheet(
        lessonPlan: _lessonPlan ?? {},
        existing: existing,
      ),
    );

    if (result == true) {
      await _loadEvaluations(selectId: _toInt(existing?['id']));
    }
  }

  List<Map<String, dynamic>> get _filteredStudents {
    final q = _search.trim().toLowerCase();
    final sectionId = _sectionFilter.isEmpty ? null : _toInt(_sectionFilter);
    return _students.where((s) {
      if (sectionId != null) {
        final sid = _toInt(s['section_id'] ?? s['sectionId']);
        if (sid != sectionId) return false;
      }
      if (q.isEmpty) return true;
      final blob = [
        _pickStudentRef(s),
        _pickStudentName(s),
        s['roll_number'],
        s['rollNumber'],
        _sectionName(s),
      ].map(_safeStr).join(' ').toLowerCase();
      return blob.contains(q);
    }).toList();
  }

  bool get _canEditActive =>
      _safeStr(_activeEval?['status']).toUpperCase() == 'DRAFT' ||
      _safeStr(_activeEval?['status']).isEmpty;

  @override
  Widget build(BuildContext context) {
    final title = _safeStr(_lessonPlan?['topic']).isEmpty
        ? 'Lesson Plan Evaluations'
        : _safeStr(_lessonPlan?['topic']);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Evaluations'),
        actions: [
          IconButton(
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEvaluationEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Create'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
                children: [
                  _header(title),
                  const SizedBox(height: 12),
                  _evaluationList(),
                  const SizedBox(height: 12),
                  _activePanel(),
                ],
              ),
            ),
    );
  }

  Widget _header(String title) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.quiz_rounded, color: _primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill(_className(), const Color(0xFF2563EB)),
              _pill(_subjectName(), const Color(0xFF0F766E)),
              _pill('${_evaluations.length} evaluations', _primary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _evaluationList() {
    if (_evaluations.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: _cardDecoration(),
        child: Column(
          children: [
            Icon(Icons.assignment_outlined,
                size: 42, color: Colors.grey.shade500),
            const SizedBox(height: 8),
            const Text(
              'No evaluations yet',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => _openEvaluationEditor(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create Evaluation'),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 128,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _evaluations.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final ev = _evaluations[index];
          final selected = _toInt(ev['id']) == _activeEvalId;
          return InkWell(
            onTap: () {
              final id = _toInt(ev['id']);
              if (id != null) _selectEvaluation(id);
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 240,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? _primary : const Color(0xFFE5E7EB),
                  width: selected ? 1.6 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _safeStr(ev['title']).isEmpty
                        ? 'Evaluation'
                        : _safeStr(ev['title']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const Spacer(),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _pill(
                          _safeStr(ev['type']).isEmpty
                              ? 'OBJECTIVE'
                              : _safeStr(ev['type']),
                          _primary),
                      _pill(
                          _safeStr(ev['status']).isEmpty
                              ? 'DRAFT'
                              : _safeStr(ev['status']),
                          _statusColor(ev['status'])),
                      _pill(
                          '${_safeStr(ev['totalMarks']).isEmpty ? 0 : ev['totalMarks']} marks',
                          _orange),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _activePanel() {
    if (_activeLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final ev = _activeEval;
    if (ev == null) {
      return const SizedBox.shrink();
    }

    final items = _itemsOf(ev);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _safeStr(ev['title']),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') _openEvaluationEditor(existing: ev);
                      if (value == 'publish') _publishActive();
                      if (value == 'delete') _deleteActive();
                      if (value == 'analytics') _loadAnalytics();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        enabled: _canEditActive,
                        child: const Text('Edit'),
                      ),
                      PopupMenuItem(
                        value: 'publish',
                        enabled: _canEditActive,
                        child: const Text('Publish'),
                      ),
                      const PopupMenuItem(
                        value: 'analytics',
                        child: Text('Load analytics'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill(_safeStr(ev['type']), _primary),
                  _pill(
                      _safeStr(ev['status']).isEmpty
                          ? 'DRAFT'
                          : _safeStr(ev['status']),
                      _statusColor(ev['status'])),
                  _pill(
                      '${_safeStr(ev['totalMarks']).isEmpty ? 0 : ev['totalMarks']} marks',
                      _orange),
                  _pill(
                      '${_safeStr(ev['timeMinutes']).isEmpty ? '-' : ev['timeMinutes']} min',
                      _muted),
                ],
              ),
              if (_safeStr(_configOf(ev)['instructions']).isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  _safeStr(_configOf(ev)['instructions']),
                  style: const TextStyle(
                      color: _muted, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _canEditActive
                          ? () => _openEvaluationEditor(existing: ev)
                          : null,
                      icon: const Icon(Icons.edit_rounded),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _canEditActive ? _publishActive : null,
                      icon: const Icon(Icons.publish_rounded),
                      label: const Text('Publish'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _questionsCard(items),
        const SizedBox(height: 12),
        _marksCard(),
        if (_analytics != null) ...[
          const SizedBox(height: 12),
          _analyticsCard(),
        ],
      ],
    );
  }

  Widget _questionsCard(List<Map<String, dynamic>> items) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Questions',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
              _pill('${items.length}', _primary),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const Text('No questions found.', style: TextStyle(color: _muted))
          else
            ...items.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final item = entry.value;
              final type = _safeStr(item['type']).toUpperCase();
              final options =
                  _asStringList(item['options'] ?? item['optionsJson']);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: _softBox(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _pill('$idx', _primary),
                        const SizedBox(width: 8),
                        _pill(type.isEmpty ? 'QUESTION' : type, _muted),
                        const Spacer(),
                        Text(
                          '${_safeStr(item['marks']).isEmpty ? 0 : item['marks']} marks',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _safeStr(item['question']),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (options.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...options.asMap().entries.map(
                            (o) => Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${String.fromCharCode(65 + o.key)}. ${o.value}',
                                style: const TextStyle(color: _muted),
                              ),
                            ),
                          ),
                    ],
                    if (_safeStr(item['answerKey']).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Answer: ${item['answerKey']}',
                        style: const TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _marksCard() {
    final total = _toNum(_activeEval?['totalMarks']) ?? 0;
    final filtered = _filteredStudents;
    final filled = filtered.where((s) {
      final v = _marks[_pickStudentRef(s)];
      return v != null && v.trim().isNotEmpty && num.tryParse(v.trim()) != null;
    }).length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Student Marks',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
              _pill('$filled/${filtered.length}', _green),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (value) => setState(() => _search = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Search student',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _remarksLanguage,
                items: const [
                  DropdownMenuItem(value: 'en', child: Text('EN')),
                  DropdownMenuItem(value: 'hi', child: Text('HI')),
                  DropdownMenuItem(value: 'pa', child: Text('PA')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _remarksLanguage = value);
                },
              ),
            ],
          ),
          if (_planSections().isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _sectionChip('', 'All'),
                  ..._planSections().map(
                    (s) => _sectionChip(
                      '${_toInt(s['id']) ?? ''}',
                      _safeStr(s['section_name'] ?? s['name']).isEmpty
                          ? 'Section ${s['id']}'
                          : _safeStr(s['section_name'] ?? s['name']),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (_studentsLoading)
            const Center(child: CircularProgressIndicator())
          else if (filtered.isEmpty)
            const Text('No students found.', style: TextStyle(color: _muted))
          else
            ...filtered.map((student) {
              final ref = _pickStudentRef(student);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: _softBox(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          child: Text(_pickStudentName(student)
                              .substring(0, 1)
                              .toUpperCase()),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _pickStudentName(student),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900),
                              ),
                              Text(
                                '$ref • ${_sectionName(student)}',
                                style: const TextStyle(
                                    color: _muted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 92,
                          child: TextField(
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            controller:
                                TextEditingController(text: _marks[ref] ?? '')
                                  ..selection = TextSelection.collapsed(
                                    offset: (_marks[ref] ?? '').length,
                                  ),
                            onChanged: (value) => _marks[ref] = value,
                            decoration: InputDecoration(
                              labelText: total > 0 ? '/ $total' : 'Marks',
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      minLines: 1,
                      maxLines: 3,
                      controller:
                          TextEditingController(text: _remarks[ref] ?? '')
                            ..selection = TextSelection.collapsed(
                              offset: (_remarks[ref] ?? '').length,
                            ),
                      onChanged: (value) => _remarks[ref] = value,
                      decoration: const InputDecoration(
                        labelText: 'Remark',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _aiRemarksBusy ? null : _generateAiRemarks,
                  icon: _aiRemarksBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: const Text('AI Remarks'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _savingResults ? null : _saveResults,
                  icon: _savingResults
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded),
                  label: const Text('Save Marks'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _analyticsCard() {
    final a = _analytics ?? {};
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Analytics',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metric(
                  'Students', a['studentsEvaluated'] ?? a['attempted'] ?? '-'),
              _metric('Average', a['averageMarks'] ?? a['average'] ?? '-'),
              _metric('Highest', a['highestMarks'] ?? a['maxMarks'] ?? '-'),
              _metric('Lowest', a['lowestMarks'] ?? a['minMarks'] ?? '-'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, dynamic value) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: _softBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            _safeStr(value).isEmpty ? '-' : _safeStr(value),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _sectionChip(String value, String label) {
    final selected = _sectionFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        label: Text(label),
        onSelected: (_) => setState(() => _sectionFilter = value),
      ),
    );
  }

  Widget _pill(String label, Color color) {
    final text = label.trim().isEmpty ? '-' : label.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE5E7EB)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.045),
          blurRadius: 18,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  BoxDecoration _softBox() {
    return BoxDecoration(
      color: const Color(0xFFF8FAFF),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE5E7EB)),
    );
  }

  Color _statusColor(dynamic status) {
    switch (_safeStr(status).toUpperCase()) {
      case 'PUBLISHED':
        return _green;
      case 'ARCHIVED':
        return const Color(0xFF334155);
      case 'DRAFT':
        return _muted;
      default:
        return _primary;
    }
  }

  List<int> _planSectionIds() {
    return _planSections()
        .map((s) => _toInt(s['id']))
        .whereType<int>()
        .toList();
  }

  List<Map<String, dynamic>> _planSections() {
    final raw = _lessonPlan?['Sections'] ?? _lessonPlan?['sections'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  String _className() {
    final cls = _asMap(_lessonPlan?['Class'] ?? _lessonPlan?['class']);
    return _safeStr(
      cls['class_name'] ??
          cls['name'] ??
          _lessonPlan?['className'] ??
          _lessonPlan?['class_name'] ??
          'Class',
    );
  }

  String _subjectName() {
    final subject = _asMap(_lessonPlan?['Subject'] ?? _lessonPlan?['subject']);
    return _safeStr(
      subject['name'] ??
          subject['subject_name'] ??
          _lessonPlan?['subjectName'] ??
          _lessonPlan?['subject_name'] ??
          'Subject',
    );
  }

  String _sectionName(Map<String, dynamic> student) {
    final section = _asMap(student['Section'] ?? student['section']);
    return _safeStr(
      section['section_name'] ??
          section['name'] ??
          student['section_name'] ??
          student['sectionName'] ??
          '-',
    );
  }

  static bool _ok(int code) => code >= 200 && code < 300;

  static dynamic _decode(String body) {
    if (body.trim().isEmpty) return {};
    return jsonDecode(body);
  }

  static List<Map<String, dynamic>> _normalizeList(dynamic decoded) {
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (decoded is Map) {
      for (final key in const [
        'rows',
        'evaluations',
        'items',
        'results',
        'result',
        'data',
      ]) {
        final value = decoded[key];
        if (value is List) return _normalizeList(value);
      }
      final data = decoded['data'];
      if (data is Map) {
        for (final key in const ['rows', 'evaluations', 'items', 'results']) {
          final value = data[key];
          if (value is List) return _normalizeList(value);
        }
      }
      final single = decoded['evaluation'];
      if (single is Map) return [Map<String, dynamic>.from(single)];
    }
    return [];
  }

  static List<Map<String, dynamic>> _normalizeStudents(dynamic decoded) {
    if (decoded is List) return _normalizeList(decoded);
    if (decoded is Map) {
      for (final key in const ['students', 'rows', 'items', 'data', 'result']) {
        final value = decoded[key];
        if (value is List) return _normalizeList(value);
      }
      final data = decoded['data'];
      if (data is Map) {
        for (final key in const ['students', 'rows', 'items']) {
          final value = data[key];
          if (value is List) return _normalizeList(value);
        }
      }
    }
    return [];
  }

  static Map<String, dynamic> _normalizeEvaluation(dynamic decoded) {
    final ev = _asMap(
        decoded['evaluation'] ?? decoded['data']?['evaluation'] ?? decoded);
    final config = _asMap(ev['config'] ?? _jsonMaybe(ev['configJson']));
    final rawItems = ev['items'] ??
        ev['Items'] ??
        ev['EvaluationItems'] ??
        ev['evaluation']?['items'];
    final items = _normalizeList(rawItems);
    return {
      ...ev,
      'config': config,
      'items': items.map((item) {
        final options = _asStringList(item['options'] ?? item['optionsJson']);
        return {
          ...item,
          'options': options,
          'correctIndex':
              _toInt(item['correctIndex'] ?? item['correctAnswer']) ?? 0,
        };
      }).toList(),
    };
  }

  static Map<String, dynamic> _configOf(Map<String, dynamic> ev) {
    return _asMap(ev['config'] ?? _jsonMaybe(ev['configJson']));
  }

  static List<Map<String, dynamic>> _itemsOf(Map<String, dynamic> ev) {
    return _normalizeList(ev['items'] ?? ev['Items'] ?? ev['EvaluationItems']);
  }

  static List<String> _asStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => _safeStr(e)).where((e) => e.isNotEmpty).toList();
    }
    final parsed = _jsonMaybe(value);
    if (parsed is List) return _asStringList(parsed);
    return [];
  }

  static dynamic _jsonMaybe(dynamic value) {
    if (value == null) return null;
    if (value is! String) return value;
    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }

  static String _pickStudentRef(Map<String, dynamic> s) {
    return _safeStr(
      s['admissionNo'] ??
          s['admission_no'] ??
          s['admission_number'] ??
          s['admissionNumber'] ??
          s['username'] ??
          s['userName'] ??
          s['id'],
    );
  }

  static String _pickStudentName(Map<String, dynamic> s) {
    final name = _safeStr(s['name'] ?? s['student_name']);
    if (name.isNotEmpty) return name;
    final ref = _pickStudentRef(s);
    return ref.isEmpty ? 'Student' : 'Student $ref';
  }

  static String _safeStr(dynamic value) => value == null ? '' : '$value'.trim();

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value'.trim());
  }

  static num? _toNum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse('$value'.trim());
  }

  static String _formatNum(num value) {
    if (value == value.roundToDouble()) return '${value.toInt()}';
    return '$value';
  }

  static String _error(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return _safeStr(decoded['message'] ?? decoded['error']).isEmpty
            ? fallback
            : _safeStr(decoded['message'] ?? decoded['error']);
      }
    } catch (_) {}
    return fallback;
  }

  static String _cleanError(Object e) => '$e'.replaceFirst('Exception: ', '');

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }
}

class _EvaluationEditorSheet extends StatefulWidget {
  final Map<String, dynamic> lessonPlan;
  final Map<String, dynamic>? existing;

  const _EvaluationEditorSheet({
    required this.lessonPlan,
    this.existing,
  });

  @override
  State<_EvaluationEditorSheet> createState() => _EvaluationEditorSheetState();
}

class _EvaluationEditorSheetState extends State<_EvaluationEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _totalMarks;
  late final TextEditingController _timeMinutes;
  late final TextEditingController _instructions;

  String _type = 'OBJECTIVE';
  bool _saving = false;
  bool _aiBusy = false;
  String _aiMode = 'APPEND';
  int _aiCount = 10;
  String _aiDifficulty = 'MEDIUM';
  bool _preferMcqOnly = true;
  List<_EvalItemDraft> _items = [];

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final config =
        _TeacherLessonPlanEvaluationsScreenState._configOf(existing ?? {});
    _title = TextEditingController(
      text:
          _TeacherLessonPlanEvaluationsScreenState._safeStr(existing?['title']),
    );
    _type = _TeacherLessonPlanEvaluationsScreenState._safeStr(existing?['type'])
            .isEmpty
        ? 'OBJECTIVE'
        : _TeacherLessonPlanEvaluationsScreenState._safeStr(existing?['type'])
            .toUpperCase();
    _totalMarks = TextEditingController(
      text: _TeacherLessonPlanEvaluationsScreenState._safeStr(
                  existing?['totalMarks'])
              .isEmpty
          ? '20'
          : _TeacherLessonPlanEvaluationsScreenState._safeStr(
              existing?['totalMarks']),
    );
    _timeMinutes = TextEditingController(
      text: _TeacherLessonPlanEvaluationsScreenState._safeStr(
                  existing?['timeMinutes'])
              .isEmpty
          ? '30'
          : _TeacherLessonPlanEvaluationsScreenState._safeStr(
              existing?['timeMinutes']),
    );
    _instructions = TextEditingController(
      text: _TeacherLessonPlanEvaluationsScreenState._safeStr(
          config['instructions']),
    );
    _items = _mapExistingItems(existing);
    if (_items.isEmpty) _items = [_EvalItemDraft.mcq()];
  }

  @override
  void dispose() {
    _title.dispose();
    _totalMarks.dispose();
    _timeMinutes.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final itemPayload = _buildItemsPayload();
    if (itemPayload.isEmpty) {
      _snack('Please add at least one question.', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final payload = {
        'title': _title.text.trim().isEmpty ? 'Evaluation' : _title.text.trim(),
        'type': _type,
        'totalMarks': num.tryParse(_totalMarks.text.trim()) ?? _computedMarks(),
        'timeMinutes': _timeMinutes.text.trim().isEmpty
            ? null
            : num.tryParse(_timeMinutes.text.trim()),
        'config': {
          'instructions': _instructions.text.trim().isEmpty
              ? null
              : _instructions.text.trim(),
        },
        'items': itemPayload,
      };

      final response = _editing
          ? await ApiService.rawPut(
              '/lesson-plan-evaluations/${widget.existing?['id']}',
              payload,
            )
          : await ApiService.rawPost(
              '/lesson-plans/${widget.lessonPlan['id']}/evaluations',
              payload,
            );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          _TeacherLessonPlanEvaluationsScreenState._error(
            response.body,
            _editing
                ? 'Failed to update evaluation'
                : 'Failed to create evaluation',
          ),
        );
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack(_TeacherLessonPlanEvaluationsScreenState._cleanError(e),
          error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _generateQuestionsWithAi() async {
    if (_aiBusy) return;
    final classId = _TeacherLessonPlanEvaluationsScreenState._toInt(
      widget.lessonPlan['classId'],
    );
    final subjectId = _TeacherLessonPlanEvaluationsScreenState._toInt(
      widget.lessonPlan['subjectId'],
    );
    final topic = _TeacherLessonPlanEvaluationsScreenState._safeStr(
      widget.lessonPlan['topic'],
    );
    if (classId == null || subjectId == null || topic.isEmpty) {
      _snack('Lesson plan class, subject or topic missing.', error: true);
      return;
    }

    setState(() => _aiBusy = true);
    try {
      final response =
          await ApiService.rawPost('/api/ai/lesson-plan/questions', {
        'classId': classId,
        'subjectId': subjectId,
        'topic': topic,
        'subtopic': _TeacherLessonPlanEvaluationsScreenState._safeStr(
          widget.lessonPlan['subtopic'],
        ).isEmpty
            ? null
            : _TeacherLessonPlanEvaluationsScreenState._safeStr(
                widget.lessonPlan['subtopic'],
              ),
        'evaluationType': _type,
        'preferMcqOnly': _preferMcqOnly,
        'count': _aiCount,
        'difficulty': _aiDifficulty,
        'totalMarks': num.tryParse(_totalMarks.text.trim()),
        'language': 'en',
      });

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          _TeacherLessonPlanEvaluationsScreenState._error(
            response.body,
            'AI questions generation failed',
          ),
        );
      }

      final generated = _normalizeAiQuestions(
        _TeacherLessonPlanEvaluationsScreenState._decode(response.body),
      );
      if (generated.isEmpty) {
        _snack('AI returned no usable questions.', error: true);
        return;
      }

      setState(() {
        _items = _aiMode == 'REPLACE' ? generated : [..._items, ...generated];
        final computed = _computedMarks();
        final existingTotal = num.tryParse(_totalMarks.text.trim()) ?? 0;
        if (existingTotal < computed) _totalMarks.text = '$computed';
      });
      _snack('AI generated ${generated.length} question(s).');
    } catch (e) {
      _snack(_TeacherLessonPlanEvaluationsScreenState._cleanError(e),
          error: true);
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        final media = MediaQuery.of(context);
        final bottomInset = media.viewInsets.bottom > 0
            ? media.viewInsets.bottom
            : media.viewPadding.bottom;

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _editing ? 'Edit Evaluation' : 'Create Evaluation',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context, false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      18 + bottomInset,
                    ),
                    children: [
                      TextFormField(
                        controller: _title,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Required'
                                : null,
                        decoration: const InputDecoration(
                          labelText: 'Evaluation title',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _type,
                              decoration: const InputDecoration(
                                labelText: 'Type',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'OBJECTIVE',
                                    child: Text('Objective')),
                                DropdownMenuItem(
                                    value: 'SUBJECTIVE',
                                    child: Text('Subjective')),
                                DropdownMenuItem(
                                    value: 'MIXED', child: Text('Mixed')),
                              ],
                              onChanged: (value) {
                                if (value != null)
                                  setState(() => _type = value);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _totalMarks,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Total marks',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _timeMinutes,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Time minutes',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _instructions,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Instructions',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _aiPanel(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Questions',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(
                                () => _items.add(_EvalItemDraft.mcq())),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('MCQ'),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(
                                () => _items.add(_EvalItemDraft.subjective())),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Subjective'),
                          ),
                        ],
                      ),
                      ..._items.asMap().entries.map((entry) {
                        return _questionEditor(entry.key, entry.value);
                      }),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: AnimatedPadding(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      10,
                      16,
                      16 +
                          (media.viewInsets.bottom > 0
                              ? media.viewInsets.bottom
                              : 0),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(_saving ? 'Saving...' : 'Save Evaluation'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _aiPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFF2563EB)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'AI Questions',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Switch(
                value: _preferMcqOnly,
                onChanged: (value) => setState(() => _preferMcqOnly = value),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _aiMode,
                  decoration: const InputDecoration(labelText: 'Mode'),
                  items: const [
                    DropdownMenuItem(value: 'APPEND', child: Text('Append')),
                    DropdownMenuItem(value: 'REPLACE', child: Text('Replace')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _aiMode = value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _aiDifficulty,
                  decoration: const InputDecoration(labelText: 'Difficulty'),
                  items: const [
                    DropdownMenuItem(value: 'EASY', child: Text('Easy')),
                    DropdownMenuItem(value: 'MEDIUM', child: Text('Medium')),
                    DropdownMenuItem(value: 'HARD', child: Text('Hard')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _aiDifficulty = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _aiCount.toDouble(),
                  min: 1,
                  max: 30,
                  divisions: 29,
                  label: '$_aiCount',
                  onChanged: (value) =>
                      setState(() => _aiCount = value.round()),
                ),
              ),
              Text('$_aiCount'),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _aiBusy ? null : _generateQuestionsWithAi,
                icon: _aiBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_awesome_rounded),
                label: const Text('Generate'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _questionEditor(int index, _EvalItemDraft item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Q${index + 1}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButton<String>(
                  value: item.type,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'MCQ', child: Text('MCQ')),
                    DropdownMenuItem(
                        value: 'SUBJECTIVE', child: Text('Subjective')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      item.type = value;
                      if (value == 'MCQ' && item.options.isEmpty) {
                        item.options = ['', '', '', ''];
                        item.marks.text = '1';
                      }
                      if (value == 'SUBJECTIVE') {
                        item.options = [];
                        if (item.marks.text.trim().isEmpty ||
                            item.marks.text.trim() == '1') {
                          item.marks.text = '5';
                        }
                      }
                    });
                  },
                ),
              ),
              IconButton(
                onPressed: _items.length == 1
                    ? null
                    : () => setState(() {
                          item.dispose();
                          _items.removeAt(index);
                        }),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          TextFormField(
            controller: item.question,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Question',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: item.marks,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Marks',
              border: OutlineInputBorder(),
            ),
          ),
          if (item.type == 'MCQ') ...[
            const SizedBox(height: 8),
            ...List.generate(4, (idx) {
              while (item.options.length < 4) item.options.add('');
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextFormField(
                  initialValue: item.options[idx],
                  onChanged: (value) => item.options[idx] = value,
                  decoration: InputDecoration(
                    labelText: 'Option ${String.fromCharCode(65 + idx)}',
                    border: const OutlineInputBorder(),
                    suffixIcon: Radio<int>(
                      value: idx,
                      groupValue: item.correctIndex,
                      onChanged: (value) =>
                          setState(() => item.correctIndex = value ?? 0),
                    ),
                  ),
                ),
              );
            }),
          ] else ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: item.answerKey,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Answer key',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _buildItemsPayload() {
    return _items
        .where((item) => item.question.text.trim().isNotEmpty)
        .map((item) {
      final marks = num.tryParse(item.marks.text.trim()) ?? 0;
      if (item.type == 'MCQ') {
        return {
          'sortOrder': _items.indexOf(item),
          'type': 'MCQ',
          'question': item.question.text.trim(),
          'marks': marks,
          'options': item.options
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
          'correctIndex': item.correctIndex,
        };
      }

      return {
        'sortOrder': _items.indexOf(item),
        'type': 'SUBJECTIVE',
        'question': item.question.text.trim(),
        'marks': marks,
        'answerKey': item.answerKey.text.trim().isEmpty
            ? null
            : item.answerKey.text.trim(),
      };
    }).toList();
  }

  num _computedMarks() {
    return _items.fold<num>(0, (sum, item) {
      return sum + (num.tryParse(item.marks.text.trim()) ?? 0);
    });
  }

  List<_EvalItemDraft> _mapExistingItems(Map<String, dynamic>? existing) {
    final rows =
        _TeacherLessonPlanEvaluationsScreenState._itemsOf(existing ?? {});
    return rows.map((row) {
      final type =
          _TeacherLessonPlanEvaluationsScreenState._safeStr(row['type'])
              .toUpperCase();
      final options = _TeacherLessonPlanEvaluationsScreenState._asStringList(
        row['options'] ?? row['optionsJson'],
      );
      return _EvalItemDraft(
        type: type == 'MCQ' ? 'MCQ' : 'SUBJECTIVE',
        question:
            _TeacherLessonPlanEvaluationsScreenState._safeStr(row['question']),
        marks: _TeacherLessonPlanEvaluationsScreenState._safeStr(row['marks'])
                .isEmpty
            ? (type == 'MCQ' ? '1' : '5')
            : _TeacherLessonPlanEvaluationsScreenState._safeStr(row['marks']),
        options: type == 'MCQ'
            ? [
                ...options,
                ...List.filled(4 - options.length.clamp(0, 4).toInt(), ''),
              ].take(4).toList()
            : [],
        correctIndex: _TeacherLessonPlanEvaluationsScreenState._toInt(
              row['correctIndex'] ?? row['correctAnswer'],
            ) ??
            0,
        answerKey:
            _TeacherLessonPlanEvaluationsScreenState._safeStr(row['answerKey']),
      );
    }).toList();
  }

  List<_EvalItemDraft> _normalizeAiQuestions(dynamic decoded) {
    final root = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    dynamic raw;
    if (root is Map) {
      raw = root['questions'] ??
          root['items'] ??
          root['evaluationItems'] ??
          root['result']?['questions'] ??
          root['data']?['questions'];
    }
    if (raw is! List) return [];

    return raw
        .map((q) {
          final row = _TeacherLessonPlanEvaluationsScreenState._asMap(q);
          final question = _TeacherLessonPlanEvaluationsScreenState._safeStr(
            row['question'] ?? row['q'],
          );
          if (question.isEmpty) return null;

          final options =
              _TeacherLessonPlanEvaluationsScreenState._asStringList(
                  row['options']);
          final type = _TeacherLessonPlanEvaluationsScreenState._safeStr(
            row['type'] ?? row['questionType'],
          ).toUpperCase();

          if (type == 'MCQ' || options.isNotEmpty) {
            return _EvalItemDraft(
              type: 'MCQ',
              question: question,
              marks: _TeacherLessonPlanEvaluationsScreenState._safeStr(
                          row['marks'])
                      .isEmpty
                  ? '1'
                  : _TeacherLessonPlanEvaluationsScreenState._safeStr(
                      row['marks']),
              options: [
                ...options,
                ...List.filled(4 - options.length.clamp(0, 4).toInt(), ''),
              ].take(4).toList(),
              correctIndex: _TeacherLessonPlanEvaluationsScreenState._toInt(
                    row['correctIndex'] ?? row['correctAnswer'],
                  ) ??
                  0,
            );
          }

          return _EvalItemDraft(
            type: 'SUBJECTIVE',
            question: question,
            marks:
                _TeacherLessonPlanEvaluationsScreenState._safeStr(row['marks'])
                        .isEmpty
                    ? '5'
                    : _TeacherLessonPlanEvaluationsScreenState._safeStr(
                        row['marks']),
            answerKey: _TeacherLessonPlanEvaluationsScreenState._safeStr(
              row['answerKey'] ?? row['modelAnswer'],
            ),
          );
        })
        .whereType<_EvalItemDraft>()
        .toList();
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }
}

class _EvalItemDraft {
  String type;
  final TextEditingController question;
  final TextEditingController marks;
  final TextEditingController answerKey;
  List<String> options;
  int correctIndex;

  _EvalItemDraft({
    required this.type,
    String question = '',
    String marks = '',
    String answerKey = '',
    List<String>? options,
    this.correctIndex = 0,
  })  : question = TextEditingController(text: question),
        marks = TextEditingController(text: marks),
        answerKey = TextEditingController(text: answerKey),
        options = options ?? [];

  factory _EvalItemDraft.mcq() {
    return _EvalItemDraft(
      type: 'MCQ',
      marks: '1',
      options: ['', '', '', ''],
    );
  }

  factory _EvalItemDraft.subjective() {
    return _EvalItemDraft(
      type: 'SUBJECTIVE',
      marks: '5',
      options: [],
    );
  }

  void dispose() {
    question.dispose();
    marks.dispose();
    answerKey.dispose();
  }
}
