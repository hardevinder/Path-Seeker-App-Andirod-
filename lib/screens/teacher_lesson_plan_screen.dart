// lib/screens/teacher/teacher_lesson_plan_screen.dart
// AI powered mobile Lesson Plan screen for Teacher login.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/lesson_plan_models.dart';
import '../../services/lesson_plan_api.dart';
import '../../widgets/teacher_drawer_menu.dart';

class TeacherLessonPlanScreen extends StatefulWidget {
  const TeacherLessonPlanScreen({super.key});

  @override
  State<TeacherLessonPlanScreen> createState() =>
      _TeacherLessonPlanScreenState();
}

class _TeacherLessonPlanScreenState extends State<TeacherLessonPlanScreen> {
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  List<LessonPlan> _plans = <LessonPlan>[];
  List<LessonAssignment> _assignments = <LessonAssignment>[];

  int? _filterClassId;
  int? _filterSubjectId;
  String _filterTerm = '';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (mounted) setState(() => _loading = true);
    try {
      final result = await Future.wait([
        LessonPlanApi.fetchLessonPlans(),
        LessonPlanApi.fetchTeacherAssignments(),
      ]);
      if (!mounted) return;
      setState(() {
        _plans = result[0] as List<LessonPlan>;
        _assignments = result[1] as List<LessonAssignment>;
      });
    } catch (e) {
      _showSnack(_cleanError(e), isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<LessonPlan> get _filteredPlans {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _plans.where((p) {
      if (_filterClassId != null && p.classId != _filterClassId) return false;
      if (_filterSubjectId != null && p.subjectId != _filterSubjectId) {
        return false;
      }
      if (_filterTerm.isNotEmpty && p.term != _filterTerm) return false;
      if (q.isEmpty) return true;
      final blob = '${p.topic} ${p.subtopic} ${p.className} ${p.subjectName} '
              '${p.status} ${p.completionStatus}'
          .toLowerCase();
      return blob.contains(q);
    }).toList();
  }

  List<LessonAssignment> get _uniqueClassAssignments {
    final seen = <int>{};
    return _assignments.where((a) {
      final id = a.classId;
      if (id == null || seen.contains(id)) return false;
      seen.add(id);
      return true;
    }).toList();
  }

  List<LessonAssignment> get _uniqueSubjectAssignments {
    final seen = <int>{};
    return _assignments.where((a) {
      final id = a.subjectId;
      if (id == null || seen.contains(id)) return false;
      seen.add(id);
      return true;
    }).toList();
  }

  Future<void> _openCreateSheet() async {
    if (_assignments.isEmpty) {
      _showSnack('No class-subject assignment found for this teacher.',
          isError: true);
      return;
    }
    await _openLessonPlanSheet();
  }

  Future<void> _openEditSheet(LessonPlan plan) async {
    try {
      setState(() => _busy = true);
      final full = plan.id == null
          ? plan
          : await LessonPlanApi.fetchLessonPlanById(plan.id!);
      if (!mounted) return;
      await _openLessonPlanSheet(existing: full);
    } catch (e) {
      _showSnack(_cleanError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openLessonPlanSheet({LessonPlan? existing}) async {
    final isEdit = existing?.id != null;
    final formKey = GlobalKey<FormState>();

    LessonAssignment? selectedAssignment = _assignmentForPlan(existing) ??
        (_assignments.isNotEmpty ? _assignments.first : null);

    int? editingId = existing?.id;
    int? classId = existing?.classId ?? selectedAssignment?.classId;
    int? subjectId = existing?.subjectId ?? selectedAssignment?.subjectId;
    int? breakdownId = existing?.breakdownId;
    int? breakdownItemId = existing?.breakdownItemId;

    DateTime weekStart = _parseDate(existing?.weekStart) ?? DateTime.now();
    DateTime weekEnd = _parseDate(existing?.weekEnd) ??
        DateTime.now().add(const Duration(days: 6));
    String term = existing?.term.isNotEmpty == true ? existing!.term : 'FULL_YEAR';
    String status = existing?.status.isNotEmpty == true ? existing!.status : 'Draft';
    String completionStatus = existing?.completionStatus.isNotEmpty == true
        ? existing!.completionStatus
        : 'Planned';
    bool publish = existing?.publish ?? false;
    bool saving = false;
    bool aiBusy = false;
    bool aiFilled = false;
    bool loadingMeta = false;
    bool metaRequested = false;

    List<LessonSection> sections = <LessonSection>[];
    List<int> selectedSectionIds = List<int>.from(existing?.sectionIds ?? []);
    List<BreakdownItem> breakdownItems = <BreakdownItem>[];
    List<String> topicOptions = <String>[];
    List<String> subtopicOptions = <String>[];

    final sessionCtrl = TextEditingController(text: existing?.academicSession ?? '');
    final topicCtrl = TextEditingController(text: existing?.topic ?? '');
    final subtopicCtrl = TextEditingController(text: existing?.subtopic ?? '');
    final objectivesCtrl = TextEditingController(text: existing?.specificObjectives ?? '');
    final methodCtrl = TextEditingController(text: existing?.teachingMethod ?? '');
    final aidsCtrl = TextEditingController(text: existing?.teachingAids ?? '');
    final activitiesCtrl = TextEditingController(text: existing?.activities ?? '');
    final resourcesCtrl = TextEditingController(text: existing?.resources ?? '');
    final evalCtrl = TextEditingController(text: existing?.evaluationMethod ?? '');
    final assessmentCtrl = TextEditingController(text: existing?.assessmentPlan ?? '');
    final homeworkCtrl = TextEditingController(text: existing?.homework ?? '');
    final remedialCtrl = TextEditingController(text: existing?.remedialPlan ?? '');
    final enrichmentCtrl = TextEditingController(text: existing?.enrichmentPlan ?? '');
    final periodsCtrl = TextEditingController(
      text: existing?.plannedPeriods == null ? '' : '${existing!.plannedPeriods}',
    );
    final remarksCtrl = TextEditingController(text: existing?.remarks ?? '');

    Future<void> loadMeta(StateSetter setSheetState) async {
      if (classId == null) return;
      setSheetState(() {
        loadingMeta = true;
        metaRequested = true;
      });
      try {
        final sec = await LessonPlanApi.fetchSectionsForClass(classId!);
        List<BreakdownItem> items = <BreakdownItem>[];
        if (subjectId != null) {
          items = await LessonPlanApi.fetchBreakdownItemsForPlan(
            classId: classId!,
            subjectId: subjectId!,
            term: term,
            academicSession: sessionCtrl.text,
          );
        }

        final selectedItem = items.where((e) => e.id == breakdownItemId).toList();
        final item = selectedItem.isNotEmpty ? selectedItem.first : null;

        setSheetState(() {
          sections = sec;
          breakdownItems = items;
          topicOptions = item?.topics ?? <String>[];
          subtopicOptions = item?.subtopics ?? <String>[];
          if (item != null) breakdownId = item.breakdownId;
        });
      } catch (e) {
        _showSnack(_cleanError(e), isError: true);
      } finally {
        setSheetState(() => loadingMeta = false);
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (!metaRequested && classId != null && !loadingMeta) {
              Future.microtask(() => loadMeta(setSheetState));
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

            Future<void> generateAi() async {
              if (classId == null || subjectId == null) {
                _showSnack('Please select class and subject first.',
                    isError: true);
                return;
              }
              if (topicCtrl.text.trim().isEmpty) {
                _showSnack('Please select or type topic first.', isError: true);
                return;
              }
              setSheetState(() => aiBusy = true);
              try {
                final draft = await LessonPlanApi.generateWithAi(
                  lessonPlanId: editingId,
                  classId: classId!,
                  subjectId: subjectId!,
                  term: term,
                  weekStart: _dateFormat.format(weekStart),
                  weekEnd: _dateFormat.format(weekEnd),
                  breakdownId: breakdownId,
                  breakdownItemId: breakdownItemId,
                  academicSession: sessionCtrl.text,
                  topic: topicCtrl.text,
                  subtopic: subtopicCtrl.text,
                  sectionIds: selectedSectionIds,
                  status: status,
                  completionStatus: completionStatus,
                  publish: publish,
                );

                setSheetState(() {
                  if (draft.lessonPlanId != null) editingId = draft.lessonPlanId;
                  if (draft.specificObjectives.isNotEmpty) {
                    objectivesCtrl.text = draft.specificObjectives;
                  }
                  if (draft.teachingMethod.isNotEmpty) {
                    methodCtrl.text = draft.teachingMethod;
                  }
                  if (draft.teachingAids.isNotEmpty) aidsCtrl.text = draft.teachingAids;
                  if (draft.activities.isNotEmpty) activitiesCtrl.text = draft.activities;
                  if (draft.resources.isNotEmpty) resourcesCtrl.text = draft.resources;
                  if (draft.evaluationMethod.isNotEmpty) {
                    evalCtrl.text = draft.evaluationMethod;
                  }
                  if (draft.assessmentPlan.isNotEmpty) {
                    assessmentCtrl.text = draft.assessmentPlan;
                  }
                  if (draft.homework.isNotEmpty) homeworkCtrl.text = draft.homework;
                  if (draft.remedialPlan.isNotEmpty) remedialCtrl.text = draft.remedialPlan;
                  if (draft.enrichmentPlan.isNotEmpty) {
                    enrichmentCtrl.text = draft.enrichmentPlan;
                  }
                  if (draft.remarks.isNotEmpty) remarksCtrl.text = draft.remarks;
                  if (draft.plannedPeriods != null) {
                    periodsCtrl.text = '${draft.plannedPeriods}';
                  }
                  aiFilled = true;
                });
                _showSnack('✨ AI filled your lesson plan. Review and save.');
              } catch (e) {
                _showSnack(_cleanError(e), isError: true);
              } finally {
                setSheetState(() => aiBusy = false);
              }
            }

            Future<void> savePlan() async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              if (classId == null || subjectId == null) {
                _showSnack('Class and subject are required.', isError: true);
                return;
              }
              if (weekEnd.isBefore(weekStart)) {
                _showSnack('Week end cannot be before week start.', isError: true);
                return;
              }

              final plan = LessonPlan(
                id: editingId,
                classId: classId,
                subjectId: subjectId,
                breakdownId: breakdownId,
                breakdownItemId: breakdownItemId,
                academicSession: sessionCtrl.text,
                term: term,
                weekStart: _dateFormat.format(weekStart),
                weekEnd: _dateFormat.format(weekEnd),
                topic: topicCtrl.text,
                subtopic: subtopicCtrl.text,
                specificObjectives: objectivesCtrl.text,
                teachingMethod: methodCtrl.text,
                teachingAids: aidsCtrl.text,
                activities: activitiesCtrl.text,
                resources: resourcesCtrl.text,
                evaluationMethod: evalCtrl.text,
                assessmentPlan: assessmentCtrl.text,
                homework: homeworkCtrl.text,
                remedialPlan: remedialCtrl.text,
                enrichmentPlan: enrichmentCtrl.text,
                plannedPeriods: int.tryParse(periodsCtrl.text.trim()),
                status: status,
                completionStatus: completionStatus,
                remarks: remarksCtrl.text,
                publish: publish,
                sectionIds: selectedSectionIds,
                className: selectedAssignment?.className ?? '',
                subjectName: selectedAssignment?.subjectName ?? '',
              );

              setSheetState(() => saving = true);
              try {
                await LessonPlanApi.saveLessonPlan(plan);
                if (!mounted) return;
                Navigator.of(sheetContext).pop();
                _showSnack(isEdit ? 'Lesson plan updated' : 'Lesson plan created');
                await _loadAll();
              } catch (e) {
                _showSnack(_cleanError(e), isError: true);
              } finally {
                setSheetState(() => saving = false);
              }
            }

            final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

            return DraggableScrollableSheet(
              initialChildSize: 0.94,
              minChildSize: 0.55,
              maxChildSize: 0.98,
              builder: (_, scrollController) {
                return Container(
                  padding: EdgeInsets.only(bottom: bottomPadding),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                  ),
                  child: Form(
                    key: formKey,
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
                      children: [
                        _sheetHandle(),
                        _editorHeader(
                          title: isEdit ? 'Edit Lesson Plan' : 'Create Lesson Plan',
                          subtitle:
                              'Select syllabus topic, generate AI draft, review and save.',
                          aiFilled: aiFilled,
                        ),
                        const SizedBox(height: 14),
                        _panel(
                          title: 'Basics',
                          icon: Icons.tune_rounded,
                          child: Column(
                            children: [
                              DropdownButtonFormField<LessonAssignment>(
                                value: selectedAssignment,
                                isExpanded: true,
                                decoration: _inputDecoration('Class & Subject *'),
                                items: _assignments.map((a) {
                                  return DropdownMenuItem(
                                    value: a,
                                    child: Text(
                                      a.label,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                validator: (value) => value == null
                                    ? 'Please select class and subject'
                                    : null,
                                onChanged: saving || aiBusy
                                    ? null
                                    : (value) async {
                                        if (value == null) return;
                                        setSheetState(() {
                                          selectedAssignment = value;
                                          classId = value.classId;
                                          subjectId = value.subjectId;
                                          breakdownId = null;
                                          breakdownItemId = null;
                                          breakdownItems = <BreakdownItem>[];
                                          topicOptions = <String>[];
                                          subtopicOptions = <String>[];
                                          selectedSectionIds = <int>[];
                                          metaRequested = false;
                                          topicCtrl.clear();
                                          subtopicCtrl.clear();
                                          aiFilled = false;
                                        });
                                        await loadMeta(setSheetState);
                                      },
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _dateButton(
                                      label: 'Week Start',
                                      value: _dateFormat.format(weekStart),
                                      onTap: saving || aiBusy
                                          ? null
                                          : () => pickDate(true),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _dateButton(
                                      label: 'Week End',
                                      value: _dateFormat.format(weekEnd),
                                      onTap: saving || aiBusy
                                          ? null
                                          : () => pickDate(false),
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
                                      decoration: _inputDecoration('Term'),
                                      items: _termOptions
                                          .map(
                                            (e) => DropdownMenuItem(
                                              value: e.value,
                                              child: Text(e.label),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: saving || aiBusy
                                          ? null
                                          : (value) async {
                                              setSheetState(() {
                                                term = value ?? term;
                                                metaRequested = false;
                                                aiFilled = false;
                                              });
                                              await loadMeta(setSheetState);
                                            },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextFormField(
                                      controller: sessionCtrl,
                                      decoration:
                                          _inputDecoration('Session e.g. 2026-27'),
                                      onChanged: (_) => aiFilled = false,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _panel(
                          title: 'Applicable Sections',
                          icon: Icons.groups_rounded,
                          trailing: loadingMeta
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : null,
                          child: _sectionsPicker(
                            sections: sections,
                            selected: selectedSectionIds,
                            onChanged: saving || aiBusy
                                ? null
                                : (ids) {
                                    setSheetState(() {
                                      selectedSectionIds = ids;
                                      aiFilled = false;
                                    });
                                  },
                          ),
                        ),
                        const SizedBox(height: 12),
                        _panel(
                          title: 'Syllabus Breakdown',
                          icon: Icons.account_tree_rounded,
                          child: Column(
                            children: [
                              DropdownButtonFormField<int>(
                                value: breakdownItems.any((e) => e.id == breakdownItemId)
                                    ? breakdownItemId
                                    : null,
                                isExpanded: true,
                                decoration: _inputDecoration(
                                  breakdownItems.isEmpty
                                      ? 'No unit found / select class subject first'
                                      : 'Unit / Breakdown Item',
                                ),
                                items: breakdownItems.map((item) {
                                  return DropdownMenuItem(
                                    value: item.id,
                                    child: Text(item.label,
                                        overflow: TextOverflow.ellipsis),
                                  );
                                }).toList(),
                                onChanged: saving || aiBusy
                                    ? null
                                    : (value) {
                                        final matches = breakdownItems
                                            .where((e) => e.id == value)
                                            .toList();
                                        final item = matches.isEmpty
                                            ? null
                                            : matches.first;
                                        setSheetState(() {
                                          breakdownItemId = value;
                                          breakdownId = item?.breakdownId;
                                          topicOptions = item?.topics ?? <String>[];
                                          subtopicOptions = item?.subtopics ?? <String>[];
                                          topicCtrl.clear();
                                          subtopicCtrl.clear();
                                          aiFilled = false;
                                        });
                                      },
                              ),
                              const SizedBox(height: 10),
                              _topicField(
                                controller: topicCtrl,
                                label: 'Topic *',
                                options: topicOptions,
                                onSelected: () => setSheetState(() => aiFilled = false),
                              ),
                              const SizedBox(height: 10),
                              _topicField(
                                controller: subtopicCtrl,
                                label: 'Subtopic',
                                options: subtopicOptions,
                                isRequired: false,
                                onSelected: () => setSheetState(() => aiFilled = false),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _aiBanner(onGenerate: saving || aiBusy ? null : generateAi, busy: aiBusy),
                        const SizedBox(height: 12),
                        _panel(
                          title: 'Teaching Plan',
                          icon: Icons.psychology_alt_rounded,
                          child: Column(
                            children: [
                              _textField(objectivesCtrl, 'Specific Objectives',
                                  maxLines: 3),
                              _textField(methodCtrl, 'Teaching Method', maxLines: 2),
                              _textField(aidsCtrl, 'Teaching Aids'),
                              _textField(activitiesCtrl, 'Activities', maxLines: 3),
                              _textField(resourcesCtrl, 'Resources', maxLines: 2),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _panel(
                          title: 'Evaluation & Homework',
                          icon: Icons.assignment_turned_in_rounded,
                          child: Column(
                            children: [
                              _textField(evalCtrl, 'Evaluation Method'),
                              _textField(assessmentCtrl, 'Assessment Plan', maxLines: 2),
                              _textField(homeworkCtrl, 'Homework', maxLines: 2),
                              _textField(remedialCtrl, 'Remedial Plan', maxLines: 2),
                              _textField(enrichmentCtrl, 'Enrichment Plan', maxLines: 2),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _panel(
                          title: 'Workflow',
                          icon: Icons.verified_rounded,
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      value: status,
                                      decoration: _inputDecoration('Status'),
                                      items: const ['Draft', 'Submitted', 'Approved', 'Returned']
                                          .map((e) => DropdownMenuItem(
                                                value: e,
                                                child: Text(e),
                                              ))
                                          .toList(),
                                      onChanged: saving || aiBusy
                                          ? null
                                          : (value) => setSheetState(
                                              () => status = value ?? status),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      value: completionStatus,
                                      decoration: _inputDecoration('Completion'),
                                      items: const ['Planned', 'Partial', 'Completed']
                                          .map((e) => DropdownMenuItem(
                                                value: e,
                                                child: Text(e),
                                              ))
                                          .toList(),
                                      onChanged: saving || aiBusy
                                          ? null
                                          : (value) => setSheetState(() =>
                                              completionStatus =
                                                  value ?? completionStatus),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: periodsCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: _inputDecoration('Planned Periods'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text('Publish'),
                                      subtitle: Text(publish ? 'Visible' : 'Hidden'),
                                      value: publish,
                                      onChanged: saving || aiBusy
                                          ? null
                                          : (value) => setSheetState(
                                              () => publish = value),
                                    ),
                                  ),
                                ],
                              ),
                              _textField(remarksCtrl, 'Remarks', maxLines: 2),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: saving || aiBusy
                                    ? null
                                    : () => Navigator.of(sheetContext).pop(),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton.icon(
                                onPressed: saving || aiBusy ? null : savePlan,
                                icon: saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.save_rounded),
                                label: Text(isEdit ? 'Update Lesson Plan' : 'Create Lesson Plan'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  backgroundColor: const Color(0xFF2563EB),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );

    for (final c in [
      sessionCtrl,
      topicCtrl,
      subtopicCtrl,
      objectivesCtrl,
      methodCtrl,
      aidsCtrl,
      activitiesCtrl,
      resourcesCtrl,
      evalCtrl,
      assessmentCtrl,
      homeworkCtrl,
      remedialCtrl,
      enrichmentCtrl,
      periodsCtrl,
      remarksCtrl,
    ]) {
      c.dispose();
    }
  }

  LessonAssignment? _assignmentForPlan(LessonPlan? plan) {
    if (plan == null) return null;
    for (final assignment in _assignments) {
      if (assignment.classId == plan.classId &&
          assignment.subjectId == plan.subjectId) {
        return assignment;
      }
    }
    return null;
  }

  Future<void> _openDetailSheet(LessonPlan plan) async {
    LessonPlan full = plan;
    bool loading = plan.id != null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (loading && plan.id != null) {
              Future.microtask(() async {
                try {
                  final fetched = await LessonPlanApi.fetchLessonPlanById(plan.id!);
                  setSheetState(() => full = fetched);
                } catch (_) {
                } finally {
                  setSheetState(() => loading = false);
                }
              });
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.82,
              minChildSize: 0.45,
              maxChildSize: 0.95,
              builder: (_, controller) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                  ),
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          children: [
                            _sheetHandle(),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        full.topic.isEmpty
                                            ? 'Lesson Plan Details'
                                            : full.topic,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_labelOrId(full.className, full.classId, 'Class')} • '
                                        '${_labelOrId(full.subjectName, full.subjectId, 'Subject')}',
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Close',
                                  onPressed: () => Navigator.of(sheetContext).pop(),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _statusChip(full.status),
                                _completionChip(full.completionStatus),
                                Chip(
                                  avatar: Icon(
                                    full.publish
                                        ? Icons.visibility_rounded
                                        : Icons.visibility_off_rounded,
                                    size: 17,
                                    color: full.publish
                                        ? const Color(0xFF047857)
                                        : Colors.grey.shade700,
                                  ),
                                  label: Text(full.publish ? 'Published' : 'Hidden'),
                                ),
                                Chip(
                                  avatar: const Icon(Icons.calendar_month_rounded, size: 17),
                                  label: Text('${full.weekStart} → ${full.weekEnd}'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _detailBlock('Subtopic', full.subtopic),
                            _detailBlock('Specific Objectives', full.specificObjectives),
                            _detailBlock('Teaching Method', full.teachingMethod),
                            _detailBlock('Teaching Aids', full.teachingAids),
                            _detailBlock('Activities', full.activities),
                            _detailBlock('Resources', full.resources),
                            _detailBlock('Evaluation Method', full.evaluationMethod),
                            _detailBlock('Assessment Plan', full.assessmentPlan),
                            _detailBlock('Homework', full.homework),
                            _detailBlock('Remedial Plan', full.remedialPlan),
                            _detailBlock('Enrichment Plan', full.enrichmentPlan),
                            _detailBlock('Remarks', full.remarks),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: full.id == null
                                        ? null
                                        : () async {
                                            Navigator.of(sheetContext).pop();
                                            await _openEditSheet(full);
                                          },
                                    icon: const Icon(Icons.edit_rounded),
                                    label: const Text('Edit'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: full.id == null
                                        ? null
                                        : () => _openPdf(full),
                                    icon: const Icon(Icons.picture_as_pdf_rounded),
                                    label: const Text('PDF'),
                                  ),
                                ),
                              ],
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

  Future<void> _deletePlan(LessonPlan plan) async {
    final id = plan.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete lesson plan?'),
        content: Text('This will permanently delete “${plan.topic}”.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await LessonPlanApi.deleteLessonPlan(id);
      _showSnack('Lesson plan deleted');
      await _loadAll();
    } catch (e) {
      _showSnack(_cleanError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePublish(LessonPlan plan) async {
    if (plan.id == null) return;
    setState(() => _busy = true);
    try {
      await LessonPlanApi.togglePublish(plan);
      _showSnack(plan.publish ? 'Lesson plan unpublished' : 'Lesson plan published');
      await _loadAll();
    } catch (e) {
      _showSnack(_cleanError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPdf(LessonPlan plan) async {
    final id = plan.id;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      await LessonPlanApi.openPdf(id, fileName: _pdfFileName(plan));
    } catch (e) {
      _showSnack(_cleanError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _pdfFileName(LessonPlan plan) {
    final base = 'LessonPlan_${plan.id ?? ''}_${plan.weekStart}_${plan.weekEnd}_${plan.topic}'
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-.]+'), '_');
    return '$base.pdf';
  }

  @override
  Widget build(BuildContext context) {
    final plans = _filteredPlans;

    return Scaffold(
      drawer: const TeacherDrawerMenu(),
      appBar: AppBar(
        title: const Text('AI Lesson Plans'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _busy ? null : _loadAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _busy ? null : _openCreateSheet,
        icon: const Icon(Icons.auto_awesome_rounded),
        label: const Text('Create with AI'),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadAll,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      _headerCard(),
                      const SizedBox(height: 12),
                      _filterCard(),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'My Lesson Plans',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '${plans.length} shown',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (plans.isEmpty)
                        _emptyCard()
                      else
                        ...plans.map(_planCard),
                      const SizedBox(height: 92),
                    ],
                  ),
          ),
          if (_busy)
            Container(
              color: Colors.black.withOpacity(0.12),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _headerCard() {
    final published = _plans.where((e) => e.publish).length;
    final draft = _plans
        .where((e) => e.status.toLowerCase() == 'draft')
        .length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF111827), Color(0xFF2563EB), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Powered Lesson Plans',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Plan weekly teaching faster with syllabus-linked AI drafts.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _statPill('Total', '${_plans.length}'),
              const SizedBox(width: 8),
              _statPill('Published', '$published'),
              const SizedBox(width: 8),
              _statPill('Draft', '$draft'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statPill(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Search topic, class, subject...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  value: _filterClassId,
                  isExpanded: true,
                  decoration: _inputDecoration('Class'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('All Classes'),
                    ),
                    ..._uniqueClassAssignments.map(
                      (a) => DropdownMenuItem<int?>(
                        value: a.classId,
                        child: Text(a.className.isEmpty
                            ? 'Class ${a.classId}'
                            : a.className),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _filterClassId = value),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _filterTerm,
                  isExpanded: true,
                  decoration: _inputDecoration('Term'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All Terms')),
                    DropdownMenuItem(value: 'FULL_YEAR', child: Text('Full Year')),
                    DropdownMenuItem(value: 'TERM1', child: Text('Term 1')),
                    DropdownMenuItem(value: 'TERM2', child: Text('Term 2')),
                  ],
                  onChanged: (value) => setState(() => _filterTerm = value ?? ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int?>(
            value: _filterSubjectId,
            isExpanded: true,
            decoration: _inputDecoration('Subject'),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('All Subjects'),
              ),
              ..._uniqueSubjectAssignments.map(
                (a) => DropdownMenuItem<int?>(
                  value: a.subjectId,
                  child: Text(a.subjectName.isEmpty
                      ? 'Subject ${a.subjectId}'
                      : a.subjectName),
                ),
              ),
            ],
            onChanged: (value) => setState(() => _filterSubjectId = value),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Icon(Icons.menu_book_outlined, size: 54, color: Colors.grey.shade500),
          const SizedBox(height: 10),
          const Text(
            'No lesson plans found',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap “Create with AI” to create your first mobile lesson plan.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _planCard(LessonPlan plan) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openDetailSheet(plan),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F766E), Color(0xFF2563EB)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.menu_book_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.topic.isEmpty ? 'Untitled Lesson' : plan.topic,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${_labelOrId(plan.className, plan.classId, 'Class')} • '
                          '${_labelOrId(plan.subjectName, plan.subjectId, 'Subject')}',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'view') _openDetailSheet(plan);
                      if (value == 'edit') _openEditSheet(plan);
                      if (value == 'pdf') _openPdf(plan);
                      if (value == 'publish') _togglePublish(plan);
                      if (value == 'delete') _deletePlan(plan);
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'view', child: Text('View')),
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(value: 'pdf', child: Text('Open PDF')),
                      PopupMenuItem(
                        value: 'publish',
                        child: Text(plan.publish ? 'Unpublish' : 'Publish'),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              if (plan.subtopic.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  plan.subtopic,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statusChip(plan.status),
                  _completionChip(plan.completionStatus),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(plan.publish ? 'Published' : 'Hidden'),
                    avatar: Icon(
                      plan.publish
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      size: 16,
                    ),
                  ),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.calendar_today_rounded, size: 16),
                    label: Text('${plan.weekStart} → ${plan.weekEnd}'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
                      onPressed: () => _togglePublish(plan),
                      icon: Icon(
                        plan.publish
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 18,
                      ),
                      label: Text(plan.publish ? 'Hide' : 'Publish'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'PDF',
                    onPressed: () => _openPdf(plan),
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF2563EB)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _sectionsPicker({
    required List<LessonSection> sections,
    required List<int> selected,
    required ValueChanged<List<int>>? onChanged,
  }) {
    if (sections.isEmpty) {
      return Text(
        'Select class to load sections. You can still save without sections.',
        style: TextStyle(color: Colors.grey.shade700),
      );
    }

    final allSelected = sections.every((s) => selected.contains(s.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onChanged == null
                ? null
                : () {
                    if (allSelected) {
                      onChanged(<int>[]);
                    } else {
                      onChanged(sections.map((e) => e.id).toList());
                    }
                  },
            icon: Icon(allSelected
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded),
            label: Text(allSelected ? 'Clear All' : 'Select All'),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: sections.map((section) {
            final isSelected = selected.contains(section.id);
            return FilterChip(
              label: Text(section.name),
              selected: isSelected,
              onSelected: onChanged == null
                  ? null
                  : (value) {
                      final next = List<int>.from(selected);
                      if (value) {
                        if (!next.contains(section.id)) next.add(section.id);
                      } else {
                        next.remove(section.id);
                      }
                      onChanged(next);
                    },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _topicField({
    required TextEditingController controller,
    required String label,
    required List<String> options,
    required VoidCallback onSelected,
    bool isRequired = true,
  }) {
    if (options.isEmpty) {
      return TextFormField(
        controller: controller,
        decoration: _inputDecoration(label),
        validator: isRequired
            ? (value) => value == null || value.trim().isEmpty
                ? 'Required'
                : null
            : null,
        onChanged: (_) => onSelected(),
      );
    }

    final current = options.contains(controller.text) ? controller.text : null;
    return DropdownButtonFormField<String>(
      value: current,
      isExpanded: true,
      decoration: _inputDecoration(label),
      items: options
          .map((e) => DropdownMenuItem(
                value: e,
                child: Text(e, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      validator: isRequired
          ? (value) {
              final v = value ?? controller.text;
              return v.trim().isEmpty ? 'Required' : null;
            }
          : null,
      onChanged: (value) {
        if (value != null) controller.text = value;
        onSelected();
      },
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        decoration: _inputDecoration(label),
      ),
    );
  }

  Widget _dateButton({
    required String label,
    required String value,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: _inputDecoration(label),
        child: Row(
          children: [
            const Icon(Icons.event_rounded, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(value)),
          ],
        ),
      ),
    );
  }

  Widget _editorHeader({
    required String title,
    required String subtitle,
    required bool aiFilled,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          if (aiFilled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'AI Filled',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }

  Widget _aiBanner({required VoidCallback? onGenerate, required bool busy}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF111827), Color(0xFF0F766E)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 30),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Generate with AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'AI will fill objectives, activities, assessment, homework and more.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: onGenerate,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF111827),
            ),
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Generate'),
          ),
        ],
      ),
    );
  }

  Widget _detailBlock(String title, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _sheetHandle() {
    return Center(
      child: Container(
        width: 46,
        height: 5,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.18),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      filled: true,
      fillColor: Colors.white,
      isDense: true,
    );
  }

  Widget _statusChip(String status) {
    final st = status.toUpperCase();
    Color color;
    if (st == 'APPROVED') {
      color = const Color(0xFF047857);
    } else if (st == 'SUBMITTED') {
      color = const Color(0xFFD97706);
    } else if (st == 'RETURNED') {
      color = const Color(0xFFDC2626);
    } else {
      color = const Color(0xFF64748B);
    }
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withOpacity(0.10),
      side: BorderSide(color: color.withOpacity(0.22)),
      avatar: Icon(Icons.flag_rounded, size: 16, color: color),
      label: Text(
        st,
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _completionChip(String status) {
    final st = status.toUpperCase();
    Color color;
    if (st == 'COMPLETED') {
      color = const Color(0xFF047857);
    } else if (st == 'PARTIAL') {
      color = const Color(0xFFD97706);
    } else {
      color = const Color(0xFF2563EB);
    }
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withOpacity(0.10),
      side: BorderSide(color: color.withOpacity(0.22)),
      avatar: Icon(Icons.task_alt_rounded, size: 16, color: color),
      label: Text(
        st,
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      return DateTime.parse(value.substring(0, value.length >= 10 ? 10 : value.length));
    } catch (_) {
      return null;
    }
  }

  String _labelOrId(String label, int? id, String fallback) {
    if (label.trim().isNotEmpty) return label.trim();
    if (id != null) return '$fallback $id';
    return fallback;
  }

  String _cleanError(Object e) {
    return '$e'.replaceFirst('Exception: ', '').trim();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Colors.red.shade700 : null,
      ),
    );
  }
}

class _Option {
  final String value;
  final String label;
  const _Option(this.value, this.label);
}

const List<_Option> _termOptions = <_Option>[
  _Option('FULL_YEAR', 'Full Year'),
  _Option('TERM1', 'Term 1'),
  _Option('TERM2', 'Term 2'),
];