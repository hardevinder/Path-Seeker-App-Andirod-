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
  List<dynamic> diaryList = [];
  int? expandedIndex;

  Timer? _pollTimer;
  final Duration _pollInterval = const Duration(seconds: 60);

  List<Map<String, dynamic>> students = [];
  String? activeAdmission;
  String? loggedInAdmission;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFamily();
    _fetchDiaries();
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchDiaries();
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
            famList.add(Map<String, dynamic>.from(parsed['student'])..['isSelf'] = true);
          }
          if (parsed['siblings'] is List) {
            famList.addAll(List<Map<String, dynamic>>.from(parsed['siblings']));
          }
        }
      } catch (_) {}
    }

    setState(() {
      students = famList;
      activeAdmission = storedActive ?? storedLogged;
      loggedInAdmission = storedLogged;
    });
  }

  Future<void> _handleStudentSwitch(String admission) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('activeStudentAdmission', admission);
    setState(() {
      activeAdmission = admission;
    });
    _fetchDiaries();
  }

  Future<void> _fetchDiaries() async {
    setState(() {
      loading = true;
      error = null;
    });

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
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          diaryList = (data is Map && data['data'] is List)
              ? List.from(data['data'])
              : (data is List ? data : []);
        });
      } else if (res.statusCode == 401) {
        setState(() => error = "Unauthorized. Please login again.");
      } else {
        setState(() => error = "Failed to load diaries (${res.statusCode})");
      }
    } catch (e, st) {
      debugPrint('Diary fetch error: $e\n$st');
      setState(() => error = "Error: $e");
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _acknowledgeDiary(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final url = '$baseUrl/diaries/$id/ack';
      final res = await http.post(Uri.parse(url), headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      });

      if (res.statusCode == 200 || res.statusCode == 201) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Acknowledged')));
        _fetchDiaries();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed (${res.statusCode}) to acknowledge')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return "";
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return dateStr;
    return DateFormat.yMMMd().add_jm().format(dt);
  }

  Color _typeColor(String type) {
    switch (type.toUpperCase()) {
      case 'HOMEWORK':
        return Colors.blue.shade50;
      case 'REMARK':
        return Colors.amber.shade50;
      case 'ANNOUNCEMENT':
        return Colors.green.shade50;
      default:
        return Colors.grey.shade50;
    }
  }

  IconData _typeIcon(String type) {
    switch (type.toUpperCase()) {
      case 'HOMEWORK':
        return Icons.book;
      case 'REMARK':
        return Icons.warning_amber_rounded;
      case 'ANNOUNCEMENT':
        return Icons.campaign;
      default:
        return Icons.note;
    }
  }

  Future<void> handleDownload(String rawUrl, String fileName) async {
    if (rawUrl.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No file URL provided')));
      return;
    }

    String encodedUrl = rawUrl;
    if (!rawUrl.startsWith('http')) {
      encodedUrl = baseUrl.replaceAll(RegExp(r'\/$'), '') +
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

      final savePath = '${saveDir.path}/$fileName';
      final dio = Dio();

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => DownloadProgressDialog(),
      );

      final response = await dio.download(encodedUrl, savePath);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (response.statusCode == 200 || response.statusCode == 201) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('File downloaded'),
            content: Text('$fileName\n\nSaved to: ${saveDir.path}'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close')),
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
            SnackBar(content: Text('Download failed: ${response.statusCode}')));
      }
    } catch (e, st) {
      debugPrint('Download error: $e\n$st');
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  Widget _buildAttachmentButton(Map<String, dynamic> a) {
    final url = (a['url'] ?? a['filePath'] ?? a['file'] ?? a['path'] ?? '')
        .toString();
    final name = (a['name'] ??
            a['fileName'] ??
            a['filename'] ??
            url.split('/').last)
        .toString();
    return TextButton.icon(
      onPressed: url.isEmpty ? null : () => handleDownload(url, name),
      icon: const Icon(Icons.download_rounded),
      label: Text(name, overflow: TextOverflow.ellipsis),
    );
  }

  /// 👇 Student switcher bar (horizontal buttons)
  Widget _buildStudentSwitcher() {
    if (students.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: students.map((s) {
            final adm = (s['admission_number'] ?? '').toString();
            final isActive = adm == activeAdmission;
            final name = (s['isSelf'] == true ? "Me: " : "") + (s['name'] ?? adm);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isActive ? Colors.indigo.shade600 : Colors.transparent,
                  foregroundColor: isActive ? Colors.white : Colors.indigo.shade600,
                  side: isActive ? null : const BorderSide(color: Colors.indigo),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  elevation: isActive ? 2 : 0,
                ),
                onPressed: () => _handleStudentSwitch(adm),
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            );
          }).toList(),
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
            _buildStudentSwitcher(), // 👈 Always visible at top
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : (error != null)
                      ? Center(child: Text(error!, style: const TextStyle(color: Colors.red)))
                      : RefreshIndicator(
                          onRefresh: _fetchDiaries,
                          child: diaryList.isEmpty
                              ? ListView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  children: const [
                                    SizedBox(height: 120),
                                    Center(child: Text("No diary entries found")),
                                    SizedBox(height: 120),
                                  ],
                                )
                              : ListView.builder(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.all(12),
                                  itemCount: diaryList.length,
                                  itemBuilder: (context, index) {
                                    final d = diaryList[index] as Map<String, dynamic>;
                                    final type = (d['type'] ?? 'Note').toString();
                                    final isExpanded = expandedIndex == index;
                                    final attachments = (d['attachments'] is List)
                                        ? List<Map<String, dynamic>>.from(d['attachments'])
                                        : <Map<String, dynamic>>[];

                                    return Card(
                                      margin: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12)),
                                      color: _typeColor(type),
                                      elevation: 2,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () {
                                          setState(() {
                                            expandedIndex = isExpanded ? null : index;
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(12.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Row(
                                                    children: [
                                                      CircleAvatar(
                                                        radius: 18,
                                                        backgroundColor: Colors.white,
                                                        child: Icon(_typeIcon(type),
                                                            color: Colors.indigo),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            d['title']?.toString() ?? 'Untitled',
                                                            style: const TextStyle(
                                                                fontWeight: FontWeight.w700,
                                                                fontSize: 16),
                                                          ),
                                                          const SizedBox(height: 2),
                                                          Text(
                                                            _formatDate(d['date']?.toString()),
                                                            style: const TextStyle(
                                                                color: Colors.black54, fontSize: 12),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                  Icon(
                                                    isExpanded
                                                        ? Icons.expand_less
                                                        : Icons.expand_more,
                                                    color: Colors.indigo,
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              AnimatedCrossFade(
                                                firstChild: Text(
                                                  (d['content'] ?? '').toString().length > 120
                                                      ? '${d['content'].toString().substring(0, 120)}...'
                                                      : (d['content'] ?? '').toString(),
                                                  style: const TextStyle(color: Colors.black87),
                                                ),
                                                secondChild: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text((d['content'] ?? '').toString(),
                                                        style: const TextStyle(color: Colors.black87)),
                                                    if (attachments.isNotEmpty)
                                                      const SizedBox(height: 8),
                                                    if (attachments.isNotEmpty)
                                                      Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment.start,
                                                        children: [
                                                          const Text('Attachments:',
                                                              style: TextStyle(
                                                                  fontWeight: FontWeight.w600,
                                                                  color: Colors.black87)),
                                                          const SizedBox(height: 6),
                                                          ...attachments.map((a) =>
                                                              _buildAttachmentButton(a)),
                                                        ],
                                                      ),
                                                    const SizedBox(height: 10),
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        ElevatedButton.icon(
                                                          style: ElevatedButton.styleFrom(
                                                              backgroundColor: Colors.indigo),
                                                          onPressed: () {
                                                            _acknowledgeDiary(d['id'].toString());
                                                          },
                                                          icon: const Icon(Icons.check_circle, size: 18),
                                                          label: const Text('Acknowledge'),
                                                        ),
                                                        TextButton(
                                                          onPressed: () {
                                                            setState(() {
                                                              expandedIndex = null;
                                                            });
                                                          },
                                                          child: const Text('Close'),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                                crossFadeState: isExpanded
                                                    ? CrossFadeState.showSecond
                                                    : CrossFadeState.showFirst,
                                                duration:
                                                    const Duration(milliseconds: 200),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
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
  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('Downloading...')),
        ]),
      ),
    );
  }
}