import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class DocumentVaultApiException implements Exception {
  final String message;
  const DocumentVaultApiException(this.message);
  @override
  String toString() => message;
}

class DocumentVaultApi {
  static const Duration _uploadTimeout = Duration(seconds: 120);

  static dynamic _decode(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = <String, dynamic>{'message': response.body};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map
          ? decoded['message']?.toString()
          : 'Document request failed (${response.statusCode}).';
      throw DocumentVaultApiException(
        (message ?? '').trim().isNotEmpty
            ? message!.trim()
            : 'Document request failed (${response.statusCode}).',
      );
    }
    return decoded;
  }

  static Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? prefs.getString('token');
    if (token == null || token.trim().isEmpty) {
      throw const DocumentVaultApiException('Your login session has expired.');
    }
    return token.trim();
  }

  static Future<Map<String, dynamic>> myVault(String scope) async {
    final encoded = Uri.encodeQueryComponent(scope);
    final response = await ApiService.rawGet('/document-vault/me?scope=$encoded');
    final decoded = _decode(response);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> uploadMine({
    required String scope,
    required int documentTypeId,
    required String filePath,
    String? documentNumber,
    String? issuedOn,
    String? expiresOn,
    String? notes,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiService.baseUrl}/document-vault/me/documents'),
    );
    request.headers['Authorization'] = 'Bearer ${await _token()}';
    request.headers['Accept'] = 'application/json';
    request.fields['scope'] = scope;
    request.fields['document_type_id'] = documentTypeId.toString();
    if ((documentNumber ?? '').trim().isNotEmpty) {
      request.fields['document_number'] = documentNumber!.trim();
    }
    if ((issuedOn ?? '').isNotEmpty) request.fields['issued_on'] = issuedOn!;
    if ((expiresOn ?? '').isNotEmpty) request.fields['expires_on'] = expiresOn!;
    if ((notes ?? '').trim().isNotEmpty) request.fields['notes'] = notes!.trim();
    request.files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamed = await request.send().timeout(_uploadTimeout);
    final response = await http.Response.fromStream(streamed);
    final decoded = _decode(response);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  static Future<String> downloadToTemp({
    required int documentId,
    required String scope,
    required String suggestedName,
  }) async {
    final uri = Uri.parse('${ApiService.baseUrl}/document-vault/documents/$documentId/download')
        .replace(queryParameters: {'scope': scope});
    final response = await http.get(uri, headers: {
      'Authorization': 'Bearer ${await _token()}',
      'Accept': '*/*',
    }).timeout(const Duration(seconds: 60));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decode(response);
    }

    final dir = await getTemporaryDirectory();
    var name = suggestedName.trim();
    if (name.isEmpty) name = 'document-$documentId';
    name = name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
    if (p.extension(name).isEmpty) {
      final contentType = response.headers['content-type'] ?? '';
      if (contentType.contains('pdf')) name = '$name.pdf';
      if (contentType.contains('jpeg')) name = '$name.jpg';
      if (contentType.contains('png')) name = '$name.png';
    }
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file.path;
  }

  static Future<Map<String, dynamic>> officialMine(String scope) async {
    final encoded = Uri.encodeQueryComponent(scope);
    final response = await ApiService.rawGet('/document-vault/official/me?scope=$encoded');
    final decoded = _decode(response);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> acknowledgeOfficial(int documentId) async {
    final response = await ApiService.rawPatch(
      '/document-vault/official/$documentId/acknowledge',
      <String, dynamic>{},
    );
    final decoded = _decode(response);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  static Future<String> downloadOfficialToTemp({
    required int documentId,
    required String scope,
    required String suggestedName,
  }) async {
    final uri = Uri.parse('${ApiService.baseUrl}/document-vault/official/$documentId/download')
        .replace(queryParameters: {'scope': scope});
    final response = await http.get(uri, headers: {
      'Authorization': 'Bearer ${await _token()}',
      'Accept': '*/*',
    }).timeout(const Duration(seconds: 60));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decode(response);
    }

    final dir = await getTemporaryDirectory();
    var name = suggestedName.trim();
    if (name.isEmpty) name = 'official-document-$documentId';
    name = name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
    if (p.extension(name).isEmpty) {
      final contentType = response.headers['content-type'] ?? '';
      if (contentType.contains('pdf')) name = '$name.pdf';
      if (contentType.contains('jpeg')) name = '$name.jpg';
      if (contentType.contains('png')) name = '$name.png';
    }
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file.path;
  }

}
