import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_service.dart';

const List<String> _genderOptions = ['Male', 'Female', 'Other'];
const List<String> _maritalOptions = ['Single', 'Married', 'Other'];
const List<String> _bloodOptions = [
  'A+',
  'A-',
  'B+',
  'B-',
  'AB+',
  'AB-',
  'O+',
  'O-',
];

class HrEmployeeManagementScreen extends StatefulWidget {
  const HrEmployeeManagementScreen({super.key});

  @override
  State<HrEmployeeManagementScreen> createState() =>
      _HrEmployeeManagementScreenState();
}

class _HrEmployeeManagementScreenState
    extends State<HrEmployeeManagementScreen> {
  final DateFormat _apiDate = DateFormat('yyyy-MM-dd');
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  String? _error;

  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _departments = [];

  String _departmentId = '';
  String _designation = '';
  String _status = 'all';
  DateTime? _dobFrom;
  DateTime? _dobTo;
  DateTime? _joiningFrom;
  DateTime? _joiningTo;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _designations {
    final values = _employees
        .map((employee) => _safe(employee['designation']))
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    values.sort();
    return values;
  }

  List<Map<String, dynamic>> get _filteredEmployees {
    final q = _searchController.text.trim().toLowerCase();
    return _employees.where((employee) {
      if (_status != 'all' && _safe(employee['status']) != _status) {
        return false;
      }
      if (_departmentId.isNotEmpty &&
          _safe(employee['department_id']) != _departmentId) {
        return false;
      }
      if (_designation.isNotEmpty &&
          _safe(employee['designation']) != _designation) {
        return false;
      }
      if (q.isNotEmpty &&
          !_safe(employee['name']).toLowerCase().contains(q) &&
          !_safe(employee['phone']).toLowerCase().contains(q) &&
          !_safe(employee['email']).toLowerCase().contains(q) &&
          !_safe(employee['employee_id']).toLowerCase().contains(q)) {
        return false;
      }
      if (!_inDateRange(employee['dob'], _dobFrom, _dobTo)) return false;
      if (!_inDateRange(employee['joining_date'], _joiningFrom, _joiningTo)) {
        return false;
      }
      return true;
    }).toList();
  }

  int get _enabledCount => _employees
      .where((employee) => _safe(employee['status'], 'enabled') == 'enabled')
      .length;

  int get _disabledCount => _employees
      .where((employee) => _safe(employee['status']) == 'disabled')
      .length;

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _loadEmployees(),
        _loadDepartments(),
      ]);
      if (!mounted) return;
      setState(() {
        _employees = results[0];
        _departments = results[1];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadEmployees() async {
    final response = await ApiService.rawGet('/employees');
    if (!_ok(response.statusCode)) {
      throw Exception(_apiError(response.body, 'Failed to load employees.'));
    }
    final decoded = jsonDecode(response.body);
    return _extractRows(decoded, keys: const ['employees']);
  }

  Future<List<Map<String, dynamic>>> _loadDepartments() async {
    final response = await ApiService.rawGet('/departments');
    if (!_ok(response.statusCode)) return <Map<String, dynamic>>[];
    return _extractRows(jsonDecode(response.body), keys: const ['departments']);
  }

  Future<void> _openEditor({Map<String, dynamic>? employee}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EmployeeEditorSheet(
        employee: employee,
        departments: _departments,
        onSave: _saveEmployee,
      ),
    );
    if (saved == true) await _loadAll();
  }

  Future<bool> _saveEmployee(
    Map<String, dynamic>? employee,
    Map<String, dynamic> payload,
  ) async {
    for (final field in ['name', 'phone', 'email']) {
      if (_safe(payload[field]).isEmpty) {
        _showSnack('Field "${field.replaceAll('_', ' ')}" is required.');
        return false;
      }
    }
    setState(() => _busy = true);
    try {
      final cleaned = {
        for (final entry in payload.entries)
          entry.key: _safe(entry.value).isEmpty ? null : entry.value,
      };
      if (cleaned['department_id'] != null) {
        cleaned['department_id'] = int.tryParse('${cleaned['department_id']}');
      }
      final response = employee == null
          ? await ApiService.rawPost('/employees', cleaned)
          : await ApiService.rawPut('/employees/${employee['id']}', cleaned);
      if (!_ok(response.statusCode)) {
        _showSnack(_apiError(response.body, 'Operation failed.'));
        return false;
      }
      _showSnack(employee == null ? 'Employee added.' : 'Employee updated.');
      return true;
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleStatus(Map<String, dynamic> employee) async {
    final enabled = _safe(employee['status'], 'enabled') == 'enabled';
    final action = enabled ? 'Disable' : 'Enable';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$action Employee?'),
        content: Text(
            '${employee['name'] ?? 'Employee'} will be ${enabled ? 'disabled' : 'enabled'}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final response = await ApiService.rawPut('/employees/${employee['id']}', {
        'status': enabled ? 'disabled' : 'enabled',
      });
      if (!_ok(response.statusCode)) {
        _showSnack(_apiError(response.body, 'Failed to update status.'));
        return;
      }
      _showSnack('Employee ${enabled ? 'disabled' : 'enabled'}.');
      await _loadAll();
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadFile(String endpoint, String fileName) async {
    setState(() => _busy = true);
    try {
      final response = await ApiService.rawGet(endpoint);
      if (!_ok(response.statusCode) || response.bodyBytes.isEmpty) {
        _showSnack(_apiError(response.body, 'Download failed.'));
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(response.bodyBytes, flush: true);
      await OpenFilex.open(file.path);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportData() async {
    final params = <String, String>{};
    if (_searchController.text.trim().isNotEmpty) {
      params['search'] = _searchController.text.trim();
    }
    if (_departmentId.isNotEmpty) params['department_id'] = _departmentId;
    if (_status != 'all') params['status'] = _status;
    if (_dobFrom != null) params['dob'] = _apiDate.format(_dobFrom!);
    if (_dobTo != null) params['dobTo'] = _apiDate.format(_dobTo!);
    if (_joiningFrom != null) {
      params['joining_date'] = _apiDate.format(_joiningFrom!);
    }
    if (_joiningTo != null) {
      params['joiningDateTo'] = _apiDate.format(_joiningTo!);
    }
    final query = Uri(queryParameters: params).query;
    await _downloadFile(
      '/employees/export${query.isEmpty ? '' : '?$query'}',
      'employees_export.xlsx',
    );
  }

  Future<void> _importEmployees() async {
    const typeGroup = XTypeGroup(
      label: 'Excel',
      extensions: ['xlsx', 'xls'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;

    setState(() => _busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken') ?? prefs.getString('token');
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiService.baseUrl}/employees/import'),
      );
      if (token != null && token.trim().isNotEmpty) {
        request.headers['Authorization'] = 'Bearer ${token.trim()}';
      }
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      if (!_ok(response.statusCode)) {
        _showSnack(_apiError(response.body, 'Import failed.'));
        return;
      }
      final decoded = jsonDecode(response.body);
      final inserted = decoded is Map ? decoded['insertedCount'] ?? '-' : '-';
      final duplicates =
          decoded is Map ? decoded['duplicateCount'] ?? '-' : '-';
      _showSnack(
          'Import complete. Inserted: $inserted, Duplicates: $duplicates');
      await _loadAll();
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredEmployees;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employees'),
        actions: [
          IconButton(
            tooltip: 'Export Template',
            onPressed: _busy
                ? null
                : () => _downloadFile(
                      '/employees/export-template',
                      'employee_template.xlsx',
                    ),
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            tooltip: 'Export Employees',
            onPressed: _busy ? null : _exportData,
            icon: const Icon(Icons.download_rounded),
          ),
          IconButton(
            tooltip: 'Import Employees',
            onPressed: _busy ? null : _importEmployees,
            icon: const Icon(Icons.upload_file_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _openEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Employee'),
      ),
      body: Stack(
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _state(
                      Icons.warning_rounded,
                      'Could not load employees',
                      _error!,
                      actionLabel: 'Retry',
                      onAction: _loadAll,
                    )
                  : RefreshIndicator(
                      onRefresh: _loadAll,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 92),
                        children: [
                          _hero(rows.length),
                          const SizedBox(height: 12),
                          _filters(),
                          const SizedBox(height: 12),
                          if (rows.isEmpty)
                            _state(
                              Icons.badge_rounded,
                              'No employees found',
                              'Try changing filters or add a new employee.',
                            )
                          else
                            ...rows.map(_employeeCard),
                        ],
                      ),
                    ),
          if (_busy)
            Container(
              color: Colors.black.withOpacity(0.08),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _hero(int shown) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16A34A), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.badge_rounded, color: Colors.white, size: 36),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Employee Management',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _heroStat('Shown', '$shown'),
              _heroStat('Active', '$_enabledCount'),
              _heroStat('Disabled', '$_disabledCount'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filters() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search by name, phone, email or employee ID',
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _departmentId,
            decoration: const InputDecoration(
              labelText: 'Department',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('All Departments')),
              ..._departments.map(
                (department) => DropdownMenuItem(
                  value: _safe(department['id']),
                  child: Text(_safe(department['name'], 'Department')),
                ),
              ),
            ],
            onChanged: (value) => setState(() => _departmentId = value ?? ''),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _designation,
            decoration: const InputDecoration(
              labelText: 'Designation',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(
                  value: '', child: Text('All Designations')),
              ..._designations.map(
                (designation) => DropdownMenuItem(
                  value: designation,
                  child: Text(designation),
                ),
              ),
            ],
            onChanged: (value) => setState(() => _designation = value ?? ''),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _status,
            decoration: const InputDecoration(
              labelText: 'Status',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All Statuses')),
              DropdownMenuItem(value: 'enabled', child: Text('Active')),
              DropdownMenuItem(value: 'disabled', child: Text('Disabled')),
            ],
            onChanged: (value) => setState(() => _status = value ?? 'all'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _dateFilter('DOB From', _dobFrom,
                    (value) => setState(() => _dobFrom = value)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dateFilter('DOB To', _dobTo,
                    (value) => setState(() => _dobTo = value)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _dateFilter('Joining From', _joiningFrom,
                    (value) => setState(() => _joiningFrom = value)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dateFilter('Joining To', _joiningTo,
                    (value) => setState(() => _joiningTo = value)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dateFilter(
    String label,
    DateTime? value,
    ValueChanged<DateTime?> onChanged,
  ) {
    return OutlinedButton.icon(
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(1950),
          lastDate: DateTime(2035),
        );
        onChanged(picked);
      },
      icon: const Icon(Icons.calendar_month_rounded, size: 18),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          value == null ? label : _apiDate.format(value),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _employeeCard(Map<String, dynamic> employee) {
    final disabled = _safe(employee['status'], 'enabled') == 'disabled';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      color: disabled ? const Color(0xFFFFF1F2) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: disabled
                      ? const Color(0xFFFCA5A5)
                      : const Color(0xFFBBF7D0),
                  child: Text(
                    _initials(_safe(employee['name'], 'E')),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _safe(employee['name'], '-'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_safe(employee['employee_id'], 'Emp ID -')} • ${_departmentName(employee)}',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                _statusChip(disabled),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _infoChip(Icons.phone_rounded, _safe(employee['phone'], '-')),
                _infoChip(Icons.mail_rounded, _safe(employee['email'], '-')),
                _infoChip(
                    Icons.work_rounded, _safe(employee['designation'], '-')),
                _infoChip(
                  Icons.event_rounded,
                  _safe(employee['joining_date'], '-'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _busy ? null : () => _openEditor(employee: employee),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _toggleStatus(employee),
                    icon: Icon(
                      disabled
                          ? Icons.check_circle_rounded
                          : Icons.block_rounded,
                      size: 18,
                    ),
                    label: Text(disabled ? 'Enable' : 'Disable'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(bool disabled) {
    final color = disabled ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        disabled ? 'DISABLED' : 'ACTIVE',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF475569)),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _state(
    IconData icon,
    String title,
    String body, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: Colors.grey.shade500),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ],
        ),
      ),
    );
  }

  String _departmentName(Map<String, dynamic> employee) {
    final nested = employee['Department'];
    if (nested is Map) return _safe(nested['name'], '-');
    final id = _safe(employee['department_id']);
    final match =
        _departments.where((department) => _safe(department['id']) == id);
    return match.isEmpty ? '-' : _safe(match.first['name'], '-');
  }

  bool _inDateRange(dynamic value, DateTime? from, DateTime? to) {
    final text = _safe(value);
    if (text.isEmpty) return true;
    final date = DateTime.tryParse(text);
    if (date == null) return true;
    if (from != null && date.isBefore(from)) return false;
    if (to != null && date.isAfter(to)) return false;
    return true;
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final first = parts.isNotEmpty ? parts.first[0] : 'E';
    final second = parts.length > 1 ? parts.elementAt(1)[0] : '';
    return '$first$second'.toUpperCase();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _EmployeeEditorSheet extends StatefulWidget {
  const _EmployeeEditorSheet({
    required this.employee,
    required this.departments,
    required this.onSave,
  });

  final Map<String, dynamic>? employee;
  final List<Map<String, dynamic>> departments;
  final Future<bool> Function(
    Map<String, dynamic>? employee,
    Map<String, dynamic> payload,
  ) onSave;

  @override
  State<_EmployeeEditorSheet> createState() => _EmployeeEditorSheetState();
}

class _EmployeeEditorSheetState extends State<_EmployeeEditorSheet> {
  late final Map<String, TextEditingController> _controllers;
  String _gender = '';
  String _maritalStatus = '';
  String _bloodGroup = '';
  String _departmentId = '';
  String _status = 'enabled';

  static const List<String> _fields = [
    'name',
    'dob',
    'phone',
    'email',
    'aadhaar_number',
    'pan_number',
    'educational_qualification',
    'professional_qualification',
    'experience_years',
    'emergency_contact',
    'bank_account_number',
    'ifsc_code',
    'bank_name',
    'account_holder_name',
    'designation',
    'joining_date',
    'address',
  ];

  @override
  void initState() {
    super.initState();
    final employee = widget.employee ?? const <String, dynamic>{};
    _controllers = {
      for (final field in _fields)
        field: TextEditingController(
          text: field == 'dob' || field == 'joining_date'
              ? _dateInput(employee[field])
              : _safe(employee[field]),
        ),
    };
    _gender = _safe(employee['gender']);
    _maritalStatus = _safe(employee['marital_status']);
    _bloodGroup = _safe(employee['blood_group']);
    _departmentId = _safe(employee['department_id']);
    _status = _safe(employee['status'], 'enabled');
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.employee == null ? 'Add Employee' : 'Edit Employee',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            _field('Name *', 'name'),
            _dropdown(
              'Gender',
              _gender,
              _genderOptions,
              (value) => setState(() => _gender = value ?? ''),
            ),
            _field('Date of Birth', 'dob',
                keyboardType: TextInputType.datetime),
            _field('Phone *', 'phone', keyboardType: TextInputType.phone),
            _field('Email *', 'email',
                keyboardType: TextInputType.emailAddress),
            _field('Aadhaar Number', 'aadhaar_number'),
            _field('PAN Number', 'pan_number'),
            _field('Educational Qualification', 'educational_qualification'),
            _field('Professional Qualification', 'professional_qualification'),
            _field(
              'Experience Years',
              'experience_years',
              keyboardType: TextInputType.number,
            ),
            _dropdown(
              'Blood Group',
              _bloodGroup,
              _bloodOptions,
              (value) => setState(() => _bloodGroup = value ?? ''),
            ),
            _field('Emergency Contact', 'emergency_contact'),
            _dropdown(
              'Marital Status',
              _maritalStatus,
              _maritalOptions,
              (value) => setState(() => _maritalStatus = value ?? ''),
            ),
            _field('Bank Account Number', 'bank_account_number'),
            _field('IFSC Code', 'ifsc_code'),
            _field('Bank Name', 'bank_name'),
            _field('Account Holder Name', 'account_holder_name'),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DropdownButtonFormField<String>(
                value: _departmentId,
                decoration: const InputDecoration(
                  labelText: 'Department',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Select Department'),
                  ),
                  ...widget.departments.map(
                    (department) => DropdownMenuItem(
                      value: _safe(department['id']),
                      child: Text(_safe(department['name'])),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _departmentId = value ?? ''),
              ),
            ),
            _field('Designation', 'designation'),
            _field(
              'Joining Date',
              'joining_date',
              keyboardType: TextInputType.datetime,
            ),
            _field('Address', 'address', minLines: 3),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_rounded),
                label: Text(widget.employee == null ? 'Add' : 'Update'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    String key, {
    TextInputType? keyboardType,
    int minLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _controllers[key],
        keyboardType: keyboardType,
        minLines: minLines,
        maxLines: minLines > 1 ? 5 : 1,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _dropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: options.contains(value) ? value : '',
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('Select')),
          ...options.map((option) => DropdownMenuItem(
                value: option,
                child: Text(option),
              )),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Future<void> _save() async {
    final payload = {
      for (final entry in _controllers.entries)
        entry.key: entry.value.text.trim(),
      'gender': _gender,
      'marital_status': _maritalStatus,
      'blood_group': _bloodGroup,
      'department_id': _departmentId,
      'status': _status,
    };
    final ok = await widget.onSave(widget.employee, payload);
    if (ok && mounted) Navigator.pop(context, true);
  }
}

List<Map<String, dynamic>> _extractRows(
  dynamic decoded, {
  List<String> keys = const [],
}) {
  if (decoded is List) {
    return decoded
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
  if (decoded is Map) {
    for (final key in [...keys, 'data', 'rows', 'items', 'results']) {
      final value = decoded[key];
      if (value is List) return _extractRows(value);
    }
  }
  return <Map<String, dynamic>>[];
}

String _dateInput(dynamic value) {
  final text = _safe(value);
  if (text.isEmpty) return '';
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return '';
  return DateFormat('yyyy-MM-dd').format(parsed);
}

bool _ok(int statusCode) => statusCode >= 200 && statusCode < 300;

String _safe(dynamic value, [String fallback = '']) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

String _apiError(String body, String fallback) {
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
