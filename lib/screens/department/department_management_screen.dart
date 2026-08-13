import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/role_manager.dart';
import '../../services/department_management_api.dart';
import '../../widgets/teacher_drawer_menu.dart';

class DepartmentManagementScreen extends StatefulWidget {
  const DepartmentManagementScreen({super.key});

  @override
  State<DepartmentManagementScreen> createState() =>
      _DepartmentManagementScreenState();
}

class _DepartmentManagementScreenState extends State<DepartmentManagementScreen> {
  bool _loading = true;
  bool _departmentLoading = false;
  String? _error;
  String _activeRole = AppRoles.teacher;
  Map<String, dynamic> _bootstrap = <String, dynamic>{};
  Map<String, dynamic> _my = <String, dynamic>{};
  Map<String, dynamic> _department = <String, dynamic>{};
  Map<String, dynamic> _academics = <String, dynamic>{};
  int? _selectedDepartmentId;

  List<dynamic> _list(dynamic value) => value is List ? value : const [];
  Map<String, dynamic> _map(dynamic value) =>
      value is Map<String, dynamic> ? value : <String, dynamic>{};
  String _text(dynamic value, [String fallback = '—']) {
    final valueText = value?.toString().trim() ?? '';
    return valueText.isEmpty ? fallback : valueText;
  }

