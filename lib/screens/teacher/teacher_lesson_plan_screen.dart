import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import 'teacher_lesson_plan_evaluations_screen.dart';

class TeacherLessonPlanScreen extends StatefulWidget {
  const TeacherLessonPlanScreen({super.key});

  @override
  State<TeacherLessonPlanScreen> createState() =>
      _TeacherLessonPlanScreenState();
}

class _TeacherLessonPlanScreenState extends State<TeacherLessonPlanScreen> {
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  bool _loading = true;
  bool _saving = false;
  bool _aiBusy = false;

  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _assignments = [];

  String _filterTerm = 'ALL';
  String _search = '';

  static const Color _primary = Color(0xFF4F46E5);
  static const Color _primary2 = Color(0xFF06B6D4);
  static const Color _bg = Color(0xFFF6F8FF);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    if (mounted) setState(() => _loading = true);
    await Future.wait([_loadPlans(), _loadAssignments()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPlans() async {
    try {
      final response = await ApiService.rawGet('/lesson-plans');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (mounted) setState(() => _plans = _asMapList(decoded));
      } else {
        _showSnack(
          _extractError(response.body, 'Failed to fetch lesson plans'),
        );
      }
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _loadAssignments() async {
    try {
      final response = await ApiService.rawGet(
        '/class-subject-teachers/teacher/class-subjects',
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        final rows = decoded is Map ? decoded['assignments'] : decoded;
        if (mounted) setState(() => _assignments = _asMapList(rows));
      } else {
        _showSnack(_extractError(response.body, 'Failed to fetch assignments'));
      }
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  List<Map<String, dynamic>> _asMapList(dynamic decoded) {
    final raw = decoded is List
        ? decoded
        : decoded is Map
            ? (decoded['data'] ??
                decoded['rows'] ??
                decoded['lessonPlans'] ??
                decoded['plans'] ??
                decoded['items'] ??
                decoded['records'] ??
                decoded['result'] ??
                [])
            : [];

    if (raw is! List) return [];

    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  String _safeStr(dynamic value) {
    if (value == null) return '';
    if (value is List) {
      return value
          .map(_safeStr)
          .where((x) => x.trim().isNotEmpty)
          .join('\n');
    }
    if (value is Map) {
      final parts = <String>[];
      value.forEach((key, val) {
        final s = _safeStr(val);
        if (s.trim().isNotEmpty) parts.add('${_titleize('$key')}: $s');
      });
      return parts.join('\n');
    }
    return '$value'.trim();
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final n = int.tryParse('$value');
    return n;
  }

  bool _truthy(dynamic value) {
    if (value == true) return true;
    if (value == 1) return true;
    final s = '$value'.trim().toLowerCase();
    return s == '1' || s == 'true' || s == 'yes' || s == 'published';
  }

  bool _isPublished(Map<String, dynamic> plan) {
    return _truthy(plan['publish']) ||
        _truthy(plan['published']) ||
        _truthy(plan['isPublished']) ||
        _truthy(plan['is_published']) ||
        _truthy(plan['visibleToStudents']) ||
        _truthy(plan['studentVisible']);
  }

  String _nestedName(Map<String, dynamic> row, String key, List<String> names) {
    final nested = row[key];
    if (nested is Map) {
      for (final name in names) {
        final value = nested[name];
        if (value != null && '$value'.trim().isNotEmpty) return '$value';
      }
    }

    final lowerKey = key.toLowerCase();
    final lowerNested = row[lowerKey];
    if (lowerNested is Map) {
      for (final name in names) {
        final value = lowerNested[name];
        if (value != null && '$value'.trim().isNotEmpty) return '$value';
      }
    }

    for (final name in names) {
      final value = row[name];
      if (value != null && '$value'.trim().isNotEmpty) return '$value';
    }

    return '-';
  }

  int? _classIdFromAssignment(Map<String, dynamic>? assignment) {
    if (assignment == null) return null;
    final classObj = _asMap(assignment['class'] ?? assignment['Class']);
    return _toInt(
      assignment['classId'] ??
          assignment['class_id'] ??
          assignment['ClassId'] ??
          classObj['id'],
    );
  }

  int? _subjectIdFromAssignment(Map<String, dynamic>? assignment) {
    if (assignment == null) return null;
    final subjectObj = _asMap(assignment['subject'] ?? assignment['Subject']);
    return _toInt(
      assignment['subjectId'] ??
          assignment['subject_id'] ??
          assignment['SubjectId'] ??
          subjectObj['id'],
    );
  }

  String _classSubjectLabel(Map<String, dynamic> item) {
    final cls = _nestedName(item, 'class', const ['class_name', 'name']);
    final sub = _nestedName(item, 'subject', const ['name', 'subject_name']);
    return '$cls - $sub';
  }

  String _planClassName(Map<String, dynamic> plan) {
    return _nestedName(plan, 'Class', const ['class_name', 'name']);
  }

  String _planSubjectName(Map<String, dynamic> plan) {
    return _nestedName(plan, 'Subject', const ['name', 'subject_name']);
  }

  List<String> _splitList(dynamic text) {
    final s = _safeStr(text);
    if (s.isEmpty) return [];
    return s
        .split(RegExp(r'\r?\n|,|;|\|'))
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty)
        .toSet()
        .toList();
  }

  List<Map<String, dynamic>> get _filteredPlans {
    final q = _search.trim().toLowerCase();

    return _plans.where((plan) {
      final termOk =
          _filterTerm == 'ALL' || _safeStr(plan['term']) == _filterTerm;
      if (!termOk) return false;

      if (q.isEmpty) return true;

      final blob = [
        plan['topic'],
        plan['subtopic'],
        _planClassName(plan),
        _planSubjectName(plan),
        plan['term'],
        plan['academicSession'],
        plan['status'],
      ].map(_safeStr).join(' ').toLowerCase();

      return blob.contains(q);
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchSectionsForClass(
    int? classId,
  ) async {
    if (classId == null || classId <= 0) return [];

    try {
      final query = Uri(queryParameters: {
        'classId': '$classId',
        'class_id': '$classId',
      }).query;

      final response = await ApiService.rawGet('/sections?$query');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _asMapList(jsonDecode(response.body));
      }
    } catch (_) {}

    return [];
  }

  Future<List<Map<String, dynamic>>> _fetchBreakdownItems({
    required int? classId,
    required int? subjectId,
    required String term,
    required String academicSession,
  }) async {
    if (classId == null || subjectId == null) return [];

    try {
      final qp = <String, String>{
        'classId': '$classId',
        'subjectId': '$subjectId',
        'term': term,
        if (academicSession.trim().isNotEmpty)
          'academicSession': academicSession.trim(),
      };

      final response = await ApiService.rawGet(
        '/syllabus-breakdowns/items-for-plan?${Uri(queryParameters: qp).query}',
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);

        if (decoded is Map && decoded['items'] is List) {
          return _asMapList(decoded['items']);
        }

        return _asMapList(decoded);
      }
    } catch (_) {}

    return [];
  }

  Map<String, dynamic>? _findAssignmentForPlan(Map<String, dynamic> plan) {
    final classId = _toInt(plan['classId'] ?? plan['class_id']);
    final subjectId = _toInt(plan['subjectId'] ?? plan['subject_id']);

    if (classId == null || subjectId == null) return null;

    for (final item in _assignments) {
      if (_classIdFromAssignment(item) == classId &&
          _subjectIdFromAssignment(item) == subjectId) {
        return item;
      }
    }

    return _assignments.isNotEmpty ? _assignments.first : null;
  }

  Future<void> _openCreateSheet() async {
    if (_assignments.isEmpty) {
      _showSnack('No class-subject assignment found for this teacher.');
      return;
    }

    await _openPlanSheet();
  }

  Future<void> _openEditSheet(Map<String, dynamic> plan) async {
    Map<String, dynamic> full = plan;

    try {
      final response = await ApiService.rawGet('/lesson-plans/${plan['id']}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          full = _asMap(
            decoded['lessonPlan'] ??
                decoded['plan'] ??
                decoded['data'] ??
                decoded['record'] ??
                decoded,
          );
        }
      }
    } catch (_) {}

    await _openPlanSheet(plan: full);
  }

  void _openEvaluations(Map<String, dynamic> plan) {
    final id = _toInt(plan['id']);
    if (id == null) {
      _showSnack('Please save the lesson plan before creating evaluations.');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeacherLessonPlanEvaluationsScreen(
          lessonPlanId: id,
          lessonPlan: plan,
        ),
      ),
    );
  }

  Future<void> _openPlanSheet({Map<String, dynamic>? plan}) async {
    final isEdit = plan != null;
    final planId = _toInt(plan?['id']);

    final topic = TextEditingController(text: _safeStr(plan?['topic']));
    final subtopic = TextEditingController(text: _safeStr(plan?['subtopic']));
    final objectives = TextEditingController(
      text: _safeStr(plan?['specificObjectives'] ?? plan?['objectives']),
    );
    final method = TextEditingController(text: _safeStr(plan?['teachingMethod']));
    final aids = TextEditingController(text: _safeStr(plan?['teachingAids']));
    final activities = TextEditingController(text: _safeStr(plan?['activities']));
    final resources = TextEditingController(text: _safeStr(plan?['resources']));
    final evaluationMethod =
        TextEditingController(text: _safeStr(plan?['evaluationMethod']));
    final assessmentPlan = TextEditingController(
      text: _safeStr(plan?['assessmentPlan'] ?? plan?['assessmentMethods']),
    );
    final homework = TextEditingController(text: _safeStr(plan?['homework']));
    final remedial = TextEditingController(text: _safeStr(plan?['remedialPlan']));
    final enrichment =
        TextEditingController(text: _safeStr(plan?['enrichmentPlan']));
    final remarks = TextEditingController(text: _safeStr(plan?['remarks']));
    final periods = TextEditingController(
      text: plan?['plannedPeriods'] == null ? '' : '${plan?['plannedPeriods']}',
    );
    final academicSession =
        TextEditingController(text: _safeStr(plan?['academicSession']));

    Map<String, dynamic>? assignment =
        isEdit ? _findAssignmentForPlan(plan) : _assignments.first;

    DateTime weekStart = _parseDate(plan?['weekStart']) ?? DateTime.now();
    DateTime weekEnd = _parseDate(plan?['weekEnd']) ??
        DateTime.now().add(const Duration(days: 6));

    String term =
        _safeStr(plan?['term']).isEmpty ? 'FULL_YEAR' : _safeStr(plan?['term']);
    String completionStatus = _safeStr(plan?['completionStatus']).isEmpty
        ? 'Planned'
        : _safeStr(plan?['completionStatus']);

    bool publish = plan == null ? false : _isPublished(plan);
    bool aiFilled = false;

    int? currentLessonPlanId = planId;
    int? selectedBreakdownItemId = _toInt(plan?['breakdownItemId']);
    int? selectedBreakdownId = _toInt(plan?['breakdownId']);

    List<Map<String, dynamic>> sheetSections = [];
    List<int> selectedSections = _sectionIdsFromPlan(plan);
    List<Map<String, dynamic>> breakdownItems = [];
    List<String> topicOptions = [];
    List<String> subtopicOptions = [];

    bool metaLoading = true;

    Future<void> refreshMeta({
      required void Function(void Function()) setSheetState,
      bool resetUnit = false,
    }) async {
      setSheetState(() => metaLoading = true);

      final classId = _classIdFromAssignment(assignment);
      final subjectId = _subjectIdFromAssignment(assignment);

      final results = await Future.wait([
        _fetchSectionsForClass(classId),
        _fetchBreakdownItems(
          classId: classId,
          subjectId: subjectId,
          term: term,
          academicSession: academicSession.text,
        ),
      ]);

      final secRows = results[0];
      final bdRows = results[1];

      if (resetUnit) {
        selectedBreakdownItemId = null;
        selectedBreakdownId = null;
        topicOptions = [];
        subtopicOptions = [];
      } else if (selectedBreakdownItemId != null) {
        final item = bdRows.cast<Map<String, dynamic>?>().firstWhere(
              (x) => _toInt(x?['id']) == selectedBreakdownItemId,
              orElse: () => null,
            );

        if (item != null) {
          selectedBreakdownId =
              _toInt(item['breakdownId'] ?? item['syllabusBreakdownId']);
          topicOptions = _splitList(item['topics']);
          subtopicOptions = _splitList(item['subtopics']);
        }
      }

      setSheetState(() {
        sheetSections = secRows;
        breakdownItems = bdRows;
        metaLoading = false;
      });
    }

    void applyBreakdownItem(
      int? value,
      void Function(void Function()) setSheetState,
    ) {
      final item = breakdownItems.cast<Map<String, dynamic>?>().firstWhere(
            (x) => _toInt(x?['id']) == value,
            orElse: () => null,
          );

      setSheetState(() {
        selectedBreakdownItemId = value;
        selectedBreakdownId =
            _toInt(item?['breakdownId'] ?? item?['syllabusBreakdownId']);

        topicOptions = item == null ? [] : _splitList(item['topics']);
        subtopicOptions = item == null ? [] : _splitList(item['subtopics']);

        if (topicOptions.isNotEmpty && topic.text.trim().isEmpty) {
          topic.text = topicOptions.first;
        }

        if (subtopicOptions.isNotEmpty && subtopic.text.trim().isEmpty) {
          subtopic.text = subtopicOptions.first;
        }

        aiFilled = false;
      });
    }

    Future<void> generateWithAi(
      BuildContext sheetContext,
      void Function(void Function()) setSheetState,
    ) async {
      if (_aiBusy) return;

      final classId = _classIdFromAssignment(assignment);
      final subjectId = _subjectIdFromAssignment(assignment);

      if (classId == null || subjectId == null) {
        _showSnack('Please select Class & Subject first.');
        return;
      }

      if (topic.text.trim().isEmpty) {
        _showSnack('Please enter or select Topic first.');
        return;
      }

      setSheetState(() => _aiBusy = true);
      if (mounted) setState(() => _aiBusy = true);

      try {
        final payload = <String, dynamic>{
          if (currentLessonPlanId != null) 'lessonPlanId': currentLessonPlanId,
          'classId': classId,
          'subjectId': subjectId,
          'academicSession': academicSession.text.trim().isEmpty
              ? null
              : academicSession.text.trim(),
          'term': term,
          'weekStart': _dateFormat.format(weekStart),
          'weekEnd': _dateFormat.format(weekEnd),
          'breakdownId': selectedBreakdownId,
          'breakdownItemId': selectedBreakdownItemId,
          'topic': topic.text.trim(),
          'subtopic':
              subtopic.text.trim().isEmpty ? null : subtopic.text.trim(),
          'sectionIds': selectedSections,
          'sections': selectedSections,
          'language': 'en',
          'status': 'Pending',
          'completionStatus': completionStatus,
          'publish': publish,
        };

        final response = await _postAiLessonPlan(payload);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(
            _extractError(response.body, 'AI generation failed.'),
          );
        }

        final decoded = jsonDecode(response.body);
        final ai = _extractAiObject(decoded);
        final saved = _extractSavedPlan(decoded);
        final merged = <String, dynamic>{
          ...saved,
          ...ai,
        };

        bool didFill = false;

        setSheetState(() {
          didFill = _applyAiToControllers(
            merged,
            objectives: objectives,
            method: method,
            aids: aids,
            activities: activities,
            resources: resources,
            evaluationMethod: evaluationMethod,
            assessmentPlan: assessmentPlan,
            homework: homework,
            remedial: remedial,
            enrichment: enrichment,
            remarks: remarks,
            periods: periods,
          );

          final savedId = _toInt(
            saved['id'] ??
                saved['lessonPlanId'] ??
                merged['id'] ??
                merged['lessonPlanId'],
          );
          if (savedId != null) currentLessonPlanId = savedId;

          final savedPublish = saved['publish'] ??
              saved['published'] ??
              saved['isPublished'] ??
              merged['publish'] ??
              merged['published'];
          if (savedPublish != null) publish = _truthy(savedPublish);

          final savedCompletion =
              _safeStr(saved['completionStatus'] ?? merged['completionStatus']);
          if (savedCompletion.isNotEmpty) {
            completionStatus = _completionValue(savedCompletion);
          }

          aiFilled = didFill;
        });

        if (didFill) {
          _showSnack('AI generated the lesson plan. Please review and save.');
        } else {
          _showSnack(
            'AI request completed, but no fillable lesson plan fields were found in response.',
          );
        }

        await _loadPlans();
      } catch (e) {
        _showSnack(e.toString().replaceFirst('Exception: ', ''));
      } finally {
        if (mounted) setState(() => _aiBusy = false);
        setSheetState(() => _aiBusy = false);
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (metaLoading &&
                sheetSections.isEmpty &&
                breakdownItems.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                refreshMeta(setSheetState: setSheetState);
              });
            }

            Future<void> pickDate(bool start) async {
              final picked = await showDatePicker(
                context: context,
                initialDate: start ? weekStart : weekEnd,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
              );
              if (picked == null) return;

              setSheetState(() {
                if (start) {
                  weekStart = picked;
                  if (weekEnd.isBefore(weekStart)) {
                    weekEnd = weekStart.add(const Duration(days: 6));
                  }
                } else {
                  weekEnd = picked;
                }
                aiFilled = false;
              });
            }

            final allSelected = sheetSections.isNotEmpty &&
                sheetSections
                    .every((s) => selectedSections.contains(_toInt(s['id'])));

            return DraggableScrollableSheet(
              initialChildSize: 0.93,
              minChildSize: 0.58,
              maxChildSize: 0.97,
              builder: (_, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(26)),
                  ),
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
                        padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [_primary, _primary2],
                                ),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: const Icon(
                                Icons.auto_awesome_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isEdit
                                        ? 'Edit AI Lesson Plan'
                                        : 'Create AI Lesson Plan',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const Text(
                                    'Select basics, generate with AI, review and save',
                                    style: TextStyle(
                                      color: _muted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(sheetContext),
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
                            16 + MediaQuery.of(context).viewInsets.bottom,
                          ),
                          children: [
                            if (aiFilled) _aiInfoBanner(),
                            _sectionTitle('Basics'),
                            DropdownButtonFormField<Map<String, dynamic>>(
                              value: assignment,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Class & Subject *',
                                border: OutlineInputBorder(),
                              ),
                              items: _assignments.map((item) {
                                return DropdownMenuItem(
                                  value: item,
                                  child: Text(
                                    _classSubjectLabel(item),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) async {
                                setSheetState(() {
                                  assignment = value;
                                  selectedSections = [];
                                  selectedBreakdownItemId = null;
                                  selectedBreakdownId = null;
                                  topicOptions = [];
                                  subtopicOptions = [];
                                  aiFilled = false;
                                });
                                await refreshMeta(
                                  setSheetState: setSheetState,
                                  resetUnit: true,
                                );
                              },
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => pickDate(true),
                                    icon: const Icon(Icons.event_rounded),
                                    label: Text(_dateFormat.format(weekStart)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => pickDate(false),
                                    icon: const Icon(
                                      Icons.event_available_rounded,
                                    ),
                                    label: Text(_dateFormat.format(weekEnd)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: term,
                                    decoration: const InputDecoration(
                                      labelText: 'Term',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'FULL_YEAR',
                                        child: Text('Full Year'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'TERM1',
                                        child: Text('Term 1'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'TERM2',
                                        child: Text('Term 2'),
                                      ),
                                    ],
                                    onChanged: (value) async {
                                      setSheetState(() {
                                        term = value ?? term;
                                        selectedBreakdownItemId = null;
                                        selectedBreakdownId = null;
                                        topicOptions = [];
                                        subtopicOptions = [];
                                        aiFilled = false;
                                      });
                                      await refreshMeta(
                                        setSheetState: setSheetState,
                                        resetUnit: true,
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: academicSession,
                                    decoration: const InputDecoration(
                                      labelText: 'Session',
                                      hintText: '2026-27',
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (_) =>
                                        setSheetState(() => aiFilled = false),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _sectionTitle('Sections'),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: _softBox(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (metaLoading)
                                    const LinearProgressIndicator(minHeight: 2)
                                  else if (sheetSections.isEmpty)
                                    const Text(
                                      'No sections found for this class.',
                                      style: TextStyle(
                                        color: _muted,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  else ...[
                                    SwitchListTile(
                                      value: allSelected,
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'Select all sections',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      onChanged: (value) {
                                        setSheetState(() {
                                          if (value) {
                                            selectedSections = sheetSections
                                                .map((s) => _toInt(s['id']))
                                                .whereType<int>()
                                                .toSet()
                                                .toList();
                                          } else {
                                            selectedSections = [];
                                          }
                                          aiFilled = false;
                                        });
                                      },
                                    ),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: sheetSections.map((s) {
                                        final id = _toInt(s['id']);
                                        final label = _safeStr(
                                          s['section_name'] ?? s['name'] ?? id,
                                        );
                                        final selected = id != null &&
                                            selectedSections.contains(id);

                                        return FilterChip(
                                          label: Text(label),
                                          selected: selected,
                                          onSelected: id == null
                                              ? null
                                              : (value) {
                                                  setSheetState(() {
                                                    if (value) {
                                                      if (!selectedSections
                                                          .contains(id)) {
                                                        selectedSections
                                                            .add(id);
                                                      }
                                                    } else {
                                                      selectedSections
                                                          .remove(id);
                                                    }
                                                    aiFilled = false;
                                                  });
                                                },
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _sectionTitle('Syllabus Breakdown'),
                            DropdownButtonFormField<int>(
                              value: selectedBreakdownItemId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Unit / Breakdown Item',
                                border: OutlineInputBorder(),
                              ),
                              items: breakdownItems
                                  .map((item) {
                                    final id = _toInt(item['id']);
                                    final unitNo = _safeStr(item['unitNumber']);
                                    final title =
                                        _safeStr(item['unitTitle']).isEmpty
                                            ? 'Unit #$id'
                                            : _safeStr(item['unitTitle']);
                                    return DropdownMenuItem<int>(
                                      value: id,
                                      child: Text(
                                        unitNo.isEmpty
                                            ? title
                                            : '$unitNo - $title',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  })
                                  .where((x) => x.value != null)
                                  .toList(),
                              onChanged: (value) =>
                                  applyBreakdownItem(value, setSheetState),
                            ),
                            if (topicOptions.isNotEmpty ||
                                subtopicOptions.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _suggestionChips(
                                title: 'Topic suggestions',
                                values: topicOptions,
                                onTap: (v) => setSheetState(() {
                                  topic.text = v;
                                  aiFilled = false;
                                }),
                              ),
                              _suggestionChips(
                                title: 'Subtopic suggestions',
                                values: subtopicOptions,
                                onTap: (v) => setSheetState(() {
                                  subtopic.text = v;
                                  aiFilled = false;
                                }),
                              ),
                            ],
                            const SizedBox(height: 12),
                            _field(
                              topic,
                              'Topic *',
                              required: true,
                              onChanged: () =>
                                  setSheetState(() => aiFilled = false),
                            ),
                            _field(
                              subtopic,
                              'Subtopic',
                              onChanged: () =>
                                  setSheetState(() => aiFilled = false),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _aiBusy
                                        ? null
                                        : () => generateWithAi(
                                              sheetContext,
                                              setSheetState,
                                            ),
                                    icon: _aiBusy
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.auto_awesome_rounded,
                                          ),
                                    label: Text(
                                      _aiBusy
                                          ? 'Generating...'
                                          : 'Generate with AI',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _sectionTitle('Teaching Plan'),
                            _field(objectives, 'Specific Objectives',
                                maxLines: 4),
                            _field(method, 'Teaching Method', maxLines: 3),
                            _field(aids, 'Teaching Aids', maxLines: 3),
                            _field(activities, 'Activities', maxLines: 4),
                            _field(resources, 'Resources', maxLines: 3),
                            const SizedBox(height: 8),
                            _sectionTitle('Evaluation & Homework'),
                            _field(evaluationMethod, 'Evaluation Method',
                                maxLines: 3),
                            _field(assessmentPlan, 'Assessment Plan',
                                maxLines: 4),
                            _field(homework, 'Homework', maxLines: 3),
                            const SizedBox(height: 8),
                            _sectionTitle('Teacher Support'),
                            _field(remedial, 'Remedial Plan', maxLines: 3),
                            _field(enrichment, 'Enrichment Plan',
                                maxLines: 3),
                            _field(remarks, 'Remarks', maxLines: 3),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _completionValue(completionStatus),
                                    decoration: const InputDecoration(
                                      labelText: 'Completion',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'Planned',
                                        child: Text('Planned'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Partial',
                                        child: Text('Partial'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Completed',
                                        child: Text('Completed'),
                                      ),
                                    ],
                                    onChanged: (value) => setSheetState(
                                      () => completionStatus =
                                          value ?? completionStatus,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: periods,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Planned Periods',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SwitchListTile(
                              value: publish,
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Publish for students',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: const Text(
                                'Students will see only useful learning details.',
                              ),
                              onChanged: (value) =>
                                  setSheetState(() => publish = value),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: _saving
                                    ? null
                                    : () => _savePlan(
                                          id: currentLessonPlanId,
                                          assignment: assignment,
                                          term: term,
                                          weekStart: weekStart,
                                          weekEnd: weekEnd,
                                          academicSession:
                                              academicSession.text,
                                          breakdownId: selectedBreakdownId,
                                          breakdownItemId:
                                              selectedBreakdownItemId,
                                          topic: topic.text,
                                          subtopic: subtopic.text,
                                          objectives: objectives.text,
                                          method: method.text,
                                          aids: aids.text,
                                          activities: activities.text,
                                          resources: resources.text,
                                          evaluationMethod:
                                              evaluationMethod.text,
                                          assessmentPlan: assessmentPlan.text,
                                          homework: homework.text,
                                          remedial: remedial.text,
                                          enrichment: enrichment.text,
                                          remarks: remarks.text,
                                          periods: periods.text,
                                          completionStatus: completionStatus,
                                          publish: publish,
                                          sections: selectedSections,
                                          close: () =>
                                              Navigator.pop(sheetContext),
                                        ),
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
                                label: Text(
                                  _saving
                                      ? 'Saving...'
                                      : currentLessonPlanId != null
                                          ? 'Update Lesson Plan'
                                          : 'Save Lesson Plan',
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );

    topic.dispose();
    subtopic.dispose();
    objectives.dispose();
    method.dispose();
    aids.dispose();
    activities.dispose();
    resources.dispose();
    evaluationMethod.dispose();
    assessmentPlan.dispose();
    homework.dispose();
    remedial.dispose();
    enrichment.dispose();
    remarks.dispose();
    periods.dispose();
    academicSession.dispose();
  }

  Future<dynamic> _postAiLessonPlan(Map<String, dynamic> payload) async {
    dynamic lastResponse;

    // Your app normally calls API routes without "/api".
    // Some older backends still mounted the AI route with "/api", so we try both safely.
    for (final endpoint in const [
      '/ai/lesson-plan/generate',
      '/api/ai/lesson-plan/generate',
    ]) {
      final response = await ApiService.rawPost(endpoint, payload);
      lastResponse = response;

      if (response.statusCode == 404 || response.statusCode == 405) {
        continue;
      }

      return response;
    }

    return lastResponse;
  }

  bool _applyAiToControllers(
    Map<String, dynamic> ai, {
    required TextEditingController objectives,
    required TextEditingController method,
    required TextEditingController aids,
    required TextEditingController activities,
    required TextEditingController resources,
    required TextEditingController evaluationMethod,
    required TextEditingController assessmentPlan,
    required TextEditingController homework,
    required TextEditingController remedial,
    required TextEditingController enrichment,
    required TextEditingController remarks,
    required TextEditingController periods,
  }) {
    bool didFill = false;

    void setField(TextEditingController controller, List<String> keys) {
      final value = _pickDeep(ai, keys);
      final text = _textFromAiValue(value);
      if (text.trim().isNotEmpty) {
        controller.text = text.trim();
        didFill = true;
      }
    }

    setField(objectives, const [
      'specificObjectives',
      'specific_objectives',
      'objectives',
      'learningObjectives',
      'learning_objectives',
      'lessonObjectives',
      'lesson_objectives',
    ]);

    setField(method, const [
      'teachingMethod',
      'teaching_method',
      'method',
      'pedagogy',
      'instructionalStrategy',
      'instructional_strategy',
    ]);

    setField(aids, const [
      'teachingAids',
      'teaching_aids',
      'aids',
      'materials',
      'teachingMaterials',
      'teaching_materials',
    ]);

    setField(activities, const [
      'activities',
      'learningActivities',
      'learning_activities',
      'classroomActivities',
      'classroom_activities',
    ]);

    setField(resources, const [
      'resources',
      'resourceMaterial',
      'resource_material',
      'materialsRequired',
      'materials_required',
    ]);

    setField(evaluationMethod, const [
      'evaluationMethod',
      'evaluation_method',
      'evaluation',
      'checkingUnderstanding',
      'checking_understanding',
    ]);

    setField(assessmentPlan, const [
      'assessmentPlan',
      'assessment_plan',
      'assessmentMethods',
      'assessment_methods',
      'assessment',
      'formativeAssessment',
      'formative_assessment',
    ]);

    setField(homework, const [
      'homework',
      'homeWork',
      'home_assignment',
      'homeAssignment',
      'assignment',
    ]);

    setField(remedial, const [
      'remedialPlan',
      'remedial_plan',
      'remedial',
      'supportPlan',
      'support_plan',
    ]);

    setField(enrichment, const [
      'enrichmentPlan',
      'enrichment_plan',
      'enrichment',
      'extensionActivity',
      'extension_activity',
    ]);

    setField(remarks, const [
      'remarks',
      'notes',
      'teacherNotes',
      'teacher_notes',
    ]);

    final plannedPeriods = _pickDeep(ai, const [
      'plannedPeriods',
      'planned_periods',
      'periods',
      'numberOfPeriods',
      'number_of_periods',
    ]);

    final periodText = _textFromAiValue(plannedPeriods);
    if (periodText.trim().isNotEmpty) {
      periods.text = '${_toInt(periodText) ?? periodText.trim()}';
      didFill = true;
    }

    return didFill;
  }

  dynamic _pickDeep(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      if (source.containsKey(key) && source[key] != null) return source[key];

      final lowerKey = key.toLowerCase();
      for (final entry in source.entries) {
        if (entry.key.toLowerCase() == lowerKey && entry.value != null) {
          return entry.value;
        }
      }
    }

    for (final entry in source.entries) {
      final value = entry.value;
      if (value is Map) {
        final found = _pickDeep(Map<String, dynamic>.from(value), keys);
        if (found != null && _textFromAiValue(found).trim().isNotEmpty) {
          return found;
        }
      }
    }

    return null;
  }

  String _textFromAiValue(dynamic value) {
    if (value == null) return '';

    if (value is String) {
      final s = value.trim();
      if (s.isEmpty) return '';

      // Backend may return JSON text inside "content"/"response".
      if ((s.startsWith('{') && s.endsWith('}')) ||
          (s.startsWith('[') && s.endsWith(']'))) {
        try {
          final decoded = jsonDecode(s);
          return _textFromAiValue(decoded);
        } catch (_) {}
      }

      return s;
    }

    if (value is num || value is bool) return '$value';

    if (value is List) {
      final items = value.map(_textFromAiValue).where((x) => x.trim().isNotEmpty);
      return items.join('\n');
    }

    if (value is Map) {
      final map = Map<String, dynamic>.from(value);

      for (final key in const [
        'text',
        'value',
        'description',
        'content',
        'details',
        'points',
        'items',
      ]) {
        if (map[key] != null) {
          final s = _textFromAiValue(map[key]);
          if (s.trim().isNotEmpty) return s;
        }
      }

      final parts = <String>[];
      map.forEach((key, val) {
        final s = _textFromAiValue(val);
        if (s.trim().isNotEmpty) parts.add('${_titleize('$key')}: $s');
      });
      return parts.join('\n');
    }

    return '$value'.trim();
  }

  String _titleize(String key) {
    final spaced = key
        .replaceAll('_', ' ')
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .trim();

    if (spaced.isEmpty) return key;

    return spaced
        .split(RegExp(r'\s+'))
        .map((word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }

  DateTime? _parseDate(dynamic value) {
    final s = _safeStr(value);
    if (s.isEmpty) return null;

    try {
      return DateTime.parse(s.length >= 10 ? s.substring(0, 10) : s);
    } catch (_) {
      return null;
    }
  }

  String _completionValue(String value) {
    final s = value.trim().toLowerCase();
    if (s == 'completed') return 'Completed';
    if (s == 'partial' ||
        s == 'partially completed' ||
        s == 'partially_completed') {
      return 'Partial';
    }
    return 'Planned';
  }

  Map<String, dynamic> _extractAiObject(dynamic decoded) {
    if (decoded is! Map) return {};

    final root = Map<String, dynamic>.from(decoded);
    final queue = <Map<String, dynamic>>[root];
    final visited = <int>{};

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final identity = identityHashCode(current);
      if (visited.contains(identity)) continue;
      visited.add(identity);

      final normalized = _normalizeAiFields(current);
      if (normalized.isNotEmpty) return normalized;

      for (final key in const [
        'data',
        'ai',
        'draft',
        'generated',
        'lessonPlan',
        'lesson_plan',
        'plan',
        'record',
        'result',
        'response',
        'output',
        'content',
        'saved',
      ]) {
        final value = current[key];
        if (value is Map) {
          queue.add(Map<String, dynamic>.from(value));
        } else if (value is String) {
          final parsed = _tryDecodeMap(value);
          if (parsed.isNotEmpty) queue.add(parsed);
        }
      }
    }

    // Last fallback: normalize root after recursively flattening common payloads.
    return _normalizeAiFields(root);
  }

  Map<String, dynamic> _tryDecodeMap(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {};
  }

  Map<String, dynamic> _extractSavedPlan(dynamic decoded) {
    if (decoded is! Map) return {};

    final root = Map<String, dynamic>.from(decoded);

    for (final key in const [
      'lessonPlan',
      'lesson_plan',
      'plan',
      'saved',
      'record',
      'data',
    ]) {
      final value = root[key];

      if (value is Map) {
        final map = Map<String, dynamic>.from(value);

        for (final nestedKey in const [
          'lessonPlan',
          'lesson_plan',
          'plan',
          'saved',
          'record',
        ]) {
          final nested = map[nestedKey];
          if (nested is Map) return Map<String, dynamic>.from(nested);
        }

        if (map['id'] != null || map['lessonPlanId'] != null) return map;
      }
    }

    return root['id'] != null || root['lessonPlanId'] != null ? root : {};
  }

  Map<String, dynamic> _normalizeAiFields(Map<String, dynamic> source) {
    if (source.isEmpty) return {};

    dynamic pick(List<String> keys) => _pickDeep(source, keys);

    final normalized = <String, dynamic>{};

    void set(String key, List<String> aliases) {
      final value = pick(aliases);
      final text = _textFromAiValue(value);
      if (text.trim().isNotEmpty) normalized[key] = value;
    }

    set('specificObjectives', const [
      'specificObjectives',
      'specific_objectives',
      'objectives',
      'learningObjectives',
      'learning_objectives',
      'lessonObjectives',
      'lesson_objectives',
    ]);
    set('teachingMethod', const [
      'teachingMethod',
      'teaching_method',
      'method',
      'pedagogy',
      'instructionalStrategy',
      'instructional_strategy',
    ]);
    set('teachingAids', const [
      'teachingAids',
      'teaching_aids',
      'aids',
      'materials',
      'teachingMaterials',
      'teaching_materials',
    ]);
    set('activities', const [
      'activities',
      'learningActivities',
      'learning_activities',
      'classroomActivities',
      'classroom_activities',
    ]);
    set('resources', const [
      'resources',
      'resourceMaterial',
      'resource_material',
      'materialsRequired',
      'materials_required',
    ]);
    set('evaluationMethod', const [
      'evaluationMethod',
      'evaluation_method',
      'evaluation',
      'checkingUnderstanding',
      'checking_understanding',
    ]);
    set('assessmentPlan', const [
      'assessmentPlan',
      'assessment_plan',
      'assessmentMethods',
      'assessment_methods',
      'assessment',
      'formativeAssessment',
      'formative_assessment',
    ]);
    set('homework', const [
      'homework',
      'homeWork',
      'home_assignment',
      'homeAssignment',
      'assignment',
    ]);
    set('remedialPlan', const [
      'remedialPlan',
      'remedial_plan',
      'remedial',
      'supportPlan',
      'support_plan',
    ]);
    set('enrichmentPlan', const [
      'enrichmentPlan',
      'enrichment_plan',
      'enrichment',
      'extensionActivity',
      'extension_activity',
    ]);
    set('remarks', const [
      'remarks',
      'notes',
      'teacherNotes',
      'teacher_notes',
    ]);
    set('plannedPeriods', const [
      'plannedPeriods',
      'planned_periods',
      'periods',
      'numberOfPeriods',
      'number_of_periods',
    ]);

    return normalized;
  }

  List<int> _sectionIdsFromPlan(Map<String, dynamic>? plan) {
    if (plan == null) return [];

    final sections = plan['Sections'] ?? plan['sections'];
    if (sections is List) {
      return sections
          .map((x) => x is Map ? _toInt(x['id'] ?? x['sectionId']) : _toInt(x))
          .whereType<int>()
          .toSet()
          .toList();
    }

    final sectionIds = plan['sectionIds'] ?? plan['sectionsIds'];
    if (sectionIds is List) {
      return sectionIds.map(_toInt).whereType<int>().toSet().toList();
    }

    return [];
  }

  Widget _aiInfoBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: const Row(
        children: [
          Icon(Icons.auto_awesome_rounded, color: Color(0xFF2563EB)),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'AI content added. Please review before saving.',
              style: TextStyle(
                color: Color(0xFF1D4ED8),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionChips({
    required String title,
    required List<String> values,
    required ValueChanged<String> onTap,
  }) {
    if (values.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _muted,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: values
                .take(12)
                .map(
                  (v) => ActionChip(
                    label: Text(v, overflow: TextOverflow.ellipsis),
                    onPressed: () => onTap(v),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: _text,
          fontWeight: FontWeight.w900,
          fontSize: 15,
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    VoidCallback? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        onChanged: (_) => onChanged?.call(),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          border: const OutlineInputBorder(),
          alignLabelWithHint: maxLines > 1,
        ),
      ),
    );
  }

  Future<void> _savePlan({
    required int? id,
    required Map<String, dynamic>? assignment,
    required String term,
    required DateTime weekStart,
    required DateTime weekEnd,
    required String academicSession,
    required int? breakdownId,
    required int? breakdownItemId,
    required String topic,
    required String subtopic,
    required String objectives,
    required String method,
    required String aids,
    required String activities,
    required String resources,
    required String evaluationMethod,
    required String assessmentPlan,
    required String homework,
    required String remedial,
    required String enrichment,
    required String remarks,
    required String periods,
    required String completionStatus,
    required bool publish,
    required List<int> sections,
    required VoidCallback close,
  }) async {
    final classId = _classIdFromAssignment(assignment);
    final subjectId = _subjectIdFromAssignment(assignment);

    if (classId == null || subjectId == null || topic.trim().isEmpty) {
      _showSnack('Class, subject, and topic are required.');
      return;
    }

    final payload = <String, dynamic>{
      'classId': classId,
      'subjectId': subjectId,
      'academicSession':
          academicSession.trim().isEmpty ? null : academicSession.trim(),
      'term': term,
      'weekStart': _dateFormat.format(weekStart),
      'weekEnd': _dateFormat.format(weekEnd),
      'breakdownId': breakdownId,
      'breakdownItemId': breakdownItemId,
      'topic': topic.trim(),
      'subtopic': subtopic.trim().isEmpty ? null : subtopic.trim(),
      'specificObjectives':
          objectives.trim().isEmpty ? null : objectives.trim(),
      'objectives': objectives.trim().isEmpty ? null : objectives.trim(),
      'teachingMethod': method.trim().isEmpty ? null : method.trim(),
      'teachingAids': aids.trim().isEmpty ? null : aids.trim(),
      'activities': activities.trim().isEmpty ? null : activities.trim(),
      'resources': resources.trim().isEmpty ? null : resources.trim(),
      'evaluationMethod':
          evaluationMethod.trim().isEmpty ? null : evaluationMethod.trim(),
      'assessmentPlan':
          assessmentPlan.trim().isEmpty ? null : assessmentPlan.trim(),
      'assessmentMethods':
          assessmentPlan.trim().isEmpty ? null : assessmentPlan.trim(),
      'homework': homework.trim().isEmpty ? null : homework.trim(),
      'remedialPlan': remedial.trim().isEmpty ? null : remedial.trim(),
      'enrichmentPlan': enrichment.trim().isEmpty ? null : enrichment.trim(),
      'plannedPeriods': int.tryParse(periods.trim()),
      'status': 'Pending',
      'completionStatus': completionStatus,
      'remarks': remarks.trim().isEmpty ? null : remarks.trim(),
      'publish': publish,
      'isPublished': publish,
      'visibleToStudents': publish,
      'sections': sections,
      'sectionIds': sections,
    };

    if (mounted) setState(() => _saving = true);

    try {
      final response = id != null
          ? await ApiService.rawPut('/lesson-plans/$id', payload)
          : await ApiService.rawPost('/lesson-plans', payload);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          _extractError(response.body, 'Failed to save lesson plan'),
        );
      }

      close();
      _showSnack(
        id != null
            ? 'Lesson plan updated successfully'
            : 'Lesson plan created successfully',
      );
      await _loadPlans();
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deletePlan(Map<String, dynamic> plan) async {
    final id = _toInt(plan['id']);
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete lesson plan?'),
        content: const Text('This lesson plan will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await ApiService.rawDelete('/lesson-plans/$id');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          _extractError(response.body, 'Failed to delete lesson plan'),
        );
      }
      _showSnack('Lesson plan deleted');
      await _loadPlans();
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _togglePublish(Map<String, dynamic> plan) async {
    final id = _toInt(plan['id']);
    if (id == null) return;

    final next = !_isPublished(plan);

    try {
      final response = await ApiService.rawPut('/lesson-plans/$id', {
        'publish': next,
        'isPublished': next,
        'visibleToStudents': next,
      });

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          _extractError(response.body, 'Failed to update publish status'),
        );
      }

      _showSnack(next ? 'Published for students' : 'Hidden from students');
      await _loadPlans();
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _openViewSheet(Map<String, dynamic> plan) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.86,
          minChildSize: 0.50,
          maxChildSize: 0.95,
          builder: (_, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
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
                        const Expanded(
                          child: Text(
                            'Lesson Plan Details',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
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
                        _detailInfoCard(plan),
                        const SizedBox(height: 12),
                        _detailSection(
                          'Topic',
                          '${plan['topic'] ?? '-'}${_safeStr(plan['subtopic']).isEmpty ? '' : ' • ${plan['subtopic']}'}',
                          Icons.topic_rounded,
                        ),
                        _detailSection(
                          'Specific Objectives',
                          _safeStr(
                            plan['specificObjectives'] ?? plan['objectives'],
                          ),
                          Icons.flag_rounded,
                        ),
                        _detailSection(
                          'Teaching Method',
                          _safeStr(plan['teachingMethod']),
                          Icons.psychology_rounded,
                        ),
                        _detailSection(
                          'Teaching Aids',
                          _safeStr(plan['teachingAids']),
                          Icons.widgets_rounded,
                        ),
                        _detailSection(
                          'Activities',
                          _safeStr(plan['activities']),
                          Icons.extension_rounded,
                        ),
                        _detailSection(
                          'Resources',
                          _safeStr(plan['resources']),
                          Icons.library_books_rounded,
                        ),
                        _detailSection(
                          'Evaluation Method',
                          _safeStr(plan['evaluationMethod']),
                          Icons.fact_check_rounded,
                        ),
                        _detailSection(
                          'Assessment Plan',
                          _safeStr(
                            plan['assessmentPlan'] ??
                                plan['assessmentMethods'],
                          ),
                          Icons.assignment_turned_in_rounded,
                        ),
                        _detailSection(
                          'Homework',
                          _safeStr(plan['homework']),
                          Icons.home_work_rounded,
                        ),
                        _detailSection(
                          'Remedial Plan',
                          _safeStr(plan['remedialPlan']),
                          Icons.healing_rounded,
                        ),
                        _detailSection(
                          'Enrichment Plan',
                          _safeStr(plan['enrichmentPlan']),
                          Icons.auto_awesome_rounded,
                        ),
                        _detailSection(
                          'Remarks',
                          _safeStr(plan['remarks']),
                          Icons.notes_rounded,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _openEvaluations(plan);
                            },
                            icon: const Icon(Icons.quiz_rounded),
                            label: const Text('Lesson Plan Evaluations'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _openEditSheet(plan);
                                },
                                icon: const Icon(Icons.edit_rounded),
                                label: const Text('Edit'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _togglePublish(plan);
                                },
                                icon: Icon(
                                  _isPublished(plan)
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                ),
                                label: Text(
                                  _isPublished(plan)
                                      ? 'Unpublish'
                                      : 'Publish',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailInfoCard(Map<String, dynamic> plan) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _softBox(),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _pill(_planClassName(plan), const Color(0xFF2563EB)),
          _pill(_planSubjectName(plan), const Color(0xFF0F766E)),
          _pill(_friendlyTerm(_safeStr(plan['term'])), const Color(0xFF7C3AED)),
          _pill(
            '${_shortDate(plan['weekStart'])} - ${_shortDate(plan['weekEnd'])}',
            const Color(0xFF64748B),
          ),
          _pill(
            _safeStr(plan['completionStatus']).isEmpty
                ? 'Planned'
                : _safeStr(plan['completionStatus']),
            const Color(0xFFD97706),
          ),
          _pill(
            _isPublished(plan) ? 'Published' : 'Hidden',
            _isPublished(plan)
                ? const Color(0xFF16A34A)
                : const Color(0xFF64748B),
          ),
        ],
      ),
    );
  }

  Widget _detailSection(String title, String value, IconData icon) {
    final text = value.trim();
    if (text.isEmpty || text == '-') return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8ECF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: _primary.withOpacity(0.10),
                child: Icon(icon, color: _primary, size: 18),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: const TextStyle(
              height: 1.45,
              color: Color(0xFF374151),
              fontSize: 13.2,
            ),
          ),
        ],
      ),
    );
  }

  String _extractError(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final message = decoded['message'] ??
            decoded['error'] ??
            decoded['details'] ??
            decoded['sqlMessage'];
        if (message != null && '$message'.trim().isNotEmpty) return '$message';
      }
    } catch (_) {}

    if (body.trim().isNotEmpty && body.length < 180) return body;
    return fallback;
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plans = _filteredPlans;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('AI Lesson Plans'),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateSheet,
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.auto_awesome_rounded),
        label: const Text('Create with AI'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        color: _primary,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _primary))
            : ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _headerCard(),
                  const SizedBox(height: 12),
                  _filterCard(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'My Lesson Plans',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: _text,
                          ),
                        ),
                      ),
                      _pill('${plans.length} found', _primary),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (plans.isEmpty) _emptyCard() else ...plans.map(_planCard),
                  const SizedBox(height: 88),
                ],
              ),
      ),
    );
  }

  Widget _headerCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_primary, _primary2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.22),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -34,
            top: -40,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.11),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.17),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  color: Colors.white,
                  size: 31,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI Powered Lesson Planning',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_plans.length} plans • ${_assignments.length} class-subject assignments',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.86),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: const [
                        _HeroChip(
                          icon: Icons.auto_awesome_rounded,
                          label: 'AI Generate',
                        ),
                        _HeroChip(
                          icon: Icons.fact_check_rounded,
                          label: 'Review & Save',
                        ),
                        _HeroChip(
                          icon: Icons.visibility_rounded,
                          label: 'Publish',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterCard() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          TextField(
            onChanged: (value) => setState(() => _search = value),
            decoration: InputDecoration(
              hintText: 'Search topic, class, subject...',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: const Color(0xFFF8FAFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _termChip('ALL', 'All'),
                _termChip('FULL_YEAR', 'Full Year'),
                _termChip('TERM1', 'Term 1'),
                _termChip('TERM2', 'Term 2'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _termChip(String value, String label) {
    final selected = _filterTerm == value;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        label: Text(label),
        selectedColor: _primary.withOpacity(0.14),
        labelStyle: TextStyle(
          color: selected ? _primary : _muted,
          fontWeight: FontWeight.w900,
        ),
        side: BorderSide(
          color:
              selected ? _primary.withOpacity(0.38) : const Color(0xFFE5E7EB),
        ),
        onSelected: (_) => setState(() => _filterTerm = value),
      ),
    );
  }

  Widget _emptyCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 48,
            color: Colors.grey.shade500,
          ),
          const SizedBox(height: 12),
          const Text(
            'No lesson plans found.',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap “Create with AI” to generate your first lesson plan.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _openCreateSheet,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Create with AI'),
          ),
        ],
      ),
    );
  }

  Widget _planCard(Map<String, dynamic> plan) {
    final id = _toInt(plan['id']);
    final title = _safeStr(plan['topic']).isEmpty
        ? 'Untitled lesson'
        : _safeStr(plan['topic']);
    final subtopic = _safeStr(plan['subtopic']);
    final completion = _safeStr(plan['completionStatus']).isEmpty
        ? 'Planned'
        : _safeStr(plan['completionStatus']);
    final status =
        _safeStr(plan['status']).isEmpty ? 'Pending' : _safeStr(plan['status']);
    final published = _isPublished(plan);

    return InkWell(
      onTap: () => _openViewSheet(plan),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_primary, _primary2],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _planSubjectName(plan),
                        style: const TextStyle(
                          color: _primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtopic.isEmpty ? title : '$title • $subtopic',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _text,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${_planClassName(plan)} • ${_shortDate(plan['weekStart'])} - ${_shortDate(plan['weekEnd'])}',
                        style: const TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'view') _openViewSheet(plan);
                    if (value == 'edit') _openEditSheet(plan);
                    if (value == 'evaluations') _openEvaluations(plan);
                    if (value == 'publish') _togglePublish(plan);
                    if (value == 'delete') _deletePlan(plan);
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'view', child: Text('View')),
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(
                      value: 'evaluations',
                      child: Text('Evaluations'),
                    ),
                    PopupMenuItem(
                      value: 'publish',
                      child: Text(published ? 'Unpublish' : 'Publish'),
                    ),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _pill(status, _statusColor(status)),
                _pill(completion, const Color(0xFF0F766E)),
                _pill(
                  _friendlyTerm(_safeStr(plan['term'])),
                  const Color(0xFF7C3AED),
                ),
                _pill(
                  published ? 'Published' : 'Hidden',
                  published
                      ? const Color(0xFF16A34A)
                      : const Color(0xFF64748B),
                ),
              ],
            ),
            if (_safeStr(plan['homework']).isNotEmpty) ...[
              const SizedBox(height: 11),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.home_work_outlined,
                      color: Color(0xFFD97706),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _safeStr(plan['homework']),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF92400E),
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (id != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openEditSheet(plan),
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openEvaluations(plan),
                      icon: const Icon(Icons.quiz_rounded, size: 18),
                      label: const Text('Evaluate'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _togglePublish(plan),
                      icon: Icon(
                        published
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 18,
                      ),
                      label: Text(published ? 'Hide' : 'Publish'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openViewSheet(plan),
                      icon: const Icon(Icons.visibility_rounded, size: 18),
                      label: const Text('View'),
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

  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('complete') || s.contains('approved')) {
      return const Color(0xFF16A34A);
    }
    if (s.contains('progress') || s.contains('submitted')) {
      return const Color(0xFFD97706);
    }
    if (s.contains('return')) return const Color(0xFFDC2626);
    return const Color(0xFF64748B);
  }

  String _friendlyTerm(String term) {
    final t = term.trim().toUpperCase();

    if (t == 'TERM1') return 'Term 1';
    if (t == 'TERM2') return 'Term 2';
    if (t == 'FULL_YEAR') return 'Full Year';

    return term.trim().isEmpty ? 'Term' : term;
  }

  String _shortDate(dynamic value) {
    final text = _safeStr(value);
    if (text.length >= 10) return text.substring(0, 10);
    return text.isEmpty ? '-' : text;
  }

  Widget _pill(String label, Color color) {
    final safeLabel = label.trim().isEmpty ? '-' : label.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Text(
        safeLabel,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE8ECF5)),
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
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5E7EB)),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}