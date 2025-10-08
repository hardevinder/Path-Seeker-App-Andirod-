// lib/models/timetable_models.dart
import 'package:flutter/foundation.dart';

class Period {
  final String id;
  final String periodName;
  final String? startTime;
  final String? endTime;

  Period({required this.id, required this.periodName, this.startTime, this.endTime});

  factory Period.fromJson(Map<String, dynamic> j) => Period(
        id: j['id']?.toString() ?? '',
        periodName: j['period_name']?.toString() ?? j['name']?.toString() ?? '',
        startTime: j['start_time'] as String?,
        endTime: j['end_time'] as String?,
      );
}

class TimetableRecord {
  final String id;
  final String day; // Monday..Saturday (expected)
  final String periodId;
  final String? subjectId;
  final Map<String, dynamic>? Subject;
  final Map<String, dynamic>? Teacher;

  TimetableRecord({
    required this.id,
    required this.day,
    required this.periodId,
    this.subjectId,
    this.Subject,
    this.Teacher,
  });

  factory TimetableRecord.fromJson(Map<String, dynamic> j) => TimetableRecord(
        id: j['id']?.toString() ?? '',
        day: j['day']?.toString() ?? '',
        periodId: j['periodId']?.toString() ?? j['period_id']?.toString() ?? '',
        subjectId: j['subjectId']?.toString() ?? j['subject_id']?.toString(),
        Subject: j['Subject'] is Map ? Map<String, dynamic>.from(j['Subject']) : null,
        Teacher: j['Teacher'] is Map ? Map<String, dynamic>.from(j['Teacher']) : null,
      );
}

class Holiday {
  final String id;
  final String date; // yyyy-MM-dd
  final String? description;

  Holiday({required this.id, required this.date, this.description});

  factory Holiday.fromJson(Map<String, dynamic> j) => Holiday(
        id: j['id']?.toString() ?? '',
        date: j['date']?.toString() ?? '',
        description: j['description']?.toString(),
      );
}

class Substitution {
  final String id;
  final String date; // yyyy-MM-dd
  final String day;
  final String periodId;
  final Map<String, dynamic>? Subject;
  final Map<String, dynamic>? Teacher;

  Substitution({
    required this.id,
    required this.date,
    required this.day,
    required this.periodId,
    this.Subject,
    this.Teacher,
  });

  factory Substitution.fromJson(Map<String, dynamic> j) => Substitution(
        id: j['id']?.toString() ?? '',
        date: j['date']?.toString() ?? '',
        day: j['day']?.toString() ?? '',
        periodId: j['periodId']?.toString() ?? j['period_id']?.toString() ?? '',
        Subject: j['Subject'] is Map ? Map<String, dynamic>.from(j['Subject']) : null,
        Teacher: j['Teacher'] is Map ? Map<String, dynamic>.from(j['Teacher']) : null,
      );
}
