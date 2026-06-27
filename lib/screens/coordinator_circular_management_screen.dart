import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';

class CoordinatorCircularManagementScreen extends StatefulWidget {
  const CoordinatorCircularManagementScreen({super.key});

  @override
  State<CoordinatorCircularManagementScreen> createState() =>
      _CoordinatorCircularManagementScreenState();
}

class _CoordinatorCircularManagementScreenState
    extends State<CoordinatorCircularManagementScreen> {
  final _dateFormat = DateFormat('dd MMM yyyy');

  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _circulars = [];
  List<Map<String, dynamic>> _classes = [];

  String _search = '';
  String _audienceFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  List<Map<String, dynamic>> get _filteredCirculars {
    final query = _search.trim().toLowerCase();
    return _circulars.where((row) {
      final audience = _safe(row['audience'], 'both').toLowerCase();
      if (_audienceFilter != 'all' && audience != _audienceFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      final haystack = [
        row['title'],
        row['description'],
        row['content'],
        audience,
        row['_targetMode'],
        _classSummary(row['_classIds']),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
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
        _loadCirculars(),
        _loadClasses(),
      ]);
      if (!mounted) return;
      setState(() {
        _circulars = results[0];
        _classes = results[1];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadCirculars() async {
    final response = await ApiService.rawGet('/circulars');
    if (!_ok(response.statusCode)) {
      throw Exception(_extractError(response.body, 'Failed to load circulars'));
    }
    final rows = _extractRows(jsonDecode(response.body), const ['circulars'])
        .map(_normalizeCircular)
        .toList();
    rows.sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
    return rows;
  }

  Future<List<Map<String, dynamic>>> _loadClasses() async {
    const endpoints = ['/classes', '/classes/all', '/classes/list', '/class'];
    for (final endpoint in endpoints) {
      try {
        final response = await ApiService.rawGet(endpoint);
        if (!_ok(response.statusCode)) continue;
        final rows = _extractRows(jsonDecode(response.body), const ['classes'])
            .map(_normalizeClass)
            .whereType<Map<String, dynamic>>()
            .toList();
        if (rows.isNotEmpty) {
          rows.sort((a, b) => _safe(a['name']).compareTo(_safe(b['name'])));
          return rows;
        }
      } catch (_) {}
    }
    return [];
  }

  Future<void> _openEditor({Map<String, dynamic>? circular}) async {
    final titleController = TextEditingController(
      text: _safe(circular?['title']),
    );
    final contentController = TextEditingController(
      text: _safe(circular?['description'] ?? circular?['content']),
    );

    String audience = _safe(circular?['audience'], 'both');
    if (!['both', 'student', 'teacher'].contains(audience)) audience = 'both';
    String targetMode = _safe(circular?['_targetMode'], 'ALL');
    final selectedClassIds = <int>{..._parseIds(circular?['_classIds'])};
    XFile? selectedFile;
    bool removeFile = false;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> chooseFile() async {
              final file = await openFile(
                acceptedTypeGroups: const [
                  XTypeGroup(
                    label: 'Documents and images',
                    extensions: [
                      'pdf',
                      'png',
                      'jpg',
                      'jpeg',
                      'webp',
                      'gif',
                      'bmp',
                    ],
                  ),
                ],
              );
              if (file == null) return;
              setSheetState(() {
                selectedFile = file;
                removeFile = false;
              });
            }

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
                        circular == null ? 'Add Circular' : 'Edit Circular',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: titleController,
                        maxLength: 120,
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: contentController,
                        minLines: 4,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          labelText: 'Content / Description',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: audience,
                        decoration: const InputDecoration(
                          labelText: 'Audience',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'both', child: Text('All')),
                          DropdownMenuItem(
                            value: 'student',
                            child: Text('Students'),
                          ),
                          DropdownMenuItem(
                            value: 'teacher',
                            child: Text('Teachers'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setSheetState(() {
                            audience = value;
                            if (audience == 'teacher') {
                              targetMode = 'ALL';
                              selectedClassIds.clear();
                            }
                          });
                        },
                      ),
                      if (audience != 'teacher') ...[
                        const SizedBox(height: 12),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'ALL',
                              label: Text('All Classes'),
                              icon: Icon(Icons.groups_rounded),
                            ),
                            ButtonSegment(
                              value: 'CLASSES',
                              label: Text('Selected'),
                              icon: Icon(Icons.checklist_rounded),
                            ),
                          ],
                          selected: {targetMode},
                          onSelectionChanged: (value) {
                            setSheetState(() {
                              targetMode = value.first;
                              if (targetMode == 'ALL') {
                                selectedClassIds.clear();
                              }
                            });
                          },
                        ),
                        if (targetMode == 'CLASSES') ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _classes.map((cls) {
                              final id = _toInt(cls['id']);
                              final selected =
                                  id != null && selectedClassIds.contains(id);
                              return FilterChip(
                                label: Text(_safe(cls['name'], 'Class $id')),
                                selected: selected,
                                onSelected: id == null
                                    ? null
                                    : (checked) {
                                        setSheetState(() {
                                          if (checked) {
                                            selectedClassIds.add(id);
                                          } else {
                                            selectedClassIds.remove(id);
                                          }
                                        });
                                      },
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                      const SizedBox(height: 12),
                      _attachmentEditor(
                        circular: circular,
                        selectedFile: selectedFile,
                        removeFile: removeFile,
                        onChoose: chooseFile,
                        onClearNew: () =>
                            setSheetState(() => selectedFile = null),
                        onRemoveExisting: () =>
                            setSheetState(() => removeFile = true),
                        onKeepExisting: () =>
                            setSheetState(() => removeFile = false),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving
                              ? null
                              : () async {
                                  final ok = await _saveCircular(
                                    circular: circular,
                                    title: titleController.text,
                                    content: contentController.text,
                                    audience: audience,
                                    targetMode: audience == 'teacher'
                                        ? 'ALL'
                                        : targetMode,
                                    classIds: selectedClassIds.toList()..sort(),
                                    file: selectedFile,
                                    removeFile: removeFile,
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
                          label: const Text('Save Circular'),
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

    titleController.dispose();
    contentController.dispose();
    if (saved == true) await _loadAll();
  }

  Widget _attachmentEditor({
    required Map<String, dynamic>? circular,
    required XFile? selectedFile,
    required bool removeFile,
    required Future<void> Function() onChoose,
    required VoidCallback onClearNew,
    required VoidCallback onRemoveExisting,
    required VoidCallback onKeepExisting,
  }) {
    final existing = _fileUrl(circular ?? const {});
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Attachment',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            selectedFile != null
                ? selectedFile.name
                : existing.isNotEmpty && !removeFile
                    ? 'Current attachment available'
                    : 'No file selected',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onChoose,
                icon: const Icon(Icons.upload_file_rounded),
                label: Text(selectedFile == null && existing.isEmpty
                    ? 'Upload'
                    : 'Replace'),
              ),
              if (selectedFile != null)
                OutlinedButton.icon(
                  onPressed: onClearNew,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Clear'),
                ),
              if (existing.isNotEmpty && selectedFile == null && !removeFile)
                OutlinedButton.icon(
                  onPressed: () => _openUrl(existing),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('View'),
                ),
              if (existing.isNotEmpty && selectedFile == null && !removeFile)
                OutlinedButton.icon(
                  onPressed: onRemoveExisting,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Remove File'),
                ),
              if (removeFile)
                OutlinedButton.icon(
                  onPressed: onKeepExisting,
                  icon: const Icon(Icons.undo_rounded),
                  label: const Text('Keep File'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<bool> _saveCircular({
    required Map<String, dynamic>? circular,
    required String title,
    required String content,
    required String audience,
    required String targetMode,
    required List<int> classIds,
    required XFile? file,
    required bool removeFile,
  }) async {
    final cleanTitle = title.trim();
    final cleanContent = content.trim();
    if (cleanTitle.isEmpty) {
      _showMessage('Title required', 'Please add a circular title.');
      return false;
    }
    if (cleanContent.isEmpty) {
      _showMessage('Content required', 'Please add circular details.');
      return false;
    }
    if (audience != 'teacher' && targetMode == 'CLASSES' && classIds.isEmpty) {
      _showMessage('Select classes', 'Please select at least one class.');
      return false;
    }

    setState(() => _saving = true);
    try {
      final token = await _token();
      final endpoint =
          circular == null ? '/circulars' : '/circulars/${circular['id']}';
      final request = http.MultipartRequest(
        circular == null ? 'POST' : 'PUT',
        Uri.parse('${ApiService.baseUrl}$endpoint'),
      );
      if (token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.headers['Accept'] = 'application/json';
      request.fields['title'] = cleanTitle;
      request.fields['description'] = cleanContent;
      request.fields['content'] = cleanContent;
      request.fields['audience'] = audience;
      request.fields['targetMode'] = audience == 'teacher' ? 'ALL' : targetMode;
      request.fields['classIds'] =
          jsonEncode(targetMode == 'CLASSES' ? classIds : <int>[]);
      if (removeFile) request.fields['removeFile'] = 'true';
      if (file != null) {
        request.files.add(await http.MultipartFile.fromPath('file', file.path));
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      if (!_ok(response.statusCode)) {
        _showMessage(
          'Save failed',
          _extractError(response.body, 'Failed to save circular.'),
        );
        return false;
      }
      _showMessage(
        circular == null ? 'Created' : 'Updated',
        circular == null
            ? 'Circular created successfully.'
            : 'Circular updated successfully.',
      );
      return true;
    } catch (e) {
      _showMessage('Save failed', e.toString().replaceFirst('Exception: ', ''));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteCircular(Map<String, dynamic> circular) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete circular?'),
        content: const Text('This action cannot be undone.'),
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
      final response = await ApiService.rawDelete('/circulars/${circular['id']}');
      if (!_ok(response.statusCode)) {
        _showMessage(
          'Delete failed',
          _extractError(response.body, 'Failed to delete circular.'),
        );
        return;
      }
      _showMessage('Deleted', 'Circular removed successfully.');
      await _loadAll();
    } catch (e) {
      _showMessage(
        'Delete failed',
        e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showMessage('Invalid URL', 'Attachment URL is invalid.');
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) _showMessage('Could not open', 'Attachment could not open.');
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredCirculars;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Circular Management'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _saving ? null : () => _openEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Circular'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _state(
                  Icons.warning_rounded,
                  'Could not load circulars',
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
                          Icons.campaign_rounded,
                          'No circulars found',
                          'Create your first circular or change filters.',
                        )
                      else
                        ...rows.map(_circularCard),
                    ],
                  ),
                ),
    );
  }

  Widget _hero(int filteredCount) {
    final targeted =
        _circulars.where((row) => row['_targetMode'] == 'CLASSES').length;
    final files = _circulars.where((row) => _fileUrl(row).isNotEmpty).length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF0F766E)],
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
              Icon(Icons.campaign_rounded, color: Colors.white, size: 36),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Circular Management',
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
              _heroStat('Targeted', '$targeted'),
              _heroStat('Files', '$files'),
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
            Text(label, style: const TextStyle(color: Colors.white70)),
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
              labelText: 'Search circulars',
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _search = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _audienceFilter,
            decoration: const InputDecoration(
              labelText: 'Audience',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All')),
              DropdownMenuItem(value: 'both', child: Text('All Users')),
              DropdownMenuItem(value: 'student', child: Text('Students')),
              DropdownMenuItem(value: 'teacher', child: Text('Teachers')),
            ],
            onChanged: (value) =>
                setState(() => _audienceFilter = value ?? 'all'),
          ),
        ],
      ),
    );
  }

  Widget _circularCard(Map<String, dynamic> row) {
    final fileUrl = _fileUrl(row);
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
                  backgroundColor: const Color(0xFF4F46E5).withOpacity(0.12),
                  child: const Icon(
                    Icons.campaign_rounded,
                    color: Color(0xFF4F46E5),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _safe(row['title'], 'Untitled Circular'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _safe(
                          row['description'] ?? row['content'],
                          'No content',
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(_audienceLabel(_safe(row['audience'], 'both'))),
                _pill(row['_targetMode'] == 'CLASSES'
                    ? _classSummary(row['_classIds'])
                    : 'All Classes'),
                _pill(_dateLabel(row)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (fileUrl.isNotEmpty)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openUrl(fileUrl),
                      icon: const Icon(Icons.attach_file_rounded),
                      label: const Text('Open File'),
                    ),
                  ),
                if (fileUrl.isNotEmpty) const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _openEditor(circular: row),
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _deleteCircular(row),
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
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
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

  Map<String, dynamic> _normalizeCircular(Map<String, dynamic> row) {
    final ids = _parseIds(
      row['classIds'] ?? row['class_ids'] ?? row['targetClassIds'],
    );
    final target = _safe(row['targetMode'] ?? row['target_mode']).toUpperCase();
    return {
      ...row,
      '_classIds': ids,
      '_targetMode': target == 'CLASSES' || ids.isNotEmpty ? 'CLASSES' : 'ALL',
    };
  }

  Map<String, dynamic>? _normalizeClass(Map<String, dynamic> row) {
    final id = _toInt(row['id'] ?? row['class_id'] ?? row['classId']);
    if (id == null || id <= 0) return null;
    return {
      'id': id,
      'name': _safe(
        row['name'] ?? row['class_name'] ?? row['className'],
        'Class $id',
      ),
    };
  }

  List<int> _parseIds(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value
          .map(_toInt)
          .whereType<int>()
          .where((id) => id > 0)
          .toSet()
          .toList()
        ..sort();
    }
    if (value is num) return value > 0 ? [value.toInt()] : [];
    final text = value.toString().trim();
    if (text.isEmpty) return [];
    try {
      return _parseIds(jsonDecode(text));
    } catch (_) {
      return text
          .split(',')
          .map(_toInt)
          .whereType<int>()
          .where((id) => id > 0)
          .toSet()
          .toList()
        ..sort();
    }
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
      'results',
      'circulars',
      'classes',
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

  String _classSummary(dynamic value) {
    final ids = _parseIds(value);
    if (ids.isEmpty) return 'All Classes';
    final names = ids.map((id) {
      for (final cls in _classes) {
        if (_toInt(cls['id']) == id) return _safe(cls['name'], 'Class $id');
      }
      return 'Class $id';
    }).toList();
    if (names.length <= 3) return names.join(', ');
    return '${names.take(3).join(', ')} +${names.length - 3}';
  }

  String _fileUrl(Map<String, dynamic> row) {
    final raw = _safe(row['fileUrl'] ?? row['file_url'] ?? row['file']);
    if (raw.isEmpty) return '';
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.hasScheme) return raw;
    return '${ApiService.baseUrl}${raw.startsWith('/') ? raw : '/$raw'}';
  }

  String _dateLabel(Map<String, dynamic> row) {
    final date = _dateOf(row);
    if (date.millisecondsSinceEpoch == 0) return '-';
    return _dateFormat.format(date.toLocal());
  }

  DateTime _dateOf(Map<String, dynamic> row) {
    return DateTime.tryParse(
          _safe(row['createdAt'] ?? row['created_at'] ?? row['date']),
        ) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _audienceLabel(String audience) {
    switch (audience.toLowerCase()) {
      case 'teacher':
        return 'Teachers';
      case 'student':
        return 'Students';
      default:
        return 'All';
    }
  }

  Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('authToken') ?? prefs.getString('token') ?? '')
        .trim();
  }

  bool _ok(int statusCode) => statusCode >= 200 && statusCode < 300;

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
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
