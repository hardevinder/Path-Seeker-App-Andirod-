import 'dart:convert';

import 'api_service.dart';

class StudentLeadershipApi {
  static Future<Map<String, dynamic>> myLeadership() async {
    final response = await ApiService.rawGet('/student-leadership/me');
    final decoded = response.body.isNotEmpty ? jsonDecode(response.body) : {};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map ? decoded['message'] : null;
      throw Exception(message?.toString() ?? 'Unable to load leadership profile');
    }
    return decoded is Map<String, dynamic>
        ? decoded
        : Map<String, dynamic>.from(decoded as Map);
  }
}
