import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/student_drawer_menu.dart';

class StudentAssignmentsScreen extends StatefulWidget {
  const StudentAssignmentsScreen({super.key});

  @override
  State<StudentAssignmentsScreen> createState() => _StudentAssignmentsScreenState();
}

class _StudentAssignmentsScreenState extends State<StudentAssignmentsScreen> {
  List<dynamic> assignments = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    fetchAssignments();
  }

  Future<void> fetchAssignments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("authToken");

      final response = await Dio().get(
        "https://erp.sirhindpublicschool.com:3000/student-assignments/student",
        options: Options(
          headers: { "Authorization": "Bearer $token" },
        ),
      );

      setState(() {
        assignments = response.data['assignments'] ?? [];
        loading = false;
      });
    } catch (e) {
      print("Error: $e");
      setState(() {
        error = "Failed to load assignments";
        loading = false;
      });
    }
  }

  String formatDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    return DateFormat('MMM dd, yyyy – hh:mm a').format(date);
  }

  Future<void> handleDownload(String? filePath, String fileName) async {
    if (filePath == null || filePath.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file path provided')),
      );
      return;
    }

    final rawUrl = filePath.startsWith('http')
        ? filePath
        : 'https://erp.sirhindpublicschool.com:3000/$filePath';

    final encodedUrl = Uri.encodeFull(rawUrl);

    try {
      final storage = await Permission.storage.request();
      final manage = await Permission.manageExternalStorage.request();

      if (!storage.isGranted && !manage.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage permission denied')),
        );
        return;
      }

      final dir = await getExternalStorageDirectory();
      final savePath = '${dir!.path}/$fileName';

      final dio = Dio();
      await dio.download(encodedUrl, savePath);

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('✅ File Downloaded'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.download_done_rounded, size: 48, color: Colors.green),
              const SizedBox(height: 12),
              Text(fileName, textAlign: TextAlign.center),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                if (await File(savePath).exists()) {
                  final result = await OpenFilex.open(savePath);
                  debugPrint('📂 OpenFilex result: \${result.message}');
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('File does not exist')),
                  );
                }
              },
              child: const Text('Open File'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Download error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download file\nError: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Assignments"),
        centerTitle: true,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: const StudentDrawerMenu(),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : assignments.isEmpty
                  ? const Center(child: Text("No assignments available."))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: assignments.length,
                      itemBuilder: (context, index) {
                        final a = assignments[index];
                        final files = a['AssignmentFiles'] ?? [];
                        final subject = a['Subject']?['name'] ?? a['subject']?['name'] ?? "N/A";

                        return Card(
                          elevation: 3,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a['title'] ?? "No Title", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Text(a['content'] ?? "", style: const TextStyle(fontSize: 15)),
                                const SizedBox(height: 6),
                                Text("Subject: $subject", style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
                                Text("Assigned on: \${formatDate(a['createdAt'])}", style: const TextStyle(fontSize: 13)),
                                const SizedBox(height: 8),
                                if (files.isNotEmpty)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("📎 Attachments:", style: TextStyle(fontWeight: FontWeight.bold)),
                                      ...files.map<Widget>((file) {
                                        final path = file['filePath'];
                                        final name = file['fileName'] ?? "Download File";
                                        return TextButton(
                                          onPressed: () => handleDownload(path, name),
                                          child: Text(name),
                                        );
                                      }).toList(),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
