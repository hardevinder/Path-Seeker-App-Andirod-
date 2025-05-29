import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pie_chart/pie_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';
// import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // 🔥 Firestore
import '../widgets/student_app_bar.dart';
import '../widgets/student_bottom_bar.dart'; // ⬅️ Add this
import 'package:open_filex/open_filex.dart';




class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String studentName = '';
  String currentUserId = '';
  String username = '';
  bool loading = true;
  int unreadCount = 0;

  final ScrollController _scrollController = ScrollController();

  List assignments = [];
  List fees = [];
  List attendance = [];

  @override
  void initState() {
    super.initState();
    loadUser();
  }

  Future<void> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    username = prefs.getString('username') ?? '';
    currentUserId = prefs.getString('currentUserId') ?? '';

    if (username.isEmpty) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    await fetchDashboardData();
    listenToUnreadMessages();
  }

  Future<void> fetchDashboardData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken') ?? '';

      final feeRes = await http.get(
        Uri.parse('https://erp.sirhindpublicschool.com:3000/StudentsApp/admission/$username/fees'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final assignRes = await http.get(
        Uri.parse('https://erp.sirhindpublicschool.com:3000/student-assignments/student'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final attRes = await http.get(
        Uri.parse('https://erp.sirhindpublicschool.com:3000/attendance/student/me'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final feeData = jsonDecode(feeRes.body);
      final assignData = jsonDecode(assignRes.body);
      final attData = jsonDecode(attRes.body);

      setState(() {
        studentName = feeData['name'];
        fees = feeData['feeDetails'] ?? [];
        attendance = attData ?? [];
        assignments = (assignData['assignments'] ?? []).take(3).toList();
        loading = false;
      });
    } catch (e) {
      debugPrint('Dashboard Error: $e');
      setState(() => loading = false);
    }
  }

  void listenToUnreadMessages() {
    FirebaseFirestore.instance.collection('chats').snapshots().listen((snapshot) {
      int count = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final unreadMap = data['unreadCounts'] ?? {};
        final value = unreadMap[currentUserId];
        if (value is int && value > 0) {
          count += value;
        }
      }

      if (mounted) {
        setState(() {
          unreadCount = count;
        });
      }
    });
  }

  double get totalFee => fees.fold(0.0, (sum, f) => sum + (f['originalFeeDue'] ?? 0));
  double get totalDue => fees.fold(0.0, (sum, f) => sum + (f['finalAmountDue'] ?? 0));
  double get feePaid => totalFee - totalDue;

  int get present => attendance.where((a) => a['status'] == 'present').length;
  int get absent => attendance.where((a) => a['status'] == 'absent').length;
  int get leave => attendance.where((a) => a['status'] == 'leave').length;


Future<void> handleDownload(String? filePath) async {
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
  final fileName = encodedUrl.split('/').last;

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
                debugPrint('📂 OpenFilex result: ${result.message}');
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



  int selectedTabIndex = 0; // For tracking tab state

void onBottomNavTap(int index) {
  setState(() {
    selectedTabIndex = index;
  });

  switch (index) {
    case 0:
      Navigator.pushReplacementNamed(context, '/dashboard');
      break;
    case 1:
      Navigator.pushReplacementNamed(context, '/fee-details');
      break;
    case 2:
      Navigator.pushReplacementNamed(context, '/assignments');
      break;
    case 3:
      Navigator.pushReplacementNamed(context, '/circulars');
      break;
  }
}


  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      // appBar: AppBar(
      //   title: Center(child: Text('Welcome $studentName')),
      //   backgroundColor: Colors.deepPurple,
      // ),
      appBar: StudentAppBar(studentName: studentName, parentContext: context),

      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Fee Summary', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                feeCard('Total', totalFee, Colors.indigo),
                feeCard('Paid', feePaid, Colors.green),
                feeCard('Due', totalDue, Colors.redAccent),
              ],
            ),
            const SizedBox(height: 24), // More space before the label
            const Align(
              alignment: Alignment.center,
              child: Text(
                'Attendance',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16), // Extra space between label and chart
            Center(
              child: PieChart(
                dataMap: {
                  "Present": present.toDouble(),
                  "Absent": absent.toDouble(),
                  "Leave": leave.toDouble(),
                },
                chartType: ChartType.ring,
                baseChartColor: Colors.grey[200]!,
                ringStrokeWidth: 55, // More compact ring
                chartRadius: MediaQuery.of(context).size.width / 3.2, // Smaller chart
                centerText: "",
                legendOptions: const LegendOptions(
                  showLegends: true,
                  legendPosition: LegendPosition.bottom,
                  showLegendsInRow: true,
                  legendTextStyle: TextStyle(fontWeight: FontWeight.bold),
                ),
                chartValuesOptions: const ChartValuesOptions(
                  showChartValues: true,
                  showChartValuesInPercentage: true,
                  showChartValuesOutside: true,
                  showChartValueBackground: false,
                  decimalPlaces: 0,
                ),
              ),
            ),


            const SizedBox(height: 24),
            const Text('Latest Assignments', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            for (int i = 0; i < assignments.length; i++)
              Card(
                color: i % 2 == 0 ? Colors.orange.shade50 : Colors.lightBlue.shade50,
                elevation: 3,
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(assignments[i]['title'],
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      if (assignments[i]['AssignmentFiles'] != null &&
                          assignments[i]['AssignmentFiles'].isNotEmpty)
                        for (var file in assignments[i]['AssignmentFiles'])
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text(file['fileName'])),
                              TextButton(
                                onPressed: () => handleDownload(file['filePath']),
                                child: const Text("Download"),
                              ),
                            ],
                          )
                      else
                        const Text("No files available"),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: Stack(
        alignment: Alignment.topRight,
        children: [
          FloatingActionButton(
            backgroundColor: Colors.white, // Bright button
            elevation: 5,
            onPressed: () {
              Navigator.pushNamed(context, '/contacts');
            },
            child: const Icon(Icons.chat_bubble_outline, color: Colors.deepPurple), // Purple icon
          ),
          if (unreadCount > 0)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2), // crisp border
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4)
                  ],
                ),
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                child: Text(
                  '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),

      bottomNavigationBar: StudentBottomBar(
        selectedIndex: selectedTabIndex,
        onItemTapped: onBottomNavTap,
      ),


    );
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Widget feeCard(String title, double amount, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.8),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: Column(
          children: [
            Text(title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 4),
            Text('₹${amount.toStringAsFixed(0)}',
                style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
