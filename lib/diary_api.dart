// lib/services/diary_api.dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/diary_model.dart';
import '../constants/constants.dart';

class DiaryApi {
  static const Duration _timeout = Duration(seconds: 15);
  static const String _authKey = 'authToken';

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_authKey);
    final headers = <String, String>{
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    return headers;
  }

  /// Fetch diary feed with query params.
  /// Accepts params like page, pageSize, q, type, dateFrom, dateTo, onlyUnacknowledged, order
  static Future<Map<String, dynamic>> fetchDiaries(Map<String, dynamic> params) async {
    final uri = Uri.parse('$baseUrl/diaries/student/feed/list').replace(queryParameters: params.map((k,v) => MapEntry(k, v?.toString() ?? '')));
    final resp = await http.get(uri, headers: await _headers()).timeout(_timeout);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final body = json.decode(resp.body);
      // support shapes: { data: [...], pagination: {...} } or { diaries: [...] } or raw array
      List<dynamic> list = [];
      Map<String, dynamic> pagination = {};
      if (body is Map && body['data'] is List) {
        list = body['data'];
        pagination = body['pagination'] is Map ? Map<String, dynamic>.from(body['pagination']) : {};
      } else if (body is Map && body['diaries'] is List) {
        list = body['diaries'];
        pagination = body['pagination'] is Map ? Map<String, dynamic>.from(body['pagination']) : {};
      } else if (body is List) {
        list = body;
      } else if (body is Map && body['data'] is Map && body['data']['items'] is List) {
        list = body['data']['items'];
        pagination = body['data']['pagination'] ?? {};
      }

      final items = (list as List).map((e) => DiaryItem.fromJson(Map<String, dynamic>.from(e))).toList();
      return {'items': items, 'pagination': pagination};
    } else if (resp.statusCode == 401) {
      throw Exception('Unauthorized');
    } else {
      throw Exception('Failed to fetch diaries (${resp.statusCode})');
    }
  }

  static Future<bool> acknowledge(String id) async {
    final uri = Uri.parse('$baseUrl/diaries/$id/ack');
    final resp = await http.post(uri, headers: await _headers()).timeout(_timeout);
    return resp.statusCode >= 200 && resp.statusCode < 300;
  }
}
