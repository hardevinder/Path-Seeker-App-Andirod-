// lib/models/student_lesson_plan_model.dart
import 'dart:convert';

class StudentLessonPlanResponse {
  final StudentLessonPlanStudent? student;
  final List<StudentLessonPlan> lessonPlans;

  const StudentLessonPlanResponse({
    required this.student,
    required this.lessonPlans,
  });

  factory StudentLessonPlanResponse.fromJson(dynamic json) {
    if (json is List) {
      return StudentLessonPlanResponse(
        student: null,
        lessonPlans: json
            .whereType<Map>()
            .map(
                (e) => StudentLessonPlan.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
    }

    final map =
        json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
    final data = _asMap(map['data']);
    final rawPlans = map['lessonPlans'] ??
        map['plans'] ??
        data?['lessonPlans'] ??
        data?['plans'] ??
        data?['items'] ??
        map['items'] ??
        map['data'] ??
        [];
    final list = rawPlans is List ? rawPlans : const [];

    return StudentLessonPlanResponse(
      student: map['student'] is Map
          ? StudentLessonPlanStudent.fromJson(
              Map<String, dynamic>.from(map['student']))
          : null,
      lessonPlans: list
          .whereType<Map>()
          .map((e) => StudentLessonPlan.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class StudentLessonPlanStudent {
  final int? id;
  final String name;
  final String admissionNumber;
  final int? classId;
  final int? sectionId;
  final String className;
  final String sectionName;

  const StudentLessonPlanStudent({
    required this.id,
    required this.name,
    required this.admissionNumber,
    required this.classId,
    required this.sectionId,
    required this.className,
    required this.sectionName,
  });

  factory StudentLessonPlanStudent.fromJson(Map<String, dynamic> json) {
    final cls = _asMap(json['Class']);
    final sec = _asMap(json['Section']);

    return StudentLessonPlanStudent(
      id: _toInt(json['id']),
      name: _str(json['name']),
      admissionNumber:
          _str(json['admission_number'] ?? json['admissionNumber']),
      classId: _toInt(json['class_id'] ?? json['classId']),
      sectionId: _toInt(json['section_id'] ?? json['sectionId']),
      className: _str(cls?['class_name'] ?? cls?['name'] ?? json['className']),
      sectionName:
          _str(sec?['section_name'] ?? sec?['name'] ?? json['sectionName']),
    );
  }
}

class StudentLessonPlan {
  final int id;
  final int? classId;
  final int? subjectId;
  final String className;
  final String subjectName;
  final String teacherName;
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
  final int? plannedPeriods;
  final List<String> sectionNames;
  final List<StudentLessonPlanEvaluation> evaluations;

  const StudentLessonPlan({
    required this.id,
    required this.classId,
    required this.subjectId,
    required this.className,
    required this.subjectName,
    required this.teacherName,
    required this.academicSession,
    required this.term,
    required this.weekStart,
    required this.weekEnd,
    required this.topic,
    required this.subtopic,
    required this.specificObjectives,
    required this.teachingMethod,
    required this.teachingAids,
    required this.activities,
    required this.resources,
    required this.evaluationMethod,
    required this.assessmentPlan,
    required this.homework,
    required this.remedialPlan,
    required this.enrichmentPlan,
    required this.remarks,
    required this.plannedPeriods,
    required this.sectionNames,
    this.evaluations = const [],
  });

  factory StudentLessonPlan.fromJson(Map<String, dynamic> json) {
    final cls = _asMap(json['Class'] ?? json['class']);
    final sub = _asMap(json['Subject'] ?? json['subject']);
    final teacher = _asMap(json['Teacher'] ?? json['teacher']);
    final rawSections = json['Sections'] ?? json['sections'];
    final sections = rawSections is List ? rawSections : const [];
    final rawEvaluations = json['evaluations'] ??
        json['Evaluations'] ??
        json['LessonPlanEvaluations'] ??
        json['lessonPlanEvaluations'];
    final evaluations = rawEvaluations is List ? rawEvaluations : const [];

    return StudentLessonPlan(
      id: _toInt(json['id']) ?? 0,
      classId: _toInt(json['classId'] ?? json['class_id']),
      subjectId: _toInt(json['subjectId'] ?? json['subject_id']),
      className: _str(cls?['class_name'] ??
          cls?['name'] ??
          json['className'] ??
          json['classId']),
      subjectName:
          _str(sub?['name'] ?? json['subjectName'] ?? json['subjectId']),
      teacherName: _str(teacher?['name'] ?? json['teacherName']),
      academicSession:
          _str(json['academicSession'] ?? json['academic_session']),
      term: _str(json['term']).isEmpty ? 'FULL_YEAR' : _str(json['term']),
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
      plannedPeriods: _toInt(json['plannedPeriods'] ?? json['planned_periods']),
      sectionNames: sections
          .whereType<Map>()
          .map((e) => _str(e['section_name'] ?? e['name']))
          .where((e) => e.isNotEmpty)
          .toList(),
      evaluations: evaluations
          .whereType<Map>()
          .map((e) => StudentLessonPlanEvaluation.fromJson(
              Map<String, dynamic>.from(e)))
          .where((e) => e.isPublishedLike)
          .toList(),
    );
  }

  String get title {
    final t = topic.trim();
    final st = subtopic.trim();
    if (t.isEmpty && st.isEmpty) return 'Lesson Plan #$id';
    if (st.isEmpty) return t;
    if (t.isEmpty) return st;
    return '$t • $st';
  }

  String get weekLabel {
    if (weekStart.isEmpty && weekEnd.isEmpty) return 'Week not set';
    if (weekStart == weekEnd || weekEnd.isEmpty) return weekStart;
    if (weekStart.isEmpty) return weekEnd;
    return '$weekStart → $weekEnd';
  }

  String get sectionsLabel =>
      sectionNames.isEmpty ? 'All sections' : sectionNames.join(', ');
}

class StudentLessonPlanEvaluation {
  final int id;
  final String title;
  final String type;
  final String status;
  final int? totalMarks;
  final int? timeMinutes;
  final Map<String, dynamic> config;
  final List<StudentLessonPlanEvaluationItem> items;
  final StudentLessonPlanEvaluationResult? result;
  final bool answersVisibleToStudents;

  const StudentLessonPlanEvaluation({
    required this.id,
    required this.title,
    required this.type,
    required this.status,
    required this.totalMarks,
    required this.timeMinutes,
    required this.config,
    required this.items,
    required this.result,
    required this.answersVisibleToStudents,
  });

  factory StudentLessonPlanEvaluation.fromJson(Map<String, dynamic> json) {
    final config =
        _asMap(json['config']) ?? _asMap(_jsonMaybe(json['configJson'])) ?? {};
    final rawItems = json['items'] ??
        json['Items'] ??
        json['EvaluationItems'] ??
        json['LessonPlanEvaluationItems'];
    final items = rawItems is List ? rawItems : const [];
    final resultMap = _asMap(json['result'] ??
        json['studentResult'] ??
        json['myResult'] ??
        json['evaluationResult'] ??
        json['Result']);

    return StudentLessonPlanEvaluation(
      id: _toInt(json['id']) ?? 0,
      title: _str(json['title']),
      type: _str(json['type']).isEmpty ? 'TEST' : _str(json['type']),
      status: _str(json['status']).isEmpty ? 'PUBLISHED' : _str(json['status']),
      totalMarks:
          _toInt(json['totalMarks'] ?? json['total_marks'] ?? json['maxMarks']),
      timeMinutes: _toInt(json['timeMinutes'] ?? json['time_minutes']),
      config: config,
      items: items
          .whereType<Map>()
          .map((e) => StudentLessonPlanEvaluationItem.fromJson(
                Map<String, dynamic>.from(e),
              ))
          .toList(),
      result: resultMap == null
          ? null
          : StudentLessonPlanEvaluationResult.fromJson(resultMap),
      answersVisibleToStudents: _bool(json['answersVisibleToStudents']) ||
          _bool(json['answerKeyVisibleToStudents']) ||
          _bool(json['showAnswersToStudents']) ||
          _str(json['answersPublishedAt']).isNotEmpty ||
          _bool(config['answersVisibleToStudents']) ||
          _bool(config['answerKeyVisibleToStudents']) ||
          _bool(config['showAnswersToStudents']) ||
          _str(config['answersPublishedAt']).isNotEmpty,
    );
  }

  bool get isPublishedLike {
    final s = status.toUpperCase();
    return _bool(status) ||
        _bool(config['published']) ||
        s == 'PUBLISHED' ||
        s == 'ACTIVE' ||
        s == 'VISIBLE';
  }

  String get displayTitle => title.isEmpty ? 'Evaluation #$id' : title;

  num? get marksObtained => result?.marksObtained;

  num? get effectiveTotalMarks =>
      totalMarks ?? result?.totalMarks ?? _toNum(config['totalMarks']);

  num? get percentage {
    final direct = result?.percentage;
    if (direct != null) return direct.clamp(0, 100);
    final marks = marksObtained;
    final total = effectiveTotalMarks;
    if (marks == null || total == null || total <= 0) return null;
    return ((marks / total) * 100).clamp(0, 100);
  }

  String get instructions => _str(config['instructions']);
}

class StudentLessonPlanEvaluationItem {
  final int id;
  final String type;
  final String question;
  final num? marks;
  final List<String> options;
  final int? correctIndex;
  final String answerKey;
  final int sortOrder;

  const StudentLessonPlanEvaluationItem({
    required this.id,
    required this.type,
    required this.question,
    required this.marks,
    required this.options,
    required this.correctIndex,
    required this.answerKey,
    required this.sortOrder,
  });

  factory StudentLessonPlanEvaluationItem.fromJson(Map<String, dynamic> json) {
    return StudentLessonPlanEvaluationItem(
      id: _toInt(json['id']) ?? 0,
      type: _str(json['type']).isEmpty ? 'QUESTION' : _str(json['type']),
      question: _str(json['question'] ?? json['q']),
      marks: _toNum(json['marks']),
      options: _stringList(json['options'] ?? json['optionsJson']),
      correctIndex: _toInt(json['correctIndex'] ?? json['correctAnswer']),
      answerKey: _str(
        json['answerKey'] ?? json['modelAnswer'] ?? json['correctAnswerText'],
      ),
      sortOrder: _toInt(json['sortOrder'] ?? json['sort_order']) ?? 0,
    );
  }
}

class StudentLessonPlanEvaluationResult {
  final num? marksObtained;
  final num? totalMarks;
  final num? percentage;
  final String remark;

  const StudentLessonPlanEvaluationResult({
    required this.marksObtained,
    required this.totalMarks,
    required this.percentage,
    required this.remark,
  });

  factory StudentLessonPlanEvaluationResult.fromJson(
      Map<String, dynamic> json) {
    return StudentLessonPlanEvaluationResult(
      marksObtained: _toNum(json['marksObtained'] ??
          json['marks_obtained'] ??
          json['obtainedMarks'] ??
          json['score'] ??
          json['marks']),
      totalMarks: _toNum(json['totalMarks'] ?? json['total_marks']),
      percentage: _toNum(json['percentage'] ?? json['percent']),
      remark: _str(json['remark'] ?? json['remarks'] ?? json['teacherRemark']),
    );
  }
}

Map<String, dynamic>? _asMap(dynamic v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

String _str(dynamic v) => v == null ? '' : v.toString().trim();

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

num? _toNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse(v.toString().trim());
}

bool _bool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = _str(v).toLowerCase();
  return s == 'true' || s == '1' || s == 'yes';
}

dynamic _jsonMaybe(dynamic v) {
  if (v == null || v is Map || v is List) return v;
  if (v is! String) return null;
  try {
    return jsonDecode(v);
  } catch (_) {
    return null;
  }
}

List<String> _stringList(dynamic value) {
  final raw = value is String ? _jsonMaybe(value) : value;
  if (raw is List) {
    return raw.map(_str).where((e) => e.isNotEmpty).toList();
  }
  return [];
}

String _dateOnly(dynamic v) {
  final s = _str(v);
  if (s.length >= 10) return s.substring(0, 10);
  return s;
}
