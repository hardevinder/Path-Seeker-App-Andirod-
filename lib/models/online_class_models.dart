class ZoomConnection {
  final bool connected;
  final String? email;
  final DateTime? connectedAt;
  final String tokenStatus;

  const ZoomConnection({
    required this.connected,
    this.email,
    this.connectedAt,
    this.tokenStatus = 'not_connected',
  });

  factory ZoomConnection.fromJson(Map<String, dynamic> json) => ZoomConnection(
        connected: json['connected'] == true,
        email: json['zoom_email']?.toString(),
        connectedAt: DateTime.tryParse(json['connected_at']?.toString() ?? ''),
        tokenStatus: json['token_status']?.toString() ?? 'not_connected',
      );
}

class OnlineClass {
  final int id;
  final int classId;
  final int? sectionId;
  final int subjectId;
  final String title;
  final String? agenda;
  final DateTime startTime;
  final String timezone;
  final int durationMinutes;
  final String status;
  final String teacherName;
  final String className;
  final String sectionName;
  final String subjectName;
  final bool canStart;
  final bool canManage;
  final Map<String, dynamic> settings;

  const OnlineClass({
    required this.id,
    required this.classId,
    this.sectionId,
    required this.subjectId,
    required this.title,
    this.agenda,
    required this.startTime,
    required this.timezone,
    required this.durationMinutes,
    required this.status,
    required this.teacherName,
    required this.className,
    required this.sectionName,
    required this.subjectName,
    required this.canStart,
    required this.canManage,
    required this.settings,
  });

  static int _int(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;

  factory OnlineClass.fromJson(Map<String, dynamic> json) => OnlineClass(
        id: _int(json['id']),
        classId: _int(json['class_id']),
        sectionId: json['section_id'] == null ? null : _int(json['section_id']),
        subjectId: _int(json['subject_id']),
        title: json['title']?.toString() ?? 'Online class',
        agenda: json['agenda']?.toString(),
        startTime: DateTime.tryParse(json['start_time']?.toString() ?? '')
                ?.toLocal() ??
            DateTime.now(),
        timezone: json['timezone']?.toString() ?? 'Asia/Kolkata',
        durationMinutes: _int(json['duration_minutes']),
        status: json['status']?.toString() ?? 'scheduled',
        teacherName:
            (json['teacher'] as Map?)?['name']?.toString() ?? 'Teacher',
        className:
            (json['class'] as Map?)?['class_name']?.toString() ?? 'Class',
        sectionName:
            (json['section'] as Map?)?['section_name']?.toString() ?? '',
        subjectName:
            (json['subject'] as Map?)?['name']?.toString() ?? 'Subject',
        canStart: json['can_start'] == true,
        canManage: json['can_manage'] == true,
        settings: json['settings'] is Map
            ? Map<String, dynamic>.from(json['settings'])
            : const {},
      );
}

class AcademicOption {
  final int id;
  final String name;
  final int? classId;
  const AcademicOption({required this.id, required this.name, this.classId});
}

class OnlineClassAssignment {
  final int classId;
  final String className;
  final int sectionId;
  final String sectionName;
  final int subjectId;
  final String subjectName;

  const OnlineClassAssignment({
    required this.classId,
    required this.className,
    required this.sectionId,
    required this.sectionName,
    required this.subjectId,
    required this.subjectName,
  });

  factory OnlineClassAssignment.fromJson(Map<String, dynamic> json) {
    int number(dynamic value) =>
        value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
    return OnlineClassAssignment(
      classId: number(json['class_id']),
      className: json['class_name']?.toString() ?? '',
      sectionId: number(json['section_id']),
      sectionName: json['section_name']?.toString() ?? '',
      subjectId: number(json['subject_id']),
      subjectName: json['subject_name']?.toString() ?? '',
    );
  }
}

class OnlineClassAttendanceStudent {
  final int id;
  final String name;
  final String admissionNumber;

