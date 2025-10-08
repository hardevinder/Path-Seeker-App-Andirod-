// File: lib/screens/student_diary_screen.dart
import 'dart:io';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/constants.dart';

class StudentDiaryScreen extends StatefulWidget {
  const StudentDiaryScreen({super.key});

  @override
  State<StudentDiaryScreen> createState() => _StudentDiaryScreenState();
}

class _StudentDiaryScreenState extends State<StudentDiaryScreen> {
  bool loading = true;
  String? error;
  List<dynamic> diaryList = [];
  int? expandedIndex;

  @override
  void initState() {
    super.initState();
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

      final res = await http.get(
        Uri.parse('$baseUrl/diaries/student/feed/list'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data is Map && data['data'] is List) {
          setState(() {
            diaryList = data['data'] as List<dynamic>;
          });
        } else if (data is List) {
          // Fallback if API returns array directly
          setState(() {
            diaryList = data;
          });
        } else {
          setState(() => error = "Invalid data format from server");
        }
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No file URL provided')));
      return;
    }

    String encodedUrl = rawUrl;
    // If the backend returns relative paths, attempt to make absolute using baseUrl
    if (!rawUrl.startsWith('http')) {
      encodedUrl = baseUrl.replaceAll(RegExp(r'\/$'), '') + '/' + rawUrl.replaceAll(RegExp(r'^\/'), '');
    }

    try {
      // Ask for storage permission (Android)
      if (Platform.isAndroid) {
        final storageStatus = await Permission.storage.request();
        final manageStatus = await Permission.manageExternalStorage.status;
        if (!storageStatus.isGranted && !manageStatus.isGranted) {
          // Try request manage if available (Android 11+)
          await Permission.manageExternalStorage.request();
        }
        if (!await Permission.storage.isGranted && !await Permission.manageExternalStorage.isGranted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Storage permission denied')));
          return;
        }
      }

      final dir = Platform.isAndroid
          ? await getExternalStorageDirectory()
          : await getApplicationDocumentsDirectory();

      if (dir == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot access storage directory')));
        return;
      }

      // Create folder 'StudentApp' inside external storage for easier access
      final saveDir = Directory('${dir.path}/StudentApp');
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      final savePath = '${saveDir.path}/$fileName';

      final dio = Dio();

      // Show a simple progress indicator dialog while downloading
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => DownloadProgressDialog(),
      );

      final response = await dio.download(
        encodedUrl,
        savePath,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          // Dio 5: timeouts are Durations
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 2),
        ),
        onReceiveProgress: (received, total) {
          // you can pass progress to dialog via setState or similar.
          // For simplicity we ignore live progress here (dialog is just an indeterminate spinner).
        },
      );

      // Close progress dialog
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (!mounted) return;
        // Success dialog with open option
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('File downloaded'),
            content: Text(fileName),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  final file = File(savePath);
                  if (await file.exists()) {
                    await OpenFilex.open(savePath);
                  } else {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File not found')));
                  }
                },
                child: const Text('Open'),
              ),
            ],
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: ${response.statusCode}')));
      }
    } catch (e, st) {
      debugPrint('Download error: $e\n$st');
      if (!mounted) return;
      // Close progress dialog if open
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  Widget _buildAttachmentButton(Map<String, dynamic> a) {
    final url = (a['url'] ?? a['filePath'] ?? a['file'] ?? a['path'] ?? '').toString();
    final name = (a['name'] ?? a['fileName'] ?? a['filename'] ?? url.split('/').last).toString();
    return TextButton.icon(
      onPressed: url.isEmpty ? null : () => handleDownload(url, name),
      icon: const Icon(Icons.download_rounded),
      label: Text(name, overflow: TextOverflow.ellipsis),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diaries'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Back',
        ),
      ),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : (error != null)
                ? Center(child: Text(error!, style: const TextStyle(color: Colors.red)))
                : RefreshIndicator(
                    onRefresh: _fetchDiaries,
                    child: diaryList.isEmpty
                        ? ListView(
                            // must return a scrollable widget for RefreshIndicator
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
                              final attachments = (d['attachments'] is List) ? List<Map<String, dynamic>>.from(d['attachments']) : <Map<String, dynamic>>[];

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                                                  child: Icon(_typeIcon(type), color: Colors.indigo),
                                                ),
                                                const SizedBox(width: 12),
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      d['title']?.toString() ?? 'Untitled',
                                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      _formatDate(d['date']?.toString()),
                                                      style: const TextStyle(color: Colors.black54, fontSize: 12),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.indigo),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        AnimatedCrossFade(
                                          firstChild: Text(
                                            (d['content'] ?? '').toString().length > 120 ? '${d['content'].toString().substring(0, 120)}...' : (d['content'] ?? '').toString(),
                                            style: const TextStyle(color: Colors.black87),
                                          ),
                                          secondChild: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text((d['content'] ?? '').toString(), style: const TextStyle(color: Colors.black87)),
                                              if (attachments.isNotEmpty) const SizedBox(height: 8),
                                              if (attachments.isNotEmpty)
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    const Text('Attachments:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
                                                    const SizedBox(height: 6),
                                                    ...attachments.map((a) => _buildAttachmentButton(Map<String, dynamic>.from(a))).toList(),
                                                  ],
                                                ),
                                              const SizedBox(height: 10),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  ElevatedButton.icon(
                                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, minimumSize: const Size(120, 40)),
                                                    onPressed: () {
                                                      // Acknowledge action: call API if required
                                                      // For now just show a small confirmation
                                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Acknowledged')));
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
                                          crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                                          duration: const Duration(milliseconds: 200),
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
    );
  }
}

/// Simple indeterminate download progress dialog
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
