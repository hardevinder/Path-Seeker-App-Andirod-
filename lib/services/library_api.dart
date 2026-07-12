import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart';

class LibraryApiException implements Exception {
  final String message;

  const LibraryApiException(this.message);

  @override
  String toString() => message;
}

class LibraryApi {
  static Map<String, dynamic> _decodeMap(http.Response response) {
    dynamic decoded;
    try {
      decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
    } catch (_) {
      decoded = <String, dynamic>{};
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map
          ? decoded['message'] ?? decoded['error'] ?? decoded['detail']
          : null;
      throw LibraryApiException(
        (message?.toString().trim().isNotEmpty ?? false)
            ? message.toString()
            : 'Library request failed. Please try again.',
      );
    }

    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    if (decoded is List) return {'data': decoded};
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _listFrom(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  static Future<Map<String, dynamic>> fetchMyLibrary() async {
    final response = await ApiService.rawGet('/api/library/me');
    final decoded = _decodeMap(response);
    final issues =
        _listFrom(decoded['issues'] ?? decoded['data'] ?? decoded['rows']);
    final active = _listFrom(decoded['active']);

    return {
      ...decoded,
      'issues': issues,
      'active': active.isEmpty
          ? issues
              .where((issue) => '${issue['status']}'.toLowerCase() == 'issued')
              .toList()
          : active,
    };
  }

  static Future<Map<String, dynamic>> fetchDashboard() async {
    return _decodeMap(await ApiService.rawGet('/api/library/dashboard'));
  }

  static Future<List<Map<String, dynamic>>> fetchIssues() async {
    final decoded = _decodeMap(await ApiService.rawGet('/api/library/issues'));
    return _listFrom(
        decoded['data'] ?? decoded['issues'] ?? decoded['rows'] ?? decoded);
  }
}
