import 'dart:convert';
import 'api_service.dart';

class TeacherPerformanceApiException implements Exception {
  final String message;
  const TeacherPerformanceApiException(this.message);
  @override
  String toString() => message;
}

class TeacherPerformanceApi {
  static dynamic _decode(response) {
    dynamic data;
    try { data = jsonDecode(response.body); }
    catch (_) { data = <String, dynamic>{'message': response.body}; }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final text = data is Map ? data['message']?.toString() : null;
      throw TeacherPerformanceApiException((text ?? '').trim().isEmpty ? 'Request failed (${response.statusCode})' : text!.trim());
    }
    return data;
  }

  static Future<Map<String, dynamic>> capabilities() async {
    final r = await ApiService.rawGet('/teacher-performance/capabilities');
    final d = _decode(r);
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> myDashboard({String? month}) async {
    final suffix = (month ?? '').trim().isEmpty ? '' : '?month=${Uri.encodeQueryComponent(month!.trim())}';
    final r = await ApiService.rawGet('/teacher-performance/me$suffix');
    final d = _decode(r);
    return d is Map && d['data'] is Map ? Map<String, dynamic>.from(d['data'] as Map) : <String, dynamic>{};
  }

  static Future<List<dynamic>> trend({String? month}) async {
    final params = <String, String>{'limit': '40'};
    if ((month ?? '').trim().isNotEmpty) {
      params['period_key'] = month!.trim();
      params['month'] = month.trim();
    }
    final uri = Uri(path: '/teacher-performance/trend', queryParameters: params).toString();
    final r = await ApiService.rawGet(uri);
    final d = _decode(r);
    return d is Map && d['snapshots'] is List ? List<dynamic>.from(d['snapshots']) : <dynamic>[];
  }

  static Future<Map<String, dynamic>> aiInsight({String? month}) async {
    final r = await ApiService.rawPost('/teacher-performance/ai-insight', {
      if ((month ?? '').trim().isNotEmpty) 'month': month!.trim(),
    });
    final d = _decode(r);
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }
}
