import 'dart:async';
import 'dart:convert';

import '../models/employee_attendance_model.dart';
import 'api_service.dart';

class EmployeeAttendanceApi {
  const EmployeeAttendanceApi._();

  static Future<List<EmployeeLite>> fetchEmployees() async {
    final response = await ApiService.rawGet('/employees');
    _throwIfFailed(response.statusCode, response.body, 'Failed to load employees.');

    final decoded = jsonDecode(response.body);
    final rows = _extractRows(decoded, keys: const [
      'employees',
      'data',
      'rows',
      'records',
      'items',
    ]);

    return rows
        .whereType<Map>()
        .map((item) => EmployeeLite.fromJson(Map<String, dynamic>.from(item)))
        .where((employee) => employee.id > 0 && employee.isEnabled)
        .toList();
  }

  static Future<List<EmployeeAttendanceOption>> fetchAttendanceOptions() async {
    final fallbackByValue = {
      for (final option in defaultEmployeeAttendanceOptions) option.value: option,
    };

    try {
      final response = await ApiService.rawGet('/employee-leave-types');
      _throwIfFailed(
        response.statusCode,
        response.body,
        'Failed to load attendance options.',
      );

      final decoded = jsonDecode(response.body);
      final rows = _extractRows(decoded, keys: const [
        'data',
        'leaveTypes',
        'employeeLeaveTypes',
        'rows',
        'records',
      ]);

      final byValue = <String, EmployeeAttendanceOption>{
        for (final option in defaultEmployeeAttendanceOptions) option.value: option,
      };

      for (final row in rows.whereType<Map>()) {
        final map = Map<String, dynamic>.from(row);
        final value = normalizeAttendanceStatus(map['name'] ?? map['label']);
        if (value.isEmpty) continue;
        byValue[value] = EmployeeAttendanceOption.fromLeaveType(
          map,
          fallbackByValue[value],
        );
      }

      final known = defaultEmployeeAttendanceOptions
          .map((option) => byValue[option.value])
          .whereType<EmployeeAttendanceOption>()
          .toList();
      final extras = byValue.entries
          .where((entry) => !fallbackByValue.containsKey(entry.key))
          .map((entry) => entry.value)
          .toList();

      return [...known, ...extras];
    } catch (_) {
      return defaultEmployeeAttendanceOptions;
    }
  }

  static Future<Map<int, EmployeeAttendanceDraft>> fetchMarkedAttendance(
    DateTime date,
  ) async {
    final response = await ApiService.rawGet(
      '/employee-attendance?date=${_dateOnly(date)}',
    );
    _throwIfFailed(
      response.statusCode,
      response.body,
      'Failed to load marked attendance.',
    );

    final decoded = jsonDecode(response.body);
    final rows = _extractRows(decoded, keys: const [
      'records',
      'data',
      'attendance',
      'rows',
    ]);

    final mapped = <int, EmployeeAttendanceDraft>{};
    for (final row in rows.whereType<Map>()) {
      final map = Map<String, dynamic>.from(row);
      final employeeId = _toInt(map['employee_id'] ?? map['employeeId']);
      if (employeeId == null) continue;
      mapped[employeeId] = EmployeeAttendanceDraft.fromJson(map);
    }
    return mapped;
  }

  static Future<String> markAttendance({
    required DateTime date,
    required Iterable<MapEntry<int, EmployeeAttendanceDraft>> drafts,
  }) async {
    final attendances = drafts
        .where((entry) => normalizeAttendanceStatus(entry.value.status).isNotEmpty)
        .map((entry) => entry.value.toApiPayload(entry.key))
        .toList();

    if (attendances.isEmpty) {
      throw Exception('Please mark at least one employee attendance.');
    }

    final response = await ApiService.rawPost('/employee-attendance/mark', {
      'date': _dateOnly(date),
      'attendances': attendances,
    });

    _throwIfFailed(response.statusCode, response.body, 'Failed to save attendance.');

    final decoded = _tryJson(response.body);
    if (decoded is Map) {
      final message = decoded['message'] ?? decoded['msg'];
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString();
      }
    }
    return 'Employee attendance saved successfully.';
  }

  static Future<EmployeeMonthlyAttendanceSummary> fetchEmployeeMonthSummary({
    required int employeeId,
    required DateTime month,
  }) async {
    final monthKey =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
    final response = await ApiService.rawGet(
      '/employee-attendance/summary/$employeeId?month=$monthKey',
    );

    _throwIfFailed(
      response.statusCode,
      response.body,
      'Failed to load employee attendance calendar.',
    );

    final decoded = _tryJson(response.body);
    if (decoded is Map) {
      return EmployeeMonthlyAttendanceSummary.fromJson(
        Map<String, dynamic>.from(decoded),
        DateTime(month.year, month.month),
      );
    }

    return EmployeeMonthlyAttendanceSummary.fromJson(
      <String, dynamic>{'records': decoded is List ? decoded : []},
      DateTime(month.year, month.month),
    );
  }

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static dynamic _tryJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static void _throwIfFailed(int statusCode, String body, String fallback) {
    if (statusCode >= 200 && statusCode < 300) return;
    if (statusCode == 401) throw Exception('Unauthorized. Please login again.');
    throw Exception(_extractError(body, fallback));
  }

  static String _extractError(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final message = decoded['message'] ?? decoded['error'] ?? decoded['msg'];
        if (message != null && message.toString().trim().isNotEmpty) {
          return message.toString();
        }
      }
    } catch (_) {}
    return fallback;
  }

  static List<dynamic> _extractRows(dynamic decoded, {required List<String> keys}) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      for (final key in keys) {
        final value = decoded[key];
        if (value is List) return value;
      }
      final data = decoded['data'];
      if (data is List) return data;
      if (data is Map) {
        for (final key in keys) {
          final value = data[key];
          if (value is List) return value;
        }
      }
    }
    return <dynamic>[];
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}