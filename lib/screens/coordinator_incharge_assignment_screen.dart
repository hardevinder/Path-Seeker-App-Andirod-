import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/api_service.dart';

class CoordinatorInchargeAssignmentScreen extends StatefulWidget {
  const CoordinatorInchargeAssignmentScreen({super.key});

  @override
  State<CoordinatorInchargeAssignmentScreen> createState() =>
      _CoordinatorInchargeAssignmentScreenState();
}

class _CoordinatorInchargeAssignmentScreenState
    extends State<CoordinatorInchargeAssignmentScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _sections = [];
  List<Map<String, dynamic>> _teachers = [];

  String _classSearch = '';
  String _sectionSearch = '';
  String _teacherSearch = '';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  List<Map<String, dynamic>> get _filteredAssignments {
    final classQuery = _classSearch.trim().toLowerCase();
    final sectionQuery = _sectionSearch.trim().toLowerCase();
    final teacherQuery = _teacherSearch.trim().toLowerCase();

    return _assignments.where((assignment) {
      final className = _className(assignment).toLowerCase();
      final sectionName = _sectionName(assignment).toLowerCase();
      final teacherName = _teacherName(assignment).toLowerCase();
      return className.contains(classQuery) &&
          sectionName.contains(sectionQuery) &&
          teacherName.contains(teacherQuery);
    }).toList();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _loadList('/incharges/all'),
        _loadList('/classes', preferredKeys: const ['classes']),
        _loadList('/sections', preferredKeys: const ['sections']),
        _loadList('/teachers', preferredKeys: const ['teachers']),
      ]);

      if (!mounted) return;
      setState(() {
        _assignments = results[0];
        _classes = results[1];
        _sections = results[2];
        _teachers = results[3]
            .map(_normalizeTeacher)
            .whereType<Map<String, dynamic>>()
            .toList()
          ..sort(
            (a, b) => _safe(a['name']).toLowerCase().compareTo(
                  _safe(b['name']).toLowerCase(),
                ),
          );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadList(
    String endpoint, {
    List<String> preferredKeys = const [],
  }) async {
    final response = await ApiService.rawGet(endpoint);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractError(response.body, 'Failed to load $endpoint'));
    }
    return _extractRows(jsonDecode(response.body), preferredKeys);
  }

  Future<void> _openAssignmentSheet({Map<String, dynamic>? assignment}) async {
    if (_classes.isEmpty || _sections.isEmpty || _teachers.isEmpty) {
      _showMessage(
        'Missing setup',
        'Classes, sections and teachers are required first.',
      );
      return;
    }

    int? selectedClassId = assignment == null
        ? _idOf(_classes.first)
        : _assignmentClassId(assignment);
    int? selectedSectionId = assignment == null
        ? _idOf(_sections.first)
        : _assignmentSectionId(assignment);
    int? selectedTeacherId = assignment == null
        ? _idOf(_teachers.first)
        : _assignmentTeacherId(assignment);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
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
                        assignment == null
                            ? 'Assign Incharge'
                            : 'Edit Incharge Assignment',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _sheetDropdown(
                        label: 'Class',
                        value: selectedClassId,
                        items: _classes,
                        labelBuilder: _classOptionName,
                        onChanged: (value) =>
                            setSheetState(() => selectedClassId = value),
                      ),
                      const SizedBox(height: 10),
                      _sheetDropdown(
                        label: 'Section',
                        value: selectedSectionId,
                        items: _sections,
                        labelBuilder: _sectionOptionName,
                        onChanged: (value) =>
                            setSheetState(() => selectedSectionId = value),
                      ),
                      const SizedBox(height: 10),
                      _sheetDropdown(
                        label: 'Teacher',
                        value: selectedTeacherId,
                        items: _teachers,
                        labelBuilder: (teacher) =>
                            _safe(teacher['name'], 'Unnamed'),
                        onChanged: (value) =>
                            setSheetState(() => selectedTeacherId = value),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving
                              ? null
                              : () async {
                                  if (selectedClassId == null ||
                                      selectedSectionId == null ||
                                      selectedTeacherId == null) {
                                    _showMessage(
                                      'Missing fields',
                                      'All fields are required.',
                                    );
                                    return;
                                  }
                                  final ok = await _saveAssignment(
                                    assignment: assignment,
                                    classId: selectedClassId!,
                                    sectionId: selectedSectionId!,
                                    teacherId: selectedTeacherId!,
                                  );
                                  if (ok && context.mounted) {
                                    Navigator.pop(context, true);
                                  }
                                },
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save_rounded),
                          label: Text(
                            assignment == null ? 'Assign' : 'Save Changes',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (saved == true) await _loadAll();
  }

  Widget _sheetDropdown({
    required String label,
    required int? value,
    required List<Map<String, dynamic>> items,
    required String Function(Map<String, dynamic>) labelBuilder,
    required ValueChanged<int?> onChanged,
  }) {
    final values = items.map(_idOf).whereType<int>().toSet();
    return DropdownButtonFormField<int>(
      value: values.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: items
          .map(
            (item) => DropdownMenuItem<int>(
              value: _idOf(item),
              child: Text(
                labelBuilder(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .where((item) => item.value != null)
          .toList(),
      onChanged: onChanged,
    );
  }

  Future<bool> _saveAssignment({
    required Map<String, dynamic>? assignment,
    required int classId,
    required int sectionId,
    required int teacherId,
    bool confirm = false,
  }) async {
    if (!mounted) return false;
    setState(() => _saving = true);
    try {
      final body = {
        'classId': classId,
        'sectionId': sectionId,
        'teacherId': teacherId,
        if (confirm) 'confirm': true,
      };

      final response = assignment == null
          ? await ApiService.rawPost('/incharges/assign', body)
          : await ApiService.rawPut(
              '/incharges/update/${assignment['id']}',
              body,
            );

      if (response.statusCode == 409 && assignment == null && !confirm) {
        final proceed = await _confirmDuplicate(response.body);
        if (proceed) {
          return _saveAssignment(
            assignment: assignment,
            classId: classId,
            sectionId: sectionId,
            teacherId: teacherId,
            confirm: true,
          );
        }
        return false;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _showMessage(
          'Save failed',
          _extractError(response.body, 'Failed to save incharge assignment.'),
        );
        return false;
      }

      _showMessage(
        assignment == null ? 'Assigned' : 'Updated',
        assignment == null
            ? 'Incharge has been assigned successfully.'
            : 'Incharge assignment has been updated.',
      );
      return true;
    } catch (e) {
      _showMessage('Save failed', e.toString().replaceFirst('Exception: ', ''));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDuplicate(String body) async {
    final message = _extractError(
      body,
      'This teacher is already an incharge for that class and section.',
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Duplicate Incharge'),
        content: Text('$message\n\nAssign again?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Assign Again'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _deleteAssignment(Map<String, dynamic> assignment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove incharge?'),
        content: Text(
          'Remove ${_teacherName(assignment)} as incharge of '
          '${_className(assignment)} - ${_sectionName(assignment)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final response = await ApiService.rawDelete(
        '/incharges/remove/${assignment['id']}',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _showMessage(
          'Remove failed',
          _extractError(response.body, 'Failed to remove incharge.'),
        );
        return;
      }
      _showMessage('Removed', 'Incharge has been removed successfully.');
      await _loadAll();
    } catch (e) {
      _showMessage(
        'Remove failed',
        e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredAssignments;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Incharge Assignment'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _saving ? null : () => _openAssignmentSheet(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Assign'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _state(
                  Icons.warning_rounded,
                  'Could not load incharges',
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
                          Icons.supervisor_account_rounded,
                          'No incharge assignments found',
                          'Try changing filters or tap Assign to create one.',
                        )
                      else
                        ...rows.map(_assignmentCard),
                    ],
                  ),
                ),
    );
  }

  Widget _hero(int filteredCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF0F766E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.supervisor_account_rounded,
            color: Colors.white,
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Incharge Assignment',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$filteredCount shown of ${_assignments.length} assignments',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
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
          _searchField(
            label: 'Search Class',
            icon: Icons.school_rounded,
            onChanged: (value) => setState(() => _classSearch = value),
          ),
          const SizedBox(height: 10),
          _searchField(
            label: 'Search Section',
            icon: Icons.dashboard_customize_rounded,
            onChanged: (value) => setState(() => _sectionSearch = value),
          ),
          const SizedBox(height: 10),
          _searchField(
            label: 'Search Teacher',
            icon: Icons.person_search_rounded,
            onChanged: (value) => setState(() => _teacherSearch = value),
          ),
        ],
      ),
    );
  }

  Widget _searchField({
    required String label,
    required IconData icon,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      onChanged: onChanged,
    );
  }

  Widget _assignmentCard(Map<String, dynamic> assignment) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF2563EB).withOpacity(0.12),
                  child: const Icon(
                    Icons.supervisor_account_rounded,
                    color: Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _teacherName(assignment),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_className(assignment)} - ${_sectionName(assignment)}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _openAssignmentSheet(assignment: assignment),
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _saving ? null : () => _deleteAssignment(assignment),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Remove'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _state(
    IconData icon,
    String title,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: const Color(0xFF64748B)),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ],
      ),
    );
  }

  Map<String, dynamic>? _normalizeTeacher(Map<String, dynamic> row) {
    final user = _mapOf(row['user'] ?? row['User']);
    final employee = _mapOf(row['employee'] ?? row['Employee']);
    final id = _toInt(
      user['id'] ??
          row['user_id'] ??
          row['teacherId'] ??
          row['teacher_id'] ??
          employee['id'] ??
          row['employee_id'] ??
          row['emp_id'] ??
          row['id'],
    );
    if (id == null) return null;
    return {
      'id': id,
      'name': _safe(
        row['name'] ??
            user['name'] ??
            employee['name'] ??
            row['full_name'] ??
            row['teacherName'],
        'Unnamed',
      ),
    };
  }

  String _className(Map<String, dynamic> assignment) {
    final cls = _mapOf(assignment['Class'] ?? assignment['class']);
    return _safe(
      cls['class_name'] ??
          cls['name'] ??
          assignment['className'] ??
          assignment['class_name'],
      'Unknown',
    );
  }

  String _sectionName(Map<String, dynamic> assignment) {
    final section = _mapOf(assignment['Section'] ?? assignment['section']);
    return _safe(
      section['section_name'] ??
          section['name'] ??
          assignment['sectionName'] ??
          assignment['section_name'],
      'Unknown',
    );
  }

  String _teacherName(Map<String, dynamic> assignment) {
    final teacher = _mapOf(assignment['Teacher'] ?? assignment['teacher']);
    final user = _mapOf(assignment['User'] ?? assignment['user']);
    return _safe(
      teacher['name'] ??
          user['name'] ??
          assignment['teacherName'] ??
          assignment['name'],
      'Unknown',
    );
  }

  String _classOptionName(Map<String, dynamic> row) {
    return _safe(row['class_name'] ?? row['name'], 'Class ${row['id'] ?? ''}');
  }

  String _sectionOptionName(Map<String, dynamic> row) {
    return _safe(
      row['section_name'] ?? row['name'],
      'Section ${row['id'] ?? ''}',
    );
  }

  int? _assignmentClassId(Map<String, dynamic> assignment) {
    return _toInt(
      _mapOf(assignment['Class'] ?? assignment['class'])['id'] ??
          assignment['classId'] ??
          assignment['class_id'],
    );
  }

  int? _assignmentSectionId(Map<String, dynamic> assignment) {
    return _toInt(
      _mapOf(assignment['Section'] ?? assignment['section'])['id'] ??
          assignment['sectionId'] ??
          assignment['section_id'],
    );
  }

  int? _assignmentTeacherId(Map<String, dynamic> assignment) {
    return _toInt(
      _mapOf(assignment['Teacher'] ?? assignment['teacher'])['id'] ??
          assignment['teacher_id'] ??
          assignment['teacherId'] ??
          assignment['user_id'] ??
          assignment['userId'],
    );
  }

  int? _idOf(Map<String, dynamic> row) {
    return _toInt(row['id'] ?? row['userId'] ?? row['teacherId']);
  }

  List<Map<String, dynamic>> _extractRows(
    dynamic decoded,
    List<String> preferredKeys,
  ) {
    final keys = [
      ...preferredKeys,
      'data',
      'rows',
      'items',
      'list',
      'records',
      'assignments',
      'incharges',
      'classes',
      'sections',
      'teachers',
    ].toSet().toList();
    final raw = decoded is List
        ? decoded
        : decoded is Map
            ? keys.map((key) => decoded[key]).firstWhere(
                  (value) => value is List,
                  orElse: () => [],
                )
            : [];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  Map<String, dynamic> _mapOf(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  String _safe(dynamic value, [String fallback = '']) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  String _extractError(String body, String fallback) {
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

  void _showMessage(String title, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title: $message'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
