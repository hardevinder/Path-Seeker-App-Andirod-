import 'dart:convert';
import '../models/online_class_models.dart';
import 'api_service.dart';

class OnlineClassApiException implements Exception {
  final String message;
  const OnlineClassApiException(this.message);
  @override
  String toString() => message;
}

class OnlineClassApi {
  static dynamic _decode(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};
    return jsonDecode(body);
  }

  static dynamic _data(dynamic decoded) =>
      decoded is Map && decoded['data'] != null ? decoded['data'] : decoded;

  static void _check(int code, dynamic decoded) {
    if (code >= 200 && code < 300) return;
    final errors = decoded is Map ? decoded['errors'] : null;
    final message = errors is List
        ? errors.join('. ')
        : decoded is Map
            ? decoded['message']?.toString()
            : null;
    throw OnlineClassApiException(message ?? 'Request failed ($code)');
  }

  static Future<ZoomConnection> zoomStatus() async {
    final response = await ApiService.rawGet('/api/zoom/status');
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
    return ZoomConnection.fromJson(
        Map<String, dynamic>.from(_data(decoded) as Map));
  }

  static Future<Uri> zoomAuthorizationUrl() async {
    final response = await ApiService.rawGet('/api/zoom/connect?client=mobile');
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
    final url = (_data(decoded) as Map)['authorization_url']?.toString();
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null) {
      throw const OnlineClassApiException(
          'Zoom authorization URL was not returned.');
    }
    return uri;
  }

  static Future<void> disconnectZoom() async {
    final response = await ApiService.rawDelete('/api/zoom/disconnect');
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
  }

  static Future<List<OnlineClass>> classes() async {
    final response = await ApiService.rawGet('/api/online-classes');
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
    final value = _data(decoded);
    final rows = value is List ? value : <dynamic>[];
    return rows
        .whereType<Map>()
        .map((row) => OnlineClass.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  static Future<List<AcademicOption>> options(
      String endpoint, String nameKey) async {
    final response = await ApiService.rawGet(endpoint);
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
    dynamic value = _data(decoded);
    if (value is Map) {
      value = value['rows'] ??
          value['classes'] ??
          value['sections'] ??
          value['subjects'] ??
          <dynamic>[];
    }
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((row) {
          final map = Map<String, dynamic>.from(row);
          return AcademicOption(
            id: int.tryParse(map['id']?.toString() ?? '') ?? 0,
            name: map[nameKey]?.toString() ?? '',
            classId: int.tryParse(map['class_id']?.toString() ?? ''),
          );
        })
        .where((item) => item.id > 0 && item.name.isNotEmpty)
        .toList();
  }

  static Future<List<OnlineClassAssignment>> assignments() async {
    final response = await ApiService.rawGet('/api/online-classes/options');
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
    final value = _data(decoded);
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((row) =>
            OnlineClassAssignment.fromJson(Map<String, dynamic>.from(row)))
        .where(
            (row) => row.classId > 0 && row.sectionId > 0 && row.subjectId > 0)
        .toList();
  }

  static Future<void> save(Map<String, dynamic> payload, {int? id}) async {
    final response = id == null
        ? await ApiService.rawPost('/api/online-classes', payload)
        : await ApiService.rawPatch('/api/online-classes/$id', payload);
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
  }

  static Future<void> cancel(int id) async {
    final response = await ApiService.rawDelete('/api/online-classes/$id');
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
  }

  static Future<Uri> actionUrl(int id, {required bool start}) async {
    final response = start
        ? await ApiService.rawPost('/api/online-classes/$id/start', {})
        : await ApiService.rawGet('/api/online-classes/$id/join');
    final decoded = _decode(response.body);
    _check(response.statusCode, decoded);
    final data = _data(decoded) as Map;
    final uri =
        Uri.tryParse(data[start ? 'start_url' : 'join_url']?.toString() ?? '');
    if (uri == null || !uri.hasScheme) {
      throw const OnlineClassApiException('Zoom link is unavailable.');
    }
    return uri;
  }
}
