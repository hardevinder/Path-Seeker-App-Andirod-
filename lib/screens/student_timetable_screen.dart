// File: lib/screens/student_timetable_screen.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/constants.dart'; // expects baseUrl constant

class StudentTimetableScreen extends StatefulWidget {
  const StudentTimetableScreen({super.key});

  @override
  State<StudentTimetableScreen> createState() => _StudentTimetableScreenState();
}

class _StudentTimetableScreenState extends State<StudentTimetableScreen> {
  bool isLoading = true;
  String? error;
  List<dynamic> periods = [];
  List<dynamic> timetable = [];
  List<dynamic> holidays = [];
  Map<String, List<dynamic>> studentSubs = {};
  Map<String, Map<dynamic, List<dynamic>>> grid = {};

  // Student & family
  String? token;
  List<String> roles = [];
  bool isStudent = false;
  bool isParent = false;
  bool canSeeStudentSwitcher = false;
  Map<String, dynamic>? family;
  String activeStudentAdmission = '';
  String loggedInAdmission = '';

  // Week state
  final List<String> days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  late DateTime currentMonday;
  int mobileOpenIdx = 0;
  bool showNoMatchHint = false;

  @override
  void initState() {
    super.initState();
    currentMonday = _computeCurrentMonday(DateTime.now());
    _loadRolesAndFamily().then((_) => _loadAll());
  }

  // ------------------ Role + Family Logic ------------------
  Future<void> _loadRolesAndFamily() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('authToken');

    // Load roles
    try {
      final stored = prefs.getString('roles');
      if (stored != null) {
        roles = (json.decode(stored) as List).map((e) => e.toString().toLowerCase()).toList();
      } else {
        final single = prefs.getString('userRole');
        if (single != null) roles = [single.toLowerCase()];
      }
    } catch (_) {}

    isStudent = roles.contains('student');
    isParent = roles.contains('parent');
    canSeeStudentSwitcher = isStudent || isParent;

    // Family info
    try {
      final rawFamily = prefs.getString('family');
      family = rawFamily != null ? json.decode(rawFamily) : null;
    } catch (_) {}

