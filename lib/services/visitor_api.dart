import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class VisitorApi {
  static Future<String> _token() async {
    final value = (await SharedPreferences.getInstance()).getString('authToken');
    if (value == null || value.trim().isEmpty) throw Exception('Please sign in again.');
    return value.trim();
  }

  static Future<Map<String, dynamic>> scanId(File image) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiService.baseUrl}/visitors/extract-id'),
    );
    request.headers['Authorization'] = 'Bearer ${await _token()}';
    request.files.add(await http.MultipartFile.fromPath(
      'id_proof',
      image.path,
      contentType: MediaType('image', 'jpeg'),
    ));
    final response = await http.Response.fromStream(await request.send());
    final data = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['error'] ?? 'Could not read ID proof.');
    }
    return Map<String, dynamic>.from(data);
  }

  static Future<List<Map<String, dynamic>>> employees() async {
    final response = await ApiService.rawGet('/visitors/employee-options');
    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded is Map ? decoded['error'] : 'Could not load employees.');
    }
    final list = decoded is List ? decoded : (decoded['employees'] ?? decoded['data'] ?? []);
    return List<Map<String, dynamic>>.from(list.map((e) => Map<String, dynamic>.from(e)));
  }

  static Future<void> create(Map<String, dynamic> payload) async {
    final response = await ApiService.rawPost('/visitors', payload);
    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error'] ?? 'Could not check in visitor.');
    }
  }

  static Future<List<Map<String, dynamic>>> myVisitors() async {
    final response = await ApiService.rawGet('/visitors/my');
    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded is Map ? decoded['error'] : 'Could not load visitors.');
    }
    return List<Map<String, dynamic>>.from(
      (decoded as List).map((e) => Map<String, dynamic>.from(e)),
    );
  }

  static Future<void> action(int id, String action, {String? decision}) async {
    final endpoint = switch (action) {
      'respond' => '/visitors/$id/respond',
      'start' => '/visitors/$id/meeting/start',
      'end' => '/visitors/$id/meeting/end',
      _ => throw ArgumentError('Unknown visitor action'),
    };
    final response = await ApiService.rawPost(
      endpoint,
      decision == null ? const {} : {'decision': decision},
    );
    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error'] ?? 'Visitor action failed.');
    }
  }

  static Future<Uint8List> idProof(int id) async {
    final response = await http.get(
      Uri.parse('${ApiService.baseUrl}/visitors/$id/id-proof'),
      headers: {'Authorization': 'Bearer ${await _token()}'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'ID proof is unavailable or expired.';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] != null) {
          message = '${decoded['error']}';
        }
      } catch (_) {}
      throw Exception(message);
    }
    return response.bodyBytes;
  }
}
