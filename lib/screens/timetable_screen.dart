import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/student_drawer_menu.dart'; // ✅ Import Drawer

class TimeTableScreen extends StatefulWidget {
  const TimeTableScreen({super.key});

  @override
  State<TimeTableScreen> createState() => _TimeTableScreenState();
}

class _TimeTableScreenState extends State<TimeTableScreen> {
  List timetable = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchTimetable();
  }

  Future<void> fetchTimetable() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      if (token == null) {
        setState(() {
          loading = false;
        });
        return;
      }

      final response = await Dio().get(
        'https://erp.sirhindpublicschool.com:3000/period-class-teacher-subject/student/timetable',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      setState(() {
        timetable = response.data;
        loading = false;
      });
    } catch (e) {
      setState(() {
        loading = false;
      });
      debugPrint('Error fetching timetable: $e');
    }
  }

  Map<String, List<dynamic>> groupByDay() {
    final Map<String, List<dynamic>> grouped = {};
    for (var item in timetable) {
      final day = item['day'] ?? 'Unknown';
      grouped.putIfAbsent(day, () => []).add(item);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final groupedData = groupByDay();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Table'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: const StudentDrawerMenu(), // ✅ Use consistent drawer
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: groupedData.entries.map((entry) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                    const SizedBox(height: 10),
                    ...entry.value.map((period) => Card(
                          elevation: 2,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            leading: const Icon(Icons.schedule),
                            title: Text('Period: ${period['Period']['period_name']}'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Subject: ${period['Subject']['name']}'),
                                Text('Teacher: ${period['Teacher']['name']}'),
                              ],
                            ),
                          ),
                        )),
                    const SizedBox(height: 20),
                  ],
                );
              }).toList(),
            ),
    );
  }
}
