import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/api_service.dart';

const List<String> _subjectTypes = ['Scholastic', 'Co-Scholastic'];

class CoordinatorSubjectManagementScreen extends StatefulWidget {
  const CoordinatorSubjectManagementScreen({super.key});

  @override
  State<CoordinatorSubjectManagementScreen> createState() =>
      _CoordinatorSubjectManagementScreenState();
}

class _CoordinatorSubjectManagementScreenState
    extends State<CoordinatorSubjectManagementScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _subjects = [];
  String _search = '';
  String _typeFilter = 'All';
  String _sortBy = 'name';
  bool _sortAsc = true;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  List<Map<String, dynamic>> get _filteredSubjects {
    final query = _search.trim().toLowerCase();
    final rows = _subjects.where((subject) {
      final type = _subjectType(subject);
      if (_typeFilter != 'All' && type != _typeFilter) return false;
      if (query.isEmpty) return true;
      final haystack = [
        subject['name'],
        subject['description'],
        type,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();

    rows.sort((a, b) {
      final left = _sortBy == 'type' ? _subjectType(a) : _safe(a['name']);
      final right = _sortBy == 'type' ? _subjectType(b) : _safe(b['name']);
      final compared = left.toLowerCase().compareTo(right.toLowerCase());
      return _sortAsc ? compared : -compared;
    });
    return rows;
  }

  int get _scholasticCount =>
      _subjects.where((subject) => _subjectType(subject) == 'Scholastic').length;

  int get _coScholasticCount => _subjects
      .where((subject) => _subjectType(subject) == 'Co-Scholastic')
      .length;

  Future<void> _loadSubjects() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await ApiService.rawGet('/subjects');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_extractError(response.body, 'Failed to load subjects'));
      }
      final rows = _extractRows(jsonDecode(response.body));
      if (!mounted) return;
      setState(() => _subjects = rows.map(_normalizeSubject).toList());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor({Map<String, dynamic>? subject}) async {
    final nameController = TextEditingController(text: _safe(subject?['name']));
    final descriptionController = TextEditingController(
      text: _safe(subject?['description']),
    );
    String type = _subjectType(subject ?? const {});

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
                        subject == null ? 'Add Subject' : 'Edit Subject',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: nameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Subject Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: type,
                        decoration: const InputDecoration(
                          labelText: 'Type',
                          border: OutlineInputBorder(),
                        ),
                        items: _subjectTypes
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setSheetState(() => type = value);
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: descriptionController,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving
                              ? null
                              : () async {
                                  final ok = await _saveSubject(
                                    subject: subject,
                                    name: nameController.text,
                                    description: descriptionController.text,
                                    type: type,
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
                            subject == null ? 'Save Subject' : 'Save Changes',
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

    nameController.dispose();
    descriptionController.dispose();
    if (saved == true) await _loadSubjects();
  }

  Future<bool> _saveSubject({
    required Map<String, dynamic>? subject,
    required String name,
    required String description,
    required String type,
  }) async {
    final cleanName = name.trim();
    final cleanDescription = description.trim();
    if (cleanName.isEmpty) {
      _showMessage('Validation', 'Subject name is required.');
      return false;
    }
    if (!_subjectTypes.contains(type)) {
      _showMessage(
        'Validation',
        'Type must be Scholastic or Co-Scholastic.',
      );
      return false;
    }

    setState(() => _saving = true);
    try {
      final payload = {
        'name': cleanName,
        'description': cleanDescription,
        'type': type,
      };
      final response = subject == null
          ? await ApiService.rawPost('/subjects', payload)
          : await ApiService.rawPut('/subjects/${subject['id']}', payload);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _showMessage(
          'Save failed',
          _extractError(response.body, 'Failed to save subject.'),
        );
        return false;
      }
      _showMessage(
        subject == null ? 'Added' : 'Updated',
        subject == null
            ? 'Subject has been added.'
            : 'Subject has been updated.',
      );
      return true;
    } catch (e) {
      _showMessage('Save failed', e.toString().replaceFirst('Exception: ', ''));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteSubject(Map<String, dynamic> subject) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete subject?'),
        content: const Text('This will permanently delete the subject.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final response = await ApiService.rawDelete('/subjects/${subject['id']}');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _showMessage(
          'Delete failed',
          _extractError(response.body, 'Failed to delete subject.'),
        );
        return;
      }
      _showMessage('Deleted', 'Subject has been removed.');
      await _loadSubjects();
    } catch (e) {
      _showMessage(
        'Delete failed',
        e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggleSort(String key) {
    setState(() {
      if (_sortBy == key) {
        _sortAsc = !_sortAsc;
      } else {
        _sortBy = key;
        _sortAsc = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredSubjects;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subjects'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadSubjects,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _saving ? null : () => _openEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Subject'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _state(
                  Icons.warning_rounded,
                  'Could not load subjects',
                  _error!,
                  actionLabel: 'Retry',
                  onAction: _loadSubjects,
                )
              : RefreshIndicator(
                  onRefresh: _loadSubjects,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 92),
                    children: [
                      _hero(rows.length),
                      const SizedBox(height: 12),
                      _filters(),
                      const SizedBox(height: 12),
                      if (rows.isEmpty)
                        _state(
                          Icons.menu_book_rounded,
                          'No subjects found',
                          'Try changing filters or add a new subject.',
                        )
                      else
                        ...rows.map(_subjectCard),
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
          colors: [Color(0xFFB45309), Color(0xFF2563EB)],
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
              Icon(Icons.menu_book_rounded, color: Colors.white, size: 36),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Subjects',
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
              _heroStat('Shown', '$filteredCount'),
              _heroStat('Scholastic', '$_scholasticCount'),
              _heroStat('Co-Scholastic', '$_coScholasticCount'),
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
            decoration: const InputDecoration(
              labelText: 'Search subjects',
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _search = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _typeFilter,
            decoration: const InputDecoration(
              labelText: 'Type',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'All', child: Text('All')),
              DropdownMenuItem(
                value: 'Scholastic',
                child: Text('Scholastic'),
              ),
              DropdownMenuItem(
                value: 'Co-Scholastic',
                child: Text('Co-Scholastic'),
              ),
            ],
            onChanged: (value) => setState(() => _typeFilter = value ?? 'All'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _toggleSort('name'),
                  icon: Icon(
                    _sortBy == 'name' && !_sortAsc
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                  ),
                  label: const Text('Sort Name'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _toggleSort('type'),
                  icon: Icon(
                    _sortBy == 'type' && !_sortAsc
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                  ),
                  label: const Text('Sort Type'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _subjectCard(Map<String, dynamic> subject) {
    final type = _subjectType(subject);
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: (type == 'Co-Scholastic'
                          ? const Color(0xFF64748B)
                          : const Color(0xFF16A34A))
                      .withOpacity(0.12),
                  child: Icon(
                    type == 'Co-Scholastic'
                        ? Icons.palette_rounded
                        : Icons.menu_book_rounded,
                    color: type == 'Co-Scholastic'
                        ? const Color(0xFF64748B)
                        : const Color(0xFF16A34A),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _safe(subject['name'], 'Untitled Subject'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      _pill(type),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _safe(subject['description'], 'No description'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _saving ? null : () => _openEditor(subject: subject),
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _deleteSubject(subject),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: text == 'Co-Scholastic'
            ? const Color(0xFFF1F5F9)
            : const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: text == 'Co-Scholastic'
              ? const Color(0xFF475569)
              : const Color(0xFF047857),
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

  Map<String, dynamic> _normalizeSubject(Map<String, dynamic> row) {
    return {
      ...row,
      'type': _subjectType(row),
      'description': _safe(row['description']),
    };
  }

  String _subjectType(Map<String, dynamic> subject) {
    final type = _safe(subject['type'], 'Scholastic');
    return _subjectTypes.contains(type) ? type : 'Scholastic';
  }

  List<Map<String, dynamic>> _extractRows(dynamic decoded) {
    final raw = decoded is List
        ? decoded
        : decoded is Map
            ? (decoded['subjects'] ??
                decoded['data'] ??
                decoded['rows'] ??
                decoded['items'] ??
                [])
            : [];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
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
