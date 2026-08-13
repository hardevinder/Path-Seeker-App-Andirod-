import 'dart:convert';

import 'api_service.dart';

class DepartmentManagementApi {
  static Map<String, dynamic> _decode(dynamic response) {
    final dynamic decoded = jsonDecode(response.body);
    final data = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'data': decoded};

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['message'] ?? 'Department request failed');
    }
    return data;
  }

  static Future<Map<String, dynamic>> bootstrap() async {
    return _decode(await ApiService.rawGet('/department-management/bootstrap'));
  }

  static Future<Map<String, dynamic>> myDashboard() async {
    return _decode(await ApiService.rawGet('/department-management/my-dashboard'));
  }

  static Future<Map<String, dynamic>> studentActivities() async {
    return _decode(await ApiService.rawGet(
      '/department-management/student/my-activities',
    ));
  }

  static Future<Map<String, dynamic>> departmentDashboard(int departmentId) async {
    return _decode(await ApiService.rawGet(
      '/department-management/departments/$departmentId/dashboard',
    ));
  }

  static Future<Map<String, dynamic>> academics(int departmentId) async {
    return _decode(await ApiService.rawGet(
      '/department-management/departments/$departmentId/academics',
    ));
  }

  static Future<Map<String, dynamic>> updateTask(
    int taskId,
    Map<String, dynamic> body,
  ) async {
    return _decode(await ApiService.rawPatch(
      '/department-management/tasks/$taskId',
      body,
    ));
  }

  static Future<Map<String, dynamic>> updateDuty(
    int dutyId,
    Map<String, dynamic> body,
  ) async {
    return _decode(await ApiService.rawPatch(
      '/department-management/duties/$dutyId',
      body,
    ));
  }

  static Future<Map<String, dynamic>> requestReturn(int transactionId) async {
    return _decode(await ApiService.rawPost(
      '/department-management/inventory-issues/$transactionId/request-return',
      const <String, dynamic>{},
    ));
  }

  static Future<Map<String, dynamic>> confirmReturn(int transactionId) async {
    return _decode(await ApiService.rawPost(
      '/department-management/inventory-issues/$transactionId/confirm-return',
      const <String, dynamic>{},
    ));
  }

  static Future<Map<String, dynamic>> createTask(
    int departmentId,
    Map<String, dynamic> body,
  ) async {
    return _decode(await ApiService.rawPost(
      '/department-management/departments/$departmentId/tasks',
      body,
    ));
  }

  static Future<Map<String, dynamic>> createEvent(
    int departmentId,
    Map<String, dynamic> body,
  ) async {
    return _decode(await ApiService.rawPost(
      '/department-management/departments/$departmentId/events',
      body,
    ));
  }

  static Future<Map<String, dynamic>> createAchievement(
    int departmentId,
    Map<String, dynamic> body,
  ) async {
    return _decode(await ApiService.rawPost(
      '/department-management/departments/$departmentId/achievements',
      body,
    ));
  }

  static Future<Map<String, dynamic>> createInventoryLocation(
    int departmentId,
    Map<String, dynamic> body,
  ) async {
    return _decode(await ApiService.rawPost(
      '/department-management/departments/$departmentId/inventory/locations',
      body,
    ));
  }

  static Future<Map<String, dynamic>> createInventoryItem(
    int departmentId,
    Map<String, dynamic> body,
  ) async {
    return _decode(await ApiService.rawPost(
      '/department-management/departments/$departmentId/inventory/items',
      body,
    ));
  }

  static Future<Map<String, dynamic>> receiveInventoryStock(
    int departmentId,
    int itemId,
    Map<String, dynamic> body,
  ) async {
    return _decode(await ApiService.rawPost(
      '/department-management/departments/$departmentId/inventory/items/$itemId/receive',
      body,
    ));
  }

  static Future<Map<String, dynamic>> issueInventoryStock(
    int departmentId,
    int itemId,
    Map<String, dynamic> body,
  ) async {
    return _decode(await ApiService.rawPost(
      '/department-management/departments/$departmentId/inventory/items/$itemId/issue',
      body,
    ));
  }
}
