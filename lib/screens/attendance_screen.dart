import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../widgets/student_drawer_menu.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  Map<DateTime, String> attendanceData = {};
  Set<DateTime> holidayDates = {};
  bool loading = true;

  int present = 0, absent = 0, leave = 0;
  DateTime? selectedDate;
  String? selectedStatus;

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  Future<void> fetchData() async {
    setState(() => loading = true);
    await Future.wait([
      fetchAttendance(),
      fetchHolidays(),
    ]);
    setState(() => loading = false);
  }

  Future<void> fetchAttendance() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';
    final response = await http.get(
      Uri.parse('https://erp.sirhindpublicschool.com:3000/attendance/student/me'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      Map<DateTime, String> tempMap = {};
      int p = 0, a = 0, l = 0;

      for (var entry in data) {
        DateTime date = DateTime.parse(entry['date']);
        String status = entry['status'];
        tempMap[date] = status;
        if (status == 'present') p++;
        if (status == 'absent') a++;
        if (status == 'leave') l++;
      }

      setState(() {
        attendanceData = tempMap;
        present = p;
        absent = a;
        leave = l;
      });
    }
  }

  Future<void> fetchHolidays() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';
    final response = await http.get(
      Uri.parse('https://erp.sirhindpublicschool.com:3000/holidays'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      Set<DateTime> temp = {};

      for (var entry in data) {
        DateTime date = DateTime.parse(entry['date']);
        temp.add(date);
      }

      setState(() => holidayDates = temp);
    }
  }

  Widget _buildStatusMarker(DateTime day) {
    String? status = attendanceData[day];
    bool isHoliday = holidayDates.contains(day);

    if (isHoliday) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${day.day}', style: const TextStyle(color: Colors.black)),
          const SizedBox(height: 2),
          Icon(Icons.celebration, color: Colors.orange, size: 12),
        ],
      );
    }

    if (status == null) {
      return Center(
        child: Text('${day.day}', style: const TextStyle(color: Colors.black)),
      );
    }

    Color dotColor = Colors.grey;
    if (status == 'present') dotColor = Colors.green;
    if (status == 'absent') dotColor = Colors.red;
    if (status == 'leave') dotColor = Colors.orange;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('${day.day}', style: const TextStyle(color: Colors.black)),
        const SizedBox(height: 2),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        )
      ],
    );
  }

  void _handleDayPressed(DateTime day, DateTime _) {
    setState(() {
      selectedDate = day;
      selectedStatus = attendanceData[day]?.toUpperCase() ??
          (holidayDates.contains(day) ? 'HOLIDAY' : 'No Record');
    });
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              DateFormat('EEEE, MMMM d, yyyy').format(day),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text('Status: $selectedStatus', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async => await fetchData();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1976D2),
        elevation: 6,
        shadowColor: Colors.black.withOpacity(0.3),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white, size: 26),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        centerTitle: true,
        title: const Text('Attendance', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: Colors.white)),
      ),
      drawer: const StudentDrawerMenu(),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildSummaryCard('Present', present, Colors.green),
                        _buildSummaryCard('Absent', absent, Colors.red),
                        _buildSummaryCard('Leave', leave, Colors.orange),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TableCalendar(
                      focusedDay: DateTime.now(),
                      firstDay: DateTime.utc(2022, 1, 1),
                      lastDay: DateTime.utc(2030, 12, 31),
                      calendarFormat: CalendarFormat.month,
                      startingDayOfWeek: StartingDayOfWeek.monday,
                      headerStyle: const HeaderStyle(
                        titleCentered: true,
                        formatButtonVisible: false,
                        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                        leftChevronIcon: Icon(Icons.arrow_back_ios, color: Colors.indigo),
                        rightChevronIcon: Icon(Icons.arrow_forward_ios, color: Colors.indigo),
                      ),
                      daysOfWeekStyle: const DaysOfWeekStyle(
                        weekdayStyle: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                        weekendStyle: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                      calendarStyle: const CalendarStyle(
                        defaultTextStyle: TextStyle(color: Colors.black),
                        weekendTextStyle: TextStyle(color: Colors.red),
                        todayDecoration: BoxDecoration(color: Colors.indigo, shape: BoxShape.circle),
                        selectedDecoration: BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                        outsideDaysVisible: false,
                      ),
                      calendarBuilders: CalendarBuilders(
                        defaultBuilder: (context, day, _) => _buildStatusMarker(day),
                        todayBuilder: (context, day, _) => _buildStatusMarker(day),
                        selectedBuilder: (context, day, _) => _buildStatusMarker(day),
                      ),
                      onDaySelected: _handleDayPressed,
                    ),
                    const SizedBox(height: 20),
                    _buildLegend(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSummaryCard(String label, int count, Color color) {
    return Card(
      elevation: 4,
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            Text('$count', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 20,
        children: [
          _legendItem('Present', Colors.green),
          _legendItem('Absent', Colors.red),
          _legendItem('Leave', Colors.orange),
          _legendItem('Holiday', Colors.yellow),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label),
      ],
    );
  }
}
