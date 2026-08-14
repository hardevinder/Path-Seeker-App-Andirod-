import 'dart:convert';
import 'api_service.dart';

class DailyReadinessApiException implements Exception {
  final String message;
  const DailyReadinessApiException(this.message);
  @override
  String toString() => message;
}

class DailyReadinessApi {
  static dynamic _decode(response) {
    dynamic data;
    try { data = jsonDecode(response.body); }
    catch (_) { data = <String, dynamic>{'message': response.body}; }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final text = data is Map ? data['message']?.toString() : null;
      throw DailyReadinessApiException((text ?? '').trim().isEmpty ? 'Request failed (${response.statusCode})' : text!.trim());
    }
    return data;
  }

  static Future<Map<String, dynamic>> capabilities() async {
    final r = await ApiService.rawGet('/daily-readiness/capabilities');
    final d = _decode(r);
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  static Future<List<dynamic>> classes() async {
    final r = await ApiService.rawGet('/daily-readiness/classes');
    final d = _decode(r);
    return d is Map && d['classes'] is List ? List<dynamic>.from(d['classes']) : <dynamic>[];
  }

  static Future<Map<String, dynamic>> classDay(int classId, int sectionId, String date) async {
    final r = await ApiService.rawGet('/daily-readiness/class-day?class_id=$classId&section_id=$sectionId&date=$date');
    final d = _decode(r);
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> saveClassDay(Map<String, dynamic> payload) async {
    final r = await ApiService.rawPost('/daily-readiness/class-day', payload);
    final d = _decode(r);
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> myRecord({String? month}) async {
    final suffix = (month ?? '').isEmpty ? '' : '?month=$month';
    final r = await ApiService.rawGet('/daily-readiness/me$suffix');
    final d = _decode(r);
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }
}
