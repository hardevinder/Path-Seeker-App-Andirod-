import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/assessment_models.dart';
import 'api_service.dart';

class AssessmentApiException implements Exception {
  final String message;
  const AssessmentApiException(this.message);
  @override
  String toString() => message;
}

class AssessmentApi {
  static dynamic _decode(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};
    return jsonDecode(body);
  }

  static dynamic _data(dynamic value) =>
      value is Map && value['data'] != null ? value['data'] : value;

  static void _check(int code, dynamic decoded) {
    if (code >= 200 && code < 300) return;
    final errors = decoded is Map ? decoded['errors'] : null;
    final message = errors is List
        ? errors.join('. ')
        : decoded is Map
            ? decoded['message']?.toString()
            : null;
    throw AssessmentApiException(message ?? 'Request failed ($code)');
  }

  static Future<Map<String, String>> _headers({bool json = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken')?.trim();
    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<List<Assessment>> list({
    int? onlineClassId,
    String? assessmentType,
  }) async {
    final params = <String, String>{
      if (onlineClassId != null) 'online_class_id': '$onlineClassId',
      if (assessmentType != null && assessmentType.trim().isNotEmpty)
        'assessment_type': assessmentType.trim(),
    };
    final suffix = params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';
    final response = await ApiService.rawGet('/api/assessments$suffix');
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
    final rows = _data(decoded);
    return rows is List
        ? rows
            .whereType<Map>()
            .map((e) => Assessment.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : [];
  }

  static Future<Assessment> detail(int id) async {
    final response = await ApiService.rawGet('/api/assessments/$id');
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
    return Assessment.fromJson(
        Map<String, dynamic>.from(_data(decoded) as Map));
  }

  static Future<List<Map<String, dynamic>>> options() async {
    final response = await ApiService.rawGet('/api/assessments/options');
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
    final rows = _data(decoded);
    return rows is List
        ? rows
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : [];
  }

  static Future<Map<String, dynamic>> generateAi(
      Map<String, dynamic> payload) async {
    final response =
        await ApiService.rawPost('/api/assessments/ai/generate', payload);
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
    return Map<String, dynamic>.from(_data(decoded) as Map);
  }

  static Future<Assessment> save({
    int? id,
    required Map<String, dynamic> fields,
    String? questionPaperPath,
    List<String> supportingPaths = const [],
  }) async {
    final request = http.MultipartRequest(
      id == null ? 'POST' : 'PATCH',
      Uri.parse('${ApiService.baseUrl}/api/assessments${id == null ? '' : '/$id'}'),
    );
    request.headers.addAll(await _headers(json: false));
    fields.forEach((key, value) {
      if (value == null) return;
      request.fields[key] = value is String ? value : jsonEncode(value);
    });
    if (questionPaperPath != null && questionPaperPath.isNotEmpty) {
      request.files.add(await http.MultipartFile.fromPath(
          'question_paper', questionPaperPath));
    }
    for (final path in supportingPaths) {
      request.files.add(
          await http.MultipartFile.fromPath('supporting_files', path));
    }
    final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 120)));
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
    return Assessment.fromJson(
        Map<String, dynamic>.from(_data(decoded) as Map));
  }

  static Future<void> action(int id, String action) async {
    final response = await ApiService.rawPost('/api/assessments/$id/$action', {});
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
  }

  static Future<void> cancel(int id) async {
    final response = await ApiService.rawDelete('/api/assessments/$id');
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
  }

  static Future<({Assessment assessment, AssessmentAttempt attempt})>
      startAttempt(int id) async {
    final response = await ApiService.rawPost(
        '/api/assessments/$id/attempts/start', {
      'client_meta': {'source': 'mobile'}
    });
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
    final data = Map<String, dynamic>.from(_data(decoded) as Map);
    return (
      assessment: Assessment.fromJson(
          Map<String, dynamic>.from(data['assessment'] as Map)),
      attempt: AssessmentAttempt.fromJson(
          Map<String, dynamic>.from(data['attempt'] as Map)),
    );
  }

  static Future<void> saveAnswers(
      int assessmentId, int attemptId, List<Map<String, dynamic>> answers) async {
    final response = await ApiService.rawPut(
        '/api/assessments/$assessmentId/attempts/$attemptId/answers',
        {'answers': answers});
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
  }

  static Future<void> submitOnline(
      int assessmentId, int attemptId, List<Map<String, dynamic>> answers) async {
    final response = await ApiService.rawPost(
        '/api/assessments/$assessmentId/submit', {
      'attempt_id': attemptId,
      'answers': answers,
    });
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
  }

  static Future<void> submitOffline(
      int assessmentId, List<String> paths) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiService.baseUrl}/api/assessments/$assessmentId/submit'),
    );
    request.headers.addAll(await _headers(json: false));
    request.fields['client_meta'] = jsonEncode({'source': 'mobile_scan'});
    for (final path in paths) {
      request.files.add(
          await http.MultipartFile.fromPath('submission_files', path));
    }
    final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 120)));
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
  }

  static Future<List<AssessmentSubmission>> submissions(int id) async {
    final response = await ApiService.rawGet('/api/assessments/$id/submissions');
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
    final rows = _data(decoded);
    return rows is List
        ? rows
            .whereType<Map>()
            .map((e) =>
                AssessmentSubmission.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : [];
  }

  static Future<void> grade({
    required int assessmentId,
    required int studentId,
    required double obtainedMarks,
    required String feedback,
    List<Map<String, dynamic>> answerGrades = const [],
    List<String> correctedPaths = const [],
  }) async {
    final request = http.MultipartRequest(
      'PATCH',
      Uri.parse('${ApiService.baseUrl}/api/assessments/$assessmentId/submissions/$studentId/grade'),
    );
    request.headers.addAll(await _headers(json: false));
    request.fields['obtained_marks'] = '$obtainedMarks';
    request.fields['teacher_feedback'] = feedback;
    request.fields['answer_grades'] = jsonEncode(answerGrades);
    for (final path in correctedPaths) {
      request.files.add(
          await http.MultipartFile.fromPath('corrected_files', path));
    }
    final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 120)));
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
  }

  static Future<void> downloadAndOpen(
      String endpoint, String suggestedName) async {
    final response = await http
        .get(Uri.parse('${ApiService.baseUrl}$endpoint'),
            headers: await _headers(json: false))
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final decoded = _decode(response.body);
      _check(response.statusCode, decoded);
    }
    final dir = await getTemporaryDirectory();
    final safe = suggestedName.replaceAll(RegExp(r'[^a-zA-Z0-9._ -]'), '_');
    final file = File(p.join(dir.path, safe));
    await file.writeAsBytes(response.bodyBytes, flush: true);
    await OpenFilex.open(file.path);
  }
}
