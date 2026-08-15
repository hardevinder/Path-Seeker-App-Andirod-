import 'dart:convert';
import 'api_service.dart';

class HouseDutyApi {
  static Future<Map<String, dynamic>> myDuties() async {
    final response = await ApiService.rawGet('/house-duty/me');
    final decoded = response.body.isNotEmpty ? jsonDecode(response.body) : {};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map ? decoded['message'] : null;
      throw Exception(message?.toString() ?? 'Unable to load House duties');
    }
    return decoded is Map<String, dynamic> ? decoded : Map<String, dynamic>.from(decoded as Map);
  }

  static Future<Map<String, dynamic>> updateDuty(int dutyId, String status) async {
    final response = await ApiService.rawPatch('/house-duty/assignments/$dutyId', {'status': status});
    final decoded = response.body.isNotEmpty ? jsonDecode(response.body) : {};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map ? decoded['message'] : null;
      throw Exception(message?.toString() ?? 'Unable to update House duty');
    }
    return decoded is Map<String, dynamic> ? decoded : Map<String, dynamic>.from(decoded as Map);
  }
}