  int? _id(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  double _number(dynamic value) =>
      double.tryParse(value?.toString() ?? '') ?? 0;

  String _quantity(dynamic value) {
    final number = _number(value);
    return number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toStringAsFixed(2);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final results = await Future.wait([
        DepartmentManagementApi.bootstrap(),
        DepartmentManagementApi.myDashboard(),
      ]);
      final bootstrap = results[0];
      final my = results[1];
      final assignments = _list(bootstrap['my_assignments']);
      final departments = _list(bootstrap['departments']);
      int? selected;
      if (assignments.isNotEmpty) {
        selected = _id(_map(assignments.first)['department_id']);
      } else if (departments.isNotEmpty) {
        selected = _id(_map(departments.first)['id']);
      }
      if (!mounted) return;
      setState(() {
        _activeRole = AppRoles.normalize(prefs.getString('activeRole'));
        _bootstrap = bootstrap;
        _my = my;
        _selectedDepartmentId = selected;
        _loading = false;
      });
      if (selected != null) await _loadDepartment(selected);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadDepartment(int departmentId) async {
    if (mounted) {
      setState(() {
        _departmentLoading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        DepartmentManagementApi.departmentDashboard(departmentId),
        DepartmentManagementApi.academics(departmentId),
      ]);
      if (!mounted) return;
      setState(() {
        _selectedDepartmentId = departmentId;
        _department = results[0];
        _academics = results[1];
        _departmentLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _departmentLoading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Updated successfully')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Widget _metric(String label, dynamic value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.indigo),
            const SizedBox(height: 6),
            Text(
              _text(value, '0'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  Widget _empty(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(message, style: const TextStyle(color: Colors.black54)),
    );
  }

  Widget _statusChip(dynamic status) {
    final text = _text(status, 'PENDING').replaceAll('_', ' ');
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(text, style: const TextStyle(fontSize: 10)),
    );
  }

  Widget _taskCard(dynamic raw) {
    final task = _map(raw);
    final id = _id(task['id']);
    final status = _text(task['status'], 'PENDING');
    final department = _map(task['department']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _text(task['title']),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                _statusChip(status),
              ],
            ),
            if (_text(task['description'], '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_text(task['description'], '')),
              ),
            const SizedBox(height: 6),
            Text(
              '${_text(department['name'], 'Department')} • Due ${_text(task['due_date'])}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            if (id != null && status != 'COMPLETED')
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (status == 'PENDING')
                      TextButton(
                        onPressed: () => _runAction(() async {
                          await DepartmentManagementApi.updateTask(
                            id,
                            const {'status': 'IN_PROGRESS'},
                          );
                        }),
                        child: const Text('Start'),
                      ),
                    FilledButton.tonal(
                      onPressed: () => _runAction(() async {
                        await DepartmentManagementApi.updateTask(
                          id,
                          const {'status': 'COMPLETED'},
                        );
                      }),
                      child: const Text('Complete'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _dutyCard(dynamic raw) {
    final duty = _map(raw);
    final event = _map(duty['event']);
    final department = _map(event['department']);
    final id = _id(duty['id']);
    final status = _text(duty['status'], 'ASSIGNED');
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.assignment_ind_rounded)),
        title: Text(_text(duty['duty_name'])),
        subtitle: Text(
          '${_text(event['title'])}\n${_text(department['name'], 'Department')} • ${_text(event['start_date'])} • ${_text(event['venue'])}',
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: id == null
              ? null
              : (value) => _runAction(() async {
                    await DepartmentManagementApi.updateDuty(id, {'status': value});
                  }),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'ACKNOWLEDGED', child: Text('Acknowledge')),
            PopupMenuItem(value: 'COMPLETED', child: Text('Complete')),
          ],
          child: _statusChip(status),
        ),
      ),
    );
  }

  Widget _itemCard(dynamic raw) {
    final transaction = _map(raw);
    final item = _map(transaction['item']);
    final department = _map(item['department']);
    final id = _id(transaction['id']);
    final status = _text(transaction['return_status'], 'ISSUED');
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
        title: Text(_text(item['name'])),
        subtitle: Text(
          '${_text(department['name'], 'Owner department')} • Qty ${_text(transaction['quantity'], '1')}\nReturn due: ${_text(transaction['issue_due_date'])}',
        ),
        isThreeLine: true,
        trailing: status == 'ISSUED' && id != null
            ? TextButton(
                onPressed: () => _runAction(() async {
                  await DepartmentManagementApi.requestReturn(id);
                }),
                child: const Text('Return'),
              )
            : _statusChip(status),
      ),
    );
  }

  Widget _myWork() {
    final summary = _map(_my['summary']);
    final tasks = _list(_my['tasks']);
    final duties = _list(_my['duties']);
    final items = _list(_my['issued_items']);
    final events = _list(_my['events']);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(
            children: [
              _metric('Pending Tasks', summary['pending_tasks'], Icons.task_alt),
              const SizedBox(width: 8),
              _metric('Duties', summary['active_duties'], Icons.badge_outlined),
              const SizedBox(width: 8),
              _metric('Issued Items', summary['issued_items'], Icons.inventory_2),
            ],
          ),
          _sectionTitle('My Tasks'),
          if (tasks.isEmpty) _empty('No department tasks assigned.') else ...tasks.map(_taskCard),
          _sectionTitle('My Event Duties'),
          if (duties.isEmpty) _empty('No active event duties.') else ...duties.map(_dutyCard),
          _sectionTitle('Items Issued to Me'),
          if (items.isEmpty) _empty('No department inventory is issued to you.') else ...items.map(_itemCard),
          _sectionTitle('Upcoming Department Events'),
          if (events.isEmpty)
            _empty('No upcoming department events.')
          else
            ...events.map((raw) {
              final event = _map(raw);
              final department = _map(event['department']);
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.event_available_rounded),
                  title: Text(_text(event['title'])),
                  subtitle: Text(
                    '${_text(department['name'])} • ${_text(event['start_date'])}\n${_text(event['venue'])}',
                  ),
                  isThreeLine: true,
                  trailing: _statusChip(event['status']),
                ),
              );
            }),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  List<dynamic> get _availableDepartments {
    final assignments = _list(_bootstrap['my_assignments']);
    if (assignments.isNotEmpty) {
      return assignments.map((raw) {
        final assignment = _map(raw);
        final department = _map(assignment['department']);
        return department.isEmpty
            ? <String, dynamic>{
                'id': assignment['department_id'],
                'name': 'Department ${assignment['department_id']}',
              }
            : department;
      }).toList();
    }
    return _list(_bootstrap['departments']);
  }

