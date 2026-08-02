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
