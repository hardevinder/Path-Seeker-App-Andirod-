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

  // ✅ NEW: active classId for correct holiday filtering
  dynamic activeClassId;

  // Week state
  final List<String> days = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday"
  ];
  late DateTime currentMonday;
  int mobileOpenIdx = 0;
  bool showNoMatchHint = false;

  @override
  void initState() {
    super.initState();
    currentMonday = _computeCurrentMonday(DateTime.now());
    _loadRolesAndFamily().then((_) => _loadAll());
  }

  // ------------------ Helpers ------------------
  String _normalizeAdmission(String s) =>
      s.replaceAll("/", "-").trim(); // ✅ matches your React logic

  DateTime _computeCurrentMonday(DateTime forDate) {
    final dayIndex = (forDate.weekday + 6) % 7; // Monday = 0
    return DateTime(forDate.year, forDate.month, forDate.day - dayIndex);
  }

  String _formatDateYmd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Map<String, String> _weekDatesMap() {
    final map = <String, String>{};
    for (var i = 0; i < days.length; i++) {
      final d = DateTime(currentMonday.year, currentMonday.month,
          currentMonday.day + i);
      map[days[i]] = _formatDateYmd(d);
    }
    return map;
  }

  // ✅ NEW: compute active classId from family + active admission
  void _computeActiveClassId() {
    activeClassId = null;

    if (family == null) return;
    final active = _normalizeAdmission(activeStudentAdmission);

    final candidates = <Map<String, dynamic>>[];
    if (family?['student'] != null) {
      candidates.add(Map<String, dynamic>.from(family!['student']));
    }
    for (final s in (family?['siblings'] ?? [])) {
      if (s is Map) candidates.add(Map<String, dynamic>.from(s));
    }

    Map<String, dynamic>? activeStudent;
    for (final s in candidates) {
      final adm = _normalizeAdmission((s['admission_number'] ?? '').toString());
      if (adm == active) {
        activeStudent = s;
        break;
      }
    }

    if (activeStudent == null) return;

    // Try multiple shapes
    activeClassId = activeStudent['classId'] ??
        activeStudent['class_id'] ??
        (activeStudent['class'] is Map ? activeStudent['class']['id'] : null);
  }

  // ✅ NEW: holiday lookup by date + classId
  dynamic _holidayForDate(String dateYmd) {
    if (activeClassId == null) return null;
    for (final h in holidays) {
      if (h is! Map) continue;
      final hDate = (h['date'] ?? '').toString();
      final hClassId = h['classId'] ?? (h['class'] is Map ? h['class']['id'] : null);
      if (hDate == dateYmd && hClassId == activeClassId) return h;
    }
    return null;
  }

  String _periodTitle(dynamic p) {
    if (p is Map) {
      return (p['period_name'] ?? p['name'] ?? 'Period').toString();
    }
    return p?.toString() ?? 'Period';
  }

  String _periodTimes(dynamic p) {
    if (p is Map && p['start_time'] != null && p['end_time'] != null) {
      return '${p['start_time']}-${p['end_time']}';
    }
    return '';
  }

  dynamic _periodId(dynamic p) {
    if (p is Map) return p['id'] ?? p['periodId'] ?? p['period_id'];
    return p;
  }

  // ------------------ Role + Family Logic ------------------
  Future<void> _loadRolesAndFamily() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('authToken');

    // roles
    try {
      final stored = prefs.getString('roles');
      if (stored != null) {
        roles = (json.decode(stored) as List)
            .map((e) => e.toString().toLowerCase())
            .toList();
      } else {
        final single = prefs.getString('userRole');
        if (single != null) roles = [single.toLowerCase()];
      }
    } catch (_) {}

    isStudent = roles.contains('student');
    isParent = roles.contains('parent');
    canSeeStudentSwitcher = isStudent || isParent;

    // family
    try {
      final rawFamily = prefs.getString('family');
      family = rawFamily != null ? json.decode(rawFamily) : null;
    } catch (_) {}

    activeStudentAdmission = prefs.getString('activeStudentAdmission') ??
        prefs.getString('username') ??
        '';
    loggedInAdmission = prefs.getString('username') ?? '';

    // normalize admission like web
    activeStudentAdmission = _normalizeAdmission(activeStudentAdmission);
    loggedInAdmission = _normalizeAdmission(loggedInAdmission);

    _computeActiveClassId(); // ✅ important
  }

  Future<String> _resolveTimetableUrl() async {
    final active = _normalizeAdmission(activeStudentAdmission);
    final logged = _normalizeAdmission(loggedInAdmission);

    // ✅ If parent OR switched student => by-admission
    if (!isStudent || (active.isNotEmpty && active != logged)) {
      final adm = Uri.encodeComponent(active);
      return '$baseUrl/period-class-teacher-subject/timetable/by-admission/$adm';
    }
    return '$baseUrl/period-class-teacher-subject/student/timetable';
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

      // refresh these (in case switch happened)
      activeStudentAdmission = _normalizeAdmission(
          prefs.getString('activeStudentAdmission') ??
              prefs.getString('username') ??
              '');
      loggedInAdmission =
          _normalizeAdmission(prefs.getString('username') ?? '');

      // refresh family too
      try {
        final rawFamily = prefs.getString('family');
        family = rawFamily != null ? json.decode(rawFamily) : family;
      } catch (_) {}
      _computeActiveClassId();

      if (baseUrl.isEmpty || token == null) {
        setState(() => isLoading = false);
        return;
      }

      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'
      };
      final timetableUrl = await _resolveTimetableUrl();

      final responses = await Future.wait([
        http.get(Uri.parse('$baseUrl/periods'), headers: headers),
        http.get(Uri.parse(timetableUrl), headers: headers),
        http.get(Uri.parse('$baseUrl/holidays'), headers: headers),
      ]);

      // periods
      final pRes = responses[0];
      if (pRes.statusCode == 200) {
        final decoded = json.decode(pRes.body);
        periods = decoded is List ? decoded : (decoded['periods'] ?? []);
      } else {
        periods = [];
      }

      // timetable
      final tRes = responses[1];
      if (tRes.statusCode == 200) {
        final parsed = json.decode(tRes.body);
        if (parsed is List) {
          timetable = parsed;
        } else if (parsed is Map) {
          timetable = parsed['timetable'] ?? parsed['data'] ?? [];
        } else {
          timetable = [];
        }
      } else {
        timetable = [];
      }

      // holidays
      final hRes = responses[2];
      if (hRes.statusCode == 200) {
        final decoded = json.decode(hRes.body);
        holidays = decoded is List ? decoded : (decoded['holidays'] ?? []);
      } else {
        holidays = [];
      }

      await _fetchSubsForWeek(token!);
      _buildGrid();

      // today open on mobile
      final todayStr = _formatDateYmd(DateTime.now());
      final weekMap = _weekDatesMap();
      final idx = days.indexWhere((d) => weekMap[d] == todayStr);

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
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json'
    };

    final dates = List.generate(days.length, (i) {
      final d = DateTime(
          currentMonday.year, currentMonday.month, currentMonday.day + i);
      return _formatDateYmd(d);
    });

    await Future.wait(dates.map((date) async {
      try {
        final res = await http.get(
          Uri.parse('$baseUrl/substitutions/by-date/student?date=$date'),
          headers: headers,
        );
        final decoded = res.statusCode == 200 ? json.decode(res.body) : [];
        subs[date] = decoded is List ? decoded : [];
      } catch (_) {
        subs[date] = [];
      }
    }));

    if (mounted) setState(() => studentSubs = subs);
  }

  // ------------------ Grid Builder ------------------
  void _buildGrid() {
    final newGrid = <String, Map<dynamic, List<dynamic>>>{};

    final periodIds = <dynamic>[];
    for (final p in periods) {
      final pid = _periodId(p);
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
      final raw = rawDay?.toString() ?? '';

      final dayNorm = days.firstWhere(
        (d) => d.toLowerCase() == raw.toLowerCase(),
        orElse: () => '',
      );

      if (dayNorm.isNotEmpty && pid != null) {
        newGrid[dayNorm]?[pid]?.add(rec);
      }
    }

    setState(() => grid = newGrid);
  }

  // ------------------ Student Switcher ------------------
  Future<void> _handleStudentSwitch(String admissionNumber) async {
    final prefs = await SharedPreferences.getInstance();
    final adm = _normalizeAdmission(admissionNumber);
    if (adm == activeStudentAdmission) return;

    await prefs.setString('activeStudentAdmission', adm);
    setState(() => activeStudentAdmission = adm);

    _computeActiveClassId();
    await _loadAll();
  }

  List<Widget> _buildStudentSwitcherButtons() {
    final students = <Map<String, dynamic>>[];
    if (family?['student'] != null) {
      students.add({...family!['student'], 'isSelf': true});
    }
    for (final s in (family?['siblings'] ?? [])) {
      if (s is Map) students.add({...s, 'isSelf': false});
    }

    return students.map((s) {
      final adm = _normalizeAdmission((s['admission_number'] ?? '').toString());
      final isActive = adm == activeStudentAdmission;
      final label = s['isSelf'] == true ? 'Me' : (s['name'] ?? 'Unknown');
      final classInfo = (s['class'] is Map && s['class']['name'] != null)
          ? ' · ${s['class']['name']}-${(s['section'] is Map ? s['section']['name'] : null) ?? '—'}'
          : '';

      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ElevatedButton(
          onPressed: () => _handleStudentSwitch(adm),
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: isActive ? Colors.amber.shade400 : Colors.white,
            foregroundColor:
                isActive ? Colors.black : Colors.blueGrey.shade700,
            side: BorderSide(
              color: isActive ? Colors.amber : Colors.grey.shade300,
              width: 1,
            ),
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
    final weekRangeText =
        '${weekMap[days.first] ?? ''} — ${weekMap[days.last] ?? ''}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Table'),
        centerTitle: true,
        elevation: 3,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAll,
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Card(
                      elevation: 2,
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'My Timetable',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Week: $weekRangeText',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: () async {
                                        setState(() {
                                          currentMonday = currentMonday
                                              .subtract(const Duration(days: 7));
                                        });
                                        await _loadAll();
                                      },
                                      child: const Text('‹ Prev'),
                                    ),
                                    OutlinedButton(
                                      onPressed: () async {
                                        setState(() {
                                          currentMonday = _computeCurrentMonday(
                                              DateTime.now());
                                        });
                                        await _loadAll();
                                      },
                                      child: const Text('This Week'),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        setState(() {
                                          currentMonday =
                                              currentMonday.add(const Duration(days: 7));
                                        });
                                        await _loadAll();
                                      },
                                      child: const Text('Next ›'),
                                    ),
                                  ],
                                ),
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
                        label: const Text('Today'),
                      ),
                      Chip(
                        backgroundColor: Colors.red.shade50,
                        label: const Text('Holiday'),
                      ),
                      Chip(
                        backgroundColor: Colors.teal.shade50,
                        label: const Text('Substitution'),
                      ),
                    ]),
                    const SizedBox(height: 12),

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
                          borderRadius: BorderRadius.circular(8),
                        ),
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

  // ------------------ Desktop ------------------
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
            return DataColumn(
              label: ConstrainedBox(
                constraints: cellBase,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _periodTitle(p),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (_periodTimes(p).isNotEmpty)
                      Text(
                        _periodTimes(p),
                        style:
                            TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
        rows: days.map((day) {
          final date = weekMap[day] ?? '';
          final subs = studentSubs[date] ?? [];
          final isToday = date == _formatDateYmd(DateTime.now());

          // ✅ FIX: holiday by classId
          final holiday = _holidayForDate(date);

          if (holiday != null) {
            // ✅ safer: exactly periods.length cells
            final cells = <DataCell>[
              DataCell(Text('$day (${holiday['description'] ?? 'Holiday'})')),
              ...List.generate(
                periods.length,
                (_) => const DataCell(Text('Holiday')),
              ),
            ];
            return DataRow(
              color: MaterialStateProperty.all(Colors.red.withOpacity(.06)),
              cells: cells,
            );
          }

          return DataRow(
            color: isToday
                ? MaterialStateProperty.all(Colors.blue.withOpacity(.05))
                : null,
            cells: [
              DataCell(Text(day)),
              ...periods.map((p) {
                final pid = _periodId(p);

                final subsForPeriod = subs.where((s) {
                  if (s is! Map) return false;
                  final spid = s['periodId'] ?? s['period_id'];
                  return spid?.toString() == pid?.toString() &&
                      (s['day']?.toString().toLowerCase() ?? '') ==
                          day.toLowerCase();
                }).toList();

                if (subsForPeriod.isNotEmpty) {
                  final s = subsForPeriod.first as Map;
                  return DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Substitution',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        Text((s['Subject'] is Map ? s['Subject']['name'] : '')?.toString() ?? ''),
                        Text(
                          (s['Teacher'] is Map ? s['Teacher']['name'] : '')?.toString() ?? '',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  );
                }

                final recs = grid[day]?[pid] ?? [];
                if (recs.isEmpty) return const DataCell(Text('—'));

                return DataCell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: recs.map<Widget>((r) {
                      if (r is! Map) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text((r['Subject'] is Map ? r['Subject']['name'] : '')?.toString() ?? ''),
                            Text(
                              (r['Teacher'] is Map ? r['Teacher']['name'] : '')?.toString() ?? '',
                              style: TextStyle(
                                  color: Colors.grey.shade700, fontSize: 12),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                );
              }).toList(),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ------------------ Mobile (Accordion) ------------------
  Widget _buildMobileList() {
    final weekMap = _weekDatesMap();

    return ExpansionPanelList.radio(
      // ✅ FIX: open “Today” by default
      initialOpenPanelValue: mobileOpenIdx,
      children: days.asMap().entries.map((entry) {
        final idx = entry.key;
        final day = entry.value;
        final date = weekMap[day] ?? '';
        final subs = studentSubs[date] ?? [];

        // ✅ FIX: holiday by classId
        final holiday = _holidayForDate(date);

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
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text((holiday['description'] ?? 'Holiday').toString()),
                  )
                : Column(
                    children: periods.map((p) {
                      final pid = _periodId(p);
                      final title = _periodTitle(p);

                      final subsForPeriod = subs.where((s) {
                        if (s is! Map) return false;
                        final spid = s['periodId'] ?? s['period_id'];
                        final sday = (s['day'] ?? '').toString().toLowerCase();
                        return spid?.toString() == pid?.toString() &&
                            sday == day.toLowerCase();
                      }).toList();

                      if (subsForPeriod.isNotEmpty) {
                        final s = subsForPeriod.first as Map;
                        return Card(
                          child: ListTile(
                            title: Text(title),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Substitution: ${(s['Subject'] is Map ? s['Subject']['name'] : '') ?? ''}',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text((s['Teacher'] is Map ? s['Teacher']['name'] : '')?.toString() ?? ''),
                              ],
                            ),
                          ),
                        );
                      }

                      final recs = grid[day]?[pid] ?? [];
                      return Card(
                        child: ListTile(
                          title: Text(title),
                          subtitle: recs.isEmpty
                              ? const Text('No class')
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: recs.map<Widget>((r) {
                                    if (r is! Map) return const SizedBox.shrink();
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text((r['Subject'] is Map ? r['Subject']['name'] : '')?.toString() ?? ''),
                                          Text(
                                            (r['Teacher'] is Map ? r['Teacher']['name'] : '')?.toString() ?? '',
                                            style: TextStyle(color: Colors.grey.shade700),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
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