  Future<void> _showTaskDialog() async {
    final departmentId = _selectedDepartmentId;
    if (departmentId == null) return;
    final assignments = _list(_department['assignments']);
    if (assignments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assign department members first.')),
      );
      return;
    }
    final title = TextEditingController();
    final description = TextEditingController();
    final dueDate = TextEditingController();
    int? assignee = _id(_map(assignments.first)['user_id']);
    String priority = 'NORMAL';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Assign Department Task'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Task title *')),
                TextField(controller: description, decoration: const InputDecoration(labelText: 'Description')),
                DropdownButtonFormField<int>(
                  value: assignee,
                  decoration: const InputDecoration(labelText: 'Assign to'),
                  items: assignments.map((raw) {
                    final assignment = _map(raw);
                    final user = _map(assignment['user']);
                    final id = _id(assignment['user_id']) ?? 0;
                    return DropdownMenuItem<int>(
                      value: id,
                      child: Text(_text(user['name'], 'User $id')),
                    );
                  }).toList(),
                  onChanged: (value) => setDialogState(() => assignee = value),
                ),
                DropdownButtonFormField<String>(
                  value: priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: const ['LOW', 'NORMAL', 'HIGH', 'URGENT']
                      .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                      .toList(),
                  onChanged: (value) => setDialogState(() => priority = value ?? 'NORMAL'),
                ),
                TextField(
                  controller: dueDate,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Due date'),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (picked != null) {
                      dueDate.text = picked.toIso8601String().split('T').first;
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Assign')),
          ],
        ),
      ),
    );
    if (saved != true || title.text.trim().isEmpty || assignee == null) return;
    await _runAction(() async {
      await DepartmentManagementApi.createTask(departmentId, {
        'title': title.text.trim(),
        'description': description.text.trim(),
        'assigned_to_user_id': assignee,
        'priority': priority,
        if (dueDate.text.isNotEmpty) 'due_date': dueDate.text,
      });
    });
  }

  Future<void> _showEventDialog() async {
    final departmentId = _selectedDepartmentId;
    if (departmentId == null) return;
    final title = TextEditingController();
    final venue = TextEditingController();
    final session = TextEditingController();
    final date = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Department Event'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Event title *')),
              TextField(controller: venue, decoration: const InputDecoration(labelText: 'Venue')),
              TextField(controller: session, decoration: const InputDecoration(labelText: 'Academic session (e.g. 2026-27)')),
              TextField(
                controller: date,
                readOnly: true,
                decoration: const InputDecoration(labelText: 'Event date *'),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 30)),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (picked != null) date.text = picked.toIso8601String().split('T').first;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit')),
        ],
      ),
    );
    if (saved != true || title.text.trim().isEmpty || date.text.isEmpty) return;
    await _runAction(() async {
      await DepartmentManagementApi.createEvent(departmentId, {
        'title': title.text.trim(),
        'event_type': 'EVENT',
        'venue': venue.text.trim(),
        'academic_session': session.text.trim(),
        'start_date': date.text,
        'end_date': date.text,
        'status': 'SUBMITTED',
      });
    });
  }

  Future<void> _showAchievementDialog() async {
    final departmentId = _selectedDepartmentId;
    if (departmentId == null) return;
    final students = _list(_bootstrap['students']);
    final title = TextEditingController();
    final position = TextEditingController();
    final session = TextEditingController();
    final date = TextEditingController();
    final description = TextEditingController();
    String level = 'SCHOOL';
    int? studentId;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Achievement / Result'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Achievement title *')),
                TextField(controller: position, decoration: const InputDecoration(labelText: 'Position / award')),
                TextField(controller: session, decoration: const InputDecoration(labelText: 'Academic session')),
                DropdownButtonFormField<String>(
                  value: level,
                  decoration: const InputDecoration(labelText: 'Level'),
                  items: const ['SCHOOL', 'CLUSTER', 'ZONAL', 'DISTRICT', 'STATE', 'NATIONAL', 'INTERNATIONAL', 'OTHER']
                      .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                      .toList(),
                  onChanged: (value) => setDialogState(() => level = value ?? 'SCHOOL'),
                ),
                if (students.isNotEmpty)
                  DropdownButtonFormField<int>(
                    value: studentId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Student (optional)'),
                    items: students.map((raw) {
                      final student = _map(raw);
                      final id = _id(student['id']) ?? 0;
                      final classData = _map(student['Class']);
                      return DropdownMenuItem<int>(
                        value: id,
                        child: Text(
                          '${_text(student['name'])} • ${_text(student['admission_number'], 'No admission no.')} • ${_text(classData['name'], 'Class')}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) => setDialogState(() => studentId = value),
                  ),
                TextField(
                  controller: date,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Achievement date *'),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 730)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) date.text = picked.toIso8601String().split('T').first;
                  },
                ),
                TextField(
                  controller: description,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Details'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit')),
          ],
        ),
      ),
    );
    if (saved != true || title.text.trim().isEmpty || date.text.isEmpty) return;
    await _runAction(() async {
      await DepartmentManagementApi.createAchievement(departmentId, {
        'title': title.text.trim(),
        'position': position.text.trim(),
        'academic_session': session.text.trim(),
        'achievement_date': date.text,
        'description': description.text.trim(),
        'level': level,
        if (studentId != null) 'student_id': studentId,
        'status': 'SUBMITTED',
      });
    });
  }

  Future<void> _showInventoryLocationDialog() async {
    final departmentId = _selectedDepartmentId;
    if (departmentId == null) return;
    final name = TextEditingController();
    final code = TextEditingController();
    final description = TextEditingController();
    String type = 'department';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Department Store / Location'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Location name *'),
                ),
                TextField(
                  controller: code,
                  decoration: const InputDecoration(labelText: 'Code (optional)'),
                ),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Location type'),
                  items: const ['department', 'store', 'lab', 'office', 'classroom', 'other']
                      .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                      .toList(),
                  onChanged: (value) => setDialogState(() => type = value ?? 'department'),
                ),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (saved != true || name.text.trim().isEmpty) return;
    await _runAction(() async {
      await DepartmentManagementApi.createInventoryLocation(departmentId, {
        'name': name.text.trim(),
        'code': code.text.trim(),
        'type': type,
        'description': description.text.trim(),
      });
    });
  }

  Future<void> _showInventoryItemDialog() async {
    final departmentId = _selectedDepartmentId;
    if (departmentId == null) return;
    final categories = _list(_department['inventory_categories']);
    final locations = _list(_department['inventory_locations']);
    final name = TextEditingController();
    final code = TextEditingController();
    final newCategory = TextEditingController();
    final unit = TextEditingController(text: 'pcs');
    final openingQuantity = TextEditingController();
    final minStock = TextEditingController(text: '0');
    final unitPrice = TextEditingController();
    final newLocation = TextEditingController();
    final vendor = TextEditingController();
    final billNo = TextEditingController();
    final description = TextEditingController();
    int? categoryId;
    int? locationId;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Department Inventory Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Item name *')),
                TextField(controller: code, decoration: const InputDecoration(labelText: 'Item code')),
                DropdownButtonFormField<int>(
                  value: categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Existing category'),
                  items: categories.map((raw) {
                    final category = _map(raw);
                    final id = _id(category['id']) ?? 0;
                    return DropdownMenuItem<int>(value: id, child: Text(_text(category['name'])));
                  }).toList(),
                  onChanged: (value) => setDialogState(() => categoryId = value),
                ),
                TextField(
                  controller: newCategory,
                  enabled: categoryId == null,
                  decoration: const InputDecoration(labelText: 'New category (optional)'),
                ),
                Row(
                  children: [
                    Expanded(child: TextField(controller: unit, decoration: const InputDecoration(labelText: 'Unit'))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: openingQuantity,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Opening quantity'),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minStock,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Minimum stock'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: unitPrice,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Unit price'),
                      ),
                    ),
                  ],
                ),
                DropdownButtonFormField<int>(
                  value: locationId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Store / lab location'),
                  items: locations.map((raw) {
                    final location = _map(raw);
                    final id = _id(location['id']) ?? 0;
                    return DropdownMenuItem<int>(value: id, child: Text(_text(location['name'])));
                  }).toList(),
                  onChanged: (value) => setDialogState(() => locationId = value),
                ),
                TextField(
                  controller: newLocation,
                  enabled: locationId == null,
                  decoration: const InputDecoration(labelText: 'New location (optional)'),
                ),
                TextField(controller: vendor, decoration: const InputDecoration(labelText: 'Vendor')),
                TextField(controller: billNo, decoration: const InputDecoration(labelText: 'Bill number')),
                TextField(
                  controller: description,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Description / condition / remarks'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add Item')),
          ],
        ),
      ),
    );
    if (saved != true || name.text.trim().isEmpty) return;
    await _runAction(() async {
      await DepartmentManagementApi.createInventoryItem(departmentId, {
        'name': name.text.trim(),
        'code': code.text.trim(),
        if (categoryId != null) 'category_id': categoryId,
        if (categoryId == null) 'new_category_name': newCategory.text.trim(),
        'unit': unit.text.trim().isEmpty ? 'pcs' : unit.text.trim(),
        'opening_quantity': double.tryParse(openingQuantity.text) ?? 0,
        'min_stock': double.tryParse(minStock.text) ?? 0,
        'unit_price': double.tryParse(unitPrice.text) ?? 0,
        if (locationId != null) 'location_id': locationId,
        if (locationId == null) 'new_location_name': newLocation.text.trim(),
        'vendor_name': vendor.text.trim(),
        'bill_no': billNo.text.trim(),
        'description': description.text.trim(),
      });
    });
  }

  Future<void> _showReceiveStockDialog(Map<String, dynamic> item) async {
    final departmentId = _selectedDepartmentId;
    final itemId = _id(item['id']);
    if (departmentId == null || itemId == null) return;
    final locations = _list(_department['inventory_locations']);
    final balances = _list(item['location_balances']);
    int? locationId = balances.isNotEmpty
        ? _id(_map(balances.first)['location_id'])
        : (locations.isNotEmpty ? _id(_map(locations.first)['id']) : null);
    final quantity = TextEditingController();
    final unitPrice = TextEditingController();
    final newLocation = TextEditingController();
    final vendor = TextEditingController();
    final billNo = TextEditingController();
    final remarks = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Receive ${_text(item['name'])}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: quantity,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Quantity (${_text(item['unit'], 'pcs')}) *'),
                ),
                TextField(
                  controller: unitPrice,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Unit price'),
                ),
                DropdownButtonFormField<int>(
                  value: locationId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Destination location'),
                  items: locations.map((raw) {
                    final location = _map(raw);
                    final id = _id(location['id']) ?? 0;
                    return DropdownMenuItem<int>(value: id, child: Text(_text(location['name'])));
                  }).toList(),
                  onChanged: (value) => setDialogState(() => locationId = value),
                ),
                if (locationId == null)
                  TextField(
                    controller: newLocation,
                    decoration: const InputDecoration(labelText: 'New location (optional)'),
                  ),
                TextField(controller: vendor, decoration: const InputDecoration(labelText: 'Vendor')),
                TextField(controller: billNo, decoration: const InputDecoration(labelText: 'Bill number')),
                TextField(controller: remarks, decoration: const InputDecoration(labelText: 'Remarks')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Receive')),
          ],
        ),
      ),
    );
    if (saved != true || (double.tryParse(quantity.text) ?? 0) <= 0) return;
    await _runAction(() async {
      await DepartmentManagementApi.receiveInventoryStock(departmentId, itemId, {
        'quantity': double.parse(quantity.text),
        'unit_price': double.tryParse(unitPrice.text) ?? 0,
        if (locationId != null) 'location_id': locationId,
        if (locationId == null) 'new_location_name': newLocation.text.trim(),
        'vendor_name': vendor.text.trim(),
        'bill_no': billNo.text.trim(),
        'remarks': remarks.text.trim(),
      });
    });
  }

  Future<void> _showIssueStockDialog(Map<String, dynamic> item) async {
    final departmentId = _selectedDepartmentId;
    final itemId = _id(item['id']);
    if (departmentId == null || itemId == null) return;
    final balances = _list(item['location_balances'])
        .where((raw) => _number(_map(raw)['quantity']) > 0)
        .toList();
    if (balances.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No stock is available for issue.')),
      );
      return;
    }
    final users = _list(_bootstrap['users']);
    final departments = _list(_bootstrap['receiver_departments']).isNotEmpty
        ? _list(_bootstrap['receiver_departments'])
        : _list(_bootstrap['departments']);
    int? locationId = _id(_map(balances.first)['location_id']);
    int? userId;
    int? receiverDepartmentId;
    final quantity = TextEditingController();
    final dueDate = TextEditingController();
    final purpose = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Issue ${_text(item['name'])}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: locationId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Source location *'),
                  items: balances.map((raw) {
                    final balance = _map(raw);
                    final location = _map(balance['location']);
                    final id = _id(balance['location_id']) ?? 0;
                    return DropdownMenuItem<int>(
                      value: id,
                      child: Text('${_text(location['name'], 'Location $id')} • ${_quantity(balance['quantity'])} available'),
                    );
                  }).toList(),
                  onChanged: (value) => setDialogState(() => locationId = value),
                ),
                TextField(
                  controller: quantity,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Quantity (${_text(item['unit'], 'pcs')}) *'),
                ),
                DropdownButtonFormField<int>(
                  value: userId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Issue to staff / user'),
                  items: users.map((raw) {
                    final user = _map(raw);
                    final id = _id(user['id']) ?? 0;
                    return DropdownMenuItem<int>(value: id, child: Text(_text(user['name'], 'User $id')));
                  }).toList(),
                  onChanged: (value) => setDialogState(() => userId = value),
                ),
                DropdownButtonFormField<int>(
                  value: receiverDepartmentId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Receiver department'),
                  items: departments.map((raw) {
                    final department = _map(raw);
                    final id = _id(department['id']) ?? 0;
                    return DropdownMenuItem<int>(value: id, child: Text(_text(department['name'])));
                  }).toList(),
                  onChanged: (value) => setDialogState(() => receiverDepartmentId = value),
                ),
                TextField(
                  controller: dueDate,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Return due date'),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (picked != null) dueDate.text = picked.toIso8601String().split('T').first;
                  },
                ),
                TextField(controller: purpose, decoration: const InputDecoration(labelText: 'Purpose / event')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Issue')),
          ],
        ),
      ),
    );
    if (saved != true || (double.tryParse(quantity.text) ?? 0) <= 0) return;
    if (userId == null && receiverDepartmentId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select receiving staff or department.')),
      );
      return;
    }
    await _runAction(() async {
      await DepartmentManagementApi.issueInventoryStock(departmentId, itemId, {
        'from_location_id': locationId,
        'quantity': double.parse(quantity.text),
        if (userId != null) 'issued_to_user_id': userId,
        if (receiverDepartmentId != null) 'issued_to_department_id': receiverDepartmentId,
        if (dueDate.text.isNotEmpty) 'issue_due_date': dueDate.text,
        'purpose': purpose.text.trim(),
      });
    });
  }

  Widget _inventoryItemCard(dynamic raw, bool canManage) {
    final item = _map(raw);
    final category = _map(item['category']);
    final balances = _list(item['location_balances']);
    final stock = _number(item['total_stock']);
    final locationText = balances.isEmpty
        ? 'No stock location'
        : balances.map((rawBalance) {
            final balance = _map(rawBalance);
            final location = _map(balance['location']);
            return '${_text(location['name'], 'Location')}: ${_quantity(balance['quantity'])}';
          }).join(' • ');
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: item['low_stock'] == true ? Colors.red.shade50 : Colors.green.shade50,
          child: Icon(
            Icons.inventory_2_outlined,
            color: item['low_stock'] == true ? Colors.red.shade700 : Colors.green.shade700,
          ),
        ),
        title: Text(_text(item['name']), style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          '${_text(category['name'], 'General')} • ${_text(item['code'], 'No code')}\n'
          'Stock ${_quantity(stock)} ${_text(item['unit'], 'pcs')} • $locationText',
        ),
        isThreeLine: true,
        trailing: canManage
            ? PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'receive') _showReceiveStockDialog(item);
                  if (value == 'issue') _showIssueStockDialog(item);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'receive', child: Text('Receive stock')),
                  PopupMenuItem(value: 'issue', enabled: stock > 0, child: const Text('Issue item')),
                ],
              )
            : Text('${_quantity(stock)} ${_text(item['unit'], 'pcs')}'),
      ),
    );
  }

  Widget _departmentOverview() {
    final canManage = _department['can_manage'] == true;
    final department = _map(_department['department']);
    final summary = _map(_department['summary']);
    final assignments = _list(_department['assignments']);
    final tasks = _list(_department['tasks']);
    final events = _list(_department['events']);
    final achievements = _list(_department['achievements']);
    final inventoryItems = _list(_department['inventory_items']);
    final inventoryIssues = _list(_department['inventory_issues']);
    final academicSummary = _map(_academics['summary']);

    return RefreshIndicator(
      onRefresh: () async {
        if (_selectedDepartmentId != null) await _loadDepartment(_selectedDepartmentId!);
      },
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (_availableDepartments.length > 1)
            DropdownButtonFormField<int>(
              value: _selectedDepartmentId,
              decoration: const InputDecoration(
                labelText: 'Department',
                border: OutlineInputBorder(),
              ),
              items: _availableDepartments.map((raw) {
                final item = _map(raw);
                return DropdownMenuItem<int>(
                  value: _id(item['id']),
                  child: Text(_text(item['name'])),
                );
              }).where((item) => item.value != null).toList(),
              onChanged: (value) {
                if (value != null) _loadDepartment(value);
              },
            ),
          const SizedBox(height: 12),
          Text(
            _text(department['name'], 'Department Dashboard'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          if (_text(department['description'], '').isNotEmpty)
            Text(_text(department['description'], ''), style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 12),
          Row(
            children: [
              _metric('Members', summary['members'], Icons.groups_rounded),
              const SizedBox(width: 8),
              _metric('Tasks', summary['pending_tasks'], Icons.task_alt),
              const SizedBox(width: 8),
              _metric('Events', summary['upcoming_events'], Icons.event),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _metric('Inventory', summary['inventory_items'], Icons.inventory_2),
              const SizedBox(width: 8),
              _metric('Achievements', summary['achievements'], Icons.emoji_events),
              const SizedBox(width: 8),
              _metric('Lesson Plans', academicSummary['lesson_plans'], Icons.menu_book),
            ],
          ),
          _sectionTitle(
            'Department Team',
            action: canManage
                ? FilledButton.tonalIcon(
                    onPressed: _showTaskDialog,
                    icon: const Icon(Icons.add_task),
                    label: const Text('Task'),
                  )
                : null,
          ),
          if (assignments.isEmpty)
            _empty('No HOD or department members assigned.')
          else
            ...assignments.map((raw) {
              final assignment = _map(raw);
              final user = _map(assignment['user']);
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(_text(user['name'], 'User ${assignment['user_id']}')),
                  subtitle: Text(_text(assignment['designation'], 'MEMBER').replaceAll('_', ' ')),
                  trailing: assignment['is_primary'] == true && assignment['designation'] == 'HOD'
                      ? const Chip(label: Text('Primary HOD', style: TextStyle(fontSize: 10)))
                      : null,
                ),
              );
            }),
          _sectionTitle('Department Tasks'),
          if (tasks.isEmpty) _empty('No department tasks.') else ...tasks.take(10).map(_taskCard),
          _sectionTitle(
            'Department Inventory',
            action: canManage
                ? PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'item') _showInventoryItemDialog();
                      if (value == 'location') _showInventoryLocationDialog();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'item', child: Text('Add inventory item')),
                      PopupMenuItem(value: 'location', child: Text('Add store / location')),
                    ],
                    child: const Chip(
                      avatar: Icon(Icons.add, size: 18),
                      label: Text('Add'),
                    ),
                  )
                : null,
          ),
          if (inventoryItems.isEmpty)
            _empty('No inventory item added for this department.')
          else
            ...inventoryItems.take(50).map((raw) => _inventoryItemCard(raw, canManage)),
          _sectionTitle('Items Issued from Department'),
          if (inventoryIssues.isEmpty)
            _empty('No department item is currently issued.')
          else
            ...inventoryIssues.take(20).map((raw) {
              final issue = _map(raw);
              final item = _map(issue['item']);
              final user = _map(issue['issuedToUser']);
              final receiverDepartment = _map(issue['issuedToDepartment']);
              final id = _id(issue['id']);
              final status = _text(issue['return_status'], 'ISSUED');
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
                  title: Text(_text(item['name'])),
                  subtitle: Text(
                    '${_text(user['name'], 'Receiver')} • ${_text(receiverDepartment['name'], 'No receiver department')}\n'
                    'Qty ${_text(issue['quantity'], '1')} • Due ${_text(issue['issue_due_date'])}',
                  ),
                  isThreeLine: true,
                  trailing: status == 'RETURN_REQUESTED' && canManage && id != null
                      ? FilledButton.tonal(
                          onPressed: () => _runAction(() async {
                            await DepartmentManagementApi.confirmReturn(id);
                          }),
                          child: const Text('Confirm'),
                        )
                      : _statusChip(status),
                ),
              );
            }),
          _sectionTitle(
            'Events & Competitions',
            action: canManage
                ? FilledButton.tonalIcon(
                    onPressed: _showEventDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Event'),
                  )
                : null,
          ),
          if (events.isEmpty)
            _empty('No department events.')
          else
            ...events.take(12).map((raw) {
              final event = _map(raw);
              final duties = _list(event['duties']);
              final participants = _list(event['participants']);
              return Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.event_note_rounded),
                  title: Text(_text(event['title'])),
                  subtitle: Text('${_text(event['start_date'])} • ${_text(event['venue'])}'),
                  trailing: _statusChip(event['status']),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Teacher duties: ${duties.length} • Students: ${participants.length}'),
                    ),
                    if (_text(event['coordinator_remarks'], '').isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Coordinator: ${_text(event['coordinator_remarks'], '')}'),
                      ),
                  ],
                ),
              );
            }),
          _sectionTitle(
            'Achievements',
            action: canManage
                ? FilledButton.tonalIcon(
                    onPressed: _showAchievementDialog,
                    icon: const Icon(Icons.emoji_events_rounded),
                    label: const Text('Add'),
                  )
                : null,
          ),
          if (achievements.isEmpty)
            _empty('No achievements recorded.')
          else
            ...achievements.take(12).map((raw) {
              final achievement = _map(raw);
              final student = _map(achievement['student']);
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.emoji_events_rounded)),
                  title: Text(_text(achievement['title'])),
                  subtitle: Text(
                    '${_text(achievement['level'])} • ${_text(achievement['position'])}\n${_text(student['name'], _text(achievement['team_name'], 'Department achievement'))}',
                  ),
                  isThreeLine: true,
                  trailing: _statusChip(achievement['status']),
                ),
              );
            }),
          _sectionTitle('Academic Monitoring'),
          _academicCards(),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _academicCards() {
    final teachers = _list(_academics['teachers']);
    final lessonPlans = _list(_academics['lesson_plans']);
    final breakups = _list(_academics['syllabus_breakups']);
    final diaries = _list(_academics['diaries']);
    if (teachers.isEmpty && lessonPlans.isEmpty && breakups.isEmpty && diaries.isEmpty) {
      return _empty('Map subjects to this department to see syllabus, lesson plans and diaries.');
    }
    return Column(
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.groups_2_outlined),
            title: Text('${teachers.length} department teachers'),
            subtitle: Text(
              '${breakups.length} syllabus breakups • ${lessonPlans.length} lesson plans • ${diaries.length} diary entries',
            ),
          ),
        ),
        ...teachers.take(20).map((raw) {
          final teacher = _map(raw);
          final assignments = _list(teacher['assignments']);
          final assignmentText = assignments.map((item) {
            final assignment = _map(item);
            final subject = _map(assignment['subject']);
            final classData = _map(assignment['class']);
            return '${_text(classData['name'], 'Class')} • ${_text(subject['name'], 'Subject')}';
          }).join(', ');
          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.school_outlined)),
              title: Text(_text(teacher['name'], 'Teacher')),
              subtitle: Text(
                '${assignmentText.isEmpty ? 'Department subject assignment' : assignmentText}\n'
                'Plans ${_text(teacher['lesson_plans'], '0')} • Completed ${_text(teacher['completed_lesson_plans'], '0')} • Breakups ${_text(teacher['syllabus_breakups'], '0')} • Diaries ${_text(teacher['diaries'], '0')}',
              ),
              isThreeLine: true,
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasDepartment = _selectedDepartmentId != null;
    return DefaultTabController(
      length: hasDepartment ? 2 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Department Management'),
          bottom: TabBar(
            tabs: [
              const Tab(icon: Icon(Icons.person_pin_outlined), text: 'My Work'),
              if (hasDepartment)
                const Tab(icon: Icon(Icons.apartment_rounded), text: 'Department'),
            ],
          ),
          actions: [
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ],
        ),
        drawer: TeacherDrawerMenu(activeRole: _activeRole),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _my.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: Colors.red),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _load, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      TabBarView(
                        children: [
                          _myWork(),
                          if (hasDepartment) _departmentOverview(),
                        ],
                      ),
                      if (_departmentLoading)
                        const LinearProgressIndicator(minHeight: 3),
                      if (_error != null && _my.isNotEmpty)
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: Material(
                            color: Colors.red.shade700,
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(_error!, style: const TextStyle(color: Colors.white)),
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}
