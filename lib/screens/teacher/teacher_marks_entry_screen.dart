import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class TeacherMarksEntryScreen extends StatefulWidget {
  const TeacherMarksEntryScreen({super.key});

  @override
  State<TeacherMarksEntryScreen> createState() =>
      _TeacherMarksEntryScreenState();
}

class _TeacherMarksEntryScreenState extends State<TeacherMarksEntryScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _initialLoading = true;
  bool _loadingMarks = false;
  bool _saving = false;

  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _accessibleSchedules = [];
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _components = [];
  List<dynamic> _gradeOptions = [];

  String? _sessionId;
  String? _classId;
  String? _sectionId;
  String? _examId;
  String? _subjectId;
  String _evaluationMode = 'MARKS';
  dynamic _examScheduleId;

  final Map<String, TextEditingController> _marksControllers = {};
  final Map<String, String> _attendance = {};
  final Map<String, String> _gradeValues = {};
  final Map<String, String> _gradeAttendance = {};

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    for (final controller in _marksControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() => _initialLoading = true);
    await Future.wait([
      _loadSessions(),
      _loadMarksScope(),
    ]);
    if (mounted) setState(() => _initialLoading = false);
  }

  Future<void> _loadSessions() async {
    try {
      final response = await ApiService.rawGet('/sessions');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final rows = _asMapList(jsonDecode(response.body));
        if (!mounted) return;
        setState(() {
          _sessions = rows;
          final active = rows.firstWhere(
            (row) =>
                row['is_current'] == true ||
                row['isCurrent'] == true ||
                row['current'] == true ||
                '${row['status'] ?? ''}'.toLowerCase() == 'active',
            orElse: () => rows.isNotEmpty ? rows.first : <String, dynamic>{},
          );
          _sessionId ??= _idOf(active);
        });
      }
    } catch (_) {}
  }

  Future<void> _loadMarksScope() async {
    try {
      final response = await ApiService.rawGet('/marks-access/my-scope');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        final rows = decoded is Map
            ? _asMapList(decoded['schedules'])
            : <Map<String, dynamic>>[];
        if (mounted) setState(() => _accessibleSchedules = rows);
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> _asMapList(dynamic decoded) {
    final raw = decoded is List
        ? decoded
        : decoded is Map
            ? (decoded['data'] ??
                decoded['rows'] ??
                decoded['sections'] ??
                decoded['sessions'] ??
                decoded['classes'] ??
                [])
            : [];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String? _idOf(Map<String, dynamic>? row, [List<String> keys = const []]) {
    if (row == null || row.isEmpty) return null;
    for (final key in [...keys, 'id', 'session_id', 'class_id', 'exam_id']) {
      final value = row[key];
      if (value != null && '$value'.isNotEmpty) return '$value';
    }
    return null;
  }

  String _labelOf(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty) return '$value';
    }
    return _idOf(row) ?? '-';
  }

  List<Map<String, dynamic>> get _sessionSchedules => _accessibleSchedules
      .where(
          (row) => _sessionId == null || '${row['session_id']}' == _sessionId)
      .toList();

  List<Map<String, dynamic>> _uniqueBy(
    Iterable<Map<String, dynamic>> rows,
    String key,
  ) {
    final unique = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final value = row[key];
      if (value != null && '$value'.isNotEmpty) unique['$value'] = row;
    }
    return unique.values.toList();
  }

  List<Map<String, dynamic>> get _classes =>
      _uniqueBy(_sessionSchedules, 'class_id');

  List<Map<String, dynamic>> get _filteredSections {
    if (_classId == null || _classId!.isEmpty) return [];
    return _uniqueBy(
      _sessionSchedules.where((row) => '${row['class_id']}' == _classId),
      'section_id',
    );
  }

  List<Map<String, dynamic>> get _filteredExams {
    if (_classId == null || _sectionId == null) return [];
    return _uniqueBy(
      _sessionSchedules.where((row) =>
          '${row['class_id']}' == _classId &&
          '${row['section_id']}' == _sectionId),
      'exam_id',
    );
  }

  List<Map<String, dynamic>> get _filteredSubjects {
    if (_classId == null || _sectionId == null || _examId == null) return [];
    return _uniqueBy(
      _sessionSchedules.where((row) =>
          '${row['class_id']}' == _classId &&
          '${row['section_id']}' == _sectionId &&
          '${row['exam_id']}' == _examId),
      'subject_id',
    );
  }

  void _selectClass(String? classId) {
    setState(() {
      _classId = classId;
      _sectionId = null;
      _examId = null;
      _subjectId = null;
      _clearMarks();
    });
  }

  void _selectExam(String? examId) {
    setState(() {
      _examId = examId;
      _subjectId = null;
      _clearMarks();
    });
  }

  void _clearMarks() {
    for (final controller in _marksControllers.values) {
      controller.dispose();
    }
    _marksControllers.clear();
    _attendance.clear();
    _gradeValues.clear();
    _gradeAttendance.clear();
    _students = [];
    _components = [];
    _gradeOptions = [];
    _examScheduleId = null;
    _evaluationMode = 'MARKS';
  }

  Future<void> _loadMarks() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loadingMarks = true;
      _clearMarks();
    });

    final params = Uri(queryParameters: {
      'session_id': _sessionId!,
      'class_id': _classId!,
      'section_id': _sectionId!,
      'exam_id': _examId!,
      'subject_id': _subjectId!,
    }).query;

    try {
      final response = await ApiService.rawGet('/marks-entry?$params');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_extractError(response.body, 'Failed to fetch marks'));
      }

      final decoded = jsonDecode(response.body);
      final data = decoded is Map ? decoded : <String, dynamic>{};
      final resultMap =
          data['resultMap'] is Map ? data['resultMap'] as Map : {};

      setState(() {
        _evaluationMode =
            '${data['evaluation_mode'] ?? data['mode'] ?? data['subject_mode'] ?? 'MARKS'}'
                .toUpperCase();
        _students = _asMapList(data['students']);
        _components = _asMapList(data['components']);
        _gradeOptions = data['grade_options'] is List
            ? data['grade_options'] as List
            : data['gradeOptions'] is List
                ? data['gradeOptions'] as List
                : data['grades'] is List
                    ? data['grades'] as List
                    : [];
        _examScheduleId = data['exam_schedule_id'] ?? data['examScheduleId'];

        for (final student in _students) {
          final studentId = '${student['id']}';
          for (final component in _components) {
            final componentId =
                '${component['component_id'] ?? component['id']}';
            final key = '${studentId}_$componentId';
            final saved = resultMap[key];
            final savedMap = saved is Map ? saved : <String, dynamic>{};
            _attendance[key] = '${savedMap['attendance'] ?? 'P'}';
            _gradeAttendance[key] = '${savedMap['attendance'] ?? 'P'}';
            _gradeValues[key] = '${savedMap['grade'] ?? ''}';
            _marksControllers[key] = TextEditingController(
              text:
                  '${savedMap['marks'] ?? savedMap['marks_obtained'] ?? savedMap['marksObtained'] ?? ''}',
            );
          }
        }
      });
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingMarks = false);
    }
  }

  Future<void> _saveMarks() async {
    if (_examScheduleId == null) {
      _showSnack('Exam schedule not found.');
      return;
    }

    setState(() => _saving = true);
    final marksData = <Map<String, dynamic>>[];

    for (final student in _students) {
      final studentId = student['id'];
      for (final component in _components) {
        final componentId = component['component_id'] ?? component['id'];
        final key = '${studentId}_$componentId';

        if (_evaluationMode == 'GRADE') {
          marksData.add({
            'student_id': studentId,
            'component_id': componentId,
            'grade': _gradeValues[key] ?? '',
            'attendance': _gradeAttendance[key] ?? 'P',
          });
        } else {
          final att = _attendance[key] ?? 'P';
          marksData.add({
            'student_id': studentId,
            'component_id': componentId,
            'marks_obtained':
                att == 'P' ? _marksControllers[key]?.text.trim() ?? '' : null,
            'attendance': att,
          });
        }
      }
    }

    try {
      final response = await ApiService.rawPost('/marks-entry/save', {
        'exam_schedule_id': _examScheduleId,
        'marksData': marksData,
      });

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_extractError(response.body, 'Failed to save marks'));
      }

      _showSnack(_evaluationMode == 'GRADE'
          ? 'Grades saved successfully'
          : 'Marks saved successfully');
      await _loadMarks();
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _extractError(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final message = decoded['message'] ?? decoded['error'];
        if (message != null && '$message'.isNotEmpty) return '$message';
      }
    } catch (_) {}
    return fallback;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Marks Entry')),
      floatingActionButton: _students.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _saving ? null : _saveMarks,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('Save'),
            ),
      body: _initialLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadMarks,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _filtersCard(),
                  const SizedBox(height: 12),
                  if (_loadingMarks)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_students.isEmpty)
                    _emptyState()
                  else
                    ..._students.map(_studentMarksCard),
                  const SizedBox(height: 90),
                ],
              ),
            ),
    );
  }

  Widget _filtersCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Exam Context',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            _dropdown(
              label: 'Session',
              value: _sessionId,
              items: _sessions,
              itemId: (row) => _idOf(row, const ['session_id']),
              itemLabel: (row) =>
                  _labelOf(row, const ['session_name', 'name', 'title']),
              onChanged: (value) => setState(() {
                _sessionId = value;
                _classId = null;
                _sectionId = null;
                _examId = null;
                _subjectId = null;
                _clearMarks();
              }),
            ),
            _dropdown(
              label: 'Class',
              value: _classId,
              items: _classes,
              itemId: (row) => '${row['class_id'] ?? row['id']}',
              itemLabel: (row) =>
                  _labelOf(row, const ['class_name', 'name', 'class']),
              onChanged: _selectClass,
            ),
            _dropdown(
              label: 'Section',
              value: _sectionId,
              items: _filteredSections,
              itemId: (row) => '${row['id'] ?? row['section_id']}',
              itemLabel: (row) =>
                  _labelOf(row, const ['section_name', 'name', 'section']),
              onChanged: (value) => setState(() {
                _sectionId = value;
                _examId = null;
                _subjectId = null;
                _clearMarks();
              }),
            ),
            _dropdown(
              label: 'Exam',
              value: _examId,
              items: _filteredExams,
              itemId: (row) => '${row['exam_id'] ?? row['id']}',
              itemLabel: (row) =>
                  _labelOf(row, const ['exam_name', 'name', 'title']),
              onChanged: _selectExam,
            ),
            _dropdown(
              label: 'Subject',
              value: _subjectId,
              items: _filteredSubjects,
              itemId: (row) => '${row['subject_id'] ?? row['id']}',
              itemLabel: (row) =>
                  _labelOf(row, const ['subject_name', 'name', 'title']),
              onChanged: (value) => setState(() {
                _subjectId = value;
                _clearMarks();
              }),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loadingMarks ? null : _loadMarks,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Load Students'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required List<Map<String, dynamic>> items,
    required String? Function(Map<String, dynamic>) itemId,
    required String Function(Map<String, dynamic>) itemLabel,
    required ValueChanged<String?> onChanged,
  }) {
    final unique = <String, Map<String, dynamic>>{};
    for (final item in items) {
      final id = itemId(item);
      if (id != null && id.isNotEmpty) unique[id] = item;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: unique.containsKey(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
        ),
        items: unique.entries
            .map(
              (entry) => DropdownMenuItem<String>(
                value: entry.key,
                child: Text(itemLabel(entry.value),
                    overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        validator: (value) =>
            value == null || value.isEmpty ? 'Required' : null,
        onChanged: onChanged,
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        children: [
          Icon(Icons.edit_note_rounded, size: 42, color: Color(0xFF2563EB)),
          SizedBox(height: 8),
          Text(
            'Load a class, exam, and subject to enter marks.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _studentMarksCard(Map<String, dynamic> student) {
    final studentId = '${student['id']}';
    final name =
        '${student['name'] ?? '${student['first_name'] ?? ''} ${student['last_name'] ?? ''}'.trim()}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name.isEmpty ? 'Student $studentId' : name,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          ..._components.map((component) {
            final componentId =
                '${component['component_id'] ?? component['id']}';
            final key = '${studentId}_$componentId';
            final componentName =
                '${component['component_name'] ?? component['name'] ?? 'Component'}';

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(componentName,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      SizedBox(
                        width: 92,
                        child: DropdownButtonFormField<String>(
                          value: (_evaluationMode == 'GRADE'
                                  ? _gradeAttendance[key]
                                  : _attendance[key]) ??
                              'P',
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'P', child: Text('P')),
                            DropdownMenuItem(value: 'A', child: Text('A')),
                            DropdownMenuItem(value: 'L', child: Text('L')),
                          ],
                          onChanged: (value) => setState(() {
                            if (_evaluationMode == 'GRADE') {
                              _gradeAttendance[key] = value ?? 'P';
                            } else {
                              _attendance[key] = value ?? 'P';
                            }
                          }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _evaluationMode == 'GRADE'
                            ? _gradeDropdown(key)
                            : TextField(
                                controller: _marksControllers[key],
                                enabled: (_attendance[key] ?? 'P') == 'P',
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  labelText: 'Marks',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _gradeDropdown(String key) {
    final labels = _gradeOptions
        .map((item) => item is Map
            ? '${item['grade'] ?? item['name'] ?? item['label'] ?? item['title'] ?? ''}'
            : '$item')
        .where((label) => label.trim().isNotEmpty)
        .toSet()
        .toList();

    return DropdownButtonFormField<String>(
      value: labels.contains(_gradeValues[key]) ? _gradeValues[key] : null,
      decoration: const InputDecoration(
        isDense: true,
        labelText: 'Grade',
        border: OutlineInputBorder(),
      ),
      items: labels
          .map((label) => DropdownMenuItem(value: label, child: Text(label)))
          .toList(),
      onChanged: (value) => setState(() => _gradeValues[key] = value ?? ''),
    );
  }
}
