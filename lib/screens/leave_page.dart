import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LeavePage extends StatefulWidget {
  @override
  _LeavePageState createState() => _LeavePageState();
}

class _LeavePageState extends State<LeavePage> {
  final String apiUrl = "https://erp.sirhindpublicschool.com:3000";

  List<dynamic> leaveRequests = [];
  String selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String reason = "";
  String? token;
  final TextEditingController reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadToken();
  }

  Future<void> loadToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? storedToken = prefs.getString("authToken");
    if (storedToken != null) {
      setState(() {
        token = storedToken;
      });
      fetchLeaveRequests();
    }
  }

  Future<void> fetchLeaveRequests() async {
    if (token == null) return;
    try {
      final response = await http.get(
        Uri.parse("$apiUrl/leave/student/me"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          leaveRequests = data is List ? data : [];
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not fetch leave requests")),
      );
    }
  }

  Future<void> handleCreateLeave() async {
    if (token == null) return;
    try {
      final response = await http.post(
        Uri.parse("$apiUrl/leave"),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json"
        },
        body: json.encode({"date": selectedDate, "reason": reason}),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Leave request submitted")),
        );
        setState(() {
          reason = "";
          reasonController.clear();
          selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
        });
        fetchLeaveRequests();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to create leave request")),
      );
    }
  }

  List<dynamic> getLatestLeaves() {
    List<dynamic> sorted = List.from(leaveRequests);
    sorted.sort((a, b) =>
        DateTime.parse(b['date']).compareTo(DateTime.parse(a['date'])));
    return sorted.take(4).toList();
  }

  void showCalendarBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: TableCalendar(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: DateTime.parse(selectedDate),
          selectedDayPredicate: (day) =>
              DateFormat('yyyy-MM-dd').format(day) == selectedDate,
          onDaySelected: (selected, focused) {
            setState(() {
              selectedDate = DateFormat('yyyy-MM-dd').format(selected);
            });
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        title: Text(
          "Apply for Leave",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white, // ✅ Set title text color to white
          ),
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),

      drawer: _buildDrawer(context),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.deepPurple.shade50, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Select Date",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              GestureDetector(
                onTap: showCalendarBottomSheet,
                child: Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.deepPurple),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(selectedDate, style: TextStyle(fontSize: 16)),
                      Icon(Icons.calendar_today, color: Colors.deepPurple)
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16),
              Text("Reason for Leave",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: "Enter reason",
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (val) => reason = val,
              ),
              SizedBox(height: 16),
              Center(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: handleCreateLeave,
                  icon: Icon(Icons.send),
                  label: Text("Submit Leave Request"),
                ),
              ),
              SizedBox(height: 20),
              if (leaveRequests.isNotEmpty)
                Text("Your Latest Leave Requests",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ...getLatestLeaves().map((item) => Card(
                    margin: EdgeInsets.symmetric(vertical: 8),
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading:
                          Icon(Icons.event_note, color: Colors.deepPurple),
                      title: Text(item['date'],
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(item['reason'] ?? "No reason"),
                      trailing: Text(
                        item['status'] ?? "Pending",
                        style: TextStyle(
                          color: item['status'] == "Approved"
                              ? Colors.green
                              : Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ))
            ],
          ),
        ),
      ),
    );
  }

  Drawer _buildDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Colors.deepPurple),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  child:
                      Icon(Icons.school, color: Colors.deepPurple, size: 30),
                ),
                SizedBox(height: 8),
                Text("Student Menu",
                    style: TextStyle(color: Colors.white, fontSize: 20))
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
          _buildDrawerItem(Icons.logout, 'Logout', '/login'),
        ],
      ),
    );
  }

  ListTile _buildDrawerItem(IconData icon, String title, String route) {
    return ListTile(
      leading: Icon(icon, color: Colors.deepPurple),
      title: Text(title),
      onTap: () => Navigator.pushReplacementNamed(context, route),
    );
  }
}
