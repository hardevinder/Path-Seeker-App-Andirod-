import 'dart:convert';
import 'api_service.dart';

class ActionInboxApiException implements Exception {
  final String message;
  const ActionInboxApiException(this.message);
  @override
  String toString() => message;
}

class ActionInboxApi {
  static dynamic _decode(response) {
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      data = <String, dynamic>{'message': response.body};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final text = data is Map ? data['message']?.toString() : null;
      throw ActionInboxApiException((text ?? '').trim().isEmpty
          ? 'Unable to load actions (${response.statusCode}).'
          : text!.trim());
    }
    return data;
  }

  static Future<Map<String, dynamic>> list({
    String category = 'all',
    String source = 'all',
    String priority = 'all',
    String search = '',
  }) async {
    final params = <String, String>{'limit': '200'};
    if (category != 'all') params['category'] = category;
    if (source != 'all') params['source'] = source;
    if (priority != 'all') params['priority'] = priority;
    if (search.trim().isNotEmpty) params['search'] = search.trim();
    final uri = Uri(path: '/action-inbox', queryParameters: params).toString();
    final response = await ApiService.rawGet(uri);
    final data = _decode(response);
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }
}
