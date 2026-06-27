// lib/services/auth.dart
// Authentication service + AuthProvider for StudentApp (teacher & student roles)
//
// Fix included:
// - Clears all old session/student/role keys on logout
// - Clears stale old-user data before saving a new login
// - Keeps AuthProvider memory state fresh after login/logout
// - Saves common user keys when available for dashboard/screen compatibility

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'role_manager.dart';
import '../services/api_service.dart';

class AuthService {
  const AuthService();

  static const _tokenKey = 'authToken';
  static const _roleKey = 'activeRole';
  static const _userKey = 'currentUser';

  /// All user/session-specific keys that must be cleared on logout
  /// or before a fresh login.
  static const List<String> _sessionKeysToClear = [
    // Auth/session
    _tokenKey,
    _roleKey,
    _userKey,
    'selectedRole',
    'role',
    'userRole',

    // User identity
    'username',
    'userId',
    'user_id',
    'email',
    'name',

    // Student identity / sibling switcher
    'selectedStudentAdmissionNumber',
    'activeStudentAdmission',
    'admissionNumber',
    'admission_number',
    'studentId',
    'student_id',

    // Staff/teacher identity
    'employeeId',
    'employee_id',
    'teacherId',
    'teacher_id',

    // User-specific cached data
    'notifications',
    'pits_notifications',
  ];

  /// Attempts login with email & password.
  ///
  /// Returns:
  /// {
  ///   'success': bool,
  ///   'message': String,
  ///   'data': ...
  /// }
  ///
  /// On success, the token, role, and user are persisted.
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final resp = await ApiService.rawPost('/auth/login', {
        'email': email,
        'password': password,
      });

      final body = _parseResponseBody(resp);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final token =
            body['token'] ?? body['authToken'] ?? body['access_token'];

        if (token == null || token.toString().trim().isEmpty) {
          return {
            'success': false,
            'message': 'Token missing in response',
            'data': body,
          };
        }

        // Important:
        // Clear old user/student/sibling/role values before saving new login.
        await _clearLocalSession();

        final user = _extractUser(body);
        final role = _extractRole(body, user);

        await _saveToken(token.toString());

        if (role.trim().isNotEmpty) {
          await _saveRole(role.trim());
        }

        if (user != null) {
          await _saveUser(user);
          await _saveCommonUserKeys(user, role);
        } else {
          // Fallback keys if backend does not return a user object.
          await _saveFallbackLoginKeys(email: email, role: role);
        }

