import 'dart:convert';

import 'api_service.dart';

class AnswerScriptApiException implements Exception {
  const AnswerScriptApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AnswerScriptApi {
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

  static Future<List<Map<String, dynamic>>> myRoomCollections() async {
    final response = await ApiService.rawGet(
      '/answer-scripts/invigilator/my-room-collections',
    );
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AnswerScriptApiException(
        _error(decoded, 'Unable to load room answer-script collections.'),
      );
    }
    return _list(_map(decoded)['collections']);
  }

  static Future<Map<String, dynamic>> roomCollection(int id) async {
    final response = await ApiService.rawGet('/answer-scripts/room-collections/$id');
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AnswerScriptApiException(
        _error(decoded, 'Unable to load room collection record.'),
      );
    }
    return _map(_map(decoded)['collection']);
  }

  static Future<Map<String, dynamic>> saveRoomCollection(
    int id, {
    required int collectedCount,
    int damagedCount = 0,
    int extraSheetCount = 0,
    String? invigilatorRemarks,
    List<Map<String, dynamic>> groups = const [],
  }) async {
    final response = await ApiService.rawPut(
      '/answer-scripts/room-collections/$id',
      {
        'collected_count': collectedCount,
        'damaged_count': damagedCount,
        'extra_sheet_count': extraSheetCount,
        'invigilator_remarks': invigilatorRemarks,
        'groups': groups,
      },
    );
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AnswerScriptApiException(
        _error(decoded, 'Unable to save room collection.'),
      );
    }
    return _map(_map(decoded)['collection']);
  }

  static Future<Map<String, dynamic>> handoverRoomCollection(
    int id, {
    required int collectedCount,
    int damagedCount = 0,
    int extraSheetCount = 0,
    String? remarks,
  }) async {
    final response = await ApiService.rawPost(
      '/answer-scripts/room-collections/$id/handover',
      {
        'collected_count': collectedCount,
        'damaged_count': damagedCount,
        'extra_sheet_count': extraSheetCount,
        'remarks': remarks,
      },
    );
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AnswerScriptApiException(
        _error(decoded, 'Unable to hand over answer scripts.'),
      );
    }
    return _map(_map(decoded)['collection']);
  }

  static Future<List<Map<String, dynamic>>> myAssignments({bool active = false}) async {
    final response = await ApiService.rawGet(
      '/answer-scripts/evaluator/my-assignments${active ? '?active=true' : ''}',
    );
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AnswerScriptApiException(
        _error(decoded, 'Unable to load evaluation bundles.'),
      );
    }
    return _list(_map(decoded)['assignments']);
  }

  static Future<Map<String, dynamic>> assignment(int id) async {
    final response = await ApiService.rawGet(
      '/answer-scripts/evaluator/assignments/$id',
    );
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AnswerScriptApiException(
        _error(decoded, 'Unable to load evaluation assignment.'),
      );
    }
    return _map(_map(decoded)['assignment']);
  }

  static Future<void> acceptAssignment(int id) async {
    final response = await ApiService.rawPost(
      '/answer-scripts/evaluator/assignments/$id/accept',
      const {},
    );
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AnswerScriptApiException(
        _error(decoded, 'Unable to accept the evaluation bundle.'),
      );
    }
  }

  static Future<void> declineAssignment(int id, String reason) async {
    final response = await ApiService.rawPost(
      '/answer-scripts/evaluator/assignments/$id/decline',
      {'reason': reason},
    );
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AnswerScriptApiException(
        _error(decoded, 'Unable to decline the evaluation bundle.'),
      );
    }
  }

  static Future<void> updateProgress(
    int id, {
    required int checkedCount,
    String? remarks,
  }) async {
    final response = await ApiService.rawPut(
      '/answer-scripts/evaluator/assignments/$id/progress',
      {'checked_count': checkedCount, 'remarks': remarks},
    );
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AnswerScriptApiException(
        _error(decoded, 'Unable to update checking progress.'),
      );
    }
  }

  static Future<void> completeAssignment(
    int id, {
    required int checkedCount,
    String? remarks,
  }) async {
    final response = await ApiService.rawPost(
      '/answer-scripts/evaluator/assignments/$id/complete',
      {'checked_count': checkedCount, 'remarks': remarks},
    );
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AnswerScriptApiException(
        _error(decoded, 'Unable to complete bundle checking.'),
      );
    }
  }

  static Future<void> returnAssignment(int id, {String? remarks}) async {
    final response = await ApiService.rawPost(
      '/answer-scripts/evaluator/assignments/$id/return',
      {'remarks': remarks},
    );
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AnswerScriptApiException(
        _error(decoded, 'Unable to return the answer-script bundle.'),
      );
    }
  }

  static Future<List<Map<String, dynamic>>> myStudentStatuses() async {
    final response = await ApiService.rawGet('/answer-scripts/student/my-status');
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AnswerScriptApiException(
        _error(decoded, 'Unable to load answer-script status.'),
      );
    }
    return _list(_map(decoded)['students']);
  }
}
