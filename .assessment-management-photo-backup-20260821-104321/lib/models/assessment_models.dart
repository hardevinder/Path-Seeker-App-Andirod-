class AssessmentQuestion {
  final int id;
  final String type;
  final String text;
  final List<String> options;
  final double marks;
  final String difficulty;
  final dynamic correctAnswer;
  final String? explanation;
  final String? topic;

  const AssessmentQuestion({
    required this.id,
    required this.type,
    required this.text,
    required this.options,
    required this.marks,
    required this.difficulty,
    this.correctAnswer,
    this.explanation,
    this.topic,
  });

  factory AssessmentQuestion.fromJson(Map<String, dynamic> json) =>
      AssessmentQuestion(
        id: _int(json['id']),
        type: json['question_type']?.toString() ?? 'mcq',
        text: json['question_text']?.toString() ?? '',
        options: (json['options'] is List)
            ? (json['options'] as List).map((e) => e.toString()).toList()
            : const [],
        marks: _double(json['marks']),
        difficulty: json['difficulty']?.toString() ?? 'medium',
        correctAnswer: json['correct_answer'],
        explanation: json['explanation']?.toString(),
        topic: json['topic']?.toString(),
      );

  Map<String, dynamic> toDraftJson() => {
        'question_type': type,
        'question_text': text,
        'options': options,
        'correct_answer': correctAnswer,
        'marks': marks,
        'difficulty': difficulty,
        if (explanation != null) 'explanation': explanation,
        if (topic != null) 'topic': topic,
      };
}

class AssessmentFileItem {
  final int id;
  final String kind;
  final String name;
  final String? mimeType;

  const AssessmentFileItem({
    required this.id,
    required this.kind,
    required this.name,
    this.mimeType,
  });

  factory AssessmentFileItem.fromJson(Map<String, dynamic> json) =>
      AssessmentFileItem(
        id: _int(json['id']),
        kind: json['kind']?.toString() ?? '',
        name: json['original_name']?.toString() ?? 'File',
        mimeType: json['mime_type']?.toString(),
      );
}

class AssessmentEnrollment {
  final int id;
  final int studentId;
  final String status;
  final double? obtainedMarks;
  final double? percentage;
  final String? grade;
  final String? feedback;
  final DateTime? resultPublishedAt;
  final AssessmentAttempt? latestAttempt;

  const AssessmentEnrollment({
    required this.id,
    required this.studentId,
    required this.status,
    this.obtainedMarks,
    this.percentage,
    this.grade,
    this.feedback,
    this.resultPublishedAt,
    this.latestAttempt,
  });

  factory AssessmentEnrollment.fromJson(Map<String, dynamic> json) =>
      AssessmentEnrollment(
        id: _int(json['id']),
        studentId: _int(json['student_id']),
        status: json['status']?.toString() ?? 'assigned',
        obtainedMarks: _nullableDouble(json['obtained_marks']),
        percentage: _nullableDouble(json['percentage']),
        grade: json['grade']?.toString(),
        feedback: json['teacher_feedback']?.toString(),
        resultPublishedAt: _date(json['result_published_at']),
        latestAttempt: json['latestAttempt'] is Map
            ? AssessmentAttempt.fromJson(
                Map<String, dynamic>.from(json['latestAttempt'] as Map))
            : null,
      );
}

class Assessment {
  final int id;
  final int? onlineClassId;
  final int classId;
  final int? sectionId;
  final int subjectId;
  final String title;
  final String description;
  final String instructions;
  final String assessmentType;
  final String mode;
  final String status;
  final double totalMarks;
  final int? durationMinutes;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String publishTrigger;
  final int maxAttempts;
  final String resultRelease;
  final String className;
  final String sectionName;
  final String subjectName;
  final String teacherName;
  final bool canManage;
  final List<AssessmentQuestion> questions;
  final List<AssessmentFileItem> files;
  final AssessmentEnrollment? enrollment;

  const Assessment({
    required this.id,
    this.onlineClassId,
    required this.classId,
    this.sectionId,
    required this.subjectId,
    required this.title,
    required this.description,
    required this.instructions,
    required this.assessmentType,
    required this.mode,
    required this.status,
    required this.totalMarks,
    this.durationMinutes,
    this.startsAt,
    this.endsAt,
    required this.publishTrigger,
    required this.maxAttempts,
    required this.resultRelease,
    required this.className,
    required this.sectionName,
    required this.subjectName,
    required this.teacherName,
    required this.canManage,
    required this.questions,
    required this.files,
    this.enrollment,
  });

  factory Assessment.fromJson(Map<String, dynamic> json) => Assessment(
        id: _int(json['id']),
        onlineClassId: _nullableInt(json['online_class_id']),
        classId: _int(json['class_id']),
        sectionId: _nullableInt(json['section_id']),
        subjectId: _int(json['subject_id']),
        title: json['title']?.toString() ?? 'Assessment',
        description: json['description']?.toString() ?? '',
        instructions: json['instructions']?.toString() ?? '',
        assessmentType: json['assessment_type']?.toString() ?? 'test',
        mode: json['mode']?.toString() ?? 'online',
        status: json['status']?.toString() ?? 'draft',
        totalMarks: _double(json['total_marks']),
        durationMinutes: _nullableInt(json['duration_minutes']),
        startsAt: _date(json['starts_at']),
        endsAt: _date(json['ends_at']),
        publishTrigger: json['publish_trigger']?.toString() ?? 'manual',
        maxAttempts: _int(json['max_attempts'], 1),
        resultRelease: json['result_release']?.toString() ?? 'manual',
        className: _nested(json, 'class', 'class_name'),
        sectionName: _nested(json, 'section', 'section_name'),
        subjectName: _nested(json, 'subject', 'name'),
        teacherName: _nested(json, 'teacher', 'name'),
        canManage: json['can_manage'] == true,
        questions: _mapList(json['questions'], AssessmentQuestion.fromJson),
        files: _mapList(json['files'], AssessmentFileItem.fromJson),
        enrollment: json['enrollment'] is Map
            ? AssessmentEnrollment.fromJson(
                Map<String, dynamic>.from(json['enrollment'] as Map))
            : null,
      );

  bool get resultVisible => enrollment?.resultPublishedAt != null;
  bool get canAttempt => status == 'published' &&
      !const ['submitted', 'evaluated'].contains(enrollment?.status);
}

class AssessmentAttempt {
  final int id;
  final int assessmentId;
  final int studentId;
  final String status;
  final DateTime startedAt;
  final DateTime? submittedAt;
  final double? obtainedMarks;
  final String? feedback;
  final List<AssessmentAnswer> answers;
  final List<AssessmentFileItem> files;
  final String submissionSource;
  final String aiEvaluationStatus;
  final double? aiConfidence;
  final Map<String, dynamic>? aiSummary;
  final List<Map<String, dynamic>> remedials;
  final bool teacherReviewRequired;

  const AssessmentAttempt({
    required this.id,
    required this.assessmentId,
    required this.studentId,
    required this.status,
    required this.startedAt,
    this.submittedAt,
    this.obtainedMarks,
    this.feedback,
    required this.answers,
    required this.files,
    required this.submissionSource,
    required this.aiEvaluationStatus,
    this.aiConfidence,
    this.aiSummary,
    required this.remedials,
    required this.teacherReviewRequired,
  });

