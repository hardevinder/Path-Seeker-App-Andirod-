import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/constants.dart'; // ✅ uses Constants.apiBase

/// My Attendance Calendar (Teacher)
/// - Month view
/// - Summary counts
/// - Search + status filter
/// - Optional holidays
/// - Day details in bottom sheet
class MyAttendanceCalendarScreen extends StatefulWidget {
  const MyAttendanceCalendarScreen({Key? key}) : super(key: key);

  @override
  State<MyAttendanceCalendarScreen> createState() =>
      _MyAttendanceCalendarScreenState();
}

class _MyAttendanceCalendarScreenState extends State<MyAttendanceCalendarScreen> {
  // =========================
  // Endpoints
  // =========================
  static const String attendanceEndpoint = '/employee-attendance/my-calendar';
  static const String holidaysEndpoint = '/holidays';

  // =========================
  // State
  // =========================
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  bool _loading = true;
  bool _holidaysLoaded = false;

  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _holidays = [];

  // ✅ FAST lookup maps
  final Map<String, Map<String, dynamic>> _recordByDate = {};
  final Map<String, Map<String, dynamic>> _holidayByDate = {};

  String? _selectedDate; // yyyy-MM-dd

  // Search + filters
  String _searchText = '';
  String _pendingSearchText = '';
  Timer? _debounceTimer;

  final Set<String> _statusFilter = {}; // empty => all

  // Jump date
  DateTime? _jumpDate;

  // =========================
  // Formatters
  // =========================
  final DateFormat _ym = DateFormat('yyyy-MM');
  final DateFormat _ymd = DateFormat('yyyy-MM-dd');
  final DateFormat _niceMonth = DateFormat('MMMM yyyy');
  final DateFormat _niceDay = DateFormat('EEE, d MMM yyyy');

  // =========================
  // Status Colors / Labels
  // =========================
  static const Map<String, Color> STATUS_COLORS = {
    'present': Color(0xFF2E7D32),
    'absent': Color(0xFFC62828),
    'leave': Color(0xFFEF6C00),
    'half-day-without-pay': Color(0xFF6A1B9A),
    'short-leave': Color(0xFF1565C0),
    'first-half-leave': Color(0xFF00695C),
    'second-half-leave': Color(0xFF00838F),
    'full-day-leave': Color(0xFF616161),
    'unmarked': Color(0xFF9E9E9E),
  };

  static const List<String> STATUS_LABELS = [
    'present',
    'absent',
    'leave',
    'half-day-without-pay',
    'short-leave',
    'first-half-leave',
    'second-half-leave',
    'full-day-leave',
    'unmarked',
  ];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  // =========================
  // Networking (AUTH SAFE)
  // =========================
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authToken');
  }

  Uri _buildUri(String pathWithQuery) {
    final base = Constants.apiBase.replaceAll(RegExp(r"/+$"), "");
    final p = pathWithQuery.startsWith('/') ? pathWithQuery : '/$pathWithQuery';
    return Uri.parse('$base$p');
  }

  Future<http.Response> _authGet(String pathWithQuery) async {
    final token = await _getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null && token.trim().isNotEmpty)
        'Authorization': 'Bearer $token',
    };
    return http.get(_buildUri(pathWithQuery), headers: headers).timeout(
      const Duration(seconds: 20),
    );
  }

  // =========================
  // Loading
  // =========================
  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() => _loading = true);

    await Future.wait([
      _fetchAttendance(),
      _fetchHolidaysOptional(),
    ].map((f) => f.catchError((_) {})));

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _fetchAttendance() async {
    try {
      final monthStr = _ym.format(_month);

      // ✅ Ensure correct URL & token
      final res = await _authGet('$attendanceEndpoint?month=$monthStr');

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);

        final rawRecords =
            (decoded is Map && decoded['records'] is List) ? decoded['records'] as List : <dynamic>[];

        final list = rawRecords
            .where((e) => e is Map)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        // ✅ Normalize + rebuild map
        _recordByDate.clear();
        for (final r in list) {
          final ds = (r['date'] ?? '').toString();
          if (ds.isEmpty) continue;
          final st = (r['status'] ?? 'unmarked').toString().trim().toLowerCase();
          r['status'] = st;
          _recordByDate[ds] = r;
        }

        if (mounted) setState(() => _records = list);
      } else {
        _recordByDate.clear();
        if (mounted) setState(() => _records = []);
      }
    } catch (_) {
      _recordByDate.clear();
      if (mounted) setState(() => _records = []);
    }
  }

  Future<void> _fetchHolidaysOptional() async {
    try {
      final res = await _authGet(holidaysEndpoint);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);

        final list = (decoded is List) ? decoded : <dynamic>[];
        final monthStr = _ym.format(_month);

        final filtered = list
            .where((e) => e is Map)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((h) => (h['date'] ?? '').toString().startsWith(monthStr))
            .toList();

        _holidayByDate.clear();
        for (final h in filtered) {
          final ds = (h['date'] ?? '').toString();
          if (ds.isEmpty) continue;
          _holidayByDate[ds] = h;
        }

        if (mounted) {
          setState(() {
            _holidays = filtered;
            _holidaysLoaded = true;
          });
        }
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _holidaysLoaded = true);
  }

  // =========================
  // Helpers
  // =========================
  Map<String, dynamic>? _recordFor(String dateStr) => _recordByDate[dateStr];
  Map<String, dynamic>? _holidayFor(String dateStr) => _holidayByDate[dateStr];

  bool _matchesFilters(Map<String, dynamic>? rec) {
    if (_statusFilter.isNotEmpty) {
      final s = (rec?['status'] ?? 'unmarked').toString();
      if (!_statusFilter.contains(s)) return false;
    }

    final q = _searchText.trim().toLowerCase();
    if (q.isEmpty) return true;

    final hay = [
      rec?['status'],
      rec?['remarks'],
      rec?['note'],
      rec?['in_time'],
      rec?['out_time'],
    ]
        .where((v) => v != null && v.toString().trim().isNotEmpty)
        .join(' ')
        .toLowerCase();

    return hay.contains(q);
  }

  int _daysInMonth(DateTime m) {
    final next = DateTime(m.year, m.month + 1, 1);
    return next.subtract(const Duration(days: 1)).day;
  }

  DateTime _startOfCalendarGrid(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final weekday = first.weekday; // Mon=1..Sun=7
    final delta = weekday % 7; // Sunday => 0
    return first.subtract(Duration(days: delta));
  }

  List<_DayCell> _buildDayCells() {
    final start = _startOfCalendarGrid(_month);

    return List.generate(42, (i) {
      final d = start.add(Duration(days: i));
      final dateStr = _ymd.format(d);

      final inCurrentMonth = d.month == _month.month && d.year == _month.year;
      final isSunday = d.weekday == DateTime.sunday;
      final isFuture = d.isAfter(DateTime.now());

      final holiday = _holidayFor(dateStr);
      final rec = _recordFor(dateStr);

      final status = (rec?['status'] ?? 'unmarked').toString();
      final color = STATUS_COLORS[status] ?? STATUS_COLORS['unmarked']!;

      final filteredOut = !_matchesFilters(rec);

      return _DayCell(
        date: d,
        dateStr: dateStr,
        inCurrentMonth: inCurrentMonth,
        isSunday: isSunday,
        isFuture: isFuture,
        holiday: holiday,
        record: rec,
        status: status,
        color: color,
        filteredOut: filteredOut,
      );
    });
  }

  _Summary _buildSummary() {
    final totalDays = _daysInMonth(_month);

    int present = 0, absent = 0, leave = 0, unmarked = 0;

    for (int d = 1; d <= totalDays; d++) {
      final ds = _ymd.format(DateTime(_month.year, _month.month, d));
      final rec = _recordFor(ds);
      final s = (rec?['status'] ?? 'unmarked').toString();

      if (s == 'present') present++;
      else if (s == 'absent') absent++;
      else if (s == 'leave') leave++;
      else unmarked++;
    }

    return _Summary(present: present, absent: absent, leave: leave, unmarked: unmarked);
  }

  void _setMonth(DateTime newMonth) {
    setState(() {
      _month = DateTime(newMonth.year, newMonth.month, 1);
      _selectedDate = null;
    });
    _loadAll();
  }

  void _prevMonth() => _setMonth(DateTime(_month.year, _month.month - 1, 1));
  void _nextMonth() => _setMonth(DateTime(_month.year, _month.month + 1, 1));

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(DateTime.now().year - 5, 1, 1),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
      helpText: 'Select any date (month will be used)',
    );
    if (picked != null) _setMonth(DateTime(picked.year, picked.month, 1));
  }

  Future<void> _pickJumpDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _jumpDate ?? DateTime.now(),
      firstDate: DateTime(DateTime.now().year - 5, 1, 1),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
      helpText: 'Jump to date',
    );
    if (picked == null) return;

    setState(() => _jumpDate = picked);
    _setMonth(DateTime(picked.year, picked.month, 1));
    setState(() => _selectedDate = _ymd.format(picked));
  }

  void _onSearchChanged(String val) {
    setState(() => _pendingSearchText = val);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _searchText = _pendingSearchText);
    });
  }

  void _toggleStatus(String s) {
    setState(() {
      if (_statusFilter.contains(s)) _statusFilter.remove(s);
      else _statusFilter.add(s);
    });
  }

  void _clearFilters() {
    setState(() {
      _statusFilter.clear();
      _pendingSearchText = '';
      _searchText = '';
    });
  }

  String _shortBadge(String status, {bool holiday = false}) {
    if (holiday) return 'H';
    switch (status) {
      case 'present':
        return 'P';
      case 'absent':
        return 'A';
      case 'leave':
      case 'full-day-leave':
      case 'short-leave':
      case 'first-half-leave':
      case 'second-half-leave':
      case 'half-day-without-pay':
        return 'L';
      default:
        return 'U';
    }
  }

  void _openDayDetails(String dateStr, _DayCell cell) {
    setState(() => _selectedDate = dateStr);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        final rec = cell.record;
        final holiday = cell.holiday;

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 10,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 4,
                width: 44,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _niceDay.format(DateTime.parse(dateStr)),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: cell.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: cell.color.withOpacity(0.35)),
                    ),
                    child: Text(
                      (holiday != null ? 'Holiday' : cell.status.replaceAll('-', ' ')),
                      style: TextStyle(color: cell.color, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              if (holiday != null) ...[
                _infoCard(
                  icon: Icons.celebration,
                  title: 'Holiday',
                  subtitle: (holiday['description'] ?? holiday['title'] ?? 'Holiday').toString(),
                  tone: Colors.orange,
                ),
              ] else if (rec != null) ...[
                _infoCard(
                  icon: Icons.event_available,
                  title: 'Attendance Details',
                  subtitle: 'Status: ${cell.status.replaceAll('-', ' ')}',
                  tone: cell.color,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _miniStat(
                        label: 'In Time',
                        value: (rec['in_time'] ?? rec['inTime'] ?? '-').toString(),
                        icon: Icons.login,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _miniStat(
                        label: 'Out Time',
                        value: (rec['out_time'] ?? rec['outTime'] ?? '-').toString(),
                        icon: Icons.logout,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if ((rec['remarks'] ?? '').toString().trim().isNotEmpty)
                  _infoCard(
                    icon: Icons.comment,
                    title: 'Remarks',
                    subtitle: rec['remarks'].toString(),
                    tone: Colors.blueGrey,
                  ),
              ] else ...[
                _infoCard(
                  icon: Icons.info_outline,
                  title: 'No attendance',
                  subtitle: cell.isFuture ? 'Future date.' : 'Not marked.',
                  tone: Colors.grey,
                ),
              ],
              const SizedBox(height: 14),
            ],
          ),
        );
      },
    );
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    final summary = _buildSummary();
    final cells = _buildDayCells();

    return Scaffold(
      appBar: AppBar(
        elevation: 2,
        title: const Text('My Attendance'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _monthHeader(),
            const SizedBox(height: 12),

            _summaryRow(summary),
            const SizedBox(height: 10),

            _legendRow(),
            const SizedBox(height: 12),

            _filtersCard(),
            const SizedBox(height: 12),

            _calendarCard(cells),
            const SizedBox(height: 16),

            if (_holidaysLoaded && _holidays.isNotEmpty) _holidaysHint(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _monthHeader() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            IconButton(
              onPressed: _prevMonth,
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous month',
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickMonth,
                child: Column(
                  children: [
                    Text(
                      _niceMonth.format(_month),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap to pick month',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              onPressed: _nextMonth,
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next month',
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(_Summary s) {
    return Row(
      children: [
        Expanded(child: _summaryCard('Present', s.present.toString(), STATUS_COLORS['present']!)),
        const SizedBox(width: 10),
        Expanded(child: _summaryCard('Absent', s.absent.toString(), STATUS_COLORS['absent']!)),
        const SizedBox(width: 10),
        Expanded(child: _summaryCard('Leave', s.leave.toString(), STATUS_COLORS['leave']!)),
        const SizedBox(width: 10),
        Expanded(child: _summaryCard('Unmarked', s.unmarked.toString(), STATUS_COLORS['unmarked']!)),
      ],
    );
  }

  Widget _summaryCard(String title, String value, Color tone) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [tone.withOpacity(0.16), tone.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withOpacity(0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.grey.shade800, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: tone, fontSize: 20, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _legendRow() {
    Widget dot(Color c) => Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(99)));
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [dot(STATUS_COLORS['present']!), const SizedBox(width: 6), const Text('Present')]),
        Row(mainAxisSize: MainAxisSize.min, children: [dot(STATUS_COLORS['absent']!), const SizedBox(width: 6), const Text('Absent')]),
        Row(mainAxisSize: MainAxisSize.min, children: [dot(STATUS_COLORS['leave']!), const SizedBox(width: 6), const Text('Leave')]),
        Row(mainAxisSize: MainAxisSize.min, children: [dot(STATUS_COLORS['unmarked']!), const SizedBox(width: 6), const Text('Unmarked')]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: Colors.orange.withOpacity(0.9), borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 6),
          const Text('Holiday'),
        ]),
      ],
    );
  }

  Widget _filtersCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Filters', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_statusFilter.isNotEmpty || _searchText.isNotEmpty || _pendingSearchText.isNotEmpty)
                  TextButton.icon(
                    onPressed: _clearFilters,
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            TextField(
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search remarks / in-out / status…',
                filled: true,
                fillColor: Colors.grey.withOpacity(0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),

            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in STATUS_LABELS)
                  FilterChip(
                    selected: _statusFilter.contains(s),
                    label: Text(s.replaceAll('-', ' ')),
                    onSelected: (_) => _toggleStatus(s),
                    selectedColor: STATUS_COLORS[s]!.withOpacity(0.18),
                    checkmarkColor: STATUS_COLORS[s]!,
                    side: BorderSide(color: STATUS_COLORS[s]!.withOpacity(0.35)),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _pickJumpDate,
                icon: const Icon(Icons.my_location),
                label: const Text('Jump to date'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _calendarCard(List<_DayCell> cells) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            _weekHeaderRow(),
            const SizedBox(height: 8),

            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cells.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: 1.0,
                ),
                itemBuilder: (context, i) => _dayTile(cells[i]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _weekHeaderRow() {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return Row(
      children: [
        for (final d in days)
          Expanded(
            child: Center(
              child: Text(
                d,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: d == 'Sun' ? Colors.redAccent : Colors.black87,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _dayTile(_DayCell cell) {
    final isSelected = _selectedDate == cell.dateStr;
    final opacity = cell.filteredOut ? 0.18 : 1.0;

    final isHoliday = cell.holiday != null;
    final Color baseTone = isHoliday ? Colors.orange : cell.color;

    // ✅ FULL COLOR tile (what you asked)
    final Color bg = baseTone.withOpacity(cell.inCurrentMonth ? 0.22 : 0.12);

    final badgeText = _shortBadge(cell.status, holiday: isHoliday);

    return Opacity(
      opacity: opacity,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDayDetails(cell.dateStr, cell),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: bg,
            border: Border.all(
              color: isSelected ? baseTone : baseTone.withOpacity(0.25),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isSelected ? 0.08 : 0.03),
                blurRadius: isSelected ? 10 : 6,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Stack(
            children: [
              // Day number
              Positioned(
                top: 8,
                left: 8,
                child: Text(
                  '${cell.date.day}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: cell.isSunday ? Colors.redAccent : Colors.black87,
                  ),
                ),
              ),

              // Big badge (P/A/L/U/H)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: baseTone.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Center(
                    child: Text(
                      badgeText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom tiny label (status / not marked / holiday title)
              Positioned(
                left: 8,
                right: 8,
                bottom: 6,
                child: _tileBottomLabel(cell),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tileBottomLabel(_DayCell cell) {
    if (cell.holiday != null) {
      final text = (cell.holiday!['title'] ?? cell.holiday!['description'] ?? 'Holiday').toString();
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.deepOrange),
      );
    }

    if (cell.record == null) {
      return Text(
        cell.isFuture ? '' : 'Unmarked',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: STATUS_COLORS['unmarked']),
      );
    }

    final statusText = cell.status.replaceAll('-', ' ');
    return Text(
      statusText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: cell.color),
    );
  }

  Widget _holidaysHint() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.celebration, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Holidays loaded for this month (${_holidays.length}). Tap H days to see details.',
              style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // Small UI components
  // =========================
  Widget _infoCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color tone,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withOpacity(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tone.withOpacity(0.25)),
            ),
            child: Icon(icon, color: tone),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade800)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _miniStat({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.indigo),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w800, fontSize: 12)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =========================
// Data holders
// =========================
class _Summary {
  final int present;
  final int absent;
  final int leave;
  final int unmarked;

  _Summary({
    required this.present,
    required this.absent,
    required this.leave,
    required this.unmarked,
  });
}

class _DayCell {
  final DateTime date;
  final String dateStr;
  final bool inCurrentMonth;
  final bool isSunday;
  final bool isFuture;

  final Map<String, dynamic>? holiday;
  final Map<String, dynamic>? record;

  final String status;
  final Color color;
  final bool filteredOut;

  _DayCell({
    required this.date,
    required this.dateStr,
    required this.inCurrentMonth,
    required this.isSunday,
    required this.isFuture,
    required this.holiday,
    required this.record,
    required this.status,
    required this.color,
    required this.filteredOut,
  });
}
