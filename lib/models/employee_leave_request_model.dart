class EmployeeLeaveRequest {
  final int id;
  final String employeeName;
  final String employeeCode;
  final String departmentName;
  final String designation;
  final String leaveTypeName;
  final String status;
  final String reason;
  final String remarks;
  final String startDate;
  final String endDate;
  final bool isWithoutPay;
  final String createdAt;
  final Map<String, dynamic> raw;

  const EmployeeLeaveRequest({
    required this.id,
    required this.employeeName,
    required this.employeeCode,
    required this.departmentName,
    required this.designation,
    required this.leaveTypeName,
    required this.status,
    required this.reason,
    required this.remarks,
    required this.startDate,
    required this.endDate,
    required this.isWithoutPay,
    required this.createdAt,
    required this.raw,
  });

  factory EmployeeLeaveRequest.fromJson(Map<String, dynamic> json) {
    final employee = _asMap(
      json['employee'] ??
          json['Employee'] ??
          json['staff'] ??
          json['user'] ??
          json['employee_details'],
    );
    final department = _asMap(employee['department'] ?? json['department']);
    final leaveType = _asMap(
      json['leaveType'] ??
          json['leave_type'] ??
          json['leaveTypeInfo'] ??
          json['type'],
    );

    return EmployeeLeaveRequest(
      id: _asInt(json['id']),
      employeeName: _firstText([
        employee['name'],
        employee['employee_name'],
        json['employee_name'],
        json['name'],
      ], fallback: 'Employee'),
      employeeCode: _firstText([
        employee['employee_id'],
        employee['code'],
        employee['emp_code'],
        json['employee_id'],
        json['employee_code'],
      ]),
      departmentName: _firstText([
        department['name'],
        employee['department_name'],
        json['department_name'],
      ], fallback: '—'),
      designation: _firstText([
        employee['designation'],
        employee['title'],
        employee['role'],
        json['designation'],
      ], fallback: '—'),
      leaveTypeName: _firstText([
        leaveType['name'],
        leaveType['title'],
        json['leave_type_name'],
        json['leaveTypeName'],
        json['type_name'],
      ], fallback: 'Leave'),
      status: _normalize(_firstText([json['status']], fallback: 'pending')),
      reason: _firstText([json['reason'], json['description']], fallback: '—'),
      remarks: _firstText([
        json['remarks'],
        json['hr_remarks'],
        json['approval_remarks'],
      ]),
      startDate: _dateOnly(_firstText([
        json['start_date'],
        json['startDate'],
        json['from_date'],
        json['fromDate'],
      ])),
      endDate: _dateOnly(_firstText([
        json['end_date'],
        json['endDate'],
        json['to_date'],
        json['toDate'],
      ])),
      isWithoutPay: _asBool(
        json['is_without_pay'] ?? json['isWithoutPay'] ?? json['without_pay'],
      ),
      createdAt: _dateOnly(_firstText([json['createdAt'], json['created_at']])),
      raw: json,
    );
  }

  String get dateRange {
    if (startDate.isEmpty && endDate.isEmpty) return '—';
    if (endDate.isEmpty || startDate == endDate) return startDate;
    return '$startDate → $endDate';
  }

  bool get isPending => status == 'pending';

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  static bool _asBool(dynamic value) {
    if (value is bool) return value;
    final text = '${value ?? ''}'.trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'yes';
  }

  static String _firstText(List<dynamic> values, {String fallback = ''}) {
    for (final value in values) {
      final text = '${value ?? ''}'.trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return fallback;
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
  }

  static String _dateOnly(String value) {
    final text = value.trim();
    if (text.isEmpty) return '';
    if (text.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(text)) {
      return text.substring(0, 10);
    }
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return text;
    return '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }
}