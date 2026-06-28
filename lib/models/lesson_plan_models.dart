// lib/models/lesson_plan_models.dart
// Mobile-friendly models for AI powered Lesson Plans.

class LessonPlan {
  final int? id;
  final int? classId;
  final int? subjectId;
  final int? breakdownId;
  final int? breakdownItemId;
  final String academicSession;
  final String term;
  final String weekStart;
  final String weekEnd;
  final String topic;
  final String subtopic;
  final String specificObjectives;
  final String teachingMethod;
  final String teachingAids;
  final String activities;
  final String resources;
  final String evaluationMethod;
  final String assessmentPlan;
  final String homework;
  final String remedialPlan;
  final String enrichmentPlan;
  final String remarks;
  final String status;
  final String completionStatus;
  final int? plannedPeriods;
  final bool publish;
  final List<int> sectionIds;
  final String className;
  final String subjectName;

  const LessonPlan({
    this.id,
    this.classId,
    this.subjectId,
    this.breakdownId,
    this.breakdownItemId,
    this.academicSession = '',
    this.term = 'FULL_YEAR',
    this.weekStart = '',
    this.weekEnd = '',
    this.topic = '',
    this.subtopic = '',
    this.specificObjectives = '',
    this.teachingMethod = '',
    this.teachingAids = '',
    this.activities = '',
    this.resources = '',
    this.evaluationMethod = '',
    this.assessmentPlan = '',
    this.homework = '',
    this.remedialPlan = '',
    this.enrichmentPlan = '',
    this.remarks = '',
    this.status = 'Draft',
    this.completionStatus = 'Planned',
    this.plannedPeriods,
    this.publish = false,
    this.sectionIds = const <int>[],
    this.className = '',
    this.subjectName = '',
  });

  factory LessonPlan.fromJson(Map<String, dynamic> json) {
    final classMap = _mapOf(json['Class'] ?? json['class']);
    final subjectMap = _mapOf(json['Subject'] ?? json['subject']);

    final sectionsRaw = json['Sections'] ?? json['sections'] ?? json['sectionIds'];
    final sections = <int>[];
    if (sectionsRaw is List) {
      for (final item in sectionsRaw) {
        if (item is Map) {
          final id = _intOrNull(item['id'] ?? item['sectionId']);
          if (id != null) sections.add(id);
        } else {
          final id = _intOrNull(item);
          if (id != null) sections.add(id);
        }
      }
    }

    return LessonPlan(
      id: _intOrNull(json['id']),
      classId: _intOrNull(json['classId'] ?? json['class_id'] ?? json['ClassId']),
      subjectId:
          _intOrNull(json['subjectId'] ?? json['subject_id'] ?? json['SubjectId']),
      breakdownId: _intOrNull(json['breakdownId'] ?? json['breakdown_id']),
      breakdownItemId:
          _intOrNull(json['breakdownItemId'] ?? json['breakdown_item_id']),
      academicSession: _str(json['academicSession'] ?? json['academic_session']),
      term: _str(json['term'], fallback: 'FULL_YEAR'),
      weekStart: _dateOnly(json['weekStart'] ?? json['week_start']),
      weekEnd: _dateOnly(json['weekEnd'] ?? json['week_end']),
      topic: _str(json['topic']),
      subtopic: _str(json['subtopic']),
      specificObjectives:
          _str(json['specificObjectives'] ?? json['specific_objectives']),
      teachingMethod: _str(json['teachingMethod'] ?? json['teaching_method']),
      teachingAids: _str(json['teachingAids'] ?? json['teaching_aids']),
      activities: _str(json['activities']),
      resources: _str(json['resources']),
      evaluationMethod:
          _str(json['evaluationMethod'] ?? json['evaluation_method']),
      assessmentPlan: _str(json['assessmentPlan'] ?? json['assessment_plan']),
      homework: _str(json['homework']),
      remedialPlan: _str(json['remedialPlan'] ?? json['remedial_plan']),
      enrichmentPlan: _str(json['enrichmentPlan'] ?? json['enrichment_plan']),
      remarks: _str(json['remarks']),
      status: _str(json['status'], fallback: 'Draft'),
      completionStatus:
          _str(json['completionStatus'] ?? json['completion_status'], fallback: 'Planned'),
      plannedPeriods:
          _intOrNull(json['plannedPeriods'] ?? json['planned_periods']),
      publish: _bool(json['publish'] ?? json['isPublished'] ?? json['is_published']),
      sectionIds: sections,
      className: _str(
        classMap['class_name'] ??
            classMap['name'] ??
            json['className'] ??
            json['class_name'],
      ),
      subjectName: _str(
        subjectMap['name'] ??
            subjectMap['subject_name'] ??
            json['subjectName'] ??
            json['subject_name'],
      ),
    );
  }

  Map<String, dynamic> toPayload() {
    return {
      'classId': classId,
      'subjectId': subjectId,
      'academicSession': academicSession.trim().isEmpty ? null : academicSession.trim(),
      'term': term,
      'weekStart': weekStart,
      'weekEnd': weekEnd,
      'breakdownId': breakdownId,
      'breakdownItemId': breakdownItemId,
      'topic': topic.trim().isEmpty ? null : topic.trim(),
      'subtopic': subtopic.trim().isEmpty ? null : subtopic.trim(),
      'specificObjectives':
          specificObjectives.trim().isEmpty ? null : specificObjectives.trim(),
      'teachingMethod': teachingMethod.trim().isEmpty ? null : teachingMethod.trim(),
      'teachingAids': teachingAids.trim().isEmpty ? null : teachingAids.trim(),
      'activities': activities.trim().isEmpty ? null : activities.trim(),
      'resources': resources.trim().isEmpty ? null : resources.trim(),
      'evaluationMethod':
          evaluationMethod.trim().isEmpty ? null : evaluationMethod.trim(),
      'assessmentPlan': assessmentPlan.trim().isEmpty ? null : assessmentPlan.trim(),
      'homework': homework.trim().isEmpty ? null : homework.trim(),
      'remedialPlan': remedialPlan.trim().isEmpty ? null : remedialPlan.trim(),
      'enrichmentPlan':
          enrichmentPlan.trim().isEmpty ? null : enrichmentPlan.trim(),
      'plannedPeriods': plannedPeriods,
      'status': status,
      'completionStatus': completionStatus,
      'remarks': remarks.trim().isEmpty ? null : remarks.trim(),
      'publish': publish,
      'sections': sectionIds,
    };
  }

  LessonPlan copyWith({
    int? id,
    int? classId,
    int? subjectId,
    int? breakdownId,
    int? breakdownItemId,
    String? academicSession,
    String? term,
    String? weekStart,
    String? weekEnd,
    String? topic,
    String? subtopic,
    String? specificObjectives,
    String? teachingMethod,
    String? teachingAids,
    String? activities,
    String? resources,
    String? evaluationMethod,
    String? assessmentPlan,
    String? homework,
    String? remedialPlan,
    String? enrichmentPlan,
    String? remarks,
    String? status,
    String? completionStatus,
    int? plannedPeriods,
    bool? publish,
    List<int>? sectionIds,
    String? className,
    String? subjectName,
  }) {
    return LessonPlan(
      id: id ?? this.id,
      classId: classId ?? this.classId,
      subjectId: subjectId ?? this.subjectId,
      breakdownId: breakdownId ?? this.breakdownId,
      breakdownItemId: breakdownItemId ?? this.breakdownItemId,
      academicSession: academicSession ?? this.academicSession,
      term: term ?? this.term,
      weekStart: weekStart ?? this.weekStart,
      weekEnd: weekEnd ?? this.weekEnd,
      topic: topic ?? this.topic,
      subtopic: subtopic ?? this.subtopic,
      specificObjectives: specificObjectives ?? this.specificObjectives,
      teachingMethod: teachingMethod ?? this.teachingMethod,
      teachingAids: teachingAids ?? this.teachingAids,
      activities: activities ?? this.activities,
      resources: resources ?? this.resources,
      evaluationMethod: evaluationMethod ?? this.evaluationMethod,
      assessmentPlan: assessmentPlan ?? this.assessmentPlan,
      homework: homework ?? this.homework,
      remedialPlan: remedialPlan ?? this.remedialPlan,
      enrichmentPlan: enrichmentPlan ?? this.enrichmentPlan,
      remarks: remarks ?? this.remarks,
      status: status ?? this.status,
      completionStatus: completionStatus ?? this.completionStatus,
      plannedPeriods: plannedPeriods ?? this.plannedPeriods,
      publish: publish ?? this.publish,
      sectionIds: sectionIds ?? this.sectionIds,
      className: className ?? this.className,
      subjectName: subjectName ?? this.subjectName,
    );
  }
}

class LessonAssignment {
  final int? classId;
  final int? subjectId;
  final String className;
  final String subjectName;

  const LessonAssignment({
    this.classId,
    this.subjectId,
    this.className = '',
    this.subjectName = '',
  });

  String get label {
    final cls = className.trim().isEmpty ? 'Class ${classId ?? '-'}' : className;
    final sub = subjectName.trim().isEmpty ? 'Subject ${subjectId ?? '-'}' : subjectName;
    return '$cls • $sub';
  }

  factory LessonAssignment.fromJson(Map<String, dynamic> json) {
    final classMap = _mapOf(json['class'] ?? json['Class']);
    final subjectMap = _mapOf(json['subject'] ?? json['Subject']);

    return LessonAssignment(
      classId: _intOrNull(
        json['classId'] ?? json['class_id'] ?? classMap['id'] ?? json['ClassId'],
      ),
      subjectId: _intOrNull(
        json['subjectId'] ??
            json['subject_id'] ??
            subjectMap['id'] ??
            json['SubjectId'],
      ),
      className: _str(
        classMap['class_name'] ?? classMap['name'] ?? json['className'],
      ),
      subjectName: _str(
        subjectMap['name'] ?? subjectMap['subject_name'] ?? json['subjectName'],
      ),
    );
  }
}