  const OnlineClassAttendanceStudent({
    required this.id,
    required this.name,
    required this.admissionNumber,
  });

  factory OnlineClassAttendanceStudent.fromJson(Map<String, dynamic> json) =>
      OnlineClassAttendanceStudent(
        id: OnlineClassAttendanceReport.asInt(json['id']),
        name: json['name']?.toString() ?? 'Student',
        admissionNumber: json['admission_number']?.toString() ?? '',
      );
}

class OnlineClassAttendanceSession {
  final int id;
  final int? studentId;
  final String participantName;
  final String? zoomEmail;
  final DateTime? joinedAt;
  final DateTime? leftAt;
  final int durationSeconds;
  final String matchingStatus;

  const OnlineClassAttendanceSession({
    required this.id,
    this.studentId,
    required this.participantName,
    this.zoomEmail,
    this.joinedAt,
    this.leftAt,
    required this.durationSeconds,
    required this.matchingStatus,
  });

  factory OnlineClassAttendanceSession.fromJson(Map<String, dynamic> json) =>
      OnlineClassAttendanceSession(
        id: OnlineClassAttendanceReport.asInt(json['id']),
        studentId: json['student_id'] == null
            ? null
            : OnlineClassAttendanceReport.asInt(json['student_id']),
        participantName:
            json['participant_name']?.toString() ?? 'Unknown participant',
        zoomEmail: json['zoom_email']?.toString(),
        joinedAt: OnlineClassAttendanceReport.asDate(json['joined_at']),
        leftAt: OnlineClassAttendanceReport.asDate(json['left_at']),
        durationSeconds:
            OnlineClassAttendanceReport.asInt(json['duration_seconds']),
        matchingStatus: json['matching_status']?.toString() ?? 'unmatched',
      );
}

class OnlineClassAttendanceRow {
  final int? id;
  final OnlineClassAttendanceStudent student;
  final DateTime? firstJoinedAt;
  final DateTime? lastLeftAt;
  final int totalDurationSeconds;
  final double attendancePercentage;
  final String status;
  final bool isLate;
  final String matchingStatus;
  final int matchConfidence;
  final bool manualOverride;
  final String? notes;
  final List<OnlineClassAttendanceSession> sessions;

  const OnlineClassAttendanceRow({
    this.id,
    required this.student,
    this.firstJoinedAt,
    this.lastLeftAt,
    required this.totalDurationSeconds,
    required this.attendancePercentage,
    required this.status,
    required this.isLate,
    required this.matchingStatus,
    required this.matchConfidence,
    required this.manualOverride,
    this.notes,
    required this.sessions,
  });

  factory OnlineClassAttendanceRow.fromJson(Map<String, dynamic> json) {
    final studentJson = json['student'] is Map
        ? Map<String, dynamic>.from(json['student'] as Map)
        : <String, dynamic>{};
    final sessionRows = json['sessions'] is List
        ? (json['sessions'] as List)
            .whereType<Map>()
            .map((row) => OnlineClassAttendanceSession.fromJson(
                Map<String, dynamic>.from(row)))
            .toList()
        : <OnlineClassAttendanceSession>[];
    return OnlineClassAttendanceRow(
      id: json['id'] == null
          ? null
          : OnlineClassAttendanceReport.asInt(json['id']),
      student: OnlineClassAttendanceStudent.fromJson(studentJson),
      firstJoinedAt:
          OnlineClassAttendanceReport.asDate(json['first_joined_at']),
      lastLeftAt: OnlineClassAttendanceReport.asDate(json['last_left_at']),
      totalDurationSeconds:
          OnlineClassAttendanceReport.asInt(json['total_duration_seconds']),
      attendancePercentage:
          OnlineClassAttendanceReport.asDouble(json['attendance_percentage']),
      status: json['status']?.toString() ?? 'pending',
      isLate: json['is_late'] == true,
      matchingStatus: json['matching_status']?.toString() ?? 'unmatched',
      matchConfidence:
          OnlineClassAttendanceReport.asInt(json['match_confidence']),
      manualOverride: json['manual_override'] == true,
      notes: json['notes']?.toString(),
      sessions: sessionRows,
    );
  }
}

class OnlineClassAttendanceSummary {
  final int total;
  final int present;
  final int partial;
  final int absent;
  final int excused;
  final int pending;
  final int late;
  final int needsReview;

  const OnlineClassAttendanceSummary({
    required this.total,
    required this.present,
    required this.partial,
    required this.absent,
    required this.excused,
    required this.pending,
    required this.late,
    required this.needsReview,
  });

  factory OnlineClassAttendanceSummary.fromJson(Map<String, dynamic> json) =>
      OnlineClassAttendanceSummary(
        total: OnlineClassAttendanceReport.asInt(json['total']),
        present: OnlineClassAttendanceReport.asInt(json['present']),
        partial: OnlineClassAttendanceReport.asInt(json['partial']),
        absent: OnlineClassAttendanceReport.asInt(json['absent']),
        excused: OnlineClassAttendanceReport.asInt(json['excused']),
        pending: OnlineClassAttendanceReport.asInt(json['pending']),
        late: OnlineClassAttendanceReport.asInt(json['late']),
        needsReview: OnlineClassAttendanceReport.asInt(json['needs_review']),
      );
}

class OnlineClassAttendanceRules {
  final int presentPercent;
  final int partialPercent;
  final int lateMinutes;

  const OnlineClassAttendanceRules({
    required this.presentPercent,
    required this.partialPercent,
    required this.lateMinutes,
  });

  factory OnlineClassAttendanceRules.fromJson(Map<String, dynamic> json) =>
      OnlineClassAttendanceRules(
        presentPercent: OnlineClassAttendanceReport.asInt(
            json['presentPercent'] ?? json['present_percent'] ?? 75),
        partialPercent: OnlineClassAttendanceReport.asInt(
            json['partialPercent'] ?? json['partial_percent'] ?? 25),
        lateMinutes: OnlineClassAttendanceReport.asInt(
            json['lateMinutes'] ?? json['late_minutes'] ?? 10),
      );
}

class OnlineClassAttendanceReport {
  final OnlineClassAttendanceSummary summary;
  final OnlineClassAttendanceRules rules;
  final List<OnlineClassAttendanceRow> rows;
  final List<OnlineClassAttendanceSession> unmatchedSessions;

  const OnlineClassAttendanceReport({
    required this.summary,
    required this.rules,
    required this.rows,
    required this.unmatchedSessions,
  });

  static int asInt(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;

  static double asDouble(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  static DateTime? asDate(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed?.toLocal();
  }

  factory OnlineClassAttendanceReport.fromJson(Map<String, dynamic> json) {
    final summaryJson = json['summary'] is Map
        ? Map<String, dynamic>.from(json['summary'] as Map)
        : <String, dynamic>{};
    final rulesJson = json['rules'] is Map
        ? Map<String, dynamic>.from(json['rules'] as Map)
        : <String, dynamic>{};
    final rows = json['rows'] is List
        ? (json['rows'] as List)
            .whereType<Map>()
            .map((row) => OnlineClassAttendanceRow.fromJson(
                Map<String, dynamic>.from(row)))
            .toList()
        : <OnlineClassAttendanceRow>[];
    final unmatched = json['unmatched_sessions'] is List
        ? (json['unmatched_sessions'] as List)
            .whereType<Map>()
            .map((row) => OnlineClassAttendanceSession.fromJson(
                Map<String, dynamic>.from(row)))
            .toList()
        : <OnlineClassAttendanceSession>[];
    return OnlineClassAttendanceReport(
      summary: OnlineClassAttendanceSummary.fromJson(summaryJson),
      rules: OnlineClassAttendanceRules.fromJson(rulesJson),
      rows: rows,
      unmatchedSessions: unmatched,
    );
  }
}
