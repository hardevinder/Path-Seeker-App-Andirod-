import 'dart:convert';

import 'api_service.dart';

class StaffLeadershipApi {
  static Future<Map<String, dynamic>> myLeadership() async {
    final response = await ApiService.rawGet('/staff-leadership/me');
    final decoded = response.body.isNotEmpty ? jsonDecode(response.body) : {};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map ? decoded['message'] : null;
      throw Exception(message?.toString() ?? 'Unable to load staff leadership profile');
    }
    return decoded is Map<String, dynamic>
        ? decoded
        : Map<String, dynamic>.from(decoded as Map);
  }

  static Future<Map<String, dynamic>> updateDuty(int dutyId, String status) async {
    final response = await ApiService.rawPatch(
      '/staff-leadership/duties/$dutyId',
      {'status': status},
    );
    final decoded = response.body.isNotEmpty ? jsonDecode(response.body) : {};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map ? decoded['message'] : null;
      throw Exception(message?.toString() ?? 'Unable to update leadership duty');
    }
    return decoded is Map<String, dynamic>
        ? decoded
        : Map<String, dynamic>.from(decoded as Map);
  }
}
