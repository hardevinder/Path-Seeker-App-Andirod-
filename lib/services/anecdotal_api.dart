import 'dart:convert';
import 'api_service.dart';

class AnecdotalApiException implements Exception {
  final String message;
  const AnecdotalApiException(this.message);
  @override
  String toString() => message;
}

class AnecdotalApi {
  static dynamic _decode(response) {
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      data = <String, dynamic>{'message': response.body};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final text = data is Map ? data['message']?.toString() : null;
      throw AnecdotalApiException((text ?? '').trim().isEmpty
          ? 'Request failed (${response.statusCode})'
          : text!.trim());
    }
    return data;
  }

  static Future<Map<String, dynamic>> capabilities() async {
    final r = await ApiService.rawGet('/anecdotal-records/capabilities');
    final d = _decode(r);
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  static Future<List<dynamic>> dimensions() async {
    final r = await ApiService.rawGet('/anecdotal-records/dimensions');
    final d = _decode(r);
    return d is Map && d['dimensions'] is List ? List<dynamic>.from(d['dimensions']) : <dynamic>[];
  }

  static Future<List<dynamic>> classes() async {
    final r = await ApiService.rawGet('/anecdotal-records/classes');
    final d = _decode(r);
    return d is Map && d['classes'] is List ? List<dynamic>.from(d['classes']) : <dynamic>[];
  }

  static Future<List<dynamic>> students(int classId, int sectionId) async {
    final r = await ApiService.rawGet('/anecdotal-records/students?class_id=$classId&section_id=$sectionId');
    final d = _decode(r);
    return d is Map && d['students'] is List ? List<dynamic>.from(d['students']) : <dynamic>[];
  }

  static Future<List<dynamic>> observations({required int classId, required int sectionId, int? studentId}) async {
    final params = <String, String>{'class_id': '$classId', 'section_id': '$sectionId', 'limit': '50'};
    if (studentId != null) params['student_id'] = '$studentId';
    final uri = Uri(path: '/anecdotal-records/observations', queryParameters: params).toString();
    final r = await ApiService.rawGet(uri);
    final d = _decode(r);
    return d is Map && d['observations'] is List ? List<dynamic>.from(d['observations']) : <dynamic>[];
  }

  static Future<Map<String, dynamic>> createObservation(Map<String, dynamic> payload) async {
    final r = await ApiService.rawPost('/anecdotal-records/observations', payload);
    final d = _decode(r);
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> myRecord() async {
    final r = await ApiService.rawGet('/anecdotal-records/me');
    final d = _decode(r);
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }
}