        return {
          'success': true,
          'message': 'Login successful',
          'data': body,
        };
      }

      final errMsg = body['message'] ??
          body['error'] ??
          'Login failed with status ${resp.statusCode}';

      return {
        'success': false,
        'message': errMsg.toString(),
        'data': body,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Login error: $e',
        'data': null,
      };
    }
  }

  /// Logs out the user — clears stored token, role, user info,
  /// selected student, sibling switcher, and cached user-specific values.
  Future<void> logout() async {
    await _clearLocalSession();

    // Optional backend logout if endpoint exists.
    // Keep it commented unless your backend supports it.
    // await _api.post('/auth/logout', {});
  }

  Future<void> _clearLocalSession() async {
    final prefs = await SharedPreferences.getInstance();

    for (final key in _sessionKeysToClear) {
      await prefs.remove(key);
    }
  }

  dynamic _extractUser(Map<String, dynamic> body) {
    final user = body['user'] ?? body['data'];

    if (user is Map<String, dynamic>) {
      return user;
    }

    if (user is Map) {
      return Map<String, dynamic>.from(user);
    }

    return null;
  }

  String _extractRole(Map<String, dynamic> body, dynamic user) {
    final directRole = body['role'] ?? body['activeRole'];

    if (directRole != null && directRole.toString().trim().isNotEmpty) {
      return AppRoles.normalize(directRole.toString());
    }

    if (user is Map) {
      final userRole = user['role'] ?? user['activeRole'];

      if (userRole != null && userRole.toString().trim().isNotEmpty) {
        return AppRoles.normalize(userRole.toString());
      }

      final roles = user['roles'] ?? user['Roles'];
      if (roles is List && roles.isNotEmpty) {
        final first = roles.first;

        if (first is String) {
          return AppRoles.normalize(first);
        }

        if (first is Map) {
          final slug = first['slug'];
          final name = first['name'];

          if (slug != null && slug.toString().trim().isNotEmpty) {
            return AppRoles.normalize(slug.toString());
          }

          if (name != null && name.toString().trim().isNotEmpty) {
            return AppRoles.normalize(name.toString());
          }
        }
      }
    }

    return '';
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
      // Ignore if user object is not serializable.
    }
  }

  Future<void> _saveFallbackLoginKeys({
    required String email,
    required String role,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('email', email);

    if (role.trim().isNotEmpty) {
      await prefs.setString(_roleKey, role.trim());
    }
  }

  Future<void> _saveCommonUserKeys(dynamic user, String role) async {
    if (user is! Map) return;

    final prefs = await SharedPreferences.getInstance();

    final username = _firstNonEmpty([
      user['username'],
      user['admissionNumber'],
      user['admission_number'],
      user['email'],
      user['id'],
    ]);

    final userId = _firstNonEmpty([
      user['id'],
      user['userId'],
      user['user_id'],
    ]);

    final email = _firstNonEmpty([
      user['email'],
    ]);

    final name = _firstNonEmpty([
      user['name'],
      user['fullName'],
      user['full_name'],
    ]);

    final admissionNumber = _firstNonEmpty([
      user['admissionNumber'],
      user['admission_number'],
      user['AdmissionNumber'],
      user['username'],
    ]);

    final studentId = _firstNonEmpty([
      user['studentId'],
      user['student_id'],
      user['Student_ID'],
    ]);

    final employeeId = _firstNonEmpty([
      user['employeeId'],
      user['employee_id'],
    ]);

    final teacherId = _firstNonEmpty([
      user['teacherId'],
      user['teacher_id'],
    ]);

    if (username != null) {
      await prefs.setString('username', username);
    }

    if (userId != null) {
      await prefs.setString('userId', userId);
    }

    if (email != null) {
      await prefs.setString('email', email);
    }

    if (name != null) {
      await prefs.setString('name', name);
    }

    if (role.trim().isNotEmpty) {
      await prefs.setString(_roleKey, role.trim());
    }

    if (admissionNumber != null) {
      await prefs.setString('admissionNumber', admissionNumber);

      // Keep selected student fresh for student login.
      // On logout or next login this will be cleared again.
      final normalizedRole = role.trim().toLowerCase();
      if (normalizedRole == 'student' || normalizedRole.isEmpty) {
        await prefs.setString(
            'selectedStudentAdmissionNumber', admissionNumber);
        await prefs.setString('activeStudentAdmission', admissionNumber);
      }
    }

    if (studentId != null) {
      await prefs.setString('studentId', studentId);
    }

    if (employeeId != null) {
      await prefs.setString('employeeId', employeeId);
    }

    if (teacherId != null) {
      await prefs.setString('teacherId', teacherId);
    }
  }

  String? _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      if (value == null) continue;

      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return null;
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_roleKey);
  }

  /// Returns decoded user map if present.
  Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_userKey);

    if (s == null || s.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(s);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  /// Simple helper to check login state.
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.trim().isNotEmpty;
  }

  /// Helper to build auth headers if you need them outside ApiService.
  Future<Map<String, String>> getAuthHeaders() async {
    final token = await getToken();

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (token != null && token.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  /// Utility: parse http.Response body safely.
  Map<String, dynamic> _parseResponseBody(http.Response resp) {
    try {
      final dynamic body = jsonDecode(resp.body);

      if (body is Map<String, dynamic>) {
        return body;
      }

      if (body is Map) {
        return Map<String, dynamic>.from(body);
      }

      return {'data': body};
    } catch (_) {
      return {'raw': resp.body};
    }
  }
}

/// AuthProvider:
/// A ChangeNotifier you can register with Provider package.
/// It keeps small in-memory state and exposes login/logout.
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

  AuthProvider({AuthService? service})
      : _service = service ?? const AuthService() {
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

    _token = await _service.getToken();
    _role = (await _service.getRole()) ?? '';
    _user = await _service.getUser();

    _loading = false;
    notifyListeners();

    return result;
  }

  Future<void> logout() async {
    _loading = true;
    notifyListeners();

    await _service.logout();

    _token = null;
    _role = '';
    _user = null;
    _loading = false;

    notifyListeners();
  }

  /// Force-refresh stored details.
  Future<void> refresh() async {
    await _initFromStorage();
  }

  bool get isAuthenticated => _token != null && _token!.trim().isNotEmpty;

  bool get isTeacher => AppRoles.normalize(_role) == AppRoles.teacher;

  bool get isCoordinator => AppRoles.normalize(_role) == AppRoles.coordinator;

  bool get isStudent => AppRoles.normalize(_role) == AppRoles.student;
}
