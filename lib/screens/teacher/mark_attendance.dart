// lib/screens/teacher/mark_attendance.dart
// Teacher-only attendance marking screen with colorful UI and auto-scrolling summary cards
// (Fixed: safe PageController initialization to avoid LateInitializationError)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/constants.dart';

class Student {
  final int id;
  final String name;
  final int classId;

  Student({required this.id, required this.name, required this.classId});

  factory Student.fromJson(Map<String, dynamic> json) {
    return Student(
      id: json['id'],
      name: json['name'] ?? "${json['first_name'] ?? ''} ${json['last_name'] ?? ''}",
      classId: json['class_id'] ?? 0,
    );
  }
}

class MarkAttendanceScreen extends StatefulWidget {
  const MarkAttendanceScreen({Key? key}) : super(key: key);

  @override
  State<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends State<MarkAttendanceScreen> {
  final List<String> statuses = ['present', 'absent', 'late', 'leave'];
  List<Student> students = [];
  Map<int, String> attendance = {};
  Map<int, int> recordIds = {};
  List<dynamic> holidays = [];

  DateTime selectedDate = DateTime.now();
  bool loading = false;
  bool initialLoading = true;
  String mode = 'create';
  int? teacherClassId;

  String searchQuery = '';

  // Carousel (nullable to avoid LateInitializationError)
  PageController? _pageController;
  Timer? _carouselTimer;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.78);
    _startCarousel();
    _loadInitial();
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _pageController?.dispose();
    super.dispose();
  }

  void _startCarousel() {
    _carouselTimer?.cancel();
    _carouselTimer = Timer.periodic(const Duration(seconds: 3), (t) {
      if (_pageController != null && _pageController!.hasClients) {
        final pageCount = statuses.length + 1; // plus total card
        _currentPage = (_currentPage + 1) % pageCount;
        _pageController!.animateToPage(_currentPage,
            duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
      }
    });
  }

  Future<void> _loadInitial() async {
    setState(() => initialLoading = true);
    await Future.wait([_fetchStudents(), _fetchHolidays()]);
    await _fetchAttendanceForDate(_formatDate(selectedDate));
    setState(() => initialLoading = false);
  }

  String _formatDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<Map<String, String>> _authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ??
        prefs.getString('access_token') ??
        prefs.getString('authToken') ??
        prefs.getString('jwt');

    final headers = <String, String>{'Content-Type': 'application/json', 'Accept': 'application/json'};
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  Future<void> _handleUnauthorized() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('access_token');
    await prefs.remove('authToken');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired. Please login again.')));
    Navigator.of(context).pushReplacementNamed('/login');
  }

  Future<void> _fetchStudents() async {
    try {
      final headers = await _authHeaders();
      if (!headers.containsKey('Authorization')) {
        await _handleUnauthorized();
        return;
      }
      final resp = await http.get(Uri.parse('$baseUrl/incharges/students'), headers: headers);
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final fetched = <Student>[];
        if (data is Map && data['students'] is List) {
          fetched.addAll((data['students'] as List).map((e) => Student.fromJson(e)).toList());
        } else if (data is List) {
          fetched.addAll(data.map((e) => Student.fromJson(e)).toList());
        }
        setState(() {
          students = fetched;
          if (students.isNotEmpty) teacherClassId = students.first.classId;
          attendance = {for (var s in students) s.id: 'present'};
        });
      } else if (resp.statusCode == 401) {
        await _handleUnauthorized();
      } else {
        _showError('Failed to fetch students: ${resp.statusCode}');
      }
    } catch (e) {
      _showError('Error fetching students: $e');
    }
  }

  Future<void> _fetchHolidays() async {
    try {
      final headers = await _authHeaders();
      final resp = await http.get(Uri.parse('$baseUrl/holidays'), headers: headers);
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data is List) setState(() => holidays = data);
        else if (data is Map && data['holidays'] is List) setState(() => holidays = data['holidays']);
      } else if (resp.statusCode == 401) {
        await _handleUnauthorized();
      }
    } catch (_) {}
  }

  Future<void> _fetchAttendanceForDate(String date) async {
    try {
      final headers = await _authHeaders();
      if (!headers.containsKey('Authorization')) {
        await _handleUnauthorized();
        return;
      }
      final resp = await http.get(Uri.parse('$baseUrl/attendance/date/$date'), headers: headers);
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data is List && data.isNotEmpty) {
          final att = <int, String>{};
          final rec = <int, int>{};
          for (var a in data) {
            final sid = a['studentId'] ?? a['student_id'] ?? a['student'];
            if (sid == null) continue;
            att[sid] = (a['status'] ?? 'present') as String;
            if (a['id'] != null) rec[sid] = a['id'];
          }
          setState(() {
            attendance = att;
            recordIds = rec;
            mode = 'edit';
          });
        } else {
          setState(() {
            mode = 'create';
            attendance = {for (var s in students) s.id: 'present'};
            recordIds = {};
          });
        }
      } else if (resp.statusCode == 401) {
        await _handleUnauthorized();
      } else {
        setState(() {
          mode = 'create';
          attendance = {for (var s in students) s.id: 'present'};
          recordIds = {};
        });
      }
    } catch (_) {
      setState(() {
        mode = 'create';
        attendance = {for (var s in students) s.id: 'present'};
        recordIds = {};
      });
    }
  }

  void _showError(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _onStatusChange(int studentId, String status) {
    setState(() => attendance[studentId] = status);
  }

  void _markAll(String status) {
    setState(() => attendance = {for (var s in students) s.id: status});
  }

  Future<void> _submit() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirm'),
        content: Text(
          mode == 'create'
              ? "Submit attendance for ${DateFormat.yMMMMd().format(selectedDate)}?"
              : "Update attendance for ${DateFormat.yMMMMd().format(selectedDate)}?",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yes')),
        ],
      ),
    );

    if (confirm != true) return;
    setState(() => loading = true);

    try {
      final headers = await _authHeaders();
      if (!headers.containsKey('Authorization')) {
        await _handleUnauthorized();
        return;
      }

      Future<http.Response> send(Student s, [int? id]) {
        final body = json.encode({
          'studentId': s.id,
          'status': attendance[s.id] ?? 'present',
          'remarks': '',
          'date': _formatDate(selectedDate),
        });
        if (id != null) {
          return http.put(Uri.parse('$baseUrl/attendance/$id'), body: body, headers: headers);
        }
        return http.post(Uri.parse('$baseUrl/attendance'), body: body, headers: headers);
      }

      final futures = students.map((s) => send(s, recordIds[s.id])).toList();
      final results = await Future.wait(futures);
      final failed = results.where((r) => r.statusCode >= 400).toList();
      if (failed.isNotEmpty) {
        if (failed.any((r) => r.statusCode == 401)) {
          await _handleUnauthorized();
          return;
        }
        _showError('Some records failed.');
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Attendance ${mode == 'create' ? 'saved' : 'updated'}")));
        await _fetchAttendanceForDate(_formatDate(selectedDate));
      }
    } catch (e) {
      _showError('Error: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  Color _statusColorStr(String status) {
    switch (status) {
      case 'absent':
        return Colors.red.shade600;
      case 'late':
        return Colors.deepOrange;
      case 'leave':
        return Colors.indigo;
      default:
        return Colors.green.shade700;
    }
  }

  Map<String, int> get _summaryCounts {
    final map = {for (var s in statuses) s: 0, 'total': students.length};
    for (var s in students) {
      final st = attendance[s.id] ?? 'present';
      if (map.containsKey(st)) map[st] = map[st]! + 1;
    }
    return map;
  }

  double _percentage(int part, int total) {
    if (total == 0) return 0.0;
    return (part / total) * 100;
  }

  Widget _buildSummaryCard(String title, int count, Color color, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: MediaQuery.of(context).size.width * 0.72,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.95), color.withOpacity(0.6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: color.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 6))],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$count', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              if (subtitle != null) Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (students.isEmpty) ? 0 : (count / (students.length)),
            backgroundColor: Colors.white24,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            minHeight: 6,
          ),
        ]),
      ),
    );
  }

  List<Student> get _filteredStudents {
    final q = searchQuery.trim().toLowerCase();
    if (q.isEmpty) return students;
    return students.where((s) => s.name.toLowerCase().contains(q)).toList();
  }

  Widget _buildStudentTile(Student s, int index) {
    final stStatus = attendance[s.id] ?? 'present';
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          CircleAvatar(radius: 22, child: Text('${index + 1}')),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: statuses.map((status) {
                  final selected = stStatus == status;
                  return ChoiceChip(
                    label: Text(status.toUpperCase()),
                    selected: selected,
                    onSelected: (_) => _onStatusChange(s.id, status),
                    selectedColor: _statusColorStr(status).withOpacity(0.95),
                    backgroundColor: Colors.grey.shade200,
                    labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87, fontSize: 12),
                  );
                }).toList(),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: _statusColorStr(stStatus).withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(stStatus.toUpperCase(), style: TextStyle(color: _statusColorStr(stStatus), fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (initialLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final formatted = DateFormat.yMMMMd().format(selectedDate);
    final today = DateTime.now();
    bool isFuture = selectedDate.isAfter(DateTime(today.year, today.month, today.day));

    final holidayForDate = holidays.firstWhere(
      (h) =>
          (h['date'] == _formatDate(selectedDate)) &&
          (teacherClassId != null && h['class'] != null && (h['class']['id'].toString() == teacherClassId.toString())),
      orElse: () => null,
    );

    final sums = _summaryCounts;
    final total = sums['total'] ?? students.length;

    final cardItems = <Widget>[
      _buildSummaryCard('Total Students', total, Colors.teal, subtitle: '${total > 0 ? 100 : 0}%'),
      for (var s in statuses)
        _buildSummaryCard(
          '${s[0].toUpperCase()}${s.substring(1)}',
          sums[s] ?? 0,
          _statusColorStr(s),
          subtitle: '${_percentage((sums[s] ?? 0), total).toStringAsFixed(1)}%',
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mark Attendance'),
        actions: [IconButton(onPressed: _loadInitial, icon: const Icon(Icons.refresh))],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(84),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: defaultPadding, vertical: 8),
            child: Column(children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () async {
                      setState(() => selectedDate = selectedDate.subtract(const Duration(days: 1)));
                      await _fetchAttendanceForDate(_formatDate(selectedDate));
                    },
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setState(() => selectedDate = picked);
                          await _fetchAttendanceForDate(_formatDate(picked));
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.white24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(formatted, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(DateFormat.EEEE().format(selectedDate), style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () async {
                      setState(() => selectedDate = selectedDate.add(const Duration(days: 1)));
                      await _fetchAttendanceForDate(_formatDate(selectedDate));
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadInitial,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(defaultPadding),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Carousel of summary cards (guarded by null check)
              SizedBox(
                height: 140,
                child: _pageController == null
                    ? const Center(child: CircularProgressIndicator())
                    : PageView.builder(
                        controller: _pageController,
                        itemCount: cardItems.length,
                        onPageChanged: (p) => setState(() => _currentPage = p),
                        itemBuilder: (context, idx) {
                          return cardItems[idx];
                        },
                      ),
              ),

              const SizedBox(height: 12),

              // Info cards (future / sunday / holiday)
              if (isFuture)
                Card(
                  color: Colors.blue.shade50,
                  child: const Padding(padding: EdgeInsets.all(12), child: Text('Attendance cannot be marked for future dates.')),
                ),
              if (selectedDate.weekday == DateTime.sunday)
                Card(
                  color: Colors.yellow.shade50,
                  child: Padding(padding: const EdgeInsets.all(12), child: Text("$formatted is Sunday. No attendance required.")),
                ),
              if (holidayForDate != null)
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(padding: const EdgeInsets.all(12), child: Text("$formatted is a holiday: ${holidayForDate['description'] ?? ''}")),
                ),

              const SizedBox(height: 12),

              // Search + mark all
              Row(children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => searchQuery = v),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search student name',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (val) {
                    if (val.startsWith('mark_')) _markAll(val.split('_')[1]);
                  },
                  itemBuilder: (_) => statuses
                      .map((s) => PopupMenuItem(value: 'mark_$s', child: Text('Mark All ${s[0].toUpperCase()}${s.substring(1)}')))
                      .toList(),
                ),
              ]),

              const SizedBox(height: 12),

              // Legend
              Wrap(spacing: 14, runSpacing: 8, children: statuses.map((s) {
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: _statusColorStr(s), borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 6),
                  Text(s[0].toUpperCase() + s.substring(1)),
                ]);
              }).toList()),

              const SizedBox(height: 12),

              // Student list
              ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: _filteredStudents.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final s = _filteredStudents[i];
                  return _buildStudentTile(s, i);
                },
              ),

              const SizedBox(height: 80),
              Center(child: Text('Powered by $appName', style: const TextStyle(fontSize: 12, color: Colors.grey))),
            ]),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (isFuture || selectedDate.weekday == DateTime.sunday || holidayForDate != null || loading) ? null : _submit,
        label: loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(mode == 'create' ? 'Submit' : 'Update'),
        icon: const Icon(Icons.save),
      ),
    );
  }
}
