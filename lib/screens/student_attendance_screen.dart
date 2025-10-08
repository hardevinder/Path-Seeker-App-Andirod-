// lib/screens/student_attendance_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Replace with your API base URL or provide via constants/config
const String API_URL = String.fromEnvironment('API_URL', defaultValue: '');

class StudentAttendanceScreen extends StatefulWidget {
  const StudentAttendanceScreen({super.key});

  @override
  State<StudentAttendanceScreen> createState() => _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState extends State<StudentAttendanceScreen> {
  DateTime currentMonth = DateTime.now();
  List<Map<String, dynamic>> attendanceRecords = [];
  List<Map<String, dynamic>> holidaysRaw = [];
  String? studentName;
  int? studentClassId;
  String? selectedDate; // yyyy-MM-dd
  bool loading = true;

  // title auto-scroll
  Timer? _titleTimer;
  int _titleIndex = 0;
  final Duration _titleInterval = const Duration(seconds: 3);

  // KPI tiles pager (nullable controller for safe init)
  PageController? _kpiPageController;
  Timer? _kpiTimer;
  int _kpiPage = 0;
  final Duration _kpiInterval = const Duration(seconds: 4);
  final Duration _kpiAnim = const Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    // start data load immediately
    _loadInitial();

    // safe init: create controller now
    _kpiPageController = PageController(viewportFraction: 0.68);

    // start timers after first frame to avoid build-time race
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startTitleTimer();
      _startKpiTimer();
    });
  }

  @override
  void dispose() {
    _titleTimer?.cancel();
    _kpiTimer?.cancel();
    _kpiPageController?.dispose();
    super.dispose();
  }

  void _startTitleTimer() {
    _titleTimer?.cancel();
    _titleTimer = Timer.periodic(_titleInterval, (_) {
      setState(() {
        _titleIndex = (_titleIndex + 1) % _currentTitles().length;
      });
    });
  }

  void _startKpiTimer() {
    _kpiTimer?.cancel();
    _kpiTimer = Timer.periodic(_kpiInterval, (_) {
      final count = _kpiItems().length;
      if (count == 0 || _kpiPageController == null || !_kpiPageController!.hasClients) return;
      _kpiPage = (_kpiPage + 1) % count;
      _kpiPageController!.animateToPage(_kpiPage, duration: _kpiAnim, curve: Curves.easeInOut);
      setState(() {});
    });
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authToken') ?? prefs.getString('token');
  }

  Future<void> _loadInitial() async {
    setState(() => loading = true);
    await _fetchAttendance();
    await _fetchHolidays();
    selectedDate = DateFormat('yyyy-MM-dd').format(DateTime(currentMonth.year, currentMonth.month, 1));
    setState(() => loading = false);
  }

  Future<void> _fetchAttendance() async {
    final token = await _getToken();
    if (token == null || API_URL.isEmpty) return;
    try {
      final res = await http.get(Uri.parse('$API_URL/attendance/student/me'), headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = (body is List) ? List<Map<String, dynamic>>.from(body) : <Map<String, dynamic>>[];
        setState(() {
          attendanceRecords = list;
          if (list.isNotEmpty) {
            studentName = list.first['student']?['name'] ?? list.first['studentName'] ?? studentName;
            studentClassId = list.first['student']?['class_id'] ?? list.first['student']?['classId'] ?? studentClassId;
          }
        });
      }
    } catch (e) {
      debugPrint('attendance fetch error: $e');
    }
  }

  Future<void> _fetchHolidays() async {
    final token = await _getToken();
    if (token == null || API_URL.isEmpty) return;
    try {
      final res = await http.get(Uri.parse('$API_URL/holidays'), headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = (body is List) ? List<Map<String, dynamic>>.from(body) : <Map<String, dynamic>>[];
        setState(() => holidaysRaw = list);
      }
    } catch (e) {
      debugPrint('holidays fetch error: $e');
    }
  }

  Map<String, Map<String, dynamic>> get holidaysMap {
    final Map<String, Map<String, dynamic>> idx = {};
    for (final h in holidaysRaw) {
      final dStr = _dateFromAny(h['date']);
      if (dStr == null) continue;
      idx.putIfAbsent(dStr, () => {'rows': <Map<String, dynamic>>[], 'byClass': <String, Map<String, dynamic>>{}});
      idx[dStr]!['rows'].add(h);
      final clsId = (h['class'] is Map) ? (h['class']['id']?.toString()) : (h['classId']?.toString());
      if (clsId != null) idx[dStr]!['byClass'][clsId] = h;
    }
    return idx;
  }

  String? _dateFromAny(dynamic d) {
    if (d == null) return null;
    try {
      if (d is String) {
        final parsed = DateTime.tryParse(d);
        if (parsed != null) return DateFormat('yyyy-MM-dd').format(parsed);
        final n = int.tryParse(d);
        if (n != null) return DateFormat('yyyy-MM-dd').format(DateTime.fromMillisecondsSinceEpoch(n));
      } else if (d is int) {
        return DateFormat('yyyy-MM-dd').format(DateTime.fromMillisecondsSinceEpoch(d));
      } else if (d is DateTime) {
        return DateFormat('yyyy-MM-dd').format(d);
      }
    } catch (_) {}
    return null;
  }

  List<DateTime?> get calendarCells {
    final startOfMonth = DateTime(currentMonth.year, currentMonth.month, 1);
    final endOfMonth = DateTime(currentMonth.year, currentMonth.month + 1, 0);
    final startDay = startOfMonth.weekday % 7;
    final totalDays = endOfMonth.day;
    final List<DateTime?> cells = [];
    for (int i = 0; i < startDay; i++) cells.add(null);
    for (int d = 1; d <= totalDays; d++) cells.add(DateTime(currentMonth.year, currentMonth.month, d));
    return cells;
  }

  Map<String, dynamic>? _attendanceForDate(String dateStr) {
    try {
      final found = attendanceRecords.firstWhere((r) => (r['date']?.toString() ?? '') == dateStr, orElse: () => <String, dynamic>{});
      return found.isEmpty ? null : found;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _holidayForDisplay(String dateStr) {
    final v = holidaysMap[dateStr];
    if (v == null) return null;
    if (studentClassId != null && v['byClass'][studentClassId.toString()] != null) {
      return v['byClass'][studentClassId.toString()] as Map<String, dynamic>?;
    }
    final rows = List<Map<String, dynamic>>.from(v['rows'] as List);
    if (rows.isEmpty) return null;
    final descs = rows.map((r) => (r['description'] ?? '').toString()).where((s) => s.isNotEmpty).toSet().toList();
    return {
      'description': descs.join(' • '),
      'rows': rows,
    };
  }

  int _countForMonth(String status) {
    final m = DateFormat('yyyy-MM').format(currentMonth);
    return attendanceRecords.where((r) {
      final d = r['date']?.toString();
      return d != null && d.startsWith(m) && (r['status'] ?? '').toString().toLowerCase() == status;
    }).length;
  }

  int _totalForMonth() {
    final m = DateFormat('yyyy-MM').format(currentMonth);
    return attendanceRecords.where((r) => (r['date']?.toString() ?? '').startsWith(m)).length;
  }

  Map<String, int> _monthStats() {
    final total = _totalForMonth();
    final p = _countForMonth('present');
    final a = _countForMonth('absent');
    final l = _countForMonth('leave');
    return {'total': total, 'present': p, 'absent': a, 'leave': l, 'percent': total > 0 ? ((p / total * 100).round()) : 0};
  }

  Map<String, dynamic>? get nextHoliday {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final keys = holidaysMap.keys.where((k) => k.compareTo(today) >= 0).toList()..sort();
    if (keys.isEmpty) return null;
    for (final k in keys) {
      final v = holidaysMap[k]!;
      if (v['byClass'][studentClassId?.toString() ?? ''] != null) {
        final row = v['byClass'][studentClassId.toString()];
        return {'date': k, 'description': row?['description'] ?? 'Holiday'};
      }
    }
    final k = keys.first;
    final rows = holidaysMap[k]!['rows'] as List;
    final descs = rows.map((r) => (r['description'] ?? '').toString()).where((s) => s.isNotEmpty).toSet().toList();
    return {'date': k, 'description': descs.join(' • ')};
  }

  void _onPrevMonth() {
    setState(() {
      currentMonth = DateTime(currentMonth.year, currentMonth.month - 1, 1);
      selectedDate = DateFormat('yyyy-MM-dd').format(DateTime(currentMonth.year, currentMonth.month, 1));
    });
  }

  void _onNextMonth() {
    setState(() {
      currentMonth = DateTime(currentMonth.year, currentMonth.month + 1, 1);
      selectedDate = DateFormat('yyyy-MM-dd').format(DateTime(currentMonth.year, currentMonth.month, 1));
    });
  }

  static Future<DateTime?> showMonthPicker(BuildContext ctx, DateTime initial) {
    int year = initial.year;
    int month = initial.month;
    return showDialog<DateTime>(
      context: ctx,
      builder: (c) {
        return StatefulBuilder(builder: (context, setSt) {
          return AlertDialog(
            title: const Text('Select month'),
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<int>(
                  value: month,
                  items: List.generate(12, (i) => i + 1).map((m) => DropdownMenuItem(value: m, child: Text(DateFormat.MMM().format(DateTime(0, m, 1))))).toList(),
                  onChanged: (v) {
                    if (v != null) setSt(() => month = v);
                  },
                ),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: year,
                  items: List.generate(6, (i) => year - 3 + i).map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
                  onChanged: (v) {
                    if (v != null) setSt(() => year = v);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(c, DateTime(year, month, 1)), child: const Text('OK')),
            ],
          );
        });
      },
    );
  }

  // Titles used by AnimatedSwitcher
  List<String> _currentTitles() {
    final stats = _monthStats();
    final percent = stats['percent'] ?? 0;
    final next = nextHoliday;
    final List<String> list = [];
    list.add('Attendance Calendar');
    list.add('% Presence: $percent%');
    if (next != null) {
      final d = DateFormat('dd MMM').format(DateTime.parse(next['date']));
      list.add('Next holiday: $d');
    }
    return list;
  }

  // ---------------------------
  // HERO (title auto-scroll: one title at a time; month box on next line)
  // ---------------------------
  Widget _hero() {
    final titles = _currentTitles();
    final currentTitle = titles.isEmpty ? 'Attendance Calendar' : titles[_titleIndex % titles.length];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF7B2FF7), Color(0xFFF107A3)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // AnimatedSwitcher shows one title at a time and switches smoothly
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            transitionBuilder: (child, anim) {
              return FadeTransition(opacity: anim, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(anim), child: child));
            },
            child: Text(
              currentTitle,
              key: ValueKey<String>(currentTitle),
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),
          // Month box centered on the next line
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(onPressed: _onPrevMonth, icon: const Icon(Icons.chevron_left, color: Colors.white)),
              SizedBox(
                height: 40,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    final picked = await showMonthPicker(context, currentMonth);
                    if (picked != null) setState(() => currentMonth = picked);
                  },
                  child: Text(DateFormat('MMM yyyy').format(currentMonth), style: const TextStyle(fontSize: 14)),
                ),
              ),
              IconButton(onPressed: _onNextMonth, icon: const Icon(Icons.chevron_right, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 12),
          // legend explaining color mapping (no text inside calendar cells)
          Wrap(
            spacing: 10,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _legendChip('P', Colors.green, 'Present'),
              _legendChip('A', Colors.red, 'Absent'),
              _legendChip('L', Colors.amber, 'Leave'),
              _legendChip('S', Colors.blue, 'Sunday'),
              _legendChip('H', Colors.orange, 'Holiday'),
              _legendChip('NM', Colors.grey, 'Not marked'),
            ],
          )
        ],
      ),
    );
  }

  Widget _legendChip(String label, Color color, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  // Build KPI PageView items (narrow with gap)
  List<Map<String, dynamic>> _kpiItems() {
    final stats = _monthStats();
    return [
      {'title': 'Total', 'value': stats['total'].toString(), 'colors': [const Color(0xFF00C6FF), const Color(0xFF0072FF)]},
      {'title': 'Present', 'value': stats['present'].toString(), 'colors': [const Color(0xFF11998E), const Color(0xFF38EF7D)]},
      {'title': 'Absent', 'value': stats['absent'].toString(), 'colors': [const Color(0xFFFF416C), const Color(0xFFFF4B2B)]},
      {'title': 'Leave', 'value': stats['leave'].toString(), 'colors': [const Color(0xFFF7971E), const Color(0xFFFFD200)]},
      {'title': '% Presence', 'value': '${stats['percent']}%', 'colors': [const Color(0xFF8E2DE2), const Color(0xFF4A00E0)]},
    ];
  }

  Widget _kpiPager() {
    final items = _kpiItems();
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 100,
          child: PageView.builder(
            controller: _kpiPageController,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _kpiPage = i),
            itemBuilder: (context, i) {
              final it = items[i];
              // add horizontal gap by wrapping with padding
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: List<Color>.from(it['colors']), begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 6))],
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(it['title'], style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text(it['value'], style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                  ]),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // compact dots indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(items.length, (i) {
            final active = i == _kpiPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: active ? 18 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: active ? const Color(0xFF6C63FF) : Colors.black.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
            );
          }),
        ),
      ],
    );
  }

  // calendar grid - show date + small colored dot for status
  Widget _calendarGrid() {
    final cells = calendarCells;
    // single-letter abbreviations as requested for day headers
    final dayHeader = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Column(
      children: [
        Row(children: dayHeader.map((d) => Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(d, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))))).toList()),
        const SizedBox(height: 8),
        GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: cells.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, crossAxisSpacing: 6, mainAxisSpacing: 6, childAspectRatio: 0.95),
          itemBuilder: (c, i) {
            final cell = cells[i];
            if (cell == null) return Container(); // empty spacer
            final dateStr = DateFormat('yyyy-MM-dd').format(cell);
            final att = _attendanceForDate(dateStr);
            final hol = _holidayForDisplay(dateStr);
            final isFuture = cell.isAfter(DateTime.now());
            final isSunday = cell.weekday == DateTime.sunday;

            Color dotColor = Colors.grey;
            bool notMarkedFlag = false;
            String tooltip = DateFormat('dd MMM yyyy').format(cell);

            if (hol != null) {
              dotColor = Colors.orange;
              tooltip += '\nHoliday: ${hol['description'] ?? ''}';
            } else if (!isFuture && att != null) {
              final s = (att['status'] ?? '').toString().toLowerCase();
              if (s == 'present') dotColor = Colors.green;
              else if (s == 'absent') dotColor = Colors.red;
              else if (s == 'leave') dotColor = Colors.amber;
              else dotColor = Colors.grey;
              tooltip += '\nStatus: ${(att['status'] ?? '').toString()}';
            } else if (isSunday) {
              dotColor = Colors.blue;
              tooltip += '\nSunday';
            } else if (!isFuture && att == null) {
              dotColor = Colors.grey;
              notMarkedFlag = true;
              tooltip += '\nNot marked';
            }

            final bool isSelected = selectedDate == dateStr;

            return GestureDetector(
              onTap: () => setState(() => selectedDate = dateStr),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isSelected ? Colors.deepPurple : Colors.black12, width: isSelected ? 2 : 1),
                  boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 6))] : null,
                ),
                child: Tooltip(
                  message: tooltip,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // date number top-left
                      Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          '${cell.day}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isSelected ? Colors.deepPurple : Colors.black87),
                        ),
                      ),
                      const Spacer(),

                      // small colored dot indicator centered bottom
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // if you want a subtle outline for not-marked show a small ring instead
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: dotColor,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 3, offset: const Offset(0, 2))],
                              border: notMarkedFlag ? Border.all(color: Colors.grey.shade300, width: 1.5) : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _rightPanel() {
    if (selectedDate == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
        child: const Text('Select a date to view details', textAlign: TextAlign.center),
      );
    }

    final hol = _holidayForDisplay(selectedDate!);
    if (hol != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Holiday', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.blue.shade900)),
          const SizedBox(height: 8),
          Text(hol['description'] ?? 'Holiday for this date', style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 8),
          if ((hol['rows'] as List?)?.isNotEmpty ?? false)
            Text('Declared by: ${(hol['rows'] as List).map((r) => r['creator']?['name'] ?? r['creator']?['email']).where((e) => e != null).join(", ")}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      );
    }

    final stats = _monthStats();
    final present = stats['present'] as int;
    final absent = stats['absent'] as int;
    final leave = stats['leave'] as int;
    final total = stats['total'] as int;

    // If there's no data to plot, show placeholder instead of an empty pie chart
    if (total == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
          const Text('Attendance Summary', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 16),
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6)]),
            child: Center(child: Text('No data', style: TextStyle(color: Colors.grey.shade700))),
          ),
          const SizedBox(height: 12),
          const Text('No attendance records for this month', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
        ]),
      );
    }

    // else show pie chart
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Attendance Summary', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 30,
              sections: [
                PieChartSectionData(value: present.toDouble(), color: Colors.green, title: '${present}', titleStyle: const TextStyle(color: Colors.white)),
                PieChartSectionData(value: absent.toDouble(), color: Colors.red, title: '${absent}', titleStyle: const TextStyle(color: Colors.white)),
                PieChartSectionData(value: leave.toDouble(), color: Colors.amber, title: '${leave}', titleStyle: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          _legendDot('P = Present', Colors.green),
          _legendDot('A = Absent', Colors.red),
          _legendDot('L = Leave', Colors.amber),
          _legendDot('S = Sunday', Colors.blue),
          _legendDot('NM = Not marked', Colors.grey),
          _legendDot('H = Holiday', Colors.orange),
        ]),
        const SizedBox(height: 12),
        Text('Total marked: $total', style: const TextStyle(color: Colors.black54)),
      ]),
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12)),
    ]);
  }

  Widget _monthlyHolidayList() {
    final start = DateTime(currentMonth.year, currentMonth.month, 1);
    final end = DateTime(currentMonth.year, currentMonth.month + 1, 0);
    final list = holidaysMap.entries.where((e) {
      final d = DateTime.parse(e.key);
      return d.isAtSameMomentAs(start) || (d.isAfter(start) && d.isBefore(end)) || d.isAtSameMomentAs(end);
    }).toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (list.isEmpty) {
      return Container(padding: const EdgeInsets.all(12), child: const Text('No holidays this month.'));
    }

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
      child: Column(
        children: list.map((entry) {
          final d = entry.key;
          final rows = List<Map<String, dynamic>>.from(entry.value['rows'] as List);
          final descs = rows.map((r) => (r['description'] ?? '').toString()).where((s) => s.isNotEmpty).toSet().join(' • ');
          final creators = rows.map((r) => r['creator']?['name'] ?? r['creator']?['email']).where((s) => s != null).toSet().join(', ');
          return ListTile(
            title: Text(DateFormat('EEE, dd MMM').format(DateTime.parse(d))),
            subtitle: Text(descs.isNotEmpty ? descs : 'Holiday'),
            trailing: const Chip(label: Text('Holiday')),
            isThreeLine: creators.isNotEmpty,
            dense: true,
          );
        }).toList(),
      ),
    );
  }

  String? get studentClassName {
    if (studentClassId == null) return null;
    final map = {
      0: "Pre Nursery",1:"Nursery",2:"LKG",3:"UKG",4:"I",5:"II",6:"III",7:"IV",8:"V",9:"VI",10:"VII",11:"VIII",12:"IX",13:"X",18:"XI",19:"XII"
    };
    return map[studentClassId] ?? 'Class ${studentClassId}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        backgroundColor: const Color(0xFF6C63FF),
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF6F9FF),
      body: RefreshIndicator(
        onRefresh: _loadInitial,
        color: const Color(0xFF6C63FF),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _hero(), // title (auto-scroll) + month box on next line + legend
              const SizedBox(height: 16),
              _kpiPager(), // single KPI tile visible at a time with auto-scroll (narrow)
              const SizedBox(height: 18),
              LayoutBuilder(builder: (context, constraints) {
                final wide = constraints.maxWidth > 900;
                return wide
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          flex: 2,
                          child: Column(children: [
                            Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
                                child: _calendarGrid()),
                            const SizedBox(height: 12),
                            _monthlyHolidayList(),
                          ]),
                        ),
                        const SizedBox(width: 16),
                        Expanded(flex: 1, child: _rightPanel()),
                      ])
                    : Column(children: [
                        Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
                            child: _calendarGrid()),
                        const SizedBox(height: 12),
                        _rightPanel(),
                        const SizedBox(height: 12),
                        _monthlyHolidayList(),
                      ]);
              }),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