    activeStudentAdmission = prefs.getString('activeStudentAdmission') ??
        prefs.getString('username') ??
        '';
    loggedInAdmission = prefs.getString('username') ?? '';
  }

  // ------------------ Core Helpers ------------------
  DateTime _computeCurrentMonday(DateTime forDate) {
    final dayIndex = (forDate.weekday + 6) % 7;
    return DateTime(forDate.year, forDate.month, forDate.day - dayIndex);
  }

  String _formatDateYmd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Future<String> _resolveTimetableUrl() async {
    if (!isStudent || (activeStudentAdmission.isNotEmpty && activeStudentAdmission != loggedInAdmission)) {
      final adm = Uri.encodeComponent(activeStudentAdmission);
      return '$baseUrl/period-class-teacher-subject/timetable/by-admission/$adm';
    } else {
      return '$baseUrl/period-class-teacher-subject/student/timetable';
    }
  }

  Map<String, String> _weekDatesMap() {
    final map = <String, String>{};
    for (var i = 0; i < days.length; i++) {
      final d = DateTime(currentMonday.year, currentMonday.month, currentMonday.day + i);
      map[days[i]] = _formatDateYmd(d);
    }
    return map;
  }

  // ------------------ API Calls ------------------
  Future<void> _loadAll() async {
    setState(() {
      isLoading = true;
      error = null;
      showNoMatchHint = false;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString('authToken');
      if (baseUrl.isEmpty || token == null) {
        setState(() => isLoading = false);
        return;
      }

      final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
      final timetableUrl = await _resolveTimetableUrl();

      final responses = await Future.wait([
        http.get(Uri.parse('$baseUrl/periods'), headers: headers),
        http.get(Uri.parse(timetableUrl), headers: headers),
        http.get(Uri.parse('$baseUrl/holidays'), headers: headers),
      ]);

      // periods
      final pRes = responses[0];
      periods = (pRes.statusCode == 200)
          ? (json.decode(pRes.body) is List
              ? json.decode(pRes.body)
              : (json.decode(pRes.body)['periods'] ?? []))
          : [];

      // timetable
      final tRes = responses[1];
      if (tRes.statusCode == 200) {
        final parsed = json.decode(tRes.body);
        if (parsed is List) {
          timetable = parsed;
        } else if (parsed is Map) {
          timetable = parsed['timetable'] ?? parsed['data'] ?? [];
        }
      } else {
        timetable = [];
      }

      // holidays
      final hRes = responses[2];
      holidays = (hRes.statusCode == 200)
          ? (json.decode(hRes.body) is List
              ? json.decode(hRes.body)
              : (json.decode(hRes.body)['holidays'] ?? []))
          : [];

      await _fetchSubsForWeek(token!);
      _buildGrid();

      final todayStr = _formatDateYmd(DateTime.now());
      final idx = days.indexWhere((d) => _weekDatesMap()[d] == todayStr);
      setState(() {
        mobileOpenIdx = idx >= 0 ? idx : 0;
        isLoading = false;
      });
    } catch (e, st) {
      if (kDebugMode) debugPrint('loadAll error: $e\n$st');
      setState(() {
        error = 'Failed to load timetable';
        isLoading = false;
      });
    }
  }

  Future<void> _fetchSubsForWeek(String token) async {
    final subs = <String, List<dynamic>>{};
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
    final dates = List.generate(
        days.length, (i) => _formatDateYmd(DateTime(currentMonday.year, currentMonday.month, currentMonday.day + i)));

    await Future.wait(dates.map((date) async {
      try {
        final res =
            await http.get(Uri.parse('$baseUrl/substitutions/by-date/student?date=$date'), headers: headers);
        subs[date] =
            (res.statusCode == 200) ? (json.decode(res.body) as List? ?? []) : [];
      } catch (_) {
        subs[date] = [];
      }
    }));

    setState(() => studentSubs = subs);
  }

  // ------------------ Grid Builder ------------------
  void _buildGrid() {
    final newGrid = <String, Map<dynamic, List<dynamic>>>{};
    final periodIds = <dynamic>[];

    for (final p in periods) {
      final pid = (p is Map) ? (p['id'] ?? p['periodId'] ?? p['period_id']) : p;
      if (pid != null) periodIds.add(pid);
    }

    for (final d in days) {
      newGrid[d] = <dynamic, List<dynamic>>{};
      for (final pid in periodIds) {
        newGrid[d]![pid] = [];
      }
    }

    for (final rec in timetable) {
      if (rec is! Map) continue;
      final pid = rec['periodId'] ?? rec['period_id'];
      final rawDay = rec['day'] ?? rec['Day'];
      final dayNorm = days.firstWhere(
          (d) => d.toLowerCase() == rawDay.toString().toLowerCase(), orElse: () => '');
      if (dayNorm.isNotEmpty && pid != null) {
        newGrid[dayNorm]?[pid]?.add(rec);
      }
    }

    setState(() => grid = newGrid);
  }

  // ------------------ Student Switcher ------------------
  Future<void> _handleStudentSwitch(String admissionNumber) async {
    final prefs = await SharedPreferences.getInstance();
    if (admissionNumber == activeStudentAdmission) return;
    await prefs.setString('activeStudentAdmission', admissionNumber);
    setState(() => activeStudentAdmission = admissionNumber);
    await _loadAll();
  }

  List<Widget> _buildStudentSwitcherButtons() {
    final students = <Map<String, dynamic>>[];
    if (family?['student'] != null) students.add({...family!['student'], 'isSelf': true});
    for (final s in (family?['siblings'] ?? [])) {
      students.add({...s, 'isSelf': false});
    }

    return students.map((s) {
      final adm = (s['admission_number'] ?? '').toString();
      final isActive = adm == activeStudentAdmission;
      final label = s['isSelf'] == true ? 'Me' : (s['name'] ?? 'Unknown');
      final classInfo = s['class']?['name'] != null
          ? ' · ${s['class']['name']}-${s['section']?['name'] ?? '—'}'
          : '';

      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ElevatedButton(
          onPressed: () => _handleStudentSwitch(adm),
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: isActive ? Colors.amber.shade400 : Colors.white,
            foregroundColor: isActive ? Colors.black : Colors.blueGrey.shade700,
            side: BorderSide(
                color: isActive ? Colors.amber : Colors.grey.shade300, width: 1),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          child: Text(
            '$label$classInfo',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
    }).toList();
  }

  // ------------------ UI ------------------
  @override
  Widget build(BuildContext context) {
    final weekMap = _weekDatesMap();
    final weekRangeText = '${weekMap[days.first] ?? ''} — ${weekMap[days.last] ?? ''}';

    return Scaffold(
      appBar: AppBar(title: const Text('Time Table'), centerTitle: true, elevation: 3),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAll,
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    // 🔸 Header Card (with switcher)
                    Card(
                      elevation: 2,
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('My Timetable',
                                          style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800)),
                                      const SizedBox(height: 4),
                                      Text('Week: $weekRangeText',
                                          style: TextStyle(
                                              color: Colors.grey.shade600)),
                                    ]),
                                Row(children: [
                                  TextButton(
                                      onPressed: () => setState(() {
                                            currentMonday =
                                                currentMonday.subtract(const Duration(days: 7));
                                            _loadAll();
                                          }),
                                      child: const Text('‹ Prev')),
                                  OutlinedButton(
                                      onPressed: () => setState(() {
                                            currentMonday =
                                                _computeCurrentMonday(DateTime.now());
                                            _loadAll();
                                          }),
                                      child: const Text('This Week')),
                                  TextButton(
                                      onPressed: () => setState(() {
                                            currentMonday =
                                                currentMonday.add(const Duration(days: 7));
                                            _loadAll();
                                          }),
                                      child: const Text('Next ›')),
                                ])
                              ],
                            ),
                            if (canSeeStudentSwitcher &&
                                (family?['student'] != null ||
                                    (family?['siblings'] ?? []).isNotEmpty))
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: _buildStudentSwitcherButtons(),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      Chip(
                          backgroundColor: Colors.blue.shade50,
                          label: const Text('Today')),
                      Chip(
                          backgroundColor: Colors.red.shade50,
                          label: const Text('Holiday')),
                      Chip(
                          backgroundColor: Colors.teal.shade50,
                          label: const Text('Substitution')),
                    ]),
                    const SizedBox(height: 12),
                    // Desktop vs Mobile view
                    Builder(builder: (ctx) {
                      final width = MediaQuery.of(ctx).size.width;
                      if (width >= 800) {
                        return _buildDesktopTable(ctx);
                      } else {
                        return _buildMobileList();
                      }
                    }),
                    const SizedBox(height: 20),
                    if (showNoMatchHint)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                            color: Colors.yellow.shade50,
                            borderRadius: BorderRadius.circular(8)),
                        child: const Text(
                          'Hint: timetable items received but none matched configured periods.',
                          style: TextStyle(color: Colors.black87),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  // ------------------ Table + Mobile Accordion ------------------
  Widget _buildDesktopTable(BuildContext context) {
    final weekMap = _weekDatesMap();
    final cellBase = const BoxConstraints(minWidth: 140, minHeight: 72);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor:
            MaterialStateProperty.resolveWith((_) => Colors.grey.shade100),
        columns: [
          const DataColumn(label: SizedBox(width: 200, child: Text('Day'))),
          ...periods.map((p) {
            final title = (p is Map)
                ? (p['period_name'] ?? p['name'] ?? '')
                : p.toString();
            final times = (p is Map &&
                    p['start_time'] != null &&
                    p['end_time'] != null)
                ? '${p['start_time']}-${p['end_time']}'
                : '';
            return DataColumn(
              label: ConstrainedBox(
                constraints: cellBase,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (times.isNotEmpty)
                        Text(times,
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 12)),
                    ]),
              ),
            );
          }).toList(),
        ],
        rows: days.map((day) {
          final date = weekMap[day] ?? '';
          final subs = studentSubs[date] ?? [];
          final isToday = date == _formatDateYmd(DateTime.now());
          final holiday =
              holidays.firstWhere((h) => h['date'] == date, orElse: () => null);

          if (holiday != null) {
            return DataRow(cells: [
              DataCell(Text('$day (${holiday['description'] ?? 'Holiday'})')),
              DataCell(Text('Holiday')),
              ...List.generate(periods.length - 1, (_) => const DataCell(SizedBox()))
            ]);
          }

          return DataRow(
            color:
                isToday ? MaterialStateProperty.all(Colors.blue.withOpacity(.05)) : null,
            cells: [
              DataCell(Text(day)),
              ...periods.map((p) {
                final pid =
                    (p is Map) ? (p['id'] ?? p['periodId'] ?? p['period_id']) : p;
                final subsForPeriod = subs.where((s) =>
                    (s['periodId'] == pid) ||
                    (s['period_id'] == pid) ||
                    (s['periodId']?.toString() == pid?.toString())).toList();

                if (subsForPeriod.isNotEmpty) {
                  final s = subsForPeriod.first;
                  return DataCell(Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Substitution',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        Text(s['Subject']?['name'] ?? ''),
                        Text(s['Teacher']?['name'] ?? '',
                            style: TextStyle(color: Colors.grey.shade700))
                      ]));
                }

                final recs = grid[day]?[pid] ?? [];
                if (recs.isEmpty) {
                  return const DataCell(Text('—'));
                }
                return DataCell(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: recs.map<Widget>((r) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r['Subject']?['name'] ?? ''),
                              Text(r['Teacher']?['name'] ?? '',
                                  style: TextStyle(
                                      color: Colors.grey.shade700, fontSize: 12))
                            ]),
                      );
                    }).toList()));
              }).toList()
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMobileList() {
    final weekMap = _weekDatesMap();
    return ExpansionPanelList.radio(
      children: days.asMap().entries.map((entry) {
        final idx = entry.key;
        final day = entry.value;
        final date = weekMap[day] ?? '';
        final subs = studentSubs[date] ?? [];
        final holiday =
            holidays.firstWhere((h) => h['date'] == date, orElse: () => null);

        return ExpansionPanelRadio(
          value: idx,
          headerBuilder: (_, __) =>
              ListTile(title: Text(day), subtitle: Text(date)),
          body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: holiday != null
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(holiday['description'] ?? 'Holiday'),
                  )
                : Column(
                    children: periods.map((p) {
                      final pid = (p is Map)
                          ? (p['id'] ?? p['periodId'] ?? p['period_id'])
                          : p;
                      final subsForPeriod = subs.where((s) =>
                          (s['periodId'] == pid) ||
                          (s['period_id'] == pid) ||
                          (s['periodId']?.toString() == pid?.toString())).toList();
                      if (subsForPeriod.isNotEmpty) {
                        final s = subsForPeriod.first;
                        return Card(
                          child: ListTile(
                            title:
                                Text(p['period_name'] ?? p['name'] ?? 'Period'),
                            subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Substitution: ${s['Subject']?['name'] ?? ''}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  Text(s['Teacher']?['name'] ?? ''),
                                ]),
                          ),
                        );
                      }

                      final recs = grid[day]?[pid] ?? [];
                      return Card(
                        child: ListTile(
                          title:
                              Text(p['period_name'] ?? p['name'] ?? 'Period'),
                          subtitle: recs.isEmpty
                              ? const Text('No class')
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: recs.map<Widget>((r) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(r['Subject']?['name'] ?? ''),
                                            Text(r['Teacher']?['name'] ?? '',
                                                style: TextStyle(
                                                    color: Colors
                                                        .grey.shade700)),
                                          ]),
                                    );
                                  }).toList()),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        );
      }).toList(),
    );
  }
}
