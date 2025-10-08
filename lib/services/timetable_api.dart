// lib/services/timetable_api.dart
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/timetable_models.dart';
import '../constants/constants.dart';

class TimetableApi {
  static const Duration _timeout = Duration(seconds: 15);
  static const _authKey = 'authToken';

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_authKey);
    final h = <String, String>{'Accept': 'application/json'};
    if (token != null && token.isNotEmpty) h['Authorization'] = 'Bearer $token';
    return h;
  }

  static Future<List<Period>> fetchPeriods() async {
    final uri = Uri.parse('$baseUrl/periods');
    final resp = await http.get(uri, headers: await _headers()).timeout(_timeout);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final body = jsonDecode(resp.body);
      final list = body is List ? body : (body['periods'] ?? body['data'] ?? []);
      return (list as List).map((e) => Period.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    return [];
  }

  static Future<List<TimetableRecord>> fetchTimetable() async {
    final uri = Uri.parse('$baseUrl/period-class-teacher-subject/student/timetable');
    final resp = await http.get(uri, headers: await _headers()).timeout(_timeout);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final body = jsonDecode(resp.body);
      final list = body is List ? body : (body['timetable'] ?? body['data'] ?? []);
      return (list as List).map((e) => TimetableRecord.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    return [];
  }

  static Future<List<Holiday>> fetchHolidays() async {
    final uri = Uri.parse('$baseUrl/holidays');
    final resp = await http.get(uri, headers: await _headers()).timeout(_timeout);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final body = jsonDecode(resp.body);
      final list = body is List ? body : (body['holidays'] ?? body['data'] ?? []);
      return (list as List).map((e) => Holiday.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    return [];
  }

  static Future<List<Substitution>> fetchSubsForDate(String date) async {
    final uri = Uri.parse('$baseUrl/substitutions/by-date/student?date=$date');
    final resp = await http.get(uri, headers: await _headers()).timeout(_timeout);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final body = jsonDecode(resp.body);
      final list = body is List ? body : (body['substitutions'] ?? body['data'] ?? []);
      return (list as List).map((e) => Substitution.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    return [];
  }
}
