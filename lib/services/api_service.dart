// lib/services/api_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/circular.dart';
import '../constants/constants.dart';

class ApiService {
  static const Duration _timeout = Duration(seconds: 15);
  static const String _authKey = 'authToken';

  /// Save auth token (e.g. after login)
  static Future<void> setAuthToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authKey, token);
  }

  /// Clear saved token (e.g. logout)
  static Future<void> clearAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authKey);
  }

  /// Get headers including Authorization if token exists
  static Future<Map<String, String>> _buildHeaders([Map<String, String>? additional]) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_authKey);
    final headers = <String, String>{
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (additional != null) ...additional,
    };
    return headers;
  }

  /// Low-level GET that returns http.Response for custom callers.
  static Future<http.Response> rawGet(String endpoint, {Map<String, String>? extraHeaders}) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = await _buildHeaders(extraHeaders);
    final resp = await http.get(uri, headers: headers).timeout(_timeout);
    // debug
    // ignore: avoid_print
    print('[ApiService] GET $uri status=${resp.statusCode}');
    return resp;
  }

  /// Low-level POST that returns http.Response for custom callers.
  static Future<http.Response> rawPost(String endpoint, Map<String, dynamic> body,
      {Map<String, String>? extraHeaders}) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = await _buildHeaders({
      'Content-Type': 'application/json',
      if (extraHeaders != null) ...extraHeaders,
    });
    final resp = await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(_timeout);
    // debug
    // ignore: avoid_print
    print('[ApiService] POST $uri status=${resp.statusCode}');
    return resp;
  }

  /// Fetch circulars robustly: supports both `[{...},...]` and `{"circulars":[...]}`
  static Future<List<Circular>> fetchCirculars() async {
    const endpoint = '/circulars';
    try {
      final resp = await rawGet(endpoint);
      final body = resp.body;
      // ignore: avoid_print
      print('[ApiService] fetchCirculars status=${resp.statusCode} bodyPreview=${body.length>200 ? body.substring(0,200) + "..." : body}');

      if (resp.statusCode == 401) {
        // unauthorized: helpful debug
        // ignore: avoid_print
        print('[ApiService] Unauthorized (401) — token missing or invalid.');
        return <Circular>[];
      }

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = json.decode(body);
        List<dynamic> items = <dynamic>[];

        if (decoded is List) {
          items = decoded;
        } else if (decoded is Map && decoded['circulars'] is List) {
          items = decoded['circulars'] as List<dynamic>;
        } else if (decoded is Map && decoded['data'] is List) {
          items = decoded['data'] as List<dynamic>;
        } else {
          // Unexpected shape
          // ignore: avoid_print
          print('[ApiService] Unexpected JSON shape for circulars: ${decoded.runtimeType}');
          return <Circular>[];
        }

        final parsed = items.map((e) {
          if (e is Map<String, dynamic>) return Circular.fromJson(e);
          if (e is Map) return Circular.fromJson(Map<String, dynamic>.from(e));
          return null;
        }).whereType<Circular>().toList();

        parsed.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return parsed;
      } else {
        // ignore: avoid_print
        print('[ApiService] Non-200 status: ${resp.statusCode} - ${resp.reasonPhrase}');
        return <Circular>[];
      }
    } on TimeoutException {
      // ignore: avoid_print
      print('[ApiService] Timeout fetching circulars');
      return <Circular>[];
    } on FormatException catch (e) {
      // ignore: avoid_print
      print('[ApiService] JSON format error: ${e.message}');
      return <Circular>[];
    } catch (e, st) {
      // ignore: avoid_print
      print('[ApiService] Unexpected error: $e\n$st');
      return <Circular>[];
    }
  }
}
