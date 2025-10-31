// lib/screens/teacher/teacher_timetable_display.dart
// Teacher timetable - redesigned UI with "Today's Timetable" slider.
// Replace your existing file with this.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../constants/constants.dart' as AppConstants;

const List<String> DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

String normalizeDayShort(dynamic val) {
  if (val == null) return '';
  final s = val.toString().trim().toLowerCase();
  final map = {
    'mon': 'Mon',
    'monday': 'Mon',
    'tue': 'Tue',
    'tues': 'Tue',
    'tuesday': 'Tue',
    'wed': 'Wed',
    'weds': 'Wed',
    'wednesday': 'Wed',
    'thu': 'Thu',
    'thur': 'Thu',
    'thurs': 'Thu',
    'thursday': 'Thu',
    'fri': 'Fri',
    'friday': 'Fri',
    'sat': 'Sat',
    'saturday': 'Sat',
  };
  return map[s] ?? '';
}

String formatDateShort(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

class TeacherTimetableDisplayScreen extends StatefulWidget {
  final int? teacherId;
  const TeacherTimetableDisplayScreen({Key? key, this.teacherId}) : super(key: key);

  @override
  State<TeacherTimetableDisplayScreen> createState() => _TeacherTimetableDisplayScreenState();
}

class _TeacherTimetableDisplayScreenState extends State<TeacherTimetableDisplayScreen> {
  late DateTime _currentMonday;
  bool _loading = true;
  List<dynamic> _periods = [];
  List<dynamic> _timetable = [];
  Map<String, Map<dynamic, List<dynamic>>> _grid = {}; // dayShort -> periodId -> records
  List<dynamic> _holidays = [];
  Map<String, List<dynamic>> _originalSubs = {};
  Map<String, List<dynamic>> _substitutedSubs = {};
  List<String> _errors = [];

  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _dayKeys = {for (var d in DAYS) d: GlobalKey()};
  final PageController _todayPageController = PageController(viewportFraction: 0.88);

  int get _teacherId => widget.teacherId ?? 0;

  @override
  void initState() {
    super.initState();

    // Ensure ApiService uses the same baseUrl from your constants file if available.
    try {
      ApiService.setBaseUrl(AppConstants.baseUrl);
    } catch (_) {}

    final today = DateTime.now();
    final dayIndex = (today.weekday + 6) % 7; // Monday=0
    _currentMonday = DateTime(today.year, today.month, today.day - dayIndex);

    _loadAll().then((_) => WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTodayExact()));
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _errors = [];
    });

    try {
      await Future.wait([_fetchPeriods(), _fetchTimetable()]);
      await Future.wait([_fetchHolidays(), _fetchSubs()]);
      _buildGrid();
    } catch (e) {
      if (mounted) setState(() => _errors.add('Failed to load some data: $e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchPeriods() async {
    try {
      final res = await ApiService.rawGet('/periods');
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        final list = (decoded is List) ? decoded : (decoded['periods'] ?? decoded['data'] ?? []);
        if (mounted) setState(() => _periods = List.from(list));
      } else {
        if (mounted) setState(() => _errors.add('Failed to fetch periods (${res.statusCode})'));
      }
    } catch (e) {
      if (mounted) setState(() => _errors.add('Failed to fetch periods: $e'));
    }
  }

  Future<void> _fetchTimetable() async {
    try {
      final endpoint = _teacherId > 0
          ? '/period-class-teacher-subject/timetable-teacher?teacherId=$_teacherId'
          : '/period-class-teacher-subject/timetable-teacher';
      final res = await ApiService.rawGet(endpoint);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        final list = decoded is List ? decoded : (decoded['timetable'] ?? decoded['data'] ?? []);
        final normalized = (list as Iterable).map((rec) {
          final r = rec is Map ? Map<String, dynamic>.from(rec) : <String, dynamic>{};
          r['_dayShort'] = normalizeDayShort(r['day'] ?? r['Day'] ?? r['weekday']);
          r['_periodId'] = r['periodId'] ??
              r['period_id'] ??
              r['PeriodId'] ??
              (r['period'] is Map ? r['period']['id'] : null) ??
              r['id'];
          return r;
        }).where((r) => (r['_dayShort'] ?? '') != '' && r['_periodId'] != null).toList();
        if (mounted) setState(() => _timetable = normalized);
      } else {
        if (mounted) setState(() => _errors.add('Failed to fetch timetable (${res.statusCode})'));
      }
    } catch (e) {
      if (mounted) setState(() => _errors.add('Failed to fetch timetable: $e'));
    }
  }

  Future<void> _fetchHolidays() async {
    try {
      final start = formatDateShort(_currentMonday);
      final end = formatDateShort(_currentMonday.add(const Duration(days: 5)));
      final res = await ApiService.rawGet('/holidays?start=$start&end=$end');
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        final list = decoded is List ? decoded : (decoded['holidays'] ?? decoded['data'] ?? []);
        if (mounted) setState(() => _holidays = List.from(list));
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _fetchSubs() async {
    final orig = <String, List<dynamic>>{};
    final sub = <String, List<dynamic>>{};
    final futures = <Future>[];

    for (int i = 0; i < 6; i++) {
      final d = _currentMonday.add(Duration(days: i));
      final ds = formatDateShort(d);

      futures.add(ApiService.rawGet('/substitutions/by-date/original?date=$ds&teacherId=$_teacherId').then((res) {
        if (res.statusCode == 200) {
          final decoded = json.decode(res.body);
          final rows = decoded is List ? decoded : (decoded['rows'] ?? decoded['data'] ?? []);
          orig[ds] = List.from(rows);
        } else {
          orig[ds] = [];
        }
      }).catchError((_) {
        orig[ds] = [];
      }));

      futures.add(ApiService.rawGet('/substitutions/by-date/substituted?date=$ds&teacherId=$_teacherId').then((res) {
        if (res.statusCode == 200) {
          final decoded = json.decode(res.body);
          final rows = decoded is List ? decoded : (decoded['rows'] ?? decoded['data'] ?? []);
          sub[ds] = List.from(rows);
        } else {
          sub[ds] = [];
        }
      }).catchError((_) {
        sub[ds] = [];
      }));
    }

    await Future.wait(futures);
    if (mounted) setState(() {
      _originalSubs = orig;
      _substitutedSubs = sub;
    });
  }

  void _buildGrid() {
    final newGrid = <String, Map<dynamic, List<dynamic>>>{};
    for (final d in DAYS) {
      newGrid[d] = <dynamic, List<dynamic>>{};
      for (final p in _periods) {
        final pid = p['id'];
        newGrid[d]![pid] = [];
      }
    }

    for (final rec in _timetable) {
      final day = rec is Map ? (rec['_dayShort'] ?? '') : '';
      final pid = rec is Map ? (rec['_periodId'] ?? null) : null;
      if (day == '' || pid == null) continue;
      if (!newGrid.containsKey(day)) newGrid[day] = {};
      newGrid[day]![pid] = (newGrid[day]![pid] ?? [])..add(rec);
    }

    if (mounted) setState(() => _grid = newGrid);
  }

  void _prevWeek() {
    setState(() {
      _currentMonday = _currentMonday.subtract(const Duration(days: 7));
      _loading = true;
    });
    _loadAll().then((_) => WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTodayExact()));
  }

  void _nextWeek() {
    setState(() {
      _currentMonday = _currentMonday.add(const Duration(days: 7));
      _loading = true;
    });
    _loadAll().then((_) => WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTodayExact()));
  }

  String _weekTitle() {
    final weekOfMonth = ((_currentMonday.day - 1) ~/ 7) + 1;
    final shortMonth = DateFormat.MMM().format(_currentMonday).toUpperCase();
    return 'Week $weekOfMonth $shortMonth';
  }

  void _scrollToTodayExact() {
    final todayIndex = (DateTime.now().weekday + 6) % 7; // Monday=0
    final key = _dayKeys[DAYS[todayIndex]];
    if (key == null) return;
    final ctx = key.currentContext;
    if (ctx == null) return;
    try {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), alignment: 0.12);
    } catch (_) {}
  }

  // Helper: today's scheduled records list
  List<dynamic> _todaysRecords() {
    final todayIndex = (DateTime.now().weekday + 6) % 7;
    final dayShort = DAYS[todayIndex];
    final date = formatDateShort(_currentMonday.add(Duration(days: todayIndex)));
    // If grid has entries use that; else fall back parsing timetable for day
    final fromGrid = _grid[dayShort];
    if (fromGrid != null) {
      final list = <dynamic>[];
      for (final pid in fromGrid.keys) {
        final recs = fromGrid[pid] ?? [];
        list.addAll(recs.map((r) {
          if (r is Map) {
            return {...r, '_periodId': pid};
          }
          return r;
        }));
      }
      return list;
    }

    // fallback
    return _timetable.where((r) {
      try {
        final day = r is Map ? (r['_dayShort'] ?? '') : '';
        final recDate = r is Map ? (r['date'] ?? '') : '';
        return day == dayShort || recDate == date;
      } catch (_) {
        return false;
      }
    }).toList();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _todayPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final todayStr = formatDateShort(DateTime.now());

    // compute simple daily adjusted workloads
    final dailyAdjusted = <String, int>{};
    for (final d in DAYS) {
      final date = formatDateShort(_currentMonday.add(Duration(days: DAYS.indexOf(d))));
      final holiday = _holidays.firstWhere((h) {
        try {
          if (h is Map) return h['date'] == date || h['day'] == date;
        } catch (_) {}
        return false;
      }, orElse: () => null);
      if (holiday != null) {
        dailyAdjusted[d] = 0;
        continue;
      }

      var reg = 0, red = 0, green = 0;
      for (final p in _periods) {
        final pid = p['id'];
        final cell = _grid[d] != null ? (_grid[d]![pid] ?? []) : [];
        reg += cell.length;

        red += (_originalSubs[date] ?? []).where((s) {
          final pId = s is Map ? (s['periodId'] ?? s['period_id'] ?? s['PeriodId']) : null;
          return pId == pid;
        }).length;

        green += (_substitutedSubs[date] ?? []).where((s) {
          final pId = s is Map ? (s['periodId'] ?? s['period_id'] ?? s['PeriodId']) : null;
          return pId == pid;
        }).length;
      }

      dailyAdjusted[d] = reg - red + green;
    }

    final totalAdjusted = dailyAdjusted.values.fold<int>(0, (a, b) => a + b);

    // Today's list for the slider
    final todays = _todaysRecords();

    return Scaffold(
      appBar: AppBar(
        elevation: 2,
        title: const Text('My Timetable'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                children: [
                  if (_errors.isNotEmpty)
                    Card(
                      color: Colors.orange.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _errors.map((e) => Text('• $e', style: const TextStyle(color: Colors.black87))).toList(),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),

                  // Week header + stats chips
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      child: Row(
                        children: [
                          IconButton(onPressed: _prevWeek, icon: const Icon(Icons.chevron_left)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(_weekTitle(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                const SizedBox(height: 6),
                                Text(DateFormat.MMM().format(_currentMonday).toUpperCase(), style: const TextStyle(color: Colors.black54)),
                              ],
                            ),
                          ),
                          Column(
                            children: [
                              Chip(
                                label: Text('Adjusted $totalAdjusted'),
                                backgroundColor: Colors.indigo.shade50,
                                avatar: const Icon(Icons.assessment, color: Colors.indigo),
                              ),
                              const SizedBox(height: 6),
                              Chip(
                                label: Text('Teacher: ${_teacherId > 0 ? _teacherId : 'N/A'}'),
                                backgroundColor: Colors.grey.shade100,
                                avatar: const Icon(Icons.person, color: Colors.black54),
                              ),
                            ],
                          ),
                          IconButton(onPressed: _nextWeek, icon: const Icon(Icons.chevron_right)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Today's slider header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.today, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text('Today', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text(DateFormat.yMMMd().format(DateTime.now()), style: const TextStyle(color: Colors.black54)),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Today's timetable slider (horizontal PageView)
                  if (todays.isEmpty)
                    Card(
                      color: Colors.grey.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: const [
                            Icon(Icons.hourglass_empty),
                            SizedBox(width: 12),
                            Expanded(child: Text('No classes scheduled for today')),
                          ],
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 150,
                      child: PageView.builder(
                        controller: _todayPageController,
                        itemCount: todays.length,
                        padEnds: true,
                        itemBuilder: (context, index) {
                          final rec = todays[index] as Map?;
                          final className = rec?['Class'] is Map ? rec!['Class']['class_name'] ?? '' : (rec?['class'] ?? '');
                          final subject = rec?['Subject'] is Map ? rec!['Subject']['name'] ?? '' : (rec?['subject'] ?? rec?['subjectId'] ?? '');
                          final periodName = (() {
                            // try to find period name from _periods list
                            final pid = rec?['_periodId'] ?? rec?['periodId'] ?? rec?['period_id'];
                            final p = _periods.firstWhere((e) => e['id'] == pid, orElse: () => null);
                            if (p != null) return p['period_name'] ?? p['name'] ?? 'P$pid';
                            return rec?['period_name'] ?? rec?['period'] ?? 'P';
                          })();
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Material(
                              elevation: 3,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: LinearGradient(colors: [Colors.indigo.shade50, Colors.white]),
                                ),
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 28,
                                      backgroundColor: Colors.indigo.shade100,
                                      child: Text(periodName.toString().split(' ').map((s) => s.isNotEmpty ? s[0] : '').take(2).join(), style: const TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(className ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                          const SizedBox(height: 6),
                                          Text(subject ?? '', style: const TextStyle(color: Colors.black54)),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Chip(
                                          label: Text(periodName ?? ''),
                                          backgroundColor: Colors.green.shade50,
                                        ),
                                        const SizedBox(height: 6),
                                        IconButton(
                                          onPressed: () {
                                            // quick action: open detailed day modal for the period's day
                                            final todayIndex = (DateTime.now().weekday + 6) % 7;
                                            final date = formatDateShort(_currentMonday.add(Duration(days: todayIndex)));
                                            _openDayDetails(DAYS[todayIndex], date);
                                          },
                                          icon: const Icon(Icons.open_in_new),
                                        )
                                      ],
                                    )
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 18),

                  // Pill header: Day | Work
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 3, offset: const Offset(0, 1))]),
                    child: Row(
                      children: const [
                        SizedBox(width: 6),
                        Text('Day', style: TextStyle(fontWeight: FontWeight.bold)),
                        Spacer(),
                        Text('Work', style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(width: 6),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Day cards list
                  for (final day in DAYS)
                    _dayCard(
                      day,
                      formatDateShort(_currentMonday.add(Duration(days: DAYS.indexOf(day)))),
                      todayStr,
                      dailyAdjusted[day] ?? 0,
                    ),

                  const SizedBox(height: 12),

                  // footer summary
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(child: Text('Teacher ID: ${_teacherId > 0 ? _teacherId : 'N/A'}')),
                          Text('Adjusted total: $totalAdjusted'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _dayCard(String day, String date, String todayStr, int workload) {
    final isToday = date == todayStr;
    final key = _dayKeys[day];

    return Card(
      key: key,
      color: isToday ? Colors.blue.shade50 : Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: Container(
          width: 64,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: isToday ? Colors.blue.shade100 : Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(day, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Day ${DAYS.indexOf(day) + 1}', style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            _buildPeriodPreview(day),
            const SizedBox(height: 6),
            Row(
              children: [
                if (isToday)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.blue.shade700, borderRadius: BorderRadius.circular(6)),
                    child: const Text('Today', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                const SizedBox(width: 8),
                if (_holidays.any((h) {
                  try {
                    return (h is Map) && (h['date'] == date || h['day'] == date);
                  } catch (_) {
                    return false;
                  }
                }))
                  const Icon(Icons.beach_access, color: Colors.orange),
              ],
            )
          ],
        ),
        trailing: Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
          child: Center(child: Text('$workload', style: const TextStyle(fontWeight: FontWeight.bold))),
        ),
        onTap: () => _openDayDetails(day, date),
      ),
    );
  }

  Widget _buildPeriodPreview(String day) {
    if (_periods.isEmpty) return const Text('-', style: TextStyle(color: Colors.black54));
    final items = <Widget>[];
    for (final p in _periods.take(2)) {
      final pid = p['id'];
      final cell = _grid[day] != null ? (_grid[day]![pid] ?? []) : [];
      if (cell.isEmpty) {
        items.add(Text('${p['period_name'] ?? p['name'] ?? ''}: -', style: const TextStyle(fontSize: 12, color: Colors.black54)));
      } else {
        final rec = cell.first;
        final className = rec is Map ? (rec['Class']?['class_name'] ?? rec['class'] ?? '') : '';
        final subject = rec is Map ? (rec['Subject']?['name'] ?? rec['subject'] ?? '') : '';
        items.add(Text('${className ?? ''} • ${subject ?? ''}', style: const TextStyle(fontSize: 12)));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: items);
  }

  void _openDayDetails(String day, String date) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(height: 4, width: 40, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text(day, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView(
                  shrinkWrap: true,
                  children: _periods.map((p) {
                    final pid = p['id'];
                    final cell = _grid[day] != null ? (_grid[day]![pid] ?? []) : [];
                    if (cell.isEmpty) {
                      return ListTile(
                        leading: CircleAvatar(backgroundColor: Colors.grey.shade200, child: const Icon(Icons.hourglass_empty)),
                        title: Text(p['period_name'] ?? p['name'] ?? 'Period $pid'),
                        subtitle: const Text('No class'),
                      );
                    }
                    return Column(
                      children: cell.map<Widget>((rec) {
                        final className = rec is Map ? (rec['Class']?['class_name'] ?? rec['class'] ?? '') : '';
                        final subject = rec is Map ? (rec['Subject']?['name'] ?? rec['subject'] ?? '') : '';
                        return ListTile(
                          leading: CircleAvatar(backgroundColor: Colors.indigo.shade50, child: const Icon(Icons.class_)),
                          title: Text(className ?? ''),
                          subtitle: Text(subject ?? ''),
                          trailing: Text(p['period_name'] ?? p['name'] ?? ''),
                        );
                      }).toList(),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}
