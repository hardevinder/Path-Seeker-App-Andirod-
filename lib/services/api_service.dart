// lib/services/api_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// import your constants with an alias to avoid top-level name collisions
import '../constants/constants.dart' as AppConstants;
import '../models/circular.dart';
import '../models/student_message.dart';

class ApiService {
  static const Duration _timeout = Duration(seconds: 15);
  static const String _authKey = 'authToken';

  /// Default base URL is read from lib/constants/constants.dart via alias.
  /// You can override at runtime with setBaseUrl.
  static String baseUrl = AppConstants.baseUrl;

  /// All user/session-specific keys that should be removed on logout.
  static const List<String> _sessionKeysToClear = [
    // Auth/session
    _authKey,
    'roles',
    'activeRole',
    'selectedRole',
    'role',
    'userRole',
    'currentUser',

    // Basic user identity
    'username',
    'userId',
    'user_id',
    'name',
    'email',

    // Student/family/sibling values
    'family',
    'selectedStudentAdmissionNumber',
    'activeStudentAdmission',
    'admissionNumber',
    'admission_number',
    'studentId',
    'student_id',

    // Teacher/staff values
    'employeeId',
    'employee_id',
    'teacherId',
    'teacher_id',

    // Cached user-specific data
    'notifications',
    'pits_notifications',
  ];

  /// Override default baseUrl at runtime.
  static void setBaseUrl(String url) {
    final cleanUrl = url.trim();
    if (cleanUrl.isNotEmpty) {
      baseUrl = cleanUrl;
    }
  }