  factory AssessmentAttempt.fromJson(Map<String, dynamic> json) =>
      AssessmentAttempt(
        id: _int(json['id']),
        assessmentId: _int(json['assessment_id']),
        studentId: _int(json['student_id']),
        status: json['status']?.toString() ?? 'in_progress',
        startedAt: _date(json['started_at']) ?? DateTime.now(),
        submittedAt: _date(json['submitted_at']),
        obtainedMarks: _nullableDouble(json['obtained_marks']),
        feedback: json['teacher_feedback']?.toString(),
        answers: _mapList(json['answers'], AssessmentAnswer.fromJson),
        files: _mapList(json['files'], AssessmentFileItem.fromJson),
        submissionSource: json['submission_source']?.toString() ?? 'online',
        aiEvaluationStatus: json['ai_evaluation_status']?.toString() ?? 'not_started',
        aiConfidence: _nullableDouble(json['ai_confidence']),
        aiSummary: json['ai_summary'] is Map ? Map<String, dynamic>.from(json['ai_summary'] as Map) : null,
        remedials: json['remedials'] is List ? (json['remedials'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [],
        teacherReviewRequired: json['teacher_review_required'] == true,
      );
}

class AssessmentAnswer {
  final int id;
  final int questionId;
  final dynamic answerValue;
  final String answerText;
  final double? awardedMarks;
  final String teacherRemark;
  final String aiDetectedText;
  final double? aiAwardedMarks;
  final String aiRemark;
  final double? aiConfidence;
  final bool aiReviewRequired;
  final Map<String, dynamic>? aiMeta;
  final AssessmentQuestion? question;

  const AssessmentAnswer({
    required this.id,
    required this.questionId,
    this.answerValue,
    required this.answerText,
    this.awardedMarks,
    required this.teacherRemark,
    required this.aiDetectedText,
    this.aiAwardedMarks,
    required this.aiRemark,
    this.aiConfidence,
    required this.aiReviewRequired,
    this.aiMeta,
    this.question,
  });

  factory AssessmentAnswer.fromJson(Map<String, dynamic> json) =>
      AssessmentAnswer(
        id: _int(json['id']),
        questionId: _int(json['question_id']),
        answerValue: json['answer_value'],
        answerText: json['answer_text']?.toString() ?? '',
        awardedMarks: _nullableDouble(json['awarded_marks']),
        teacherRemark: json['teacher_remark']?.toString() ?? '',
        aiDetectedText: json['ai_detected_text']?.toString() ?? '',
        aiAwardedMarks: _nullableDouble(json['ai_awarded_marks']),
        aiRemark: json['ai_remark']?.toString() ?? '',
        aiConfidence: _nullableDouble(json['ai_confidence']),
        aiReviewRequired: json['ai_review_required'] == true,
        aiMeta: json['ai_meta'] is Map ? Map<String, dynamic>.from(json['ai_meta'] as Map) : null,
        question: json['question'] is Map
            ? AssessmentQuestion.fromJson(
                Map<String, dynamic>.from(json['question'] as Map))
            : null,
      );
}

class AssessmentSubmission {
  final int id;
  final int studentId;
  final String status;
  final String studentName;
  final String admissionNumber;
  final double? obtainedMarks;
  final String? feedback;
  final DateTime? submittedAt;
  final AssessmentAttempt? latestAttempt;

  const AssessmentSubmission({
    required this.id,
    required this.studentId,
    required this.status,
    required this.studentName,
    required this.admissionNumber,
    this.obtainedMarks,
    this.feedback,
    this.submittedAt,
    this.latestAttempt,
  });

  factory AssessmentSubmission.fromJson(Map<String, dynamic> json) =>
      AssessmentSubmission(
        id: _int(json['id']),
        studentId: _int(json['student_id']),
        status: json['status']?.toString() ?? 'assigned',
        studentName: _nested(json, 'student', 'name'),
        admissionNumber: _nested(json, 'student', 'admission_number'),
        obtainedMarks: _nullableDouble(json['obtained_marks']),
        feedback: json['teacher_feedback']?.toString(),
        submittedAt: _date(json['submitted_at']),
        latestAttempt: json['latestAttempt'] is Map
            ? AssessmentAttempt.fromJson(
                Map<String, dynamic>.from(json['latestAttempt'] as Map))
            : null,
      );
}

int _int(dynamic value, [int fallback = 0]) =>
    int.tryParse(value?.toString() ?? '') ?? fallback;
int? _nullableInt(dynamic value) =>
    value == null ? null : int.tryParse(value.toString());
double _double(dynamic value, [double fallback = 0]) =>
    double.tryParse(value?.toString() ?? '') ?? fallback;
double? _nullableDouble(dynamic value) =>
    value == null ? null : double.tryParse(value.toString());
DateTime? _date(dynamic value) =>
    value == null || value.toString().isEmpty
        ? null
        : DateTime.tryParse(value.toString())?.toLocal();
String _nested(Map<String, dynamic> json, String parent, String child) {
  final value = json[parent];
  return value is Map ? value[child]?.toString() ?? '' : '';
}
List<T> _mapList<T>(dynamic value, T Function(Map<String, dynamic>) build) =>
    value is List
        ? value
            .whereType<Map>()
            .map((row) => build(Map<String, dynamic>.from(row)))
            .toList()
        : <T>[];
