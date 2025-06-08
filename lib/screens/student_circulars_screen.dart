import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

class StudentCircularsScreen extends StatefulWidget {
  const StudentCircularsScreen({super.key});

  @override
  State<StudentCircularsScreen> createState() => _StudentCircularsScreenState();
}

class _StudentCircularsScreenState extends State<StudentCircularsScreen> {
  List<dynamic> circulars = [];
  bool loading = true;
  final String apiUrl = 'https://erp.sirhindpublicschool.com:3000/circulars';

  @override
  void initState() {
    super.initState();
    fetchCirculars();
  }

  Future<void> fetchCirculars() async {
    setState(() => loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      if (token == null) throw Exception('No token found');

      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['circulars'] ?? [];
        items.sort((a, b) => DateTime.parse(b['createdAt'])
            .compareTo(DateTime.parse(a['createdAt'])));
        setState(() {
          circulars = items;
          loading = false;
        });
      } else if (response.statusCode == 401) {
        _handleSessionExpired();
      } else {
        throw Exception('Failed to load circulars');
      }
    } catch (e) {
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching circulars: ${e.toString()}')),
      );
    }
  }

  void _handleSessionExpired() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Session Expired'),
        content: const Text('Please log in again.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
              Navigator.of(context).pushReplacementNamed('/login');
            },
            child: const Text('OK'),
          )
        ],
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url.startsWith('http')
        ? url
        : 'https://erp.sirhindpublicschool.com:3000/$url');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open file')),
      );
    }
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('authToken');
    Navigator.of(context).pushReplacementNamed('/login');
  }

  ListTile _buildDrawerItem(IconData icon, String title, String route) {
    return ListTile(
      leading: Icon(icon, color: Colors.deepPurple),
      title: Text(title),
      onTap: () {
        Navigator.of(context).pop(); // close drawer
        Navigator.pushReplacementNamed(context, route);
      },
    );
  }

  Drawer _buildDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.deepPurple),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.school, color: Colors.deepPurple, size: 30),
                ),
                SizedBox(height: 8),
                Text("Student Menu", style: TextStyle(color: Colors.white, fontSize: 20))
              ],
            ),
          ),
          _buildDrawerItem(Icons.dashboard, 'Dashboard', '/dashboard'),
          _buildDrawerItem(Icons.assignment, 'Assignments', '/assignments'),
          _buildDrawerItem(Icons.calendar_today, 'Time Table', '/timetable'),
          _buildDrawerItem(Icons.money, 'Fee Details', '/fee-details'),
          _buildDrawerItem(Icons.notifications, 'Circulars', '/circulars'),
          _buildDrawerItem(Icons.access_time, 'Attendance', '/attendance'),
          _buildDrawerItem(Icons.event_note, 'Leave Requests', '/leave'),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.deepPurple),
            title: const Text('Logout'),
            onTap: _handleLogout,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Circulars', style: TextStyle(color: Colors.white)),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      drawer: _buildDrawer(context),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: fetchCirculars,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: circulars.length,
                itemBuilder: (context, index) {
                  final item = circulars[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['title'] ?? '',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(item['description'] ?? '',
                              style: const TextStyle(fontSize: 14)),
                          const SizedBox(height: 8),
                          if (item['fileUrl'] != null &&
                              item['fileUrl'].toString().isNotEmpty)
                            ElevatedButton(
                              onPressed: () => _launchURL(item['fileUrl']),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue),
                              child: const Text('View Circular'),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            'Published: ${DateFormat('dd MMM yyyy').format(DateTime.parse(item['createdAt']))}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
