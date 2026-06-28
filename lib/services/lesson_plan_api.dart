// lib/services/lesson_plan_api.dart
// API wrapper for AI powered Lesson Plans.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../models/lesson_plan_models.dart';
import 'api_service.dart';

class LessonPlanApi {
  const LessonPlanApi._();

  static Future<List<LessonPlan>> fetchLessonPlans() async {
    final response = await ApiService.rawGet('/lesson-plans');
    _throwIfBad(response, 'Failed to fetch lesson plans');

    final decoded = _decode(response.body);
    final rows = _extractList(decoded);
    return rows
        .whereType<Map>()
        .map((e) => LessonPlan.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<LessonPlan> fetchLessonPlanById(int id) async {
    final response = await ApiService.rawGet('/lesson-plans/$id');
    _throwIfBad(response, 'Failed to fetch lesson plan details');

    final decoded = _decode(response.body);
    final row = decoded is Map ? decoded : <String, dynamic>{};
    return LessonPlan.fromJson(Map<String, dynamic>.from(row));
  }

  static Future<List<LessonAssignment>> fetchTeacherAssignments() async {
    final response = await ApiService.rawGet(
      '/class-subject-teachers/teacher/class-subjects',
    );
    _throwIfBad(response, 'Failed to fetch teacher class-subject assignments');

    final decoded = _decode(response.body);
    final rows = decoded is Map ? decoded['assignments'] : decoded;
    return _extractList(rows)
        .whereType<Map>()
        .map((e) => LessonAssignment.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.classId != null && e.subjectId != null)
        .toList();
  }

  static Future<List<LessonSection>> fetchSectionsForClass(int classId) async {
    final endpoint = _withQuery('/sections', {
      'classId': '$classId',
      'class_id': '$classId',
    });
    final response = await ApiService.rawGet(endpoint);
    _throwIfBad(response, 'Failed to fetch sections');

    final decoded = _decode(response.body);
    return _extractList(decoded)
        .whereType<Map>()
        .map((e) => LessonSection.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id > 0)
        .toList();
  }

  static Future<List<BreakdownItem>> fetchBreakdownItemsForPlan({
    required int classId,
    required int subjectId,
    required String term,
    String academicSession = '',
  }) async {
    final query = <String, String>{
      'classId': '$classId',
      'subjectId': '$subjectId',
      'term': term.isEmpty ? 'FULL_YEAR' : term,
      if (academicSession.trim().isNotEmpty)
        'academicSession': academicSession.trim(),
    };
    final response = await ApiService.rawGet(
      _withQuery('/syllabus-breakdowns/items-for-plan', query),
    );
    _throwIfBad(response, 'Failed to fetch syllabus breakdown items');

    final decoded = _decode(response.body);
    final parentBreakdownId = decoded is Map
        ? _intOrNull(decoded['breakdownId'] ??
            ((decoded['breakdown'] is Map) ? decoded['breakdown']['id'] : null))
        : null;
    final rows = decoded is Map ? decoded['items'] : decoded;
    return _extractList(rows)
        .whereType<Map>()
        .map((e) => BreakdownItem.fromJson(
              Map<String, dynamic>.from(e),
              parentBreakdownId: parentBreakdownId,
            ))
        .where((e) => e.id > 0)
        .toList();
  }

  static Future<AiLessonPlanDraft> generateWithAi({
    int? lessonPlanId,
    required int classId,
    required int subjectId,
    required String term,
    required String weekStart,
    required String weekEnd,
    int? breakdownId,
    int? breakdownItemId,
    String academicSession = '',
    String topic = '',
    String subtopic = '',
    List<int> sectionIds = const <int>[],
    String status = 'Draft',
    String completionStatus = 'Planned',
    bool publish = false,
  }) async {
    final payload = {
      if (lessonPlanId != null) 'lessonPlanId': lessonPlanId,
      'classId': classId,
      'subjectId': subjectId,
      'academicSession': academicSession.trim().isEmpty ? null : academicSession.trim(),
      'term': term,
      'weekStart': weekStart,
      'weekEnd': weekEnd,
      'breakdownId': breakdownId,
      'breakdownItemId': breakdownItemId,
      'topic': topic.trim().isEmpty ? null : topic.trim(),
      'subtopic': subtopic.trim().isEmpty ? null : subtopic.trim(),
      'sectionIds': sectionIds,
      'language': 'en',
      'status': status,
      'completionStatus': completionStatus,
      'publish': publish,
    };

    final response = await ApiService.rawPost('/api/ai/lesson-plan/generate', payload);
    _throwIfBad(response, 'AI generation failed');

    final decoded = _decode(response.body);
    if (decoded is! Map) return const AiLessonPlanDraft();
    return AiLessonPlanDraft.fromResponse(Map<String, dynamic>.from(decoded));
  }

  static Future<void> createLessonPlan(LessonPlan plan) async {
    final response = await ApiService.rawPost('/lesson-plans', plan.toPayload());
    _throwIfBad(response, 'Failed to create lesson plan');
  }

  static Future<void> updateLessonPlan(int id, Map<String, dynamic> payload) async {
    final response = await ApiService.rawPut('/lesson-plans/$id', payload);
    _throwIfBad(response, 'Failed to update lesson plan');
  }

  static Future<void> saveLessonPlan(LessonPlan plan) async {
    if (plan.id == null) {
      await createLessonPlan(plan);
    } else {
      await updateLessonPlan(plan.id!, plan.toPayload());
    }
  }

  static Future<void> deleteLessonPlan(int id) async {
    final response = await ApiService.rawDelete('/lesson-plans/$id');
    _throwIfBad(response, 'Failed to delete lesson plan');
  }

  static Future<void> togglePublish(LessonPlan plan) async {
    final id = plan.id;
    if (id == null) throw Exception('Lesson plan id missing');
    await updateLessonPlan(id, {'publish': !plan.publish});
  }

  static Future<File> downloadPdf(int id, {String? fileName}) async {
    final response = await ApiService.rawGet('/lesson-plans/$id/pdf');
    _throwIfBad(response, 'Failed to download PDF');

    final dir = await getTemporaryDirectory();
    final cleanName = (fileName == null || fileName.trim().isEmpty)
        ? 'LessonPlan_$id.pdf'
        : fileName.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_\-.]+'), '_');
    final finalName = cleanName.toLowerCase().endsWith('.pdf')
        ? cleanName
        : '$cleanName.pdf';
    final file = File('${dir.path}/$finalName');
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file;
  }

  static Future<void> openPdf(int id, {String? fileName}) async {
    final file = await downloadPdf(id, fileName: fileName);
    await OpenFilex.open(file.path);
  }

  static String _withQuery(String path, Map<String, String> query) {
    final clean = query..removeWhere((_, v) => v.trim().isEmpty);
    final encoded = clean.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return encoded.isEmpty ? path : '$path?$encoded';
  }

  static dynamic _decode(String body) {
    if (body.trim().isEmpty) return null;
    return jsonDecode(body);
  }

  static List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      for (final key in const [
        'data',
        'rows',
        'items',
        'records',
        'lessonPlans',
        'list',
        'sections',
        'assignments',
      ]) {
        final value = decoded[key];
        if (value is List) return value;
      }
      final data = decoded['data'];
      if (data is Map) return _extractList(data);
    }
    return <dynamic>[];
  }

  static void _throwIfBad(http.Response response, String fallback) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw Exception(_extractError(response.body, fallback));
  }

  static String _extractError(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final message = decoded['message'] ?? decoded['error'];
        if (message != null && '$message'.trim().isNotEmpty) return '$message';
      }
    } catch (_) {}
    return fallback;
  }

  static int? _intOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value'.trim());
  }
}