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
  Map<String, List<dynamic>> studentSubs = {}; // date -> list of substitutions
  Map<String, Map<dynamic, List<dynamic>>> grid = {}; // day -> periodId -> records

  // Week state
  final List<String> days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  late DateTime currentMonday;
  int mobileOpenIdx = 0; // which accordion is open on mobile

  // Helpful debug flag
  bool showNoMatchHint = false;

  @override
  void initState() {
    super.initState();
    currentMonday = _computeCurrentMonday(DateTime.now());
    _loadAll();
  }

  DateTime _computeCurrentMonday(DateTime forDate) {
    final dayIndex = (forDate.weekday + 6) % 7; // Monday->0 ... Sunday->6
    return DateTime(forDate.year, forDate.month, forDate.day - dayIndex);
  }

  String _formatDateYmd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authToken');
  }

  Future<void> _loadAll() async {
    setState(() {
      isLoading = true;
      error = null;
      showNoMatchHint = false;
    });
    try {
      final token = await _getToken();
      if (baseUrl.isEmpty || token == null) {
        if (kDebugMode) debugPrint('baseUrl or token missing; skipping remote fetch');
        setState(() {
          periods = [];
          timetable = [];
          holidays = [];
          studentSubs = {};
          grid = {};
          isLoading = false;
        });
        return;
      }

      final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};

      // parallel fetches
      final responses = await Future.wait([
        http.get(Uri.parse('$baseUrl/periods'), headers: headers),
        http.get(Uri.parse('$baseUrl/period-class-teacher-subject/student/timetable'), headers: headers),
        http.get(Uri.parse('$baseUrl/holidays'), headers: headers),
      ]);

      // --- periods ---
      final pRes = responses[0];
      if (pRes.statusCode == 200) {
        final parsed = json.decode(pRes.body);
        // Accept list or wrapped shapes
        periods = (parsed is List) ? parsed : (parsed['periods'] ?? parsed) as List<dynamic>? ?? [];
      } else {
        periods = [];
      }
      if (kDebugMode) {
        debugPrint('Periods status: ${pRes.statusCode}');
        debugPrint('Periods body: ${pRes.body}');
      }

      // --- timetable ---
      final tRes = responses[1];
      if (tRes.statusCode == 200) {
        final parsed = json.decode(tRes.body);
        if (parsed is List) {
          timetable = parsed;
        } else if (parsed is Map) {
          // try common keys
          if (parsed['timetable'] is List) {
            timetable = parsed['timetable'];
          } else if (parsed['data'] is List) {
            timetable = parsed['data'];
          } else {
            final firstList = parsed.values.firstWhere((v) => v is List, orElse: () => null);
            timetable = (firstList is List) ? firstList : [];
          }
        } else {
          timetable = [];
        }
      } else {
        timetable = [];
      }
      if (kDebugMode) {
        debugPrint('Timetable status: ${tRes.statusCode}');
        debugPrint('Timetable body: ${tRes.body}');
      }

      // --- holidays ---
      final hRes = responses[2];
      if (hRes.statusCode == 200) {
        final parsed = json.decode(hRes.body);
        holidays = (parsed is List) ? parsed : (parsed['holidays'] ?? parsed) as List<dynamic>? ?? [];
      } else {
        holidays = [];
      }
      if (kDebugMode) {
        debugPrint('Holidays status: ${hRes.statusCode}');
        debugPrint('Holidays body: ${hRes.body}');
      }

      // fetch substitutions for this week's dates
      await _fetchSubsForWeek(token);

      // build grid (defensive)
      _buildGrid();

      // set mobileOpenIdx to today's idx if present
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

  Map<String, String> _weekDatesMap() {
    final map = <String, String>{};
    for (var i = 0; i < days.length; i++) {
      final d = DateTime(currentMonday.year, currentMonday.month, currentMonday.day + i);
      map[days[i]] = _formatDateYmd(d);
    }
    return map;
  }

  Future<void> _fetchSubsForWeek(String token) async {
    final subs = <String, List<dynamic>>{};
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
    final dates = List.generate(days.length, (i) => _formatDateYmd(DateTime(currentMonday.year, currentMonday.month, currentMonday.day + i)));

    await Future.wait(dates.map((date) async {
      try {
        final res = await http.get(Uri.parse('$baseUrl/substitutions/by-date/student?date=$date'), headers: headers);
        if (res.statusCode == 200) {
          final parsed = json.decode(res.body);
          subs[date] = (parsed is List) ? parsed : (parsed['data'] as List<dynamic>?) ?? [];
        } else {
          subs[date] = [];
        }
        if (kDebugMode) {
          debugPrint('Subs for $date status: ${res.statusCode}');
          debugPrint('Subs for $date body: ${res.body}');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('subs fetch error for $date: $e');
        subs[date] = [];
      }
    }));

    setState(() => studentSubs = subs);
  }

  /// Build grid while accepting multiple possible key names/cases from API:
  /// - period id may be in period['id'] (periods list)
  /// - timetable records provide `periodId` and `day` (your API sample)
  void _buildGrid() {
    final newGrid = <String, Map<dynamic, List<dynamic>>>{};

    // collect period ids from periods array (fallback to Period objects inside timetable if periods empty)
    final periodIds = <dynamic>[];
    for (final p in periods) {
      dynamic pid;
      if (p is Map<String, dynamic>) {
        pid = p['id'] ?? p['periodId'] ?? p['period_id'] ?? p['periodid'];
      }
      if (pid != null) periodIds.add(pid);
    }

    // If periods endpoint returned empty, try to discover unique periodIds from timetable
    if (periodIds.isEmpty) {
      final found = <dynamic>{};
      for (final rec in timetable) {
        if (rec is Map<String, dynamic>) {
          final pid = rec['periodId'] ?? rec['period_id'] ?? (rec['Period'] is Map ? rec['Period']['id'] : null);
          if (pid != null) found.add(pid);
        }
      }
      periodIds.addAll(found);
    }

    // init grid
    for (final d in days) {
      newGrid[d] = <dynamic, List<dynamic>>{};
      for (final pid in periodIds) {
        newGrid[d]![pid] = [];
      }
    }

    // normalize day helper
    String normalizeDay(dynamic rawDay) {
      if (rawDay == null) return '';
      final s = rawDay.toString().trim();
      if (s.isEmpty) return '';
      final lower = s.toLowerCase();
      for (final d in days) {
        if (d.toLowerCase() == lower) return d;
      }
      final short = lower.substring(0, lower.length < 3 ? lower.length : 3);
      final found = days.firstWhere((d) => d.toLowerCase().startsWith(short), orElse: () => '');
      return found;
    }

    // populate
    var matchedAny = false;
    for (final rec in timetable) {
      if (rec is! Map) continue;
      final pid = rec['periodId'] ?? rec['period_id'] ?? (rec['Period'] is Map ? rec['Period']['id'] : null);
      final rawDay = rec['day'] ?? rec['Day'] ?? rec['weekday'] ?? rec['dayName'];
      final dayNorm = normalizeDay(rawDay);
      if (dayNorm.isEmpty) {
        if (kDebugMode) debugPrint('Skipping record w/ unknown day: $rec');
        continue;
      }
      if (pid == null) {
        if (kDebugMode) debugPrint('Skipping record w/o period id: $rec');
        continue;
      }

      if (newGrid.containsKey(dayNorm) && newGrid[dayNorm]!.containsKey(pid)) {
        newGrid[dayNorm]![pid]!.add(rec);
        matchedAny = true;
      } else {
        // try matching by string equality with known keys
        final pkeys = newGrid[dayNorm]?.keys.toList() ?? [];
        var added = false;
        for (final known in pkeys) {
          if (known.toString() == pid.toString()) {
            newGrid[dayNorm]![known]!.add(rec);
            added = true;
            matchedAny = true;
            break;
          }
        }
        if (!added && kDebugMode) debugPrint('No matching period slot for rec: pid=$pid day=$dayNorm rec=$rec');
      }
    }

    setState(() {
      grid = newGrid;
      showNoMatchHint = !matchedAny && timetable.isNotEmpty && periodIds.isNotEmpty;
    });
  }

  Future<void> _refresh() async {
    await _loadAll();
  }

  void _prevWeek() {
    setState(() {
      currentMonday = DateTime(currentMonday.year, currentMonday.month, currentMonday.day - 7);
    });
    _loadAll();
  }

  void _nextWeek() {
    setState(() {
      currentMonday = DateTime(currentMonday.year, currentMonday.month, currentMonday.day + 7);
    });
    _loadAll();
  }

  void _thisWeek() {
    setState(() {
      currentMonday = _computeCurrentMonday(DateTime.now());
    });
    _loadAll();
  }

  Widget _dayHeading(String day) {
    final map = _weekDatesMap();
    final todayStr = _formatDateYmd(DateTime.now());
    final isToday = map[day] == todayStr;
    final holiday = holidays.firstWhere((h) => (h['date'] ?? '') == map[day], orElse: () => null);

    return Row(
      children: [
        Text(day, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        if (isToday)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(12)),
            child: const Text('Today', style: TextStyle(fontSize: 12)),
          ),
        if (holiday != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(left: 6),
            decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(12)),
            child: const Text('Holiday', style: TextStyle(fontSize: 12)),
          ),
      ],
    );
  }

  Widget _buildDesktopTable(BuildContext context) {
    final weekMap = _weekDatesMap();
    final cellBase = BoxConstraints(minWidth: 140, minHeight: 72);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width),
        child: DataTable(
          headingRowColor: MaterialStateProperty.resolveWith((states) => Colors.grey.shade100),
          columns: [
            const DataColumn(label: SizedBox(width: 200, child: Text('Day'))),
            ...periods.map((p) {
              final title = (p is Map) ? (p['period_name'] ?? p['name'] ?? '') : p.toString();
              final times = (p is Map && p['start_time'] != null && p['end_time'] != null) ? '${p['start_time']}-${p['end_time']}' : '';
              return DataColumn(
                label: ConstrainedBox(
                  constraints: cellBase,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (times.isNotEmpty) Text(times, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ],
          rows: days.map((day) {
            final weekMapLocal = weekMap;
            final holiday = holidays.firstWhere((h) => (h['date'] ?? '') == weekMapLocal[day], orElse: () => null);
            final isToday = weekMapLocal[day] == _formatDateYmd(DateTime.now());

            if (holiday != null) {
              return DataRow(cells: [
                DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _dayHeading(day),
                  const SizedBox(height: 4),
                  Text(weekMapLocal[day] ?? '', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ])),
                DataCell(Container(
                  padding: const EdgeInsets.all(12),
                  child: Text(holiday['description'] ?? 'Holiday'),
                )),
                ...List.generate(periods.length - 1, (_) => const DataCell(SizedBox())),
              ]);
            }

            return DataRow(
              color: isToday ? MaterialStateProperty.all(Colors.blue.withOpacity(0.03)) : null,
              cells: [
                DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _dayHeading(day),
                  const SizedBox(height: 4),
                  Text(weekMapLocal[day] ?? '', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ])),
                ...periods.map((p) {
                  final pid = (p is Map) ? (p['id'] ?? p['periodId'] ?? p['period_id']) : p;
                  final subsForDay = studentSubs[weekMapLocal[day] ?? ''] ?? [];
                  final subsForPeriod = subsForDay.where((s) => (s['periodId'] == pid) || (s['period_id'] == pid) || (s['periodId']?.toString() == pid?.toString())).toList();
                  if (subsForPeriod.isNotEmpty) {
                    final s = subsForPeriod.first;
                    return DataCell(Container(
                      padding: const EdgeInsets.all(8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Substitution', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(s['Subject']?['name'] ?? s['subjectId'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(s['Teacher']?['name'] ?? '', style: TextStyle(color: Colors.grey.shade700)),
                      ]),
                    ));
                  }

                  final recs = grid[day]?[pid] ?? [];
                  if (recs.isEmpty) {
                    return const DataCell(Center(child: Text('—', style: TextStyle(color: Colors.grey))));
                  }

                  return DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: recs.map<Widget>((r) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r['Subject']?['name'] ?? r['subjectId'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(r['Teacher']?['name'] ?? '', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                      ]),
                    );
                  }).toList()));
                }).toList(),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMobileList() {
    final weekMap = _weekDatesMap();
    return ExpansionPanelList.radio(
      animationDuration: const Duration(milliseconds: 200),
      children: days.asMap().entries.map((entry) {
        final idx = entry.key;
        final day = entry.value;
        final holiday = holidays.firstWhere((h) => (h['date'] ?? '') == weekMap[day], orElse: () => null);
        final subsForDay = studentSubs[weekMap[day] ?? ''] ?? [];

        return ExpansionPanelRadio(
          value: idx,
          canTapOnHeader: true,
          headerBuilder: (context, isOpen) {
            return ListTile(
              title: _dayHeading(day),
              subtitle: Text(weekMap[day] ?? '', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              trailing: holiday != null ? const Icon(Icons.beach_access, color: Colors.red) : null,
            );
          },
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: holiday != null
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text(holiday['description'] ?? 'Holiday'),
                  )
                : Column(
                    children: periods.map((p) {
                      final pid = (p is Map) ? (p['id'] ?? p['periodId'] ?? p['period_id']) : p;
                      final subsForPeriod = subsForDay.where((s) => (s['periodId'] == pid) || (s['period_id'] == pid) || (s['periodId']?.toString() == pid?.toString())).toList();
                      if (subsForPeriod.isNotEmpty) {
                        final s = subsForPeriod.first;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(p is Map ? (p['period_name'] ?? p['name'] ?? '') : p.toString()),
                            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const SizedBox(height: 6),
                              Text('Substitution: ${s['Subject']?['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                              if ((s['Teacher']?['name'] ?? '').isNotEmpty) Text(s['Teacher']?['name'] ?? ''),
                            ]),
                          ),
                        );
                      }

                      final recs = grid[day]?[pid] ?? [];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(p is Map ? (p['period_name'] ?? p['name'] ?? '') : p.toString()),
                          subtitle: recs.isEmpty
                              ? const Text('No class', style: TextStyle(color: Colors.grey))
                              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: recs.map<Widget>((r) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6.0),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(r['Subject']?['name'] ?? r['subjectId'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                                      Text(r['Teacher']?['name'] ?? '', style: TextStyle(color: Colors.grey.shade700)),
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

  @override
  Widget build(BuildContext context) {
    final weekMap = _weekDatesMap();
    final weekRangeText = '${weekMap[days.first] ?? ''} — ${weekMap[days.last] ?? ''}';

    return Scaffold(
      // Replaced StudentAppBar with a simple AppBar titled "Time Table"
      appBar: AppBar(
        title: const Text('Time Table'),
        centerTitle: true,
        elevation: 3,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: isLoading
                ? ListView(
                    children: const [
                      SizedBox(height: 60),
                      Center(child: CircularProgressIndicator()),
                    ],
                  )
                : (error != null)
                    ? ListView(
                        children: [
                          const SizedBox(height: 40),
                          Center(child: Text(error!, style: const TextStyle(color: Colors.red))),
                        ],
                      )
                    : ListView(
                        children: [
                          Card(
                            elevation: 2,
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    const Text('My Timetable', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 4),
                                    Text('Week: $weekRangeText', style: TextStyle(color: Colors.grey.shade600)),
                                  ]),
                                  Row(children: [
                                    TextButton(onPressed: _prevWeek, child: const Text('‹ Prev')),
                                    OutlinedButton(onPressed: _thisWeek, child: const Text('This Week')),
                                    TextButton(onPressed: _nextWeek, child: const Text('Next ›')),
                                  ])
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(spacing: 8, runSpacing: 6, children: [
                            Chip(backgroundColor: Colors.blue.shade50, label: const Text('Today')),
                            Chip(backgroundColor: Colors.red.shade50, label: const Text('Holiday')),
                            Chip(backgroundColor: Colors.teal.shade50, label: const Text('Substitution')),
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
                          const SizedBox(height: 12),
                          if (showNoMatchHint)
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(top: 8),
                              decoration: BoxDecoration(color: Colors.yellow.shade50, borderRadius: BorderRadius.circular(8)),
                              child: const Text(
                                'Hint: timetable items were received from the server but none matched the configured periods. Check API field names (periodId/period_id) or day format (Monday vs monday). See console logs for the raw server response (debug mode).',
                                style: TextStyle(color: Colors.black87),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Center(child: Text('Tip: Pull to refresh or use This Week to jump back')),
                        ],
                      ),
          ),
        ),
      ),
    );
  }
}
