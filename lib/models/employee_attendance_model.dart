import 'package:flutter/material.dart';

String normalizeAttendanceStatus(dynamic value) {
  return (value ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(RegExp(r'\s+'), '_');
}

String prettyAttendanceStatus(dynamic value) {
  final normalized = normalizeAttendanceStatus(value);
  if (normalized.isEmpty) return '';
  return normalized
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}

bool isNoTimeAttendanceStatus(dynamic status) {
  const noTimeStatuses = {
    'absent',
    'leave',
    'full_day_leave',
    'medical_leave',
    'holiday',
  };
  return noTimeStatuses.contains(normalizeAttendanceStatus(status));
}

class EmployeeAttendanceOption {
  final String value;
  final String label;
  final String abbreviation;
  final Color color;

  const EmployeeAttendanceOption({
    required this.value,
    required this.label,
    required this.abbreviation,
    required this.color,
  });

  factory EmployeeAttendanceOption.fromLeaveType(
    Map<String, dynamic> json,
    EmployeeAttendanceOption? fallback,
  ) {
    final name = (json['name'] ?? json['label'] ?? '').toString().trim();
    final value = normalizeAttendanceStatus(name);
    final label = name.isNotEmpty
        ? name
        : fallback?.label ?? prettyAttendanceStatus(value);
    final abbr = (json['abbreviation'] ?? json['abbr'] ?? '')
        .toString()
        .trim()
        .toUpperCase();

    return EmployeeAttendanceOption(
      value: value,
      label: label,
      abbreviation: abbr.isNotEmpty
          ? abbr
          : fallback?.abbreviation ?? _autoAbbreviation(label),
      color: fallback?.color ?? const Color(0xFF64748B),
    );
  }

  static String _autoAbbreviation(String label) {
    final clean = label.trim();
    if (clean.isEmpty) return '-';
    final words = clean.split(RegExp(r'\s+'));
    if (words.length > 1) {
      return words.map((w) => w.isEmpty ? '' : w[0]).join().toUpperCase();
    }
    return clean.length <= 3
        ? clean.toUpperCase()
        : clean.substring(0, 3).toUpperCase();
  }
}

const List<EmployeeAttendanceOption> defaultEmployeeAttendanceOptions = [
  EmployeeAttendanceOption(
    value: 'present',
    label: 'Present',
    abbreviation: 'P',
    color: Color(0xFF16A34A),
  ),
  EmployeeAttendanceOption(
    value: 'absent',
    label: 'Absent',
    abbreviation: 'A',
    color: Color(0xFFDC2626),
  ),
  EmployeeAttendanceOption(
    value: 'first_half_day_leave',
    label: '1st Half Leave',
    abbreviation: 'H1',
    color: Color(0xFF2563EB),
  ),
  EmployeeAttendanceOption(
    value: 'second_half_day_leave',
    label: '2nd Half Leave',
    abbreviation: 'H2',
    color: Color(0xFF0EA5E9),
  ),
  EmployeeAttendanceOption(
    value: 'half_day_without_pay',
    label: 'Half-day (No Pay)',
    abbreviation: 'HNP',
    color: Color(0xFF7C3AED),
  ),
  EmployeeAttendanceOption(
    value: 'short_leave',
    label: 'Short Leave',
    abbreviation: 'SL',
    color: Color(0xFFF59E0B),
  ),
  EmployeeAttendanceOption(
    value: 'full_day_leave',
    label: 'Full Day Leave',
    abbreviation: 'FD',
    color: Color(0xFF14B8A6),
  ),
  EmployeeAttendanceOption(
    value: 'leave',
    label: 'Leave',
    abbreviation: 'L',
    color: Color(0xFF0891B2),
  ),
  EmployeeAttendanceOption(
    value: 'medical_leave',
    label: 'Medical Leave',
    abbreviation: 'ML',
    color: Color(0xFF334155),
  ),
  EmployeeAttendanceOption(
    value: 'holiday',
    label: 'Holiday',
    abbreviation: 'HOL',
    color: Color(0xFF64748B),
  ),
];

class EmployeeLite {
  final int id;
  final String name;
  final String employeeCode;
  final String phone;
  final String email;
  final String designation;
  final String status;
  final int? departmentId;
  final String departmentName;

  const EmployeeLite({
    required this.id,
    required this.name,
    required this.employeeCode,
    required this.phone,
    required this.email,
    required this.designation,
    required this.status,
    required this.departmentId,
    required this.departmentName,
  });

  bool get isEnabled => status.toLowerCase() != 'disabled';

  factory EmployeeLite.fromJson(Map<String, dynamic> json) {
    final department = json['department'];
    final departmentMap = department is Map
        ? Map<String, dynamic>.from(department)
        : <String, dynamic>{};

    return EmployeeLite(
      id: _toInt(json['id']) ?? 0,
      name: _safe(json['name']).isNotEmpty
          ? _safe(json['name'])
          : _safe(json['employee_name'], 'Employee'),
      employeeCode: _safe(
        json['employee_id'] ?? json['employeeCode'] ?? json['code'],
      ),
      phone: _safe(json['phone'] ?? json['mobile']),
      email: _safe(json['email']),
      designation: _safe(json['designation']),
      status: _safe(json['status'], 'enabled').toLowerCase(),
      departmentId: _toInt(json['department_id'] ?? departmentMap['id']),
      departmentName: _safe(
        departmentMap['name'] ??
            json['department_name'] ??
            json['departmentName'] ??
            json['department'],
        'No Department',
      ),
    );
  }
}

class EmployeeAttendanceDraft {
  final String status;
  final String remarks;
  final String inTime;
  final String outTime;

  const EmployeeAttendanceDraft({
    this.status = '',
    this.remarks = '',
    this.inTime = '',
    this.outTime = '',
  });

  EmployeeAttendanceDraft copyWith({
    String? status,
    String? remarks,
    String? inTime,
    String? outTime,
  }) {
    final nextStatus = normalizeAttendanceStatus(status ?? this.status);
    final clearTime = isNoTimeAttendanceStatus(nextStatus);
    return EmployeeAttendanceDraft(
      status: nextStatus,
      remarks: remarks ?? this.remarks,
      inTime: clearTime ? '' : inTime ?? this.inTime,
      outTime: clearTime ? '' : outTime ?? this.outTime,
    );
  }

  factory EmployeeAttendanceDraft.fromJson(Map<String, dynamic> json) {
    final status = normalizeAttendanceStatus(json['status']);
    final clearTime = isNoTimeAttendanceStatus(status);
    return EmployeeAttendanceDraft(
      status: status,
      remarks: _safe(json['remarks']),
      inTime: clearTime ? '' : _safe(json['in_time'] ?? json['inTime']),
      outTime: clearTime ? '' : _safe(json['out_time'] ?? json['outTime']),
    );
  }

  Map<String, dynamic> toApiPayload(int employeeId) {
    final clearTime = isNoTimeAttendanceStatus(status);
    return {
      'employee_id': employeeId,
      'status': normalizeAttendanceStatus(status),
      'remarks': remarks.trim(),
      'in_time': clearTime || inTime.trim().isEmpty ? null : inTime.trim(),
      'out_time': clearTime || outTime.trim().isEmpty ? null : outTime.trim(),
    };
  }
}

class EmployeeAttendanceDayRecord {
  final DateTime date;
  final String status;
  final String remarks;
  final String inTime;
  final String outTime;

  const EmployeeAttendanceDayRecord({
    required this.date,
    required this.status,
    this.remarks = '',
    this.inTime = '',
    this.outTime = '',
  });

  String get dateKey =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  factory EmployeeAttendanceDayRecord.fromJson(Map<String, dynamic> json) {
    return EmployeeAttendanceDayRecord(
      date: _parseDate(json['date']) ?? DateTime.now(),
      status: normalizeAttendanceStatus(json['status']),
      remarks: _safe(json['remarks']),
      inTime: _safe(json['in_time'] ?? json['inTime']),
      outTime: _safe(json['out_time'] ?? json['outTime']),
    );
  }
}

class EmployeeMonthlyAttendanceSummary {
  final List<EmployeeAttendanceDayRecord> records;
  final Map<String, int> counts;
  final int calendarDays;
  final int sundays;
  final int holidays;
  final int workingDays;
  final int unmarkedDays;
  final double leaveDaysEquivalent;
  final int halfDaysCount;
  final double halfDayEquivalentDays;
  final int absentDays;

  const EmployeeMonthlyAttendanceSummary({
    required this.records,
    required this.counts,
    required this.calendarDays,
    required this.sundays,
    required this.holidays,
    required this.workingDays,
    required this.unmarkedDays,
    required this.leaveDaysEquivalent,
    required this.halfDaysCount,
    required this.halfDayEquivalentDays,
    required this.absentDays,
  });

  int get presentDays => counts['present'] ?? 0;
  int get holidayRows => counts['holiday'] ?? 0;

  factory EmployeeMonthlyAttendanceSummary.fromJson(
    Map<String, dynamic> json,
    DateTime monthDate,
  ) {
    final rawRecords = _extractListFromAny(json, const ['records', 'data']);
    final records = rawRecords
        .whereType<Map>()
        .map((e) => EmployeeAttendanceDayRecord.fromJson(
              Map<String, dynamic>.from(e),
            ))
        .toList();

    final countsRaw = json['counts'] ?? json['summary'] ?? <String, dynamic>{};
    final counts = <String, int>{};
    if (countsRaw is Map) {
      countsRaw.forEach((key, value) {
        counts[normalizeAttendanceStatus(key)] = _toInt(value) ?? 0;
      });
    }

    final meta = json['meta'] is Map
        ? Map<String, dynamic>.from(json['meta'] as Map)
        : <String, dynamic>{};
    final derived = json['derived'] is Map
        ? Map<String, dynamic>.from(json['derived'] as Map)
        : <String, dynamic>{};

    final daysInMonth = DateUtils.getDaysInMonth(monthDate.year, monthDate.month);
    int sundayCount = 0;
    for (var day = 1; day <= daysInMonth; day++) {
      if (DateTime(monthDate.year, monthDate.month, day).weekday ==
          DateTime.sunday) {
        sundayCount++;
      }
    }

    final holidayCount = _toInt(meta['holidays']) ?? 0;
    final workingDays = _toInt(meta['working_days']) ??
        (daysInMonth - sundayCount - holidayCount)
            .clamp(0, daysInMonth)
            .toInt();

    final markedWorkingDates = records
        .where((record) => record.status != 'holiday')
        .where((record) => record.date.weekday != DateTime.sunday)
        .map((record) => record.dateKey)
        .toSet();

    final firstHalf = counts['first_half_day_leave'] ?? 0;
    final secondHalf = counts['second_half_day_leave'] ?? 0;
    final halfNoPay = counts['half_day_without_pay'] ?? 0;
    final halfDays = firstHalf + secondHalf + halfNoPay;
    final shortLeave = counts['short_leave'] ?? 0;
    final leaveFull = (counts['leave'] ?? 0) +
        (counts['full_day_leave'] ?? 0) +
        (counts['medical_leave'] ?? 0);

    return EmployeeMonthlyAttendanceSummary(
      records: records,
      counts: counts,
      calendarDays: _toInt(meta['calendar_days']) ?? daysInMonth,
      sundays: _toInt(meta['sundays']) ?? sundayCount,
      holidays: holidayCount,
      workingDays: workingDays,
      unmarkedDays: _toInt(derived['unmarked_days']) ??
          (workingDays - markedWorkingDates.length)
              .clamp(0, workingDays)
              .toInt(),
      leaveDaysEquivalent: _toDouble(derived['leave_days_equiv']) ??
          leaveFull.toDouble() + (halfDays.toDouble() * 0.5) + (shortLeave.toDouble() * 0.25),
      halfDaysCount: _toInt(derived['half_days_count']) ?? halfDays,
      halfDayEquivalentDays:
          _toDouble(derived['half_day_equiv_days']) ?? halfDays.toDouble() * 0.5,
      absentDays: _toInt(derived['absent_days']) ?? counts['absent'] ?? 0,
    );
  }
}

String _safe(dynamic value, [String fallback = '']) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty || text == 'null' ? fallback : text;
}

int? _toInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

DateTime? _parseDate(dynamic value) {
  final raw = _safe(value);
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw.length >= 10 ? raw.substring(0, 10) : raw);
}

List<dynamic> _extractListFromAny(dynamic decoded, List<String> keys) {
  if (decoded is List) return decoded;
  if (decoded is Map) {
    for (final key in keys) {
      final value = decoded[key];
      if (value is List) return value;
    }
    final data = decoded['data'];
    if (data is Map) {
      for (final key in keys) {
        final value = data[key];
        if (value is List) return value;
      }
    }
  }
  return <dynamic>[];
}