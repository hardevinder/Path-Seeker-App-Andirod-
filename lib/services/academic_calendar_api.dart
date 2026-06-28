// lib/services/academic_calendar_api.dart
import 'dart:async';
import 'dart:convert';

import '../models/academic_calendar_models.dart';
import 'api_service.dart';

class AcademicCalendarApi {
  static const String _base = '/academic-calendars';

  static Future<List<AcademicCalendarModel>> fetchPublishedCalendars({
    String? search,
    String? academicSession,
  }) async {
    final params = <String, String>{
      'status': 'PUBLISHED',
      if (search != null && search.trim().isNotEmpty) 'q': search.trim(),
      if (academicSession != null && academicSession.trim().isNotEmpty)
        'academic_session': academicSession.trim(),
    };

    final query = Uri(queryParameters: params).query;
    final endpoint = '$_base${query.isEmpty ? '' : '?$query'}';

    try {
      final response = await ApiService.rawGet(endpoint);
      if (response.statusCode == 401) {
        throw Exception('Unauthorized. Please login again.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_extractError(response.body, 'Failed to load academic calendars.'));
      }

      final rows = _extractRows(jsonDecode(response.body));
      final mapped = rows.map(AcademicCalendarModel.fromJson).toList();
      final published = mapped.where((calendar) => calendar.isPublished).toList();

      // The backend is queried with status=PUBLISHED. Some controller versions
      // do not include the status field in the response, so keep the returned
      // rows if filtering would otherwise hide everything.
      return published.isNotEmpty || mapped.isEmpty ? published : mapped;
    } on TimeoutException {
      throw Exception('Academic calendar request timed out.');
    }
  }

  static Future<List<AcademicCalendarEventModel>> fetchEvents(int calendarId) async {
    try {
      final response = await ApiService.rawGet('$_base/$calendarId/events');
      if (response.statusCode == 401) {
        throw Exception('Unauthorized. Please login again.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_extractError(response.body, 'Failed to load calendar events.'));
      }

      final rows = _extractRows(jsonDecode(response.body));
      return rows.map(AcademicCalendarEventModel.fromJson).toList();
    } on TimeoutException {
      throw Exception('Calendar events request timed out.');
    }
  }

  static Future<List<int>> downloadPdfBytes(int calendarId) async {
    final response = await ApiService.rawGet('$_base/$calendarId/pdf');
    if (response.statusCode == 401) {
      throw Exception('Unauthorized. Please login again.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractError(response.body, 'Failed to download calendar PDF.'));
    }
    return response.bodyBytes;
  }

  static List<Map<String, dynamic>> _extractRows(dynamic decoded) {
    if (decoded is List) {
      return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }

    if (decoded is Map) {
      for (final key in const [
        'data',
        'rows',
        'records',
        'items',
        'calendars',
        'academicCalendars',
        'events',
      ]) {
        final value = decoded[key];
        if (value is List) {
          return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
        if (value is Map) {
          for (final innerKey in const ['rows', 'records', 'items', 'calendars', 'events']) {
            final inner = value[innerKey];
            if (inner is List) {
              return inner.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
            }
          }
        }
      }
    }

    return <Map<String, dynamic>>[];
  }

  static String _extractError(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final msg = decoded['message'] ?? decoded['error'] ?? decoded['sqlMessage'];
        if (msg != null && msg.toString().trim().isNotEmpty) return msg.toString();
      }
    } catch (_) {}
    return fallback;
  }
}