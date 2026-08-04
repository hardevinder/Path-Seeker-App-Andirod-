import 'dart:convert';

import 'api_service.dart';

class ExamSeatingApiException implements Exception {
  const ExamSeatingApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ExamSeatingApi {
  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _list(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static dynamic _decode(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};
    return jsonDecode(body);
  }

  static String _error(dynamic decoded, String fallback) {
    if (decoded is Map) {
      final value = decoded['message'] ?? decoded['error'];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return fallback;
  }

  static Future<List<Map<String, dynamic>>> mySeats({bool upcoming = true}) async {
    final response = await ApiService.rawGet(
      '/exam-seating/student/my-seats?upcoming=${upcoming ? 'true' : 'false'}',
    );
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ExamSeatingApiException(
        _error(decoded, 'Unable to load examination seats.'),
      );
    }
    return _list(_map(decoded)['seats']);
  }

  static Future<List<Map<String, dynamic>>> myDuties({bool upcoming = true}) async {
    final response = await ApiService.rawGet(
      '/exam-seating/invigilator/my-duties?upcoming=${upcoming ? 'true' : 'false'}',
    );
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ExamSeatingApiException(
        _error(decoded, 'Unable to load invigilation duties.'),
      );
    }
    return _list(_map(decoded)['duties']);
  }

  static Future<Map<String, dynamic>> dutyRoom(int assignmentId) async {
    final response = await ApiService.rawGet(
      '/exam-seating/invigilator/duties/$assignmentId/room',
    );
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ExamSeatingApiException(
        _error(decoded, 'Unable to load assigned room.'),
      );
    }
    final map = _map(decoded);
    return {
      'duty': _map(map['duty']),
      'seats': _list(map['seats']),
    };
  }

  static Future<void> acknowledgeDuty(
    int assignmentId, {
    required String status,
    String? reason,
  }) async {
    final response = await ApiService.rawPost(
      '/exam-seating/invigilator/duties/$assignmentId/acknowledge',
      {'status': status, if (reason != null) 'reason': reason},
    );
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ExamSeatingApiException(
        _error(decoded, 'Unable to update duty status.'),
      );
    }
  }

  static Future<Map<String, dynamic>> saveAttendance(
    int assignmentId,
    List<Map<String, dynamic>> records,
  ) async {
    final response = await ApiService.rawPut(
      '/exam-seating/invigilator/duties/$assignmentId/attendance',
      {'records': records},
    );
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ExamSeatingApiException(
        _error(decoded, 'Unable to save examination attendance.'),
      );
    }
    return _map(decoded);
  }
}
