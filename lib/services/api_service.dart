// lib/services/api_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// import your constants with an alias to avoid top-level name collisions
import '../constants/constants.dart' as AppConstants;
import '../models/circular.dart';

class ApiService {
  static const Duration _timeout = Duration(seconds: 15);
  static const String _authKey = 'authToken';

  /// Default base URL is read from lib/constants/constants.dart via alias.
  /// You can override at runtime with setBaseUrl (useful for emulator / testing).
  static String baseUrl = AppConstants.baseUrl;

  /// Override default baseUrl at runtime.
  static void setBaseUrl(String url) {
    if (url.isNotEmpty) baseUrl = url;
  }

  /// Save auth token after login
  static Future<void> setAuthToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authKey, token);
  }

  /// Clear saved token (logout)
  static Future<void> clearAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authKey);
  }

  /// Read saved token
  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_authKey);
  }

  /// Build request headers and include Authorization: Bearer <token> if present.
  static Future<Map<String, String>> _buildHeaders([Map<String, String>? extra]) async {
    final token = await _getToken();
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (extra != null) ...extra,
    };
    return headers;
  }

  // ------------------------
  // Low-level HTTP helpers
  // ------------------------

  static Future<http.Response> rawGet(String endpoint, {Map<String, String>? extraHeaders}) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = await _buildHeaders(extraHeaders);
    final resp = await http.get(uri, headers: headers).timeout(_timeout);
    // ignore: avoid_print
    print('[ApiService] GET $uri → ${resp.statusCode}');
    return resp;
  }

  static Future<http.Response> rawPost(String endpoint, Map<String, dynamic> body,
      {Map<String, String>? extraHeaders}) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = await _buildHeaders({
      'Content-Type': 'application/json',
      if (extraHeaders != null) ...extraHeaders,
    });
    final resp = await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(_timeout);
    // ignore: avoid_print
    print('[ApiService] POST $uri → ${resp.statusCode}');
    return resp;
  }

  static Future<http.Response> rawPut(String endpoint, Map<String, dynamic> body,
      {Map<String, String>? extraHeaders}) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = await _buildHeaders({
      'Content-Type': 'application/json',
      if (extraHeaders != null) ...extraHeaders,
    });
    final resp = await http.put(uri, headers: headers, body: jsonEncode(body)).timeout(_timeout);
    // ignore: avoid_print
    print('[ApiService] PUT $uri → ${resp.statusCode}');
    return resp;
  }

  static Future<http.Response> rawDelete(String endpoint, {Map<String, String>? extraHeaders}) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = await _buildHeaders(extraHeaders);
    final resp = await http.delete(uri, headers: headers).timeout(_timeout);
    // ignore: avoid_print
    print('[ApiService] DELETE $uri → ${resp.statusCode}');
    return resp;
  }

  // ------------------------
  // Example higher-level helper
  // ------------------------

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
