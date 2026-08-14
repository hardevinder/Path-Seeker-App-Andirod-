import 'dart:convert';

import 'api_service.dart';

class StudentHealthApiException implements Exception {
  final String message;
  const StudentHealthApiException(this.message);
  @override
  String toString() => message;
}

class StudentHealthApi {
  static dynamic _decode(dynamic response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = <String, dynamic>{'message': response.body};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map ? decoded['message']?.toString() : null;
      throw StudentHealthApiException(
        (message ?? '').trim().isNotEmpty
            ? message!.trim()
            : 'Health record request failed (${response.statusCode}).',
      );
    }
    return decoded;
  }

  static Future<Map<String, dynamic>> mine() async {
    final response = await ApiService.rawGet('/student-health/me');
    final decoded = _decode(response);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> updateMyProfile(
      Map<String, dynamic> payload) async {
    final response = await ApiService.rawPatch(
      '/student-health/me/profile',
      payload,
    );
    final decoded = _decode(response);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> addFamilyMeasurement({
    required String measurementDate,
    String? heightCm,
    String? weightKg,
    String? notes,
  }) async {
    final response = await ApiService.rawPost('/student-health/me/measurements', {
      'measurement_date': measurementDate,
      if ((heightCm ?? '').trim().isNotEmpty) 'height_cm': heightCm!.trim(),
      if ((weightKg ?? '').trim().isNotEmpty) 'weight_kg': weightKg!.trim(),
      if ((notes ?? '').trim().isNotEmpty) 'notes': notes!.trim(),
    });
    final decoded = _decode(response);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }
}
