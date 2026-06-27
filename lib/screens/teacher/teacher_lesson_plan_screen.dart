import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';

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
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _assignments = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await Future.wait([_loadPlans(), _loadAssignments()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPlans() async {
    try {
      final response = await ApiService.rawGet('/lesson-plans');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (mounted) setState(() => _plans = _asMapList(decoded));
      }
    } catch (_) {}
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
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> _asMapList(dynamic decoded) {
    final raw = decoded is List
        ? decoded
        : decoded is Map
            ? (decoded['data'] ??
                decoded['rows'] ??
                decoded['lessonPlans'] ??
                [])
            : [];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _nestedName(Map<String, dynamic> row, String key, List<String> names) {
    final nested = row[key];
    if (nested is Map) {
      for (final name in names) {
        final value = nested[name];
        if (value != null && '$value'.trim().isNotEmpty) return '$value';
      }
    }
    for (final name in names) {
      final value = row[name];
      if (value != null && '$value'.trim().isNotEmpty) return '$value';
    }
    return '-';
  }

  Future<void> _openCreateSheet() async {
    if (_assignments.isEmpty) {
      _showSnack('No class-subject assignment found for this teacher.');
      return;
    }

    final topic = TextEditingController();
    final objectives = TextEditingController();
    final method = TextEditingController();
    final aids = TextEditingController();
    final activities = TextEditingController();
    final homework = TextEditingController();
    final periods = TextEditingController();

    Map<String, dynamic>? assignment = _assignments.first;
    DateTime weekStart = DateTime.now();
    DateTime weekEnd = DateTime.now().add(const Duration(days: 6));
    String term = 'FULL_YEAR';
    String completionStatus = 'Planned';
    bool publish = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
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
                } else {
                  weekEnd = picked;
                }
              });
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.9,
              minChildSize: 0.55,
              maxChildSize: 0.96,
              builder: (_, scrollController) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(22)),
                  ),
                  child: ListView(
                    controller: scrollController,
                    children: [
                      const Text(
                        'Create Lesson Plan',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<Map<String, dynamic>>(
                        value: assignment,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Class & Subject',
                          border: OutlineInputBorder(),
                        ),
                        items: _assignments.map((item) {
                          final cls = _nestedName(
                              item, 'class', const ['class_name', 'name']);
                          final sub = _nestedName(
                              item, 'subject', const ['name', 'subject_name']);
                          return DropdownMenuItem(
                            value: item,
                            child: Text('$cls - $sub',
                                overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (value) =>
                            setSheetState(() => assignment = value),
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
                              icon: const Icon(Icons.event_available_rounded),
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
                              onChanged: (value) =>
                                  setSheetState(() => term = value ?? term),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: completionStatus,
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
                              onChanged: (value) => setSheetState(() =>
                                  completionStatus = value ?? completionStatus),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _field(topic, 'Topic', required: true),
                      _field(objectives, 'Specific Objectives', maxLines: 3),
                      _field(method, 'Teaching Method', maxLines: 2),
                      _field(aids, 'Teaching Aids'),
                      _field(activities, 'Activities', maxLines: 2),
                      _field(homework, 'Homework'),
                      _field(
                        periods,
                        'Planned Periods',
                        keyboardType: TextInputType.number,
                      ),
                      SwitchListTile(
                        value: publish,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Publish'),
                        onChanged: (value) =>
                            setSheetState(() => publish = value),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _savePlan(
                                    assignment: assignment,
                                    term: term,
                                    weekStart: weekStart,
                                    weekEnd: weekEnd,
                                    topic: topic.text,
                                    objectives: objectives.text,
                                    method: method.text,
                                    aids: aids.text,
                                    activities: activities.text,
                                    homework: homework.text,
                                    periods: periods.text,
                                    completionStatus: completionStatus,
                                    publish: publish,
                                    close: () => Navigator.pop(sheetContext),
                                  ),
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save_rounded),
                          label: const Text('Save Lesson Plan'),
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
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Future<void> _savePlan({
    required Map<String, dynamic>? assignment,
    required String term,
    required DateTime weekStart,
    required DateTime weekEnd,
    required String topic,
    required String objectives,
    required String method,
    required String aids,
    required String activities,
    required String homework,
    required String periods,
    required String completionStatus,
    required bool publish,
    required VoidCallback close,
  }) async {
    if (assignment == null || topic.trim().isEmpty) {
      _showSnack('Class, subject, and topic are required.');
      return;
    }

    final classObj =
        assignment['class'] is Map ? assignment['class'] as Map : {};
    final subjectObj =
        assignment['subject'] is Map ? assignment['subject'] as Map : {};

    final payload = {
      'classId': assignment['classId'] ??
          assignment['class_id'] ??
          classObj['id'] ??
          assignment['ClassId'],
      'subjectId': assignment['subjectId'] ??
          assignment['subject_id'] ??
          subjectObj['id'] ??
          assignment['SubjectId'],
      'academicSession': '',
      'term': term,
      'weekStart': _dateFormat.format(weekStart),
      'weekEnd': _dateFormat.format(weekEnd),
      'topic': topic.trim(),
      'specificObjectives':
          objectives.trim().isEmpty ? null : objectives.trim(),
      'teachingMethod': method.trim().isEmpty ? null : method.trim(),
      'teachingAids': aids.trim().isEmpty ? null : aids.trim(),
      'activities': activities.trim().isEmpty ? null : activities.trim(),
      'homework': homework.trim().isEmpty ? null : homework.trim(),
      'plannedPeriods': int.tryParse(periods.trim()),
      'status': 'Draft',
      'completionStatus': completionStatus,
      'publish': publish,
      'sections': <int>[],
    };

    setState(() => _saving = true);
    try {
      final response = await ApiService.rawPost('/lesson-plans', payload);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
            _extractError(response.body, 'Failed to save lesson plan'));
      }
      close();
      _showSnack('Lesson plan created successfully');
      await _loadPlans();
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
      appBar: AppBar(title: const Text('Lesson Plan')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Create'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _headerCard(),
                  const SizedBox(height: 12),
                  if (_plans.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No lesson plans yet.')),
                    )
                  else
                    ..._plans.map(_planCard),
                  const SizedBox(height: 88),
                ],
              ),
      ),
    );
  }

  Widget _headerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.menu_book_rounded, color: Colors.white, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Lesson Planning',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                Text(
                  '${_plans.length} plans • ${_assignments.length} class-subject assignments',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard(Map<String, dynamic> plan) {
    final title = '${plan['topic'] ?? 'Untitled lesson'}';
    final status = '${plan['status'] ?? 'Draft'}';
    final completion =
        '${plan['completionStatus'] ?? plan['completion_status'] ?? 'Planned'}';
    final cls = _nestedName(plan, 'Class', const ['class_name', 'name']);
    final subject =
        _nestedName(plan, 'Subject', const ['name', 'subject_name']);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              _pill(status, const Color(0xFF2563EB)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$cls • $subject',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _pill(completion, const Color(0xFF0F766E)),
              _pill('${plan['term'] ?? 'FULL_YEAR'}', const Color(0xFF7C3AED)),
              _pill(
                '${_shortDate(plan['weekStart'])} - ${_shortDate(plan['weekEnd'])}',
                const Color(0xFF64748B),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _shortDate(dynamic value) {
    final text = '${value ?? ''}';
    if (text.length >= 10) return text.substring(0, 10);
    return text.isEmpty ? '-' : text;
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}