class LessonSection {
  final int id;
  final String name;

  const LessonSection({required this.id, required this.name});

  factory LessonSection.fromJson(Map<String, dynamic> json) {
    final id = _intOrNull(json['id'] ?? json['sectionId']) ?? 0;
    return LessonSection(
      id: id,
      name: _str(json['section_name'] ?? json['name'], fallback: 'Section $id'),
    );
  }
}

class BreakdownItem {
  final int id;
  final int? breakdownId;
  final String unitNumber;
  final String unitTitle;
  final List<String> topics;
  final List<String> subtopics;

  const BreakdownItem({
    required this.id,
    this.breakdownId,
    this.unitNumber = '',
    this.unitTitle = '',
    this.topics = const <String>[],
    this.subtopics = const <String>[],
  });

  String get label {
    final prefix = unitNumber.trim().isEmpty ? '' : '$unitNumber - ';
    final title = unitTitle.trim().isEmpty ? 'Unit #$id' : unitTitle;
    return '$prefix$title';
  }

  factory BreakdownItem.fromJson(Map<String, dynamic> json, {int? parentBreakdownId}) {
    final id = _intOrNull(json['id']) ?? 0;
    return BreakdownItem(
      id: id,
      breakdownId: _intOrNull(json['breakdownId'] ?? json['breakdown_id']) ??
          parentBreakdownId,
      unitNumber: _str(json['unitNumber'] ?? json['unit_number']),
      unitTitle: _str(json['unitTitle'] ?? json['unit_title'] ?? json['title']),
      topics: _splitList(json['topics']),
      subtopics: _splitList(json['subtopics']),
    );
  }
}

class AiLessonPlanDraft {
  final String specificObjectives;
  final String teachingMethod;
  final String teachingAids;
  final String activities;
  final String resources;
  final String evaluationMethod;
  final String assessmentPlan;
  final String homework;
  final String remedialPlan;
  final String enrichmentPlan;
  final String remarks;
  final int? plannedPeriods;
  final int? lessonPlanId;

  const AiLessonPlanDraft({
    this.specificObjectives = '',
    this.teachingMethod = '',
    this.teachingAids = '',
    this.activities = '',
    this.resources = '',
    this.evaluationMethod = '',
    this.assessmentPlan = '',
    this.homework = '',
    this.remedialPlan = '',
    this.enrichmentPlan = '',
    this.remarks = '',
    this.plannedPeriods,
    this.lessonPlanId,
  });

  factory AiLessonPlanDraft.fromResponse(Map<String, dynamic> decoded) {
    final dataMap = _mapOf(decoded['data']);
    final ai = _mapOf(decoded['ai'] ?? dataMap['ai'] ?? dataMap);

    return AiLessonPlanDraft(
      specificObjectives:
          _str(ai['specificObjectives'] ?? ai['specific_objectives']),
      teachingMethod: _str(ai['teachingMethod'] ?? ai['teaching_method']),
      teachingAids: _str(ai['teachingAids'] ?? ai['teaching_aids']),
      activities: _str(ai['activities']),
      resources: _str(ai['resources']),
      evaluationMethod: _str(ai['evaluationMethod'] ?? ai['evaluation_method']),
      assessmentPlan: _str(ai['assessmentPlan'] ?? ai['assessment_plan']),
      homework: _str(ai['homework']),
      remedialPlan: _str(ai['remedialPlan'] ?? ai['remedial_plan']),
      enrichmentPlan: _str(ai['enrichmentPlan'] ?? ai['enrichment_plan']),
      remarks: _str(ai['remarks']),
      plannedPeriods: _intOrNull(ai['plannedPeriods'] ?? ai['planned_periods']),
      lessonPlanId: _intOrNull(dataMap['lessonPlanId'] ?? decoded['lessonPlanId']),
    );
  }
}

Map<String, dynamic> _mapOf(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

String _str(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final s = '$value'.trim();
  return s.isEmpty ? fallback : s;
}

String _dateOnly(dynamic value) {
  final s = _str(value);
  if (s.length >= 10) return s.substring(0, 10);
  return s;
}

int? _intOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value'.trim());
}

bool _bool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final s = '$value'.trim().toLowerCase();
  return s == 'true' || s == '1' || s == 'yes';
}

List<String> _splitList(dynamic value) {
  if (value == null) return <String>[];
  if (value is List) {
    return value.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList();
  }
  final s = '$value'.trim();
  if (s.isEmpty) return <String>[];
  return s
      .split(RegExp(r'\r?\n|,|;'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}