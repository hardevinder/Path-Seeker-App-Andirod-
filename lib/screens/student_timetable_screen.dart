import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/constants.dart';

class StudentTimetableScreen extends StatefulWidget {
  const StudentTimetableScreen({super.key});

  @override
  State<StudentTimetableScreen> createState() => _StudentTimetableScreenState();
}

class _StudentTimetableScreenState extends State<StudentTimetableScreen> {
  static const Color kBrand = Color(0xFF5B5FEF);
  static const Color kBrandDark = Color(0xFF3D43C6);
  static const Color kPageBg = Color(0xFFF6F8FF);

  bool isLoading = true;
  String? error;
  List<dynamic> periods = [];
  List<dynamic> timetable = [];
  List<dynamic> holidays = [];
  Map<String, List<dynamic>> studentSubs = {};
  Map<String, Map<dynamic, List<dynamic>>> grid = {};

  String? token;
  List<String> roles = [];
  bool isStudent = false;
  bool isParent = false;
  bool canSeeStudentSwitcher = false;
  Map<String, dynamic>? family;
  String activeStudentAdmission = '';
  String loggedInAdmission = '';
  dynamic activeClassId;

  final List<String> days = const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
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

  String _normalizeAdmission(String s) => s.replaceAll('/', '-').trim();

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

  String _formatDayDate(DateTime d) => DateFormat('dd MMM').format(d);

  Map<String, String> _weekDatesMap() {
    final map = <String, String>{};
    for (var i = 0; i < days.length; i++) {
      final d = DateTime(currentMonday.year, currentMonday.month, currentMonday.day + i);
      map[days[i]] = _formatDateYmd(d);
    }
    return map;
  }

  String _weekRangeLabel() {
    final start = currentMonday;
    final end = currentMonday.add(const Duration(days: 5));
    final sameMonth = start.month == end.month && start.year == end.year;
    if (sameMonth) {
      return '${DateFormat('dd').format(start)}–${DateFormat('dd MMM yyyy').format(end)}';
    }
    return '${DateFormat('dd MMM').format(start)} – ${DateFormat('dd MMM yyyy').format(end)}';
  }

  List<Map<String, dynamic>> _familyStudents() {
    final students = <Map<String, dynamic>>[];
    if (family?['student'] != null) {
      students.add({...Map<String, dynamic>.from(family!['student']), 'isSelf': true});
    }
    for (final s in (family?['siblings'] ?? [])) {
      if (s is Map) {
        students.add({...Map<String, dynamic>.from(s), 'isSelf': false});
      }
    }
    return students;
  }

  void _computeActiveClassId() {
    activeClassId = null;
    if (family == null) return;

    final active = _normalizeAdmission(activeStudentAdmission);
    Map<String, dynamic>? activeStudent;

    for (final s in _familyStudents()) {
      final adm = _normalizeAdmission((s['admission_number'] ?? '').toString());
      if (adm == active) {
        activeStudent = s;
        break;
      }
    }

    if (activeStudent == null) return;

    activeClassId = activeStudent['classId'] ??
        activeStudent['class_id'] ??
        (activeStudent['class'] is Map ? activeStudent['class']['id'] : null);
  }

  Map<String, dynamic>? _holidayForDate(String dateYmd) {
    Map<String, dynamic>? globalHoliday;

    for (final h in holidays) {
      if (h is! Map) continue;
      final hDate = (h['date'] ?? '').toString();
      if (hDate != dateYmd) continue;

      final hClassId = h['classId'] ?? h['class_id'] ?? (h['class'] is Map ? h['class']['id'] : null);
      if (activeClassId != null && hClassId?.toString() == activeClassId.toString()) {
        return Map<String, dynamic>.from(h);
      }
      if (hClassId == null) {
        globalHoliday = Map<String, dynamic>.from(h);
      }
    }

    return globalHoliday;
  }

  String _holidayDescription(Map<String, dynamic>? holiday) {
    if (holiday == null) return 'Holiday';
    return (holiday['description'] ?? holiday['name'] ?? holiday['title'] ?? 'Holiday').toString();
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

  Future<void> _loadRolesAndFamily() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('authToken');

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

    try {
      final rawFamily = prefs.getString('family');
      family = rawFamily != null ? json.decode(rawFamily) : null;
    } catch (_) {}

    activeStudentAdmission = prefs.getString('activeStudentAdmission') ?? prefs.getString('username') ?? '';
    loggedInAdmission = prefs.getString('username') ?? '';

    activeStudentAdmission = _normalizeAdmission(activeStudentAdmission);
    loggedInAdmission = _normalizeAdmission(loggedInAdmission);
    _computeActiveClassId();
  }

  Future<String> _resolveTimetableUrl() async {
    final active = _normalizeAdmission(activeStudentAdmission);
    final logged = _normalizeAdmission(loggedInAdmission);

    if (!isStudent || (active.isNotEmpty && active != logged)) {
      final adm = Uri.encodeComponent(active);
      return '$baseUrl/period-class-teacher-subject/timetable/by-admission/$adm';
    }
    return '$baseUrl/period-class-teacher-subject/student/timetable';
  }

  Future<void> _loadAll() async {
    setState(() {
      isLoading = true;
      error = null;
      showNoMatchHint = false;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString('authToken');

      activeStudentAdmission = _normalizeAdmission(
        prefs.getString('activeStudentAdmission') ?? prefs.getString('username') ?? '',
      );
      loggedInAdmission = _normalizeAdmission(prefs.getString('username') ?? '');

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
        'Content-Type': 'application/json',
      };
      final timetableUrl = await _resolveTimetableUrl();

      final responses = await Future.wait([
        http.get(Uri.parse('$baseUrl/periods'), headers: headers),
        http.get(Uri.parse(timetableUrl), headers: headers),
        http.get(Uri.parse('$baseUrl/holidays'), headers: headers),
      ]);

      final pRes = responses[0];
      if (pRes.statusCode == 200) {
        final decoded = json.decode(pRes.body);
        periods = decoded is List ? decoded : (decoded['periods'] ?? []);
      } else {
        periods = [];
      }

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

      final hRes = responses[2];
      if (hRes.statusCode == 200) {
        final decoded = json.decode(hRes.body);
        holidays = decoded is List ? decoded : (decoded['holidays'] ?? []);
      } else {
        holidays = [];
      }

      await _fetchSubsForWeek(token!);
      _buildGrid();

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
      'Content-Type': 'application/json',
    };

    final dates = List.generate(days.length, (i) {
      final d = DateTime(currentMonday.year, currentMonday.month, currentMonday.day + i);
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

    if (mounted) {
      setState(() => studentSubs = subs);
    }
  }

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

    final hasMappedItem = newGrid.values.any((periodMap) => periodMap.values.any((items) => items.isNotEmpty));

    setState(() {
      grid = newGrid;
      showNoMatchHint = timetable.isNotEmpty && !hasMappedItem;
    });
  }

  Future<void> _handleStudentSwitch(String admissionNumber) async {
    final prefs = await SharedPreferences.getInstance();
    final adm = _normalizeAdmission(admissionNumber);
    if (adm == activeStudentAdmission) return;

    await prefs.setString('activeStudentAdmission', adm);
    setState(() => activeStudentAdmission = adm);

    _computeActiveClassId();
    await _loadAll();
  }

  String? get _activeStudentName {
    for (final s in _familyStudents()) {
      final adm = _normalizeAdmission((s['admission_number'] ?? '').toString());
      if (adm == activeStudentAdmission) {
        return (s['isSelf'] == true ? 'Me' : (s['name'] ?? 'Student')).toString();
      }
    }
    return null;
  }

  String? get _activeStudentClassLabel {
    for (final s in _familyStudents()) {
      final adm = _normalizeAdmission((s['admission_number'] ?? '').toString());
      if (adm == activeStudentAdmission) {
        final className = s['class'] is Map ? (s['class']['name'] ?? '') : (s['class_name'] ?? '');
        final sectionName = s['section'] is Map ? (s['section']['name'] ?? '') : (s['section_name'] ?? '');
        final classStr = className.toString().trim();
        final secStr = sectionName.toString().trim();
        if (classStr.isEmpty && secStr.isEmpty) return null;
        if (classStr.isNotEmpty && secStr.isNotEmpty) return '$classStr - $secStr';
        return classStr.isNotEmpty ? classStr : secStr;
      }
    }
    return null;
  }

  int get _weeklyClassCount {
    var count = 0;
    for (final day in days) {
      for (final p in periods) {
        final pid = _periodId(p);
        count += (grid[day]?[pid] ?? []).length;
      }
    }
    return count;
  }

  int get _weeklySubstitutionCount {
    var count = 0;
    for (final list in studentSubs.values) {
      count += list.length;
    }
    return count;
  }

  int get _weeklyHolidayCount {
    final weekMap = _weekDatesMap();
    var count = 0;
    for (final day in days) {
      if (_holidayForDate(weekMap[day] ?? '') != null) count++;
    }
    return count;
  }

  int _dayClassCount(String day) {
    var count = 0;
    for (final p in periods) {
      final pid = _periodId(p);
      count += (grid[day]?[pid] ?? []).length;
    }
    return count;
  }

  Widget _buildStudentSwitcher() {
    final students = _familyStudents();
    if (!canSeeStudentSwitcher || students.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.switch_account_rounded, color: kBrand, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Student Switcher',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Wrap(
              spacing: 8,
              children: students.map((s) {
                final adm = _normalizeAdmission((s['admission_number'] ?? '').toString());
                final isActive = adm == activeStudentAdmission;
                final label = (s['isSelf'] == true ? 'Me • ' : '') +
                    ((s['name'] ?? s['admission_number'] ?? 'Student').toString());

                return ChoiceChip(
                  selected: isActive,
                  showCheckmark: false,
                  selectedColor: kBrand,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: isActive ? kBrand : Colors.indigo.shade100),
                  labelStyle: TextStyle(
                    color: isActive ? Colors.white : kBrandDark,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                  ),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(label, overflow: TextOverflow.ellipsis),
                  ),
                  onSelected: (_) => _handleStudentSwitch(adm),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroHeader() {
    final activeName = _activeStudentName ?? 'Student';
    final classLabel = _activeStudentClassLabel;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF6B68FF), Color(0xFF464CDA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Weekly Timetable',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Class schedule at a glance',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      classLabel == null ? activeName : '$activeName • $classLabel',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: IconButton(
                  tooltip: 'Refresh',
                  onPressed: _loadAll,
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Current Week',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _weekRangeLabel(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _weekActionButton(
                      icon: Icons.chevron_left_rounded,
                      onTap: () async {
                        setState(() => currentMonday = currentMonday.subtract(const Duration(days: 7)));
                        await _loadAll();
                      },
                    ),
                    const SizedBox(width: 8),
                    _weekActionButton(
                      icon: Icons.chevron_right_rounded,
                      onTap: () async {
                        setState(() => currentMonday = currentMonday.add(const Duration(days: 7)));
                        await _loadAll();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      backgroundColor: Colors.white.withOpacity(0.12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      setState(() => currentMonday = _computeCurrentMonday(DateTime.now()));
                      await _loadAll();
                    },
                    icon: const Icon(Icons.calendar_today_rounded, size: 16),
                    label: const Text('Go to this week'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _weekActionButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.white.withOpacity(0.14),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }

  Widget _quickStat(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summarySection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 700;
          final items = [
            _quickStat('Planned Classes', _weeklyClassCount.toString(), Icons.menu_book_rounded, const Color(0xFF2E90FA)),
            _quickStat('Substitutions', _weeklySubstitutionCount.toString(), Icons.swap_horiz_rounded, const Color(0xFF12B76A)),
            _quickStat('Holidays', _weeklyHolidayCount.toString(), Icons.celebration_rounded, const Color(0xFFF79009)),
          ];

          if (wide) {
            return Row(
              children: [
                Expanded(child: items[0]),
                const SizedBox(width: 12),
                Expanded(child: items[1]),
                const SizedBox(width: 12),
                Expanded(child: items[2]),
              ],
            );
          }

          return Column(
            children: [
              items[0],
              const SizedBox(height: 12),
              items[1],
              const SizedBox(height: 12),
              items[2],
            ],
          );
        },
      ),
    );
  }

  Widget _legendSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _legendChip('Today', const Color(0xFFE8F0FF), kBrandDark),
          _legendChip('Holiday', const Color(0xFFFFF1E8), const Color(0xFFF79009)),
          _legendChip('Substitution', const Color(0xFFEAFBF2), const Color(0xFF12B76A)),
          _legendChip('No Class', const Color(0xFFF2F4F7), const Color(0xFF667085)),
        ],
      ),
    );
  }

  Widget _legendChip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _cellContainer({
    required Widget child,
    Color? color,
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
    bool borderRight = true,
    bool borderBottom = true,
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        border: Border(
          right: borderRight ? BorderSide(color: Colors.grey.shade200) : BorderSide.none,
          bottom: borderBottom ? BorderSide(color: Colors.grey.shade200) : BorderSide.none,
        ),
      ),
      child: child,
    );
  }

  Widget _buildDesktopTable(BuildContext context) {
    final weekMap = _weekDatesMap();
    final tableChildren = <TableRow>[];

    tableChildren.add(
      TableRow(
        decoration: BoxDecoration(color: Colors.grey.shade50),
        children: [
          _cellContainer(
            borderBottom: true,
            child: const Text('Day', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          ...List.generate(periods.length, (index) {
            final p = periods[index];
            final isLast = index == periods.length - 1;
            return _cellContainer(
              borderRight: !isLast,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _periodTitle(p),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (_periodTimes(p).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _periodTimes(p),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );

    for (final day in days) {
      final date = weekMap[day] ?? '';
      final dateObj = DateTime.tryParse(date);
      final isToday = date == _formatDateYmd(DateTime.now());
      final holiday = _holidayForDate(date);
      final subs = studentSubs[date] ?? [];

      tableChildren.add(
        TableRow(
          children: [
            _cellContainer(
              color: isToday ? const Color(0xFFF1F4FF) : Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          day,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: isToday ? kBrandDark : Colors.black87,
                          ),
                        ),
                      ),
                      if (isToday)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: kBrand.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Today',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kBrandDark),
                          ),
                        ),
                    ],
                  ),
                  if (dateObj != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('dd MMM yyyy').format(dateObj),
                      style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (holiday != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _holidayDescription(holiday),
                      style: const TextStyle(color: Color(0xFFF79009), fontWeight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
            ),
            ...List.generate(periods.length, (index) {
              final p = periods[index];
              final pid = _periodId(p);
              final isLast = index == periods.length - 1;
              final subsForPeriod = subs.where((s) {
                if (s is! Map) return false;
                final spid = s['periodId'] ?? s['period_id'];
                return spid?.toString() == pid?.toString() &&
                    (s['day']?.toString().toLowerCase() ?? '') == day.toLowerCase();
              }).toList();

              Widget child;
              Color bg = isToday ? const Color(0xFFFBFCFF) : Colors.white;

              if (holiday != null) {
                bg = const Color(0xFFFFF7ED);
                child = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Icon(Icons.celebration_rounded, color: Color(0xFFF79009), size: 18),
                    SizedBox(height: 6),
                    Text(
                      'Holiday',
                      style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFB54708)),
                    ),
                  ],
                );
              } else if (subsForPeriod.isNotEmpty) {
                final s = subsForPeriod.first as Map;
                final subject = (s['Subject'] is Map ? s['Subject']['name'] : '')?.toString() ?? '';
                final teacher = (s['Teacher'] is Map ? s['Teacher']['name'] : '')?.toString() ?? '';
                bg = const Color(0xFFEAFBF2);
                child = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Substitution',
                      style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF027A48)),
                    ),
                    if (subject.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(subject, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                    if (teacher.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(teacher, style: TextStyle(color: Colors.grey.shade700)),
                    ],
                  ],
                );
              } else {
                final recs = grid[day]?[pid] ?? [];
                if (recs.isEmpty) {
                  child = Text('—', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600));
                } else {
                  child = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: recs.map<Widget>((r) {
                      if (r is! Map) return const SizedBox.shrink();
                      final subject = (r['Subject'] is Map ? r['Subject']['name'] : '')?.toString() ?? '';
                      final teacher = (r['Teacher'] is Map ? r['Teacher']['name'] : '')?.toString() ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              subject.isEmpty ? 'Class' : subject,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            if (teacher.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(teacher, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  );
                }
              }

              return _cellContainer(
                color: bg,
                borderRight: !isLast,
                child: child,
              );
            }),
          ],
        ),
      );
    }

    return _sectionCard(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 32),
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              columnWidths: {
                0: const FixedColumnWidth(190),
                for (int i = 0; i < periods.length; i++) i + 1: const FixedColumnWidth(170),
              },
              children: tableChildren,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDayHeaderCard(String day, String date, bool isToday, Map<String, dynamic>? holiday) {
    final dateObj = DateTime.tryParse(date);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isToday ? const Color(0xFFF1F4FF) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isToday ? kBrand.withOpacity(0.22) : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isToday ? kBrand.withOpacity(0.12) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              holiday != null ? Icons.celebration_rounded : Icons.calendar_today_rounded,
              color: holiday != null ? const Color(0xFFF79009) : kBrand,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        day,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ),
                    if (isToday)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: kBrand.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Today',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kBrandDark),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  dateObj == null ? date : DateFormat('dd MMM yyyy').format(dateObj),
                  style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                ),
                if (holiday != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _holidayDescription(holiday),
                    style: const TextStyle(color: Color(0xFFF79009), fontWeight: FontWeight.w700),
                  ),
                ] else ...[
                  const SizedBox(height: 6),
                  Text(
                    '${_dayClassCount(day)} classes planned',
                    style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodCard({
    required String title,
    required String time,
    String? subject,
    String? teacher,
    required Color stripe,
    String? badge,
    Color? badgeBg,
    Color? badgeFg,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 5,
            height: 90,
            decoration: BoxDecoration(
              color: stripe,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (badge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: badgeBg ?? stripe.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: badgeFg ?? stripe),
                          ),
                        ),
                    ],
                  ),
                  if (time.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      time,
                      style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    (subject == null || subject.trim().isEmpty) ? 'No class assigned' : subject,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (teacher != null && teacher.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(teacher, style: TextStyle(color: Colors.grey.shade700)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileList() {
    final weekMap = _weekDatesMap();

    return _sectionCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ExpansionPanelList.radio(
          initialOpenPanelValue: mobileOpenIdx,
          elevation: 0,
          expandedHeaderPadding: EdgeInsets.zero,
          children: days.asMap().entries.map((entry) {
            final idx = entry.key;
            final day = entry.value;
            final date = weekMap[day] ?? '';
            final isToday = date == _formatDateYmd(DateTime.now());
            final subs = studentSubs[date] ?? [];
            final holiday = _holidayForDate(date);

            return ExpansionPanelRadio(
              value: idx,
              canTapOnHeader: true,
              headerBuilder: (_, __) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: _buildDayHeaderCard(day, date, isToday, holiday),
              ),
              body: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: holiday != null
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFED7AA)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.celebration_rounded, color: Color(0xFFF79009)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _holidayDescription(holiday),
                                style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB54708)),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: periods.map((p) {
                          final pid = _periodId(p);
                          final title = _periodTitle(p);
                          final time = _periodTimes(p);

                          final subsForPeriod = subs.where((s) {
                            if (s is! Map) return false;
                            final spid = s['periodId'] ?? s['period_id'];
                            final sday = (s['day'] ?? '').toString().toLowerCase();
                            return spid?.toString() == pid?.toString() && sday == day.toLowerCase();
                          }).toList();

                          if (subsForPeriod.isNotEmpty) {
                            final s = subsForPeriod.first as Map;
                            final subject = (s['Subject'] is Map ? s['Subject']['name'] : '')?.toString() ?? '';
                            final teacher = (s['Teacher'] is Map ? s['Teacher']['name'] : '')?.toString() ?? '';
                            return _periodCard(
                              title: title,
                              time: time,
                              subject: subject,
                              teacher: teacher,
                              stripe: const Color(0xFF12B76A),
                              badge: 'Substitution',
                              badgeBg: const Color(0xFFEAFBF2),
                              badgeFg: const Color(0xFF027A48),
                            );
                          }

                          final recs = grid[day]?[pid] ?? [];
                          if (recs.isEmpty) {
                            return _periodCard(
                              title: title,
                              time: time,
                              subject: 'No class',
                              stripe: const Color(0xFF98A2B3),
                              badge: 'Free',
                              badgeBg: const Color(0xFFF2F4F7),
                              badgeFg: const Color(0xFF667085),
                            );
                          }

                          return Column(
                            children: recs.map<Widget>((r) {
                              if (r is! Map) return const SizedBox.shrink();
                              final subject = (r['Subject'] is Map ? r['Subject']['name'] : '')?.toString() ?? '';
                              final teacher = (r['Teacher'] is Map ? r['Teacher']['name'] : '')?.toString() ?? '';
                              return _periodCard(
                                title: title,
                                time: time,
                                subject: subject,
                                teacher: teacher,
                                stripe: kBrand,
                              );
                            }).toList(),
                          );
                        }).toList(),
                      ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyOrError() {
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 40, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: kBrand, foregroundColor: Colors.white),
                onPressed: _loadAll,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPageBg,
      appBar: AppBar(
        title: const Text('Student Timetable'),
        centerTitle: true,
        backgroundColor: kBrand,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAll,
          color: kBrand,
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.only(bottom: 28),
                  children: [
                    _heroHeader(),
                    _buildStudentSwitcher(),
                    _summarySection(),
                    _legendSection(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Builder(
                        builder: (ctx) {
                          final width = MediaQuery.of(ctx).size.width;
                          if (error != null) return _buildEmptyOrError();
                          if (width >= 900) {
                            return _buildDesktopTable(ctx);
                          }
                          return _buildMobileList();
                        },
                      ),
                    ),
                    if (showNoMatchHint)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFAEB),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFEC84B)),
                        ),
                        child: const Text(
                          'Timetable data was received, but it did not match the configured periods. Please verify period IDs and day names from the backend.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}