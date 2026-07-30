import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class PtmApiException implements Exception {
  final String message;

  const PtmApiException(this.message);

  @override
  String toString() => message;
}

class PtmApi {
  static const Duration _timeout = Duration(seconds: 90);

  static Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? prefs.getString('token');
    if (token == null || token.trim().isEmpty) {
      throw const PtmApiException('Your login session has expired.');
    }
    return token.trim();
  }

  static dynamic _decode(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = <String, dynamic>{'message': response.body};
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String message = decoded is Map
          ? (decoded['message']?.toString() ?? '')
          : 'PTM request failed (${response.statusCode}).';
      throw PtmApiException(
        message.trim().isNotEmpty
            ? message
            : 'PTM request failed (${response.statusCode}).',
      );
    }
    return decoded;
  }

  static Future<List<Map<String, dynamic>>> listMeetings() async {
    final response = await ApiService.rawGet('/ptm/meetings');
    final decoded = _decode(response);
    final rows = decoded is Map ? decoded['meetings'] : null;
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  static Future<Map<String, dynamic>> dashboard(int meetingId) async {
    final response = await ApiService.rawGet('/ptm/meetings/$meetingId/dashboard');
    final decoded = _decode(response);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> classStudents(int meetingClassId) async {
    final response =
        await ApiService.rawGet('/ptm/meeting-classes/$meetingClassId/students');
    final decoded = _decode(response);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> uploadScan(
    int formId,
    File scanFile,
  ) async {
    final token = await _token();
    final uri = Uri.parse('${ApiService.baseUrl}/ptm/forms/$formId/scan');
    final extension = scanFile.path.split('.').last.toLowerCase();
    final mediaType = extension == 'pdf'
        ? MediaType('application', 'pdf')
        : extension == 'png'
            ? MediaType('image', 'png')
            : extension == 'webp'
                ? MediaType('image', 'webp')
                : MediaType('image', 'jpeg');

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      })
      ..fields['process_ai'] = 'true'
      ..files.add(
        await http.MultipartFile.fromPath(
          'scan',
          scanFile.path,
          contentType: mediaType,
        ),
      );

    final streamed = await request.send().timeout(_timeout);
    final response = await http.Response.fromStream(streamed);
    final decoded = _decode(response);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> saveForm(
    int formId,
    Map<String, dynamic> payload,
  ) async {
    final response = await ApiService.rawPut('/ptm/forms/$formId', payload);
    final decoded = _decode(response);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }
}
