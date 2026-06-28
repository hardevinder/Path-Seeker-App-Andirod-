// lib/models/academic_calendar_models.dart

class AcademicCalendarModel {
  final int? id;
  final String title;
  final String academicSession;
  final String status;
  final String schoolName;
  final String startDate;
  final String endDate;
  final int? totalWorkingDays;
  final String remarks;

  const AcademicCalendarModel({
    required this.id,
    required this.title,
    required this.academicSession,
    required this.status,
    required this.schoolName,
    required this.startDate,
    required this.endDate,
    required this.totalWorkingDays,
    required this.remarks,
  });

  factory AcademicCalendarModel.fromJson(Map<String, dynamic> json) {
    final school = _asMap(json['school'] ?? json['School']);

    return AcademicCalendarModel(
      id: _intValue(json['id'] ?? json['calendar_id']),
      title: _stringValue(
        json['title'] ?? json['name'],
        fallback: 'Academic Calendar',
      ),
      academicSession: _stringValue(
        json['academic_session'] ??
            json['session'] ??
            json['session_name'] ??
            json['academicSession'],
        fallback: '-',
      ),
      status: _statusValue(json),
      schoolName: _stringValue(
        json['school_name'] ?? school?['name'] ?? school?['school_name'],
        fallback: '',
      ),
      startDate: _dateOnly(json['start_date'] ?? json['startDate']),
      endDate: _dateOnly(json['end_date'] ?? json['endDate']),
      totalWorkingDays: _intValue(
        json['total_working_days'] ?? json['working_days'] ?? json['workingDays'],
      ),
      remarks: _stringValue(json['remarks'] ?? json['description'], fallback: ''),
    );
  }

  bool get isPublished {
    final normalized = status.trim().toLowerCase();
    return normalized == 'published' || normalized == 'publish' || normalized == 'active';
  }

  String get dateRange {
    if (startDate.isEmpty && endDate.isEmpty) return '-';
    if (startDate.isEmpty) return endDate;
    if (endDate.isEmpty) return startDate;
    return '$startDate to $endDate';
  }
}

class AcademicCalendarEventModel {
  final int? id;
  final String title;
  final String type;
  final String date;
  final String startDate;
  final String endDate;
  final String description;
  final String venue;

  const AcademicCalendarEventModel({
    required this.id,
    required this.title,
    required this.type,
    required this.date,
    required this.startDate,
    required this.endDate,
    required this.description,
    required this.venue,
  });

  factory AcademicCalendarEventModel.fromJson(Map<String, dynamic> json) {
    return AcademicCalendarEventModel(
      id: _intValue(json['id'] ?? json['event_id']),
      title: _stringValue(
        json['title'] ?? json['name'] ?? json['event_title'] ?? json['eventTitle'],
        fallback: 'Calendar Event',
      ),
      type: _stringValue(json['type'] ?? json['event_type'] ?? json['eventType'], fallback: 'OTHER'),
      date: _dateOnly(json['date'] ?? json['event_date'] ?? json['eventDate']),
      startDate: _dateOnly(json['start_date'] ?? json['startDate']),
      endDate: _dateOnly(json['end_date'] ?? json['endDate']),
      description: _stringValue(json['description'] ?? json['remarks'] ?? json['note'], fallback: ''),
      venue: _stringValue(json['venue'] ?? json['location'], fallback: ''),
    );
  }

  String get displayDate {
    if (date.isNotEmpty) return date;
    if (startDate.isEmpty && endDate.isEmpty) return '-';
    if (startDate.isEmpty) return endDate;
    if (endDate.isEmpty || endDate == startDate) return startDate;
    return '$startDate to $endDate';
  }
}


String _statusValue(Map<String, dynamic> json) {
  final direct = _stringValue(json['status'], fallback: '');
  if (direct.isNotEmpty) return direct;

  final rawPublished = json['is_published'] ??
      json['isPublished'] ??
      json['published'] ??
      json['is_active'] ??
      json['isActive'];

  if (rawPublished is bool) return rawPublished ? 'PUBLISHED' : 'DRAFT';
  if (rawPublished != null) {
    final text = rawPublished.toString().trim().toLowerCase();
    if (text == '1' || text == 'true' || text == 'yes' || text == 'published') {
      return 'PUBLISHED';
    }
  }

  return '';
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

String _stringValue(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

int? _intValue(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

String _dateOnly(dynamic value) {
  if (value == null) return '';
  final text = value.toString().trim();
  if (text.isEmpty) return '';
  if (text.length >= 10) return text.substring(0, 10);
  return text;
}