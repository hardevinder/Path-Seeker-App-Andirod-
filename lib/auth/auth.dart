// lib/services/auth.dart
// Authentication service + AuthProvider for StudentApp (teacher & student roles)
//
// - Stores authToken and activeRole in SharedPreferences
// - Exposes login/logout/getters and an AuthProvider for Provider package
// - Uses ApiService for HTTP requests (so Authorization header is added automatically)
// - Adjust endpoint paths ('/auth/login') if your backend uses different routes.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../constants/constants.dart';
import 'api.dart';

class AuthService {
  const AuthService();

  static const _tokenKey = 'authToken';
  static const _roleKey = 'activeRole';
  static const _userKey = 'currentUser'; // optional: store a small JSON of user info

  final ApiService _api = const ApiService();

  /// Attempts login with email & password.
  ///
  /// Returns a map: { 'success': bool, 'message': String, 'data': ... }
  /// On success the token, role and user are persisted.
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final resp = await _api.post('/auth/login', {
        'email': email,
        'password': password,
      });

      final body = _parseResponseBody(resp);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        // Expecting response to include token and role (adjust keys as necessary)
        final token = body['token'] ?? body['authToken'] ?? body['access_token'];
        final role = (body['role'] ?? body['user']?['role'] ?? '').toString();
        final user = body['user'] ?? body['data'] ?? null;

        if (token != null) {
          await _saveToken(token.toString());
          if (role != null && role.toString().isNotEmpty) {
            await _saveRole(role.toString());
          }
          if (user != null) {
            await _saveUser(user);
          }
          return {'success': true, 'message': 'Login successful', 'data': body};
        } else {
          return {'success': false, 'message': 'Token missing in response', 'data': body};
        }
      } else {
        final errMsg = body['message'] ??
            body['error'] ??
            'Login failed with status ${resp.statusCode}';
        return {'success': false, 'message': errMsg, 'data': body};
      }
    } catch (e) {
      return {'success': false, 'message': 'Login error: $e', 'data': null};
    }
  }

  /// Logs out the user — clears stored token, role and user info.
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_userKey);
    // Optionally notify backend about logout (if endpoint exists)
    // await _api.post('/auth/logout', {}); // uncomment if your backend supports it
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> _saveRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roleKey, role);
  }

  Future<void> _saveUser(dynamic user) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final jsonStr = jsonEncode(user);
      await prefs.setString(_userKey, jsonStr);
    } catch (_) {
      // ignore: user object not serializable
    }
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_roleKey);
  }

  /// Returns decoded user map if present
  Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_userKey);
    if (s == null) return null;
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return m;
    } catch (_) {
      return null;
    }
  }

  /// Simple helper to check login state
  Future<bool> isLoggedIn() async {
    final t = await getToken();
    return t != null && t.trim().isNotEmpty;
  }

  /// Helper to build auth headers (if you need them outside ApiService)
  Future<Map<String, String>> getAuthHeaders() async {
    final token = await getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  /// Utility: parse http.Response body safely
  Map<String, dynamic> _parseResponseBody(http.Response resp) {
    try {
      final dynamic body = jsonDecode(resp.body);
      if (body is Map<String, dynamic>) {
        return body;
      } else {
        return {'data': body};
      }
    } catch (e) {
      return {'raw': resp.body};
    }
  }
}

/// AuthProvider: a ChangeNotifier you can register with Provider package.
/// It keeps small in-memory state and exposes login/logout that update SharedPreferences.
class AuthProvider extends ChangeNotifier {
  final AuthService _service;

  bool _loading = false;
  bool get loading => _loading;

  String? _token;
  String? get token => _token;

  String _role = '';
  String get role => _role;

  Map<String, dynamic>? _user;
  Map<String, dynamic>? get user => _user;

  AuthProvider({AuthService? service}) : _service = service ?? const AuthService() {
    _initFromStorage();
  }

  Future<void> _initFromStorage() async {
    _token = await _service.getToken();
    _role = (await _service.getRole()) ?? '';
    _user = await _service.getUser();
    notifyListeners();
  }

  /// Authenticate and update provider state.
  Future<Map<String, dynamic>> login(String email, String password) async {
    _loading = true;
    notifyListeners();

    final result = await _service.login(email, password);

    if (result['success'] == true) {
      _token = await _service.getToken();
      _role = (await _service.getRole()) ?? '';
      _user = await _service.getUser();
      _loading = false;
      notifyListeners();
    } else {
      _loading = false;
      notifyListeners();
    }
    return result;
  }

  Future<void> logout() async {
    await _service.logout();
    _token = null;
    _role = '';
    _user = null;
    notifyListeners();
  }

  /// Force-refresh stored details (useful after profile edit)
  Future<void> refresh() async {
    await _initFromStorage();
  }

  /// Convenience check
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  /// Whether the current user is a teacher
  bool get isTeacher => _role.toLowerCase() == 'teacher';

  /// Whether the current user is a student
  bool get isStudent => _role.toLowerCase() == 'student';
}
