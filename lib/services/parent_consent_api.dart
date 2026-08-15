import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class ParentConsentApiException implements Exception {
  final String message;
  const ParentConsentApiException(this.message);
  @override
  String toString() => message;
}

class ParentConsentApi {
  static dynamic _decode(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = <String, dynamic>{'message': response.body};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map ? decoded['message']?.toString() : null;
      throw ParentConsentApiException((message ?? '').trim().isNotEmpty
          ? message!.trim()
          : 'Consent request failed (${response.statusCode}).');
    }
    return decoded;
  }

  static Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? prefs.getString('token');
    if (token == null || token.trim().isEmpty) {
      throw const ParentConsentApiException('Your login session has expired.');
    }
    return token.trim();
  }

  static Future<Map<String, dynamic>> myRequests() async {
    final response = await ApiService.rawGet('/parent-consents/my');
    final decoded = _decode(response);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
  }

  static Future<void> markViewed(int recipientId) async {
    final response = await ApiService.rawPatch('/parent-consents/my/$recipientId/viewed', <String, dynamic>{});
    _decode(response);
  }

  static Future<Map<String, dynamic>> respond({
    required int recipientId,
    required String responseValue,
    String note = '',
  }) async {
    final response = await ApiService.rawPatch('/parent-consents/my/$recipientId/respond', {
      'response': responseValue,
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
    final decoded = _decode(response);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> uploadSignedScan({
    required int recipientId,
    required String filePath,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiService.baseUrl}/parent-consents/my/$recipientId/signed-scan'),
    );
    request.headers['Authorization'] = 'Bearer ${await _token()}';
    request.headers['Accept'] = 'application/json';
    request.files.add(await http.MultipartFile.fromPath('signed_scan', filePath));
    final streamed = await request.send().timeout(const Duration(seconds: 120));
    final response = await http.Response.fromStream(streamed);
    final decoded = _decode(response);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
  }

  static Future<String> downloadToTemp({
    required int recipientId,
    required bool signedScan,
    String suggestedName = 'parent-consent.pdf',
  }) async {
    final endpoint = signedScan
        ? '/parent-consents/recipients/$recipientId/signed-scan'
        : '/parent-consents/recipients/$recipientId/form';
    final response = await http.get(Uri.parse('${ApiService.baseUrl}$endpoint'), headers: {
      'Authorization': 'Bearer ${await _token()}',
      'Accept': '*/*',
    }).timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) _decode(response);

    final dir = await getTemporaryDirectory();
    var name = suggestedName.trim().replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
    if (name.isEmpty) name = 'parent-consent-$recipientId';
    if (p.extension(name).isEmpty) {
      final type = response.headers['content-type'] ?? '';
      if (type.contains('pdf')) name = '$name.pdf';
      else if (type.contains('jpeg')) name = '$name.jpg';
      else if (type.contains('png')) name = '$name.png';
    }
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file.path;
  }
}
