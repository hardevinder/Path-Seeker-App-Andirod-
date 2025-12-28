// File: lib/screens/student_diary_screen.dart
import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/constants.dart';

class StudentDiaryScreen extends StatefulWidget {
  const StudentDiaryScreen({super.key});

  @override
  State<StudentDiaryScreen> createState() => _StudentDiaryScreenState();
}

class _StudentDiaryScreenState extends State<StudentDiaryScreen>
    with WidgetsBindingObserver {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> diaryList = [];
  int? expandedIndex;

  Timer? _pollTimer;
  final Duration _pollInterval = const Duration(seconds: 60);

  bool _isFetching = false;
  DateTime? _lastFetchAt;

  List<Map<String, dynamic>> students = [];
  String? activeAdmission;
  String? loggedInAdmission;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Load family first, then fetch
    _loadFamily().then((_) {
      _fetchDiaries();
      _startPolling();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause polling when app in background; resume + refresh on return
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      _fetchDiaries(force: true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _stopPolling();
    }
  }

  void _startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!mounted) return;
      _fetchDiaries();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _loadFamily() async {
    final prefs = await SharedPreferences.getInstance();
    final storedFamily = prefs.getString('family');
    final storedActive = prefs.getString('activeStudentAdmission');
    final storedLogged = prefs.getString('username');

    List<Map<String, dynamic>> famList = [];

    if (storedFamily != null) {
      try {
        final parsed = json.decode(storedFamily);
        if (parsed is Map) {
          if (parsed['student'] != null) {
            famList.add(
              Map<String, dynamic>.from(parsed['student'])..['isSelf'] = true,
            );
          }
          if (parsed['siblings'] is List) {
            famList.addAll(
              List<Map<String, dynamic>>.from(parsed['siblings']),
            );
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      students = famList;
      activeAdmission = storedActive ?? storedLogged;
      loggedInAdmission = storedLogged;
    });
  }

  Future<void> _handleStudentSwitch(String admission) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('activeStudentAdmission', admission);

    if (!mounted) return;
    setState(() {
      activeAdmission = admission;
      expandedIndex = null;
    });

    _fetchDiaries(force: true);
  }

  Future<void> _fetchDiaries({bool force = false}) async {
    if (_isFetching) return;

    // Avoid too-frequent requests (unless forced)
    if (!force && _lastFetchAt != null) {
      final diff = DateTime.now().difference(_lastFetchAt!);
      if (diff.inSeconds < 3) return;
    }

    _isFetching = true;
    _lastFetchAt = DateTime.now();

    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final loggedIn = prefs.getString('username');
      final active = prefs.getString('activeStudentAdmission') ?? loggedIn;

      String url = '$baseUrl/diaries/student/feed/list';
      if (active != null && loggedIn != null && active != loggedIn) {
        url = '$baseUrl/diaries/by-admission/$active';
      }

      final res = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      );

      if (!mounted) return;

      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);

        List<Map<String, dynamic>> rows = [];
        if (decoded is Map && decoded['data'] is List) {
          rows = List<Map<String, dynamic>>.from(decoded['data']);
        } else if (decoded is List) {
          rows = List<Map<String, dynamic>>.from(decoded);
        }

        setState(() {
          diaryList = rows;
          error = null;
        });
      } else if (res.statusCode == 401) {
        setState(() => error = "Unauthorized. Please login again.");
      } else {
        setState(() => error = "Failed to load diaries (${res.statusCode})");
      }
    } catch (e, st) {
      debugPrint('Diary fetch error: $e\n$st');
      if (!mounted) return;
      setState(() => error = "Error: $e");
    } finally {
      _isFetching = false;
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  Future<void> _acknowledgeDiary(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final url = '$baseUrl/diaries/$id/ack';

      final res = await http.post(
        Uri.parse(url),
        headers: {
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (!mounted) return;

      if (res.statusCode == 200 || res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Acknowledged')),
        );
        _fetchDiaries(force: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed (${res.statusCode}) to acknowledge')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return "";
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return dateStr;
    return DateFormat.yMMMd().add_jm().format(dt);
  }

  Color _typeTint(String type) {
    switch (type.toUpperCase()) {
      case 'HOMEWORK':
        return Colors.indigo;
      case 'REMARK':
        return Colors.orange;
      case 'ANNOUNCEMENT':
        return Colors.green;
      default:
        return Colors.blueGrey;
    }
  }

  Color _typeCardBg(String type) {
    switch (type.toUpperCase()) {
      case 'HOMEWORK':
        return Colors.indigo.shade50;
      case 'REMARK':
        return Colors.orange.shade50;
      case 'ANNOUNCEMENT':
        return Colors.green.shade50;
      default:
        return Colors.grey.shade50;
    }
  }

  IconData _typeIcon(String type) {
    switch (type.toUpperCase()) {
      case 'HOMEWORK':
        return Icons.menu_book_rounded;
      case 'REMARK':
        return Icons.warning_amber_rounded;
      case 'ANNOUNCEMENT':
        return Icons.campaign_rounded;
      default:
        return Icons.sticky_note_2_rounded;
    }
  }

  String _safeStr(dynamic v) => (v == null) ? '' : v.toString();

  /// --- DOWNLOAD --------------------------------------------------------------
  Future<void> handleDownload(String rawUrl, String fileName) async {
    if (rawUrl.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file URL provided')),
      );
      return;
    }

    String finalUrl = rawUrl;
    if (!rawUrl.startsWith('http')) {
      finalUrl = baseUrl.replaceAll(RegExp(r'\/$'), '') +
          '/' +
          rawUrl.replaceAll(RegExp(r'^\/'), '');
    }

    try {
      final Directory dir = Platform.isAndroid
          ? (await getExternalStorageDirectory() ??
              await getApplicationDocumentsDirectory())
          : await getApplicationDocumentsDirectory();

      final saveDir = Directory('${dir.path}/StudentApp');
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      final safeName = fileName.trim().isEmpty ? 'Attachment' : fileName.trim();
      final savePath = '${saveDir.path}/$safeName';

      final dio = Dio();

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const DownloadProgressDialog(),
        );
      }

      final response = await dio.download(finalUrl, savePath);

      // Close progress dialog safely
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Text('✅ File downloaded'),
            content: Text('$safeName\n\nSaved to:\n${saveDir.path}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await OpenFilex.open(savePath);
                },
                child: const Text('Open'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: ${response.statusCode}')),
        );
      }
    } catch (e, st) {
      debugPrint('Download error: $e\n$st');
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  Widget _buildAttachmentChip(Map<String, dynamic> a) {
    final url = _safeStr(a['url'] ?? a['fileUrl'] ?? a['filePath'] ?? a['file'] ?? a['path']);
    final name = _safeStr(a['name'] ?? a['originalName'] ?? a['fileName'] ?? a['filename'] ?? (url.split('/').isNotEmpty ? url.split('/').last : 'Attachment'));

    return ActionChip(
      avatar: const Icon(Icons.download_rounded, size: 18),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Text(name, overflow: TextOverflow.ellipsis),
      ),
      onPressed: url.isEmpty ? null : () => handleDownload(url, name),
    );
  }

  /// --- STUDENT SWITCHER (chips) ---------------------------------------------
  Widget _buildStudentSwitcher() {
    if (students.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Wrap(
          spacing: 8,
          children: students.map((s) {
            final adm = _safeStr(s['admission_number']);
            final isActive = adm == (activeAdmission ?? '');
            final label =
                (s['isSelf'] == true ? "Me • " : "") + (_safeStr(s['name']).isNotEmpty ? _safeStr(s['name']) : adm);

            return ChoiceChip(
              selected: isActive,
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(label, overflow: TextOverflow.ellipsis),
              ),
              onSelected: (_) => _handleStudentSwitch(adm),
              selectedColor: Colors.indigo.shade600,
              labelStyle: TextStyle(
                color: isActive ? Colors.white : Colors.indigo.shade700,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
              side: BorderSide(color: Colors.indigo.shade200),
              backgroundColor: Colors.white,
              showCheckmark: false,
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTopSummary() {
    final last = _lastFetchAt == null ? null : DateFormat.Hm().format(_lastFetchAt!);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Diaries',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.indigo.shade800,
              ),
            ),
          ),
          if (last != null)
            Text(
              'Updated $last',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _fetchDiaries(force: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 140),
        Center(child: Text("No diary entries found")),
        SizedBox(height: 140),
      ],
    );
    }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 40, color: Colors.redAccent),
            const SizedBox(height: 10),
            Text(
              error ?? 'Something went wrong',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _fetchDiaries(force: true),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiaryCard(Map<String, dynamic> d, int index) {
    final type = _safeStr(d['type']).isEmpty ? 'NOTE' : _safeStr(d['type']);
    final isExpanded = expandedIndex == index;

    final title = _safeStr(d['title']).isEmpty ? 'Untitled' : _safeStr(d['title']);
    final content = _safeStr(d['content']);
    final dateStr = _formatDate(_safeStr(d['date']));

    final attachments = (d['attachments'] is List)
        ? List<Map<String, dynamic>>.from(d['attachments'])
        : <Map<String, dynamic>>[];

    final tint = _typeTint(type);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      color: _typeCardBg(type),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (!mounted) return;
          setState(() {
            expandedIndex = isExpanded ? null : index;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header (no overflow)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white,
                    child: Icon(_typeIcon(type), color: tint),
                  ),
                  const SizedBox(width: 10),

                  // Title + date (expanded so no overflow)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Chip(
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              label: Text(type.toUpperCase(), style: const TextStyle(fontSize: 11)),
                              labelStyle: TextStyle(
                                color: tint,
                                fontWeight: FontWeight.w800,
                              ),
                              backgroundColor: Colors.white,
                              side: BorderSide(color: tint.withOpacity(0.25)),
                            ),
                            if (dateStr.isNotEmpty)
                              Text(
                                dateStr,
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 6),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.black54,
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Body (crossfade)
              AnimatedCrossFade(
                firstChild: Text(
                  content.length > 140 ? '${content.substring(0, 140)}…' : content,
                  style: const TextStyle(color: Colors.black87),
                ),
                secondChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(content, style: const TextStyle(color: Colors.black87)),

                    if (attachments.isNotEmpty) const SizedBox(height: 10),
                    if (attachments.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: attachments.map(_buildAttachmentChip).toList(),
                      ),

                    const SizedBox(height: 12),

                    // Actions (Wrap => no overflow)
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _acknowledgeDiary(_safeStr(d['id'])),
                          icon: const Icon(Icons.check_circle, size: 18),
                          label: const Text('Acknowledge'),
                        ),
                        TextButton(
                          onPressed: () {
                            if (!mounted) return;
                            setState(() => expandedIndex = null);
                          },
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ],
                ),
                crossFadeState:
                    isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 220),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Diaries'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildStudentSwitcher(),
            _buildTopSummary(),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : (error != null)
                      ? _buildError()
                      : RefreshIndicator(
                          onRefresh: () => _fetchDiaries(force: true),
                          child: diaryList.isEmpty
                              ? _buildEmpty()
                              : ListView.builder(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                  itemCount: diaryList.length,
                                  itemBuilder: (context, index) {
                                    final d = diaryList[index];
                                    return _buildDiaryCard(d, index);
                                  },
                                ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class DownloadProgressDialog extends StatelessWidget {
  const DownloadProgressDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Downloading...')),
          ],
        ),
      ),
    );
  }
}
