// File: lib/screens/student_assignments_screen.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/student_drawer_menu.dart';
import '../constants/constants.dart'; // contains baseUrl

class StudentAssignmentsScreen extends StatefulWidget {
  const StudentAssignmentsScreen({super.key});

  @override
  State<StudentAssignmentsScreen> createState() => _StudentAssignmentsScreenState();
}

class _StudentAssignmentsScreenState extends State<StudentAssignmentsScreen> {
  final Dio _dio = Dio();
  List<dynamic> _assignments = [];
  bool _loading = true;
  String? _error;

  // Filters / UI state
  String _search = '';
  String _statusFilter = 'all'; // pending | submitted | graded | overdue | all
  String _sortBy = 'updated'; // updated | due
  String _sortDir = 'desc'; // asc | desc
  DateTime? _lastSyncedAt;
  bool _isRefreshing = false;

  // downloads
  final Map<String, double> _downloadProgress = {}; // fileUrl -> 0..1
  final Map<String, String> _localFilePaths = {}; // fileUrl -> savedPath

  @override
  void initState() {
    super.initState();
    _fetchAssignments();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authToken');
  }

  Future<void> _fetchAssignments({bool keepLoading = false}) async {
    setState(() {
      if (!keepLoading) _loading = true;
      _error = null;
    });

    final token = await _getToken();
    if (token == null) {
      setState(() {
        _error = 'Not logged in. Please login to view assignments.';
        _loading = false;
      });
      return;
    }
    if (baseUrl.isEmpty) {
      setState(() {
        _error = 'baseUrl is not configured (constants.dart).';
        _loading = false;
      });
      return;
    }

    try {
      if (!keepLoading) _isRefreshing = true;

      final res = await _dio.get(
        '$baseUrl/student-assignments/student',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final data = res.data;
      final list = (data is Map && data['assignments'] is List) ? data['assignments'] as List : <dynamic>[];
      setState(() {
        _assignments = list;
        _lastSyncedAt = DateTime.now();
      });
    } on DioError catch (e) {
      debugPrint('Fetch assignments DioError: $e');
      setState(() {
        _error = e.response?.data?.toString() ?? 'Failed to load assignments';
      });
    } catch (e) {
      debugPrint('Fetch assignments error: $e');
      setState(() {
        _error = 'Failed to load assignments';
      });
    } finally {
      setState(() {
        _loading = false;
        _isRefreshing = false;
      });
    }
  }

  // Helper: format date safely
  String _formatDate(String? iso) {
    if (iso == null) return 'N/A';
    try {
      final dt = DateTime.tryParse(iso);
      if (dt == null) return iso;
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  bool _isOverdue(String? dueIso) {
    if (dueIso == null) return false;
    final due = DateTime.tryParse(dueIso);
    if (due == null) return false;
    final dueEnd = DateTime(due.year, due.month, due.day, 23, 59, 59);
    return DateTime.now().isAfter(dueEnd);
  }

  // Sorting & filtering like original logic
  List<dynamic> get _filteredSorted {
    final s = _search.toLowerCase().trim();
    List<dynamic> filtered = _assignments.where((a) {
      final title = (a['title'] ?? '').toString().toLowerCase();
      final content = (a['content'] ?? '').toString().toLowerCase();
      final matchesSearch = s.isEmpty || title.contains(s) || content.contains(s);

      if (!matchesSearch) return false;

      if (_statusFilter == 'all') return true;

      final sa = (a['StudentAssignments'] is List && a['StudentAssignments'].isNotEmpty) ? a['StudentAssignments'][0] : {};
      final status = (sa?['status'] ?? '').toString().toLowerCase();

      if (_statusFilter == 'overdue') {
        return _isOverdue(sa?['dueDate']?.toString()) && !['submitted', 'graded'].contains(status);
      }
      return status == _statusFilter;
    }).toList();

    int compare(dynamic a, dynamic b) {
      final sa = (a['StudentAssignments'] is List && a['StudentAssignments'].isNotEmpty) ? a['StudentAssignments'][0] : {};
      final sb = (b['StudentAssignments'] is List && b['StudentAssignments'].isNotEmpty) ? b['StudentAssignments'][0] : {};

      int av, bv;
      if (_sortBy == 'due') {
        av = sa?['dueDate'] != null ? DateTime.tryParse(sa['dueDate'].toString())?.millisecondsSinceEpoch ?? 0 : 0;
        bv = sb?['dueDate'] != null ? DateTime.tryParse(sb['dueDate'].toString())?.millisecondsSinceEpoch ?? 0 : 0;
      } else {
        av = a['updatedAt'] != null ? DateTime.tryParse(a['updatedAt'].toString())?.millisecondsSinceEpoch ?? 0 : 0;
        bv = b['updatedAt'] != null ? DateTime.tryParse(b['updatedAt'].toString())?.millisecondsSinceEpoch ?? 0 : 0;
      }
      final diff = av - bv;
      return _sortDir == 'asc' ? diff : -diff;
    }

    filtered.sort(compare);
    return filtered;
  }

  // Request appropriate storage permission (Android) / nothing on iOS
  Future<bool> _ensureStoragePermission() async {
    if (kIsWeb) return true;
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (status.isGranted) return true;

      final manageStatus = await Permission.manageExternalStorage.request();
      if (manageStatus.isGranted) return true;

      return false;
    } else if (Platform.isIOS) {
      return true;
    } else {
      return true;
    }
  }

  Future<Directory> _defaultSaveDirectory() async {
    if (kIsWeb) throw Exception('Web is not supported for file downloads using this function.');
    if (Platform.isAndroid) {
      final dir = await getExternalStorageDirectory();
      if (dir != null) return dir;
    }
    return await getApplicationDocumentsDirectory();
  }

  String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
  }

  Future<void> _downloadAndOpen(String rawUrl, String suggestedName) async {
    if (rawUrl.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid file URL')));
      return;
    }

    final url = rawUrl.startsWith('http') ? rawUrl : '$baseUrl/$rawUrl';
    final okPerm = await _ensureStoragePermission();
    if (!okPerm) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Storage permission denied')));
      return;
    }

    Directory saveDir;
    try {
      saveDir = await _defaultSaveDirectory();
    } catch (e) {
      debugPrint('Default save dir error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to locate save directory: $e')));
      return;
    }

    final fileName = _sanitizeFilename(suggestedName.isNotEmpty ? suggestedName : url.split('/').last);
    final savePath = '${saveDir.path}/$fileName';

    setState(() => _downloadProgress[url] = 0);

    try {
      await _dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() => _downloadProgress[url] = received / total);
          }
        },
        options: Options(
          responseType: ResponseType.bytes,
          headers: {},
        ),
      );

      setState(() {
        _downloadProgress.remove(url);
        _localFilePaths[url] = savePath;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloaded: $fileName')));

      final result = await OpenFilex.open(savePath);
      debugPrint('OpenFilex result: ${result.message}');
    } on DioError catch (e) {
      debugPrint('Download DioError: $e');
      setState(() => _downloadProgress.remove(url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: ${e.message}')));
    } catch (e) {
      debugPrint('Download error: $e');
      setState(() => _downloadProgress.remove(url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  Widget _buildHeader() {
    final stats = _computeStats();
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1652F0), Color(0xFF0C77D6)]),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Your Assignments', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(_lastSyncedAt != null ? 'Last synced: ${TimeOfDay.fromDateTime(_lastSyncedAt!).format(context)}' : 'Syncing…', style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          Chip(label: Text('Total: ${stats['total']}')),
          Chip(backgroundColor: Colors.green.shade50, label: Text('Graded: ${stats['graded']}')),
          Chip(backgroundColor: Colors.blue.shade50, label: Text('Submitted: ${stats['submitted']}')),
          Chip(backgroundColor: Colors.red.shade50, label: Text('Overdue: ${stats['overdue']}')),
          ElevatedButton.icon(
            icon: _isRefreshing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.refresh),
            label: Text(_isRefreshing ? 'Refreshing…' : 'Refresh'),
            onPressed: _isRefreshing ? null : () => _fetchAssignments(keepLoading: true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
          ),
        ]),
      ]),
    );
  }

  Map<String, int> _computeStats() {
    int total = _assignments.length;
    int submitted = 0, graded = 0, overdue = 0;
    for (final a in _assignments) {
      final sa = (a['StudentAssignments'] is List && a['StudentAssignments'].isNotEmpty) ? a['StudentAssignments'][0] : {};
      final status = (sa?['status'] ?? '').toString().toLowerCase();
      if (status == 'submitted') submitted++;
      if (status == 'graded') graded++;
      if (!['submitted', 'graded'].contains(status) && _isOverdue(sa?['dueDate']?.toString())) overdue++;
    }
    return {'total': total, 'submitted': submitted, 'graded': graded, 'overdue': overdue};
  }

  Widget _buildControls() {
    return Column(children: [
      Row(children: [
        Expanded(
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search title or content…', border: OutlineInputBorder()),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          initialValue: _statusFilter,
          onSelected: (v) => setState(() => _statusFilter = v),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'all', child: Text('All statuses')),
            PopupMenuItem(value: 'pending', child: Text('Pending')),
            PopupMenuItem(value: 'submitted', child: Text('Submitted')),
            PopupMenuItem(value: 'graded', child: Text('Graded')),
            PopupMenuItem(value: 'overdue', child: Text('Overdue')),
          ],
          child: Chip(label: Text(_statusFilter.toUpperCase())),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        DropdownButton<String>(
          value: _sortBy,
          items: const [
            DropdownMenuItem(value: 'updated', child: Text('Sort: Updated')),
            DropdownMenuItem(value: 'due', child: Text('Sort: Due')),
          ],
          onChanged: (v) => setState(() => _sortBy = v ?? 'updated'),
        ),
        const SizedBox(width: 12),
        IconButton(
          onPressed: () => setState(() => _sortDir = _sortDir == 'asc' ? 'desc' : 'asc'),
          icon: Text(_sortDir == 'asc' ? '↑' : '↓', style: const TextStyle(fontSize: 18)),
        ),
        const Spacer(),
        Text(_filteredSorted.length.toString() + ' results', style: const TextStyle(color: Colors.black54)),
      ]),
    ]);
  }

  Widget _buildAssignmentCard(dynamic assignment) {
    final id = assignment['id']?.toString() ?? '';
    final title = assignment['title']?.toString() ?? 'Untitled';
    final content = assignment['content']?.toString() ?? '';
    final createdAt = assignment['createdAt']?.toString();
    final updatedAt = assignment['updatedAt']?.toString();
    final youtubeUrl = assignment['youtubeUrl']?.toString() ?? assignment['youtube_url']?.toString();
    final files = assignment['AssignmentFiles'] is List ? List.from(assignment['AssignmentFiles']) : <dynamic>[];

    final sa = (assignment['StudentAssignments'] is List && assignment['StudentAssignments'].isNotEmpty) ? assignment['StudentAssignments'][0] : {};
    final status = (sa?['status'] ?? 'unknown').toString();
    final due = sa?['dueDate']?.toString();

    final isOver = _isOverdue(due) && !['submitted', 'graded'].contains(status.toLowerCase());

    String statusLabel = status;
    if (isOver) statusLabel = 'Overdue';

    Color statusColor = Colors.grey;
    switch (statusLabel.toLowerCase()) {
      case 'submitted':
        statusColor = Colors.blue;
        break;
      case 'graded':
        statusColor = Colors.green;
        break;
      case 'overdue':
        statusColor = Colors.red;
        break;
      case 'pending':
        statusColor = Colors.orange;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Text('Due: ${due != null ? _formatDate(due) : 'N/A'}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(width: 12),
            Text('Updated: ${updatedAt != null ? _formatDate(updatedAt) : 'N/A'}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
          const SizedBox(height: 8),
          if (youtubeUrl != null && youtubeUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: ElevatedButton.icon(
                onPressed: () async {
                  final uri = Uri.tryParse(youtubeUrl);
                  if (uri != null && await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot open video link')));
                  }
                },
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Watch Video'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black87),
              ),
            ),
          const SizedBox(height: 6),
          Text(content, style: const TextStyle(color: Colors.black87)),
          const SizedBox(height: 8),
          if (files.isNotEmpty)
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Divider(),
              const Text('Attachments', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ...files.map<Widget>((f) {
                final fileUrl = (f['filePath'] ?? f['file_path'] ?? f['url'] ?? '').toString();
                final fileName = (f['fileName'] ?? f['file_name'] ?? f['name'] ?? fileUrl.split('/').last).toString();

                final progress = _downloadProgress[fileUrl] ?? 0.0;
                final savedPath = _localFilePaths[fileUrl];

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Row(children: [
                    Expanded(child: Text(fileName, style: const TextStyle(color: Colors.blueAccent, decoration: TextDecoration.underline))),
                    if (savedPath != null)
                      TextButton.icon(
                        onPressed: () => OpenFilex.open(savedPath),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Open'),
                      )
                    else if (progress > 0 && progress < 1)
                      SizedBox(
                        width: 120,
                        child: LinearProgressIndicator(value: progress),
                      )
                    else
                      TextButton.icon(
                        onPressed: () => _downloadAndOpen(fileUrl, fileName),
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Download'),
                      )
                  ]),
                );
              }).toList(),
            ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Replaced custom StudentAppBar with a simple AppBar titled "Assignments"
           appBar: AppBar(
        // If this page can be popped (pushed onto navigator), show a back arrow.
        // Otherwise show the drawer/menu icon so user can open the drawer.
        leading: Builder(builder: (innerCtx) {
          final canPop = Navigator.of(innerCtx).canPop();
          if (canPop) {
            return IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(innerCtx).pop(),
              tooltip: 'Back',
            );
          } else {
            // show drawer icon (works because Scaffold has a drawer)
            return IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () {
                final scaffold = Scaffold.maybeOf(innerCtx);
                if (scaffold != null && scaffold.hasDrawer) {
                  scaffold.openDrawer();
                }
              },
              tooltip: 'Menu',
            );
          }
        }),
        title: const Text('Assignments'),
        centerTitle: true,
        elevation: 3,
      ),

      drawer: const StudentDrawerMenu(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _fetchAssignments(keepLoading: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildHeader(),
              const SizedBox(height: 8),
              _buildControls(),
              const SizedBox(height: 12),
              if (_loading)
                Column(
                  children: List.generate(3, (i) => Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
                  )),
                )
              else if (_error != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
                    TextButton(onPressed: () => _fetchAssignments(), child: const Text('Retry')),
                  ]),
                )
              else if (_filteredSorted.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40.0),
                    child: Column(children: [
                      const Icon(Icons.inbox, size: 48, color: Colors.black26),
                      const SizedBox(height: 8),
                      const Text('No assignments found', style: TextStyle(color: Colors.black54)),
                      const SizedBox(height: 8),
                      ElevatedButton(onPressed: () => _fetchAssignments(), child: const Text('Reload')),
                    ]),
                  ),
                )
              else
                Column(children: _filteredSorted.map((a) => _buildAssignmentCard(a)).toList()),
              const SizedBox(height: 30),
            ]),
          ),
        ),
      ),
    );
  }
}
