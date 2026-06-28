// lib/services/student_lesson_plan_api.dart
import 'dart:convert';
import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../models/student_lesson_plan_model.dart';
import 'api_service.dart';

class StudentLessonPlanApi {
  static const String _base = '/lesson-plans/student';

  static Future<StudentLessonPlanResponse> fetchMyLessonPlans({
    int? subjectId,
    String? term,
    String? from,
    String? to,
  }) async {
    final params = <String, String>{
      if (subjectId != null && subjectId > 0) 'subjectId': '$subjectId',
      if (term != null && term.trim().isNotEmpty) 'term': term.trim(),
      if (from != null && from.trim().isNotEmpty) 'from': from.trim(),
      if (to != null && to.trim().isNotEmpty) 'to': to.trim(),
    };

    final query = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');

    final endpoint = query.isEmpty ? '$_base/my' : '$_base/my?$query';
    final res = await ApiService.rawGet(endpoint);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
          _messageFromBody(res.body, 'Failed to load lesson plans'));
    }

    return StudentLessonPlanResponse.fromJson(jsonDecode(res.body));
  }

  static Future<StudentLessonPlan> fetchLessonPlan(int id) async {
    final res = await _getWithFallback([
      '$_base/$id',
      '$_base/detail/$id',
      '/lesson-plans/$id?student=1',
    ]);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(_messageFromBody(res.body, 'Failed to load lesson plan'));
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map && decoded['lessonPlan'] is Map) {
      return StudentLessonPlan.fromJson(
          Map<String, dynamic>.from(decoded['lessonPlan']));
    }

    if (decoded is Map) {
      return StudentLessonPlan.fromJson(Map<String, dynamic>.from(decoded));
    }

    throw Exception('Invalid lesson plan response');
  }

  static Future<List<StudentLessonPlanEvaluation>> fetchEvaluations(
      int planId) async {
    final res = await _getWithFallback([
      '$_base/$planId/evaluations',
      '$_base/evaluations?lessonPlanId=${Uri.encodeQueryComponent('$planId')}',
      '/lesson-plans/$planId/evaluations?student=1',
    ]);

    final decoded = jsonDecode(res.body);
    return _normalizeList(decoded)
        .whereType<Map>()
        .map((e) =>
            StudentLessonPlanEvaluation.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.isPublishedLike)
        .toList();
  }

  static Future<StudentLessonPlanEvaluation> fetchEvaluation(
      int evaluationId) async {
    final res = await _getWithFallback([
      '$_base/evaluations/$evaluationId',
      '/lesson-plan-evaluations/$evaluationId/student',
      '/lesson-plans/evaluations/$evaluationId?student=1',
      '/lesson-plan-evaluations/$evaluationId',
    ]);

    final decoded = jsonDecode(res.body);
    final map = _normalizeObject(decoded, const ['evaluation']);
    return StudentLessonPlanEvaluation.fromJson(map);
  }

  static Future<File> downloadEvaluationPdf(
    StudentLessonPlanEvaluation evaluation,
  ) async {
    final res = await _getWithFallback([
      '$_base/evaluations/${evaluation.id}/pdf',
      '/lesson-plan-evaluations/${evaluation.id}/student/pdf',
      '/lesson-plans/evaluations/${evaluation.id}/pdf?student=1',
      '/lesson-plan-evaluations/${evaluation.id}/pdf?student=1',
    ], extraHeaders: {
      'Accept': 'application/pdf'
    });

    final dir = await getTemporaryDirectory();
    final file =
        File('${dir.path}/${_safeFileName('Evaluation_${evaluation.id}.pdf')}');
    await file.writeAsBytes(res.bodyBytes, flush: true);
    return file;
  }

  static Future<void> openEvaluationPdf(
    StudentLessonPlanEvaluation evaluation,
  ) async {
    final file = await downloadEvaluationPdf(evaluation);
    await OpenFilex.open(file.path);
  }

  static Future<File> downloadPdf(StudentLessonPlan plan) async {
    final res = await ApiService.rawGet(
      '$_base/${plan.id}/pdf',
      extraHeaders: {'Accept': 'application/pdf'},
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(_messageFromBody(res.body, 'Failed to download PDF'));
    }

    final dir = await getTemporaryDirectory();
    final safeName = _safeFileName(
      'LessonPlan_${plan.subjectName}_${plan.weekStart}_${plan.weekEnd}_${plan.id}.pdf',
    );
    final file = File('${dir.path}/$safeName');
    await file.writeAsBytes(res.bodyBytes, flush: true);
    return file;
  }

  static Future<void> openPdf(StudentLessonPlan plan) async {
    final file = await downloadPdf(plan);
    await OpenFilex.open(file.path);
  }

  static String _messageFromBody(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return (decoded['message'] ?? decoded['error'] ?? fallback).toString();
      }
    } catch (_) {}
    return fallback;
  }

  static Future<dynamic> _getWithFallback(
    List<String> endpoints, {
    Map<String, String>? extraHeaders,
  }) async {
    dynamic last;
    for (final endpoint in endpoints) {
      final res = await ApiService.rawGet(endpoint, extraHeaders: extraHeaders);
      if (res.statusCode >= 200 && res.statusCode < 300) return res;
      last = res;
      if (!_missingEndpoint(res.statusCode)) {
        throw Exception(_messageFromBody(res.body, 'Request failed'));
      }
    }

    if (last != null) {
      throw Exception(_messageFromBody(last.body, 'Request failed'));
    }
    throw Exception('Request failed');
  }

  static bool _missingEndpoint(int status) {
    return status == 404 || status == 405 || status == 501;
  }

  static List<dynamic> _normalizeList(dynamic payload) {
    if (payload is List) return payload;
    if (payload is Map) {
      for (final key in const [
        'rows',
        'lessonPlans',
        'plans',
        'items',
        'evaluations',
        'results',
        'result',
        'data',
      ]) {
        final value = payload[key];
        if (value is List) return value;
      }

      final data = payload['data'];
      if (data is Map) {
        for (final key in const [
          'rows',
          'lessonPlans',
          'plans',
          'items',
          'evaluations',
          'results',
        ]) {
          final value = data[key];
          if (value is List) return value;
        }
      }
    }
    return [];
  }

  static Map<String, dynamic> _normalizeObject(
    dynamic payload,
    List<String> keys,
  ) {
    if (payload is Map) {
      for (final key in keys) {
        final value = payload[key];
        if (value is Map) return Map<String, dynamic>.from(value);
      }
      for (final key in const [
        'data',
        'lessonPlan',
        'plan',
        'evaluation',
        'record',
        'result',
        'item',
      ]) {
        final value = payload[key];
        if (value is Map) return Map<String, dynamic>.from(value);
      }
      return Map<String, dynamic>.from(payload);
    }
    return {};
  }

  static String _safeFileName(String name) {
    final clean = name
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-.]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return clean.endsWith('.pdf') ? clean : '$clean.pdf';
  }
}
