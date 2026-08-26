import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class SupportCenterApiException implements Exception {
  final String message;
  const SupportCenterApiException(this.message);
  @override String toString() => message;
}

class SupportCenterApi {
  static String get _base => ApiService.baseUrl.replaceAll(RegExp(r'/+$'), '');

  static Future<String> _token() async {
    final p = await SharedPreferences.getInstance();
    final token = p.getString('authToken') ?? p.getString('token');
    if (token == null || token.trim().isEmpty) throw const SupportCenterApiException('Your login session has expired.');
    return token.trim();
  }

  static Future<Map<String, String>> _headers() async => {
    'Accept': 'application/json',
    'Authorization': 'Bearer ${await _token()}',
  };

  static dynamic _decode(http.Response response) {
    dynamic data;
    try { data = jsonDecode(response.body); } catch (_) { data = {'message': response.body}; }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = data is Map ? (data['message'] ?? data['error'])?.toString() : null;
      throw SupportCenterApiException(message?.trim().isNotEmpty == true ? message! : 'Support request failed (${response.statusCode}).');
    }
    return data;
  }

  static Future<List<Map<String, dynamic>>> tickets({String? status}) async {
    final uri = Uri.parse('$_base/api/support/tickets').replace(queryParameters: {
      if (status != null && status.isNotEmpty) 'status': status,
    });
    final r = await http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 25));
    final d = _decode(r);
    final rows = d is Map ? d['tickets'] : null;
    if (rows is! List) return <Map<String, dynamic>>[];
    return rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<Map<String, dynamic>> ticket(String ticketNo) async {
    final r = await http.get(Uri.parse('$_base/api/support/tickets/${Uri.encodeComponent(ticketNo)}'), headers: await _headers()).timeout(const Duration(seconds: 25));
    final d = _decode(r);
    return d is Map && d['ticket'] is Map ? Map<String, dynamic>.from(d['ticket']) : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> create({
    required String subject,
    required String description,
    required String category,
    String module = '',
    String priority = 'medium',
    bool sendPriority = true,
    List<String> filePaths = const [],
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_base/api/support/tickets'));
    req.headers.addAll(await _headers());
    req.fields.addAll({
      'subject': subject,
      'description': description,
      'category': category,
      'module': module,
      'appType': 'mobile',
      if (sendPriority) 'priority': priority,
    });
    for (final path in filePaths.take(5)) {
      final f = File(path);
      if (await f.exists()) req.files.add(await http.MultipartFile.fromPath('attachments', path));
    }
    final streamed = await req.send().timeout(const Duration(seconds: 60));
    final r = await http.Response.fromStream(streamed);
    final d = _decode(r);
    return d is Map && d['ticket'] is Map ? Map<String, dynamic>.from(d['ticket']) : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> reply(String ticketNo, {String message = '', List<String> filePaths = const []}) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_base/api/support/tickets/${Uri.encodeComponent(ticketNo)}/messages'));
    req.headers.addAll(await _headers());
    req.fields['message'] = message;
    for (final path in filePaths.take(5)) {
      final f = File(path);
      if (await f.exists()) req.files.add(await http.MultipartFile.fromPath('attachments', path));
    }
    final streamed = await req.send().timeout(const Duration(seconds: 60));
    final r = await http.Response.fromStream(streamed);
    final d = _decode(r);
    return d is Map && d['ticket'] is Map ? Map<String, dynamic>.from(d['ticket']) : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> reopen(String ticketNo) async {
    final h = await _headers();
    h['Content-Type'] = 'application/json';
    final r = await http.post(
      Uri.parse('$_base/api/support/tickets/${Uri.encodeComponent(ticketNo)}/reopen'),
      headers: h,
      body: jsonEncode({'reason': 'Issue still requires attention.'}),
    ).timeout(const Duration(seconds: 25));
    final d = _decode(r);
    return d is Map && d['ticket'] is Map ? Map<String, dynamic>.from(d['ticket']) : <String, dynamic>{};
  }
}