  /// Save auth token after login.
  static Future<void> setAuthToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authKey, token);
  }

  /// Clear saved token only.
  ///
  /// Note:
  /// For full logout/session cleanup, use clearLocalSession().
  static Future<void> clearAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authKey);
  }

  /// Clear full local session/cache for logout.
  ///
  /// Use this when logging out from header/app bar/drawer/login screen.
  /// This prevents old student/teacher/role/sibling data from mixing
  /// with the next login on the same Android device.
  static Future<void> clearLocalSession() async {
    final prefs = await SharedPreferences.getInstance();

    for (final key in _sessionKeysToClear) {
      await prefs.remove(key);
    }
  }

  /// Read saved token.
  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_authKey);

    if (token == null || token.trim().isEmpty) {
      return null;
    }

    return token.trim();
  }

  /// Build request headers and include Authorization: Bearer <token> if present.
  static Future<Map<String, String>> _buildHeaders([
    Map<String, String>? extra,
  ]) async {
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

  static Future<http.Response> rawGet(
    String endpoint, {
    Map<String, String>? extraHeaders,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = await _buildHeaders(extraHeaders);

    final resp = await http.get(uri, headers: headers).timeout(_timeout);

    // ignore: avoid_print
    print('[ApiService] GET $uri → ${resp.statusCode}');

    return resp;
  }

  static Future<http.Response> rawPost(
    String endpoint,
    Map<String, dynamic> body, {
    Map<String, String>? extraHeaders,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');

    final headers = await _buildHeaders({
      'Content-Type': 'application/json',
      if (extraHeaders != null) ...extraHeaders,
    });

    final resp = await http
        .post(
          uri,
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    // ignore: avoid_print
    print('[ApiService] POST $uri → ${resp.statusCode}');

    return resp;
  }

  static Future<http.Response> rawPut(
    String endpoint,
    Map<String, dynamic> body, {
    Map<String, String>? extraHeaders,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');

    final headers = await _buildHeaders({
      'Content-Type': 'application/json',
      if (extraHeaders != null) ...extraHeaders,
    });

    final resp = await http
        .put(
          uri,
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    // ignore: avoid_print
    print('[ApiService] PUT $uri → ${resp.statusCode}');

    return resp;
  }

  static Future<http.Response> rawPatch(
    String endpoint,
    Map<String, dynamic> body, {
    Map<String, String>? extraHeaders,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');

    final headers = await _buildHeaders({
      'Content-Type': 'application/json',
      if (extraHeaders != null) ...extraHeaders,
    });

    final resp = await http
        .patch(
          uri,
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    // ignore: avoid_print
    print('[ApiService] PATCH $uri → ${resp.statusCode}');

    return resp;
  }

  static Future<http.Response> rawDelete(
    String endpoint, {
    Map<String, String>? extraHeaders,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = await _buildHeaders(extraHeaders);

    final resp = await http.delete(uri, headers: headers).timeout(_timeout);

    // ignore: avoid_print
    print('[ApiService] DELETE $uri → ${resp.statusCode}');

    return resp;
  }

  // ------------------------
  // Common response helpers
  // ------------------------

  static List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;

    if (decoded is Map) {
      final keys = [
        'data',
        'rows',
        'results',
        'items',
        'transactions',
        'sessions',
        'list',
        'records',
        'classes',
        'sections',
        'students',
      ];

      for (final key in keys) {
        final value = decoded[key];
        if (value is List) return value;
      }

      final data = decoded['data'];
      if (data is Map) {
        for (final key in keys) {
          final value = data[key];
          if (value is List) return value;
        }
      }
    }

    return <dynamic>[];
  }

  static Map<String, dynamic> _extractMap(dynamic decoded) {
    if (decoded is Map<String, dynamic>) return decoded;

    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }

    return <String, dynamic>{};
  }

  /// Extract common backend error messages safely.
  static String _extractApiError(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);

      if (decoded is Map) {
        final message =
            decoded['message'] ?? decoded['error'] ?? decoded['sqlMessage'];

        if (message != null && message.toString().trim().isNotEmpty) {
          return message.toString();
        }
      }
    } catch (_) {}

    return fallback;
  }

  // ------------------------
  // Super Admin Transactions
  // ------------------------

  /// Fetch academic sessions for Super Admin transaction filters.
  ///
  /// Expected backend examples:
  /// - GET /sessions
  /// Response shapes supported:
  /// - [...]
  /// - {"data": [...]}
  /// - {"sessions": [...]}
  static Future<List<dynamic>> fetchSuperAdminSessions() async {
    try {
      final resp = await rawGet('/sessions');

      if (resp.statusCode == 401) {
        throw Exception('Unauthorized. Please login again.');
      }

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);
        return _extractList(decoded);
      }

      throw Exception(
        _extractApiError(resp.body, 'Failed to fetch sessions.'),
      );
    } on TimeoutException {
      throw Exception('Sessions request timed out.');
    } catch (e) {
      // ignore: avoid_print
      print('[ApiService] fetchSuperAdminSessions error: $e');
      rethrow;
    }
  }

  /// Fetch transactions for Super Admin mobile screen.
  ///
  /// Expected backend examples:
  /// - GET /transactions
  /// - GET /transactions?session_id=2
  ///
  /// Response shapes supported:
  /// - [...]
  /// - {"data": [...]}
  /// - {"transactions": [...]}
  /// - {"rows": [...]}
  static Future<List<Map<String, dynamic>>> fetchSuperAdminTransactions({
    int? sessionId,
  }) async {
    final endpoint = sessionId != null
        ? '/transactions?session_id=$sessionId'
        : '/transactions';

    try {
      final resp = await rawGet(endpoint);

      if (resp.statusCode == 401) {
        throw Exception('Unauthorized. Please login again.');
      }

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);
        final list = _extractList(decoded);

        return list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

      throw Exception(
        _extractApiError(resp.body, 'Failed to fetch transactions.'),
      );
    } on TimeoutException {
      throw Exception('Transactions request timed out.');
    } catch (e) {
      // ignore: avoid_print
      print('[ApiService] fetchSuperAdminTransactions error: $e');
      rethrow;
    }
  }

  /// Fetch day summary for Super Admin transaction screen.
  ///
  /// Expected backend examples:
  /// - GET /transactions/summary/day-summary
  /// - GET /transactions/summary/day-summary?session_id=2
  static Future<Map<String, dynamic>> fetchSuperAdminTransactionDaySummary({
    int? sessionId,
  }) async {
    final endpoint = sessionId != null
        ? '/transactions/summary/day-summary?session_id=$sessionId'
        : '/transactions/summary/day-summary';

    try {
      final resp = await rawGet(endpoint);

      if (resp.statusCode == 401) {
        throw Exception('Unauthorized. Please login again.');
      }

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);

        final map = _extractMap(decoded);

        if (map['data'] is Map) {
          return Map<String, dynamic>.from(map['data'] as Map);
        }

        return map;
      }

      throw Exception(
        _extractApiError(resp.body, 'Failed to fetch transaction summary.'),
      );
    } on TimeoutException {
      throw Exception('Transaction summary request timed out.');
    } catch (e) {
      // ignore: avoid_print
      print('[ApiService] fetchSuperAdminTransactionDaySummary error: $e');
      rethrow;
    }
  }

  /// Cancel transaction.
  ///
  /// Expected backend:
  /// - POST /transactions/:id/cancel
  static Future<void> cancelSuperAdminTransaction(int id) async {
    try {
      final resp = await rawPost('/transactions/$id/cancel', {});

      if (resp.statusCode == 401) {
        throw Exception('Unauthorized. Please login again.');
      }

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return;
      }

      throw Exception(
        _extractApiError(resp.body, 'Failed to cancel transaction.'),
      );
    } on TimeoutException {
      throw Exception('Cancel transaction request timed out.');
    } catch (e) {
      // ignore: avoid_print
      print('[ApiService] cancelSuperAdminTransaction error: $e');
      rethrow;
    }
  }

  /// Delete cancelled transaction.
  ///
  /// Expected backend:
  /// - DELETE /transactions/:id
  static Future<void> deleteSuperAdminTransaction(int id) async {
    try {
      final resp = await rawDelete('/transactions/$id');

      if (resp.statusCode == 401) {
        throw Exception('Unauthorized. Please login again.');
      }

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return;
      }

      throw Exception(
        _extractApiError(resp.body, 'Failed to delete transaction.'),
      );
    } on TimeoutException {
      throw Exception('Delete transaction request timed out.');
    } catch (e) {
      // ignore: avoid_print
      print('[ApiService] deleteSuperAdminTransaction error: $e');
      rethrow;
    }
  }

  // ------------------------
  // Student Messages
  // ------------------------

  /// Fetch logged-in student's / selected sibling student's message inbox.
  ///
  /// Backend:
  /// GET /api/messages/me?page=&limit=&type=&q=&unreadOnly=&admissionNumber=
  static Future<List<StudentMessageInboxItem>> fetchStudentMessages({
    int page = 1,
    int limit = 30,
    String? type,
    String? search,
    bool unreadOnly = false,
    String? admissionNumber,
  }) async {
    final uri = Uri.parse('$baseUrl/api/messages/me').replace(
      queryParameters: {
        'page': '$page',
        'limit': '$limit',
        if (type != null && type.trim().isNotEmpty) 'type': type.trim(),
        if (search != null && search.trim().isNotEmpty) 'q': search.trim(),
        'unreadOnly': unreadOnly ? 'true' : 'false',
        if (admissionNumber != null && admissionNumber.trim().isNotEmpty)
          'admissionNumber': admissionNumber.trim(),
      },
    );

    try {
      final headers = await _buildHeaders();
      final resp = await http.get(uri, headers: headers).timeout(_timeout);

      // ignore: avoid_print
      print('[ApiService] GET $uri → ${resp.statusCode}');

      if (resp.statusCode == 401) {
        throw Exception('Unauthorized. Please login again.');
      }

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);

        final rows = decoded is Map && decoded['data'] is List
            ? decoded['data'] as List
            : <dynamic>[];

        return rows
            .whereType<Map>()
            .map(
              (e) => StudentMessageInboxItem.fromJson(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList();
      }

      throw Exception(
        _extractApiError(resp.body, 'Failed to load messages.'),
      );
    } on TimeoutException {
      throw Exception('Messages request timed out.');
    } catch (e) {
      // ignore: avoid_print
      print('[ApiService] fetchStudentMessages error: $e');
      rethrow;
    }
  }

  /// Fetch one full message thread by thread id.
  ///
  /// Backend:
  /// GET /api/messages/:threadId?admissionNumber=
  static Future<StudentMessageThread> fetchStudentMessageThread(
    int threadId, {
    String? admissionNumber,
  }) async {
    final uri = Uri.parse('$baseUrl/api/messages/$threadId').replace(
      queryParameters: {
        if (admissionNumber != null && admissionNumber.trim().isNotEmpty)
          'admissionNumber': admissionNumber.trim(),
      },
    );

    try {
      final headers = await _buildHeaders();
      final resp = await http.get(uri, headers: headers).timeout(_timeout);

      // ignore: avoid_print
      print('[ApiService] GET $uri → ${resp.statusCode}');

      if (resp.statusCode == 401) {
        throw Exception('Unauthorized. Please login again.');
      }

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);
        final threadJson = decoded is Map ? decoded['thread'] : null;

        if (threadJson is Map) {
          return StudentMessageThread.fromJson(
            Map<String, dynamic>.from(threadJson),
          );
        }

        throw Exception('Invalid message thread response.');
      }

      throw Exception(
        _extractApiError(resp.body, 'Failed to load message thread.'),
      );
    } on TimeoutException {
      throw Exception('Message thread request timed out.');
    } catch (e) {
      // ignore: avoid_print
      print('[ApiService] fetchStudentMessageThread error: $e');
      rethrow;
    }
  }

  /// Reply to a message thread.
  ///
  /// Backend:
  /// POST /api/messages/:threadId/reply
  static Future<void> replyToStudentMessageThread({
    required int threadId,
    required String body,
    String? admissionNumber,
  }) async {
    final cleanBody = body.trim();

    if (cleanBody.isEmpty) {
      throw Exception('Reply message cannot be empty.');
    }

    final uri = Uri.parse('$baseUrl/api/messages/$threadId/reply');

    final payload = <String, dynamic>{
      'body': cleanBody,
      if (admissionNumber != null && admissionNumber.trim().isNotEmpty)
        'admissionNumber': admissionNumber.trim(),
    };

    try {
      final headers = await _buildHeaders({
        'Content-Type': 'application/json',
      });

      final resp = await http
          .post(
            uri,
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(_timeout);

      // ignore: avoid_print
      print('[ApiService] POST $uri → ${resp.statusCode}');

      if (resp.statusCode == 401) {
        throw Exception('Unauthorized. Please login again.');
      }

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return;
      }

      throw Exception(
        _extractApiError(resp.body, 'Failed to send reply.'),
      );
    } on TimeoutException {
      throw Exception('Reply request timed out.');
    } catch (e) {
      // ignore: avoid_print
      print('[ApiService] replyToStudentMessageThread error: $e');
      rethrow;
    }
  }

  // ------------------------
  // Circulars
  // ------------------------

  /// Fetch circulars robustly:
  /// supports both:
  /// - [{...}, ...]
  /// - {"circulars": [...]}
  /// - {"data": [...]}
  ///
  /// Also supports sibling/student filtering:
  /// GET /circulars?admissionNumber=xxxx
  static Future<List<Circular>> fetchCirculars({
    String? admissionNumber,
  }) async {
    final query = <String, String>{};

    if (admissionNumber != null && admissionNumber.trim().isNotEmpty) {
      query['admissionNumber'] = admissionNumber.trim();
    }

    final endpoint = Uri(
      path: '/circulars',
      queryParameters: query.isEmpty ? null : query,
    ).toString();

    try {
      final resp = await rawGet(endpoint);
      final body = resp.body;

      // ignore: avoid_print
      print(
        '[ApiService] fetchCirculars status=${resp.statusCode} bodyPreview=${body.length > 200 ? body.substring(0, 200) + "..." : body}',
      );

      if (resp.statusCode == 401) {
        // ignore: avoid_print
        print('[ApiService] Unauthorized (401) — token missing or invalid.');
        return <Circular>[];
      }

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(body);
        List<dynamic> items = <dynamic>[];

        if (decoded is List) {
          items = decoded;
        } else if (decoded is Map && decoded['circulars'] is List) {
          items = decoded['circulars'] as List<dynamic>;
        } else if (decoded is Map && decoded['data'] is List) {
          items = decoded['data'] as List<dynamic>;
        } else if (decoded is Map && decoded['rows'] is List) {
          items = decoded['rows'] as List<dynamic>;
        } else {
          // ignore: avoid_print
          print(
            '[ApiService] Unexpected JSON shape for circulars: ${decoded.runtimeType}',
          );
          return <Circular>[];
        }

        final parsed = items
            .map((e) {
              if (e is Map<String, dynamic>) {
                return Circular.fromJson(e);
              }

              if (e is Map) {
                return Circular.fromJson(Map<String, dynamic>.from(e));
              }

              return null;
            })
            .whereType<Circular>()
            .toList();

        parsed.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        return parsed;
      }

      // ignore: avoid_print
      print(
        '[ApiService] Non-200 status: ${resp.statusCode} - ${resp.reasonPhrase}',
      );

      return <Circular>[];
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
