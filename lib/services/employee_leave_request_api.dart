import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/employee_leave_request_model.dart';
import 'api_service.dart';

class EmployeeLeaveRequestApi {
  const EmployeeLeaveRequestApi._();

  static Future<List<EmployeeLeaveRequest>> fetchRequests({
    String status = 'pending',
  }) async {
    final endpoint = status == 'all'
        ? '/employee-leave-requests/all'
        : '/employee-leave-requests/all?status=${Uri.encodeQueryComponent(status)}';

    final response = await ApiService.rawGet(endpoint);
    final decoded = _decode(response.body);

    if (!_ok(response.statusCode)) {
      throw Exception(_message(decoded, 'Failed to load leave requests.'));
    }

    final rows = _extractRows(decoded);
    final requests = rows
        .map((row) => EmployeeLeaveRequest.fromJson(row))
        .where((request) => request.id > 0)
        .toList();

    requests.sort((a, b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      if (byDate != 0) return byDate;
      return b.id.compareTo(a.id);
    });

    return requests;
  }

  static Future<void> updateStatus({
    required int id,
    required String status,
    String remarks = '',
  }) async {
    final cleanBase = ApiService.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$cleanBase/employee-leave-requests/$id/status');
    final token = await _token();

    final response = await http
        .patch(
          uri,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'status': status,
            'remarks': remarks,
          }),
        )
        .timeout(const Duration(seconds: 20));

    final decoded = _decode(response.body);
    if (!_ok(response.statusCode)) {
      throw Exception(_message(decoded, 'Failed to update leave request.'));
    }
  }

  static bool _ok(int code) => code >= 200 && code < 300;

  static dynamic _decode(String body) {
    if (body.trim().isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  static List<Map<String, dynamic>> _extractRows(dynamic decoded) {
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }

    if (decoded is Map) {
      for (final key in ['data', 'rows', 'records', 'items', 'requests', 'results']) {
        final value = decoded[key];
        if (value is List) {
          return value
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
        }
        if (value is Map) {
          for (final nestedKey in ['data', 'rows', 'records', 'items', 'requests']) {
            final nested = value[nestedKey];
            if (nested is List) {
              return nested
                  .whereType<Map>()
                  .map((row) => Map<String, dynamic>.from(row))
                  .toList();
            }
          }
        }
      }
    }

    return <Map<String, dynamic>>[];
  }

  static String _message(dynamic decoded, String fallback) {
    if (decoded is Map) {
      return '${decoded['message'] ?? decoded['error'] ?? fallback}';
    }
    if (decoded is String && decoded.trim().isNotEmpty) return decoded;
    return fallback;
  }

  static Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? prefs.getString('token');
    if (token == null || token.trim().isEmpty) return null;
    return token.trim();
  }
}