// lib/screens/dashboard_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../widgets/student_app_bar.dart';
import '../widgets/student_drawer_menu.dart';
import '../constants/constants.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // ---- state ----
  bool loading = true;
  String username = '';

  // basic identity
  String? studentName;
  String? admissionNumber;

  // ✅ NEW: DOB + Blood Group
  String? dateOfBirth; // raw yyyy-mm-dd
  String? bloodGroup;

  // academic
  String? className;
  String? sectionName;
  String? sessionName;

  // contact / family
  String? fatherName;
  String? motherName;
  String? fatherPhone;
  String? motherPhone;

  // address
  String? address;

  // transport
  int? routeId;
  String? routeName;
  num? routeCost;

  // photo
  String? photoUrl;

  // role flag
  bool isTeacher = false;

  // KPI state
  int present = 0, absent = 0, leaveCount = 0, totalDays = 0;
  int assignTotal = 0, assignSubmitted = 0, assignGraded = 0, assignOverdue = 0;
  double feeTotalDue = 0, feeVanDue = 0;
  int diaryTotal = 0, diaryUnack = 0;

  // lists
  List<Map<String, dynamic>> assignNext3 = [];
  List<Map<String, dynamic>> recentCirculars = [];
  List<Map<String, dynamic>> todayPeriods = [];

  List<String> notifications = [];

  late NumberFormat currencyFormat;

  // Auto-scrolling slides
  late PageController _pageController;
  Timer? _pageTimer;
  int _currentPage = 0;
  final Duration slideInterval = const Duration(seconds: 5);
  final Duration slideDuration = const Duration(milliseconds: 600);

  int slideCount = 4;

  // scaffold key for reliable drawer control
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // small polish: consistent accent
  static const Color kAccent = Color(0xFF6C63FF);

  @override
  void initState() {
    super.initState();
    currencyFormat =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    _pageController = PageController(viewportFraction: 0.92);
    _startAutoSlide();
    _loadInitial();
  }

  void _startAutoSlide() {
    _pageTimer?.cancel();
    _pageTimer = Timer.periodic(slideInterval, (_) {
      if (_pageController.hasClients && slideCount > 0) {
        _currentPage = (_currentPage + 1) % slideCount;
        _pageController.animateToPage(
          _currentPage,
          duration: slideDuration,
          curve: Curves.easeInOut,
        );
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _pageTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authToken');
  }

  Future<void> _loadInitial() async {
    setState(() => loading = true);
    final prefs = await SharedPreferences.getInstance();
    username = prefs.getString('username') ?? prefs.getString('userId') ?? '';
    notifications = prefs.getStringList('notifications') ?? [];

    final activeRole = prefs.getString('activeRole')?.toLowerCase() ?? '';
    isTeacher = activeRole == 'teacher';

    await _fetchAll();
    if (mounted) setState(() => loading = false);
  }

  Future<void> _fetchAll() async {
    final token = await _getToken();
    if (baseUrl.isEmpty) return;

    final headers = <String, String>{
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    await Future.wait([
      _fetchStudentProfile(headers),
      _fetchAttendance(headers),
      _fetchAssignments(headers),
      _fetchFees(headers),
      _fetchDiarySummary(headers),
      _fetchTodayTimetable(headers),
      _fetchCirculars(headers),
    ].map((f) => f.catchError((_) {})));

    slideCount = 4;
    _startAutoSlide();
  }

  // ✅ Profile endpoint by Admission Number
  // GET /students/admission/:admission_number
  Future<void> _fetchStudentProfile(Map<String, String> headers) async {
    try {
      if (username.isEmpty) return;

      final res = await http.get(
        Uri.parse('$baseUrl/students/admission/$username'),
        headers: headers,
      );

      if (res.statusCode != 200) return;

      final j = jsonDecode(res.body);
      if (j is! Map) return;
      final json = Map<String, dynamic>.from(j);

      String? _s(dynamic v) {
        if (v == null) return null;
        final t = v.toString().trim();
        return t.isEmpty ? null : t;
      }

      int? _i(dynamic v) {
        if (v == null) return null;
        if (v is int) return v;
        return int.tryParse(v.toString());
      }

      num? _n(dynamic v) {
        if (v == null) return null;
        if (v is num) return v;
        return num.tryParse(v.toString().replaceAll(',', ''));
      }

      final cls = (json['Class'] is Map) ? Map<String, dynamic>.from(json['Class']) : null;
      final sec = (json['Section'] is Map) ? Map<String, dynamic>.from(json['Section']) : null;
      final ses = (json['Session'] is Map) ? Map<String, dynamic>.from(json['Session']) : null;
      final trans = (json['Transportation'] is Map) ? Map<String, dynamic>.from(json['Transportation']) : null;

      // ✅ API keys based on your payload
      final dob = _s(json['Date_Of_Birth']) ?? _s(json['date_of_birth']) ?? _s(json['dob']);
      final bg = _s(json['b_group']) ?? _s(json['blood_group']) ?? _s(json['bloodGroup']);

      final photo = _s(json['photo_url']) ?? _s(json['photoUrl']); // just in case

      if (!mounted) return;
      setState(() {
        // identity
        studentName = _s(json['name']) ?? studentName;
        admissionNumber = _s(json['admission_number']) ?? _s(json['admissionNumber']) ?? admissionNumber;

        // ✅ DOB + Blood Group
        dateOfBirth = dob ?? dateOfBirth;
        bloodGroup = bg ?? bloodGroup;

        // academic
        className = _s(cls?['class_name']) ?? _s(json['class_name']) ?? className;
        sectionName = _s(sec?['section_name']) ?? _s(json['section_name']) ?? sectionName;
        sessionName = _s(ses?['name']) ?? sessionName;

        // family
        fatherName = _s(json['father_name']) ?? fatherName;
        motherName = _s(json['mother_name']) ?? motherName;
        fatherPhone = _s(json['father_phone']) ?? fatherPhone;
        motherPhone = _s(json['mother_phone']) ?? motherPhone;

        // address
        address = _s(json['address']) ?? address;

        // transport
        routeId = _i(json['route_id']) ?? routeId;
        routeName = _s(trans?['RouteName']) ?? routeName;
        routeCost = _n(trans?['Cost']) ?? routeCost;

        // photo
        photoUrl = photoUrlSafe(photo ?? photoUrl);
      });
    } catch (e, st) {
      debugPrint('Error fetching student profile: $e\n$st');
    }
  }

  String? photoUrlSafe(String? u) {
    if (u == null) return null;
    final t = u.trim();
    if (t.isEmpty) return null;
    return t;
  }

  Future<void> _fetchAttendance(Map<String, String> headers) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/attendance/student/me'),
        headers: headers,
      );
      if (res.statusCode == 200) {
        final rows = jsonDecode(res.body) as List<dynamic>? ?? [];
        final now = DateTime.now();
        final monthRows = rows.where((r) {
          final d =
              DateTime.tryParse(r['date']?.toString() ?? '') ?? DateTime(1970);
          return d.month == now.month && d.year == now.year;
        }).toList();
        final p = monthRows
            .where((r) =>
                (r['status'] ?? '').toString().toLowerCase() == 'present')
            .length;
        final a = monthRows
            .where((r) =>
                (r['status'] ?? '').toString().toLowerCase() == 'absent')
            .length;
        final l = monthRows
            .where(
                (r) => (r['status'] ?? '').toString().toLowerCase() == 'leave')
            .length;
        if (!mounted) return;
        setState(() {
          present = p;
          absent = a;
          leaveCount = l;
          totalDays = monthRows.length;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchAssignments(Map<String, String> headers) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/student-assignments/student'),
        headers: headers,
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final list = (json['assignments'] as List<dynamic>?) ?? [];
        int submitted = 0, graded = 0, overdue = 0;
        final next3 = <Map<String, dynamic>>[];

        for (final a in list) {
          final sa = (a['StudentAssignments'] as List<dynamic>?)
              ?.firstWhere((_) => true, orElse: () => null);
          final status = (sa?['status'] ?? '').toString().toLowerCase();
          if (status == 'submitted') submitted++;
          if (status == 'graded') graded++;

          final dueStr = sa?['dueDate'] ?? sa?['due_date'];
          DateTime? due =
              dueStr != null ? DateTime.tryParse(dueStr.toString()) : null;
          if (due != null &&
              DateTime.now().isAfter(due.add(const Duration(days: 1))) &&
              !['submitted', 'graded'].contains(status)) {
            overdue++;
          }
        }

        final upcoming = list.where((a) {
          final sa = (a['StudentAssignments'] as List<dynamic>?)
              ?.firstWhere((_) => true, orElse: () => null);
          final dueStr = sa?['dueDate'] ?? sa?['due_date'];
          if (dueStr == null) return false;
          final due = DateTime.tryParse(dueStr.toString());
          if (due == null) return false;
          final status = (sa?['status'] ?? '').toString().toLowerCase();
          return !['submitted', 'graded'].contains(status) &&
              DateTime.now().isBefore(due);
        }).toList();

        upcoming.sort((a, b) {
          final da = DateTime.tryParse(((a['StudentAssignments'] as List?)?.first
                  ?['dueDate'] ??
              ''));
          final db = DateTime.tryParse(((b['StudentAssignments'] as List?)?.first
                  ?['dueDate'] ??
              ''));
          return (da ?? DateTime(9999)).compareTo(db ?? DateTime(9999));
        });

        for (final a in upcoming.take(3)) {
          final sa = (a['StudentAssignments'] as List?)?.first ?? {};
          next3.add({
            'id': a['id'],
            'title': a['title'] ?? 'Untitled',
            'due': sa['dueDate'] ?? sa['due_date'],
          });
        }

        if (!mounted) return;
        setState(() {
          assignTotal = list.length;
          assignSubmitted = submitted;
          assignGraded = graded;
          assignOverdue = overdue;
          assignNext3 = next3;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchFees(Map<String, String> headers) async {
    try {
      if (username.isEmpty) return;
      final res = await http.get(
        Uri.parse('$baseUrl/StudentsApp/admission/$username/fees'),
        headers: headers,
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final fees = (json['feeDetails'] as List<dynamic>?) ?? [];

        double parseNum(dynamic v) {
          if (v == null) return 0.0;
          if (v is num) return v.toDouble();
          if (v is String) return double.tryParse(v.replaceAll(',', '')) ?? 0.0;
          return 0.0;
        }

        final totalDue = fees.fold<double>(
            0.0,
            (s, f) =>
                s + parseNum(f['finalAmountDue'] ?? f['final_amount_due']));
        final vanObj = json['vanFee'] ?? {};
        final vanCost = parseNum(
            vanObj['perHeadTotalDue'] ?? vanObj['transportCost'] ?? 0);
        final vanRecv = parseNum(vanObj['totalVanFeeReceived'] ?? 0);
        final vanCon = parseNum(vanObj['totalVanFeeConcession'] ?? 0);
        final vanDueNum =
            (vanCost - (vanRecv + vanCon)).clamp(0, double.infinity).toDouble();

        if (!mounted) return;
        setState(() {
          feeTotalDue = totalDue;
          feeVanDue = vanDueNum;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchDiarySummary(Map<String, String> headers) async {
    try {
      final latestRes = await http.get(
        Uri.parse(
            '$baseUrl/diaries/student/feed/list?page=1&pageSize=5&order=date:DESC'),
        headers: headers,
      );
      final latestJson = jsonDecode(latestRes.body);
      final latestItems =
          (latestJson is Map && latestJson['data'] is List)
              ? (latestJson['data'] as List)
              : [];
      final total = int.tryParse(
              (latestJson['pagination']?['total']?.toString() ??
                  '${latestItems.length}')) ??
          latestItems.length;

      final unackRes = await http.get(
        Uri.parse(
            '$baseUrl/diaries/student/feed/list?page=1&pageSize=1&order=date:DESC&onlyUnacknowledged=true'),
        headers: headers,
      );
      final unackJson = jsonDecode(unackRes.body);
      final unack = int.tryParse(
              (unackJson['pagination']?['total']?.toString() ?? '0')) ??
          0;

      if (!mounted) return;
      setState(() {
        diaryTotal = total;
        diaryUnack = unack;
      });
    } catch (_) {}
  }

  Future<void> _fetchCirculars(Map<String, String> headers) async {
    try {
      final res =
          await http.get(Uri.parse('$baseUrl/circulars'), headers: headers);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final list = (json['circulars'] as List<dynamic>?) ?? [];
        final filtered = list.where((c) {
          final aud = (c['audience'] ?? '').toString().toLowerCase();
          return aud == 'student' || aud == 'both' || aud.isEmpty;
        }).toList();
        filtered.sort((a, b) {
          final da = DateTime.tryParse(a['createdAt']?.toString() ?? '') ??
              DateTime(1970);
          final db = DateTime.tryParse(b['createdAt']?.toString() ?? '') ??
              DateTime(1970);
          return db.compareTo(da);
        });
        if (!mounted) return;
        setState(() {
          recentCirculars =
              filtered.take(5).map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchTodayTimetable(Map<String, String> headers) async {
    try {
      final pRes =
          await http.get(Uri.parse('$baseUrl/periods'), headers: headers);
      final tRes = await http.get(
        Uri.parse('$baseUrl/period-class-teacher-subject/student/timetable'),
        headers: headers,
      );
      final periods = (jsonDecode(pRes.body) as List<dynamic>?) ?? [];
      final ttbRaw = jsonDecode(tRes.body);
      final ttb =
          (ttbRaw is List) ? ttbRaw : (ttbRaw['timetable'] as List<dynamic>?) ?? [];

      final days = [
        'Sunday',
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday'
      ];
      final todayIdx = DateTime.now().weekday % 7;
      final todayName = days[todayIdx];

      final mapByPeriod = <dynamic, dynamic>{};
      for (final r in ttb) {
        if (r['day'] == todayName) mapByPeriod[r['periodId']] = r;
      }

      final items = <Map<String, dynamic>>[];
      for (final p in periods) {
        final id = p['id'];
        final r = mapByPeriod[id];
        if (r != null) {
          items.add({
            'period': p['period_name'] ?? p['name'],
            'time': (p['start_time'] != null && p['end_time'] != null)
                ? '${p['start_time']}–${p['end_time']}'
                : '',
            'subject': r['Subject']?['name'] ?? r['subjectId'] ?? '—',
            'teacher': r['Teacher']?['name'] ?? '—',
            'start_time': p['start_time'],
            'end_time': p['end_time'],
          });
        }
      }

      items.sort((a, b) {
        final aStart = a['start_time'] as String?;
        final bStart = b['start_time'] as String?;
        if (aStart == null && bStart == null) return 0;
        if (aStart == null) return 1;
        if (bStart == null) return -1;
        final aParts = aStart.split(':');
        final bParts = bStart.split(':');
        final aH = int.tryParse(aParts[0]) ?? 0;
        final aM = int.tryParse(aParts.length > 1 ? aParts[1] : '0') ?? 0;
        final bH = int.tryParse(bParts[0]) ?? 0;
        final bM = int.tryParse(bParts.length > 1 ? bParts[1] : '0') ?? 0;
        return (aH * 60 + aM).compareTo(bH * 60 + bM);
      });

      if (!mounted) return;
      setState(() => todayPeriods = items);
    } catch (_) {}
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final bgGradient = const LinearGradient(
      colors: [Color(0xFFF7FAFF), Color(0xFFF3F0FF), Color(0xFFEFF6FF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: [0.0, 0.5, 1.0],
    );

    return Scaffold(
      key: _scaffoldKey,
      appBar: StudentAppBar(
        parentContext: context,
        scaffoldKey: _scaffoldKey,
        title: 'Welcome to Pathseekers',
      ),
      drawer: StudentDrawerMenu(),
      body: Container(
        decoration: BoxDecoration(gradient: bgGradient),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async => await _fetchAll(),
            color: kAccent,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              children: [
                _heroSection(),
                const SizedBox(height: 12),
                if (!isTeacher) _studentProfileCard(),
                if (!isTeacher) const SizedBox(height: 14),
                _slidesPanel(presencePct()),
                const SizedBox(height: 16),
                _todayCardNoClock(),
                const SizedBox(height: 12),
                _quickActionsGrid(),
                const SizedBox(height: 16),
                _recentCircularsFullWidth(),
                const SizedBox(height: 16),
                _assignmentsPanel(),
                const SizedBox(height: 16),
                _timetableSection(),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------- NEW: Profile card -------------------------
  Widget _studentProfileCard() {
    final hasAny =
        (admissionNumber?.isNotEmpty ?? false) ||
        (sessionName?.isNotEmpty ?? false) ||
        (dateOfBirth?.isNotEmpty ?? false) ||
        (bloodGroup?.isNotEmpty ?? false) ||
        (fatherName?.isNotEmpty ?? false) ||
        (motherName?.isNotEmpty ?? false) ||
        (fatherPhone?.isNotEmpty ?? false) ||
        (motherPhone?.isNotEmpty ?? false) ||
        (address?.isNotEmpty ?? false) ||
        (routeName?.isNotEmpty ?? false);

    if (!hasAny && loading) return _skeleton();

    final dobPretty = _formatDobPretty(dateOfBirth);
    final ageText = _ageFromDob(dateOfBirth);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 14,
            offset: const Offset(0, 8),
          )
        ],
        border: Border.all(color: Colors.black.withOpacity(0.03)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEEF3FF), Color(0xFFF9F5FF)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black.withOpacity(0.03)),
                ),
                child: const Icon(Icons.badge, color: kAccent, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'Student Profile',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/fee-details'),
                child: const Text(
                  'Fees',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Pills row
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if ((admissionNumber ?? '').trim().isNotEmpty)
                _miniPill('Adm No', admissionNumber!),
              if ((sessionName ?? '').trim().isNotEmpty)
                _miniPill('Session', sessionName!),
              if ((dobPretty ?? '').trim().isNotEmpty)
                _miniPill('DOB', dobPretty!),
              if ((ageText ?? '').trim().isNotEmpty)
                _miniPill('Age', ageText!),
              if ((bloodGroup ?? '').trim().isNotEmpty)
                _miniPill('Blood', bloodGroup!.trim()),
              if ((routeName ?? '').trim().isNotEmpty)
                _miniPill(
                  'Route',
                  routeId != null ? '${routeName!} (#$routeId)' : routeName!,
                ),
              if (routeCost != null)
                _miniPill('Route Fee', currencyFormat.format(routeCost)),
            ],
          ),

          const SizedBox(height: 14),

          // Details
          _kvRow(Icons.person, 'Father', _join2(fatherName, fatherPhone)),
          const SizedBox(height: 10),
          _kvRow(Icons.person_outline, 'Mother', _join2(motherName, motherPhone)),
          const SizedBox(height: 10),
          if ((address ?? '').trim().isNotEmpty)
            _kvRow(Icons.home, 'Address', address!.trim()),
        ],
      ),
    );
  }

  Widget _miniPill(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Text(
        '$k: $v',
        style: const TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _kvRow(IconData icon, String label, String value) {
    final v = value.trim().isEmpty ? '—' : value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F4FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black.withOpacity(0.03)),
          ),
          child: Icon(icon, color: kAccent, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                v,
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _join2(String? a, String? b) {
    final aa = (a ?? '').trim();
    final bb = (b ?? '').trim();
    if (aa.isEmpty && bb.isEmpty) return '—';
    if (aa.isEmpty) return bb;
    if (bb.isEmpty) return aa;
    return '$aa • $bb';
  }

  String? _formatDobPretty(String? raw) {
    final r = (raw ?? '').trim();
    if (r.isEmpty) return null;
    final dt = DateTime.tryParse(r);
    if (dt == null) return r; // fallback
    return DateFormat('d MMM yyyy').format(dt);
  }

  String? _ageFromDob(String? raw) {
    final r = (raw ?? '').trim();
    final dob = DateTime.tryParse(r);
    if (dob == null) return null;
    final now = DateTime.now();
    int years = now.year - dob.year;
    final hadBirthdayThisYear =
        (now.month > dob.month) || (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthdayThisYear) years -= 1;
    if (years < 0) return null;
    return '$years yrs';
  }

  // ------------------------- Slides panel -------------------------
  Widget _slidesPanel(int presencePct) {
    final slides = [
      _slideCard(
        title: isTeacher ? 'My Attendance' : 'Attendance',
        subtitle: isTeacher ? 'Calendar view' : '$presencePct% this month',
        trailing: isTeacher ? 'Open calendar' : '$present / $totalDays',
        icon: Icons.calendar_today,
        gradient: const [Color(0xFFDDEAFE), Color(0xFFBEE3F8)],
        iconColor: const Color(0xFF106FA4),
        onTap: () {
          Navigator.pushNamed(
            context,
            isTeacher ? '/my-attendance-calendar' : '/attendance',
          );
        },
      ),
      _slideCard(
        title: 'Assignments',
        subtitle: '$assignTotal total • $assignOverdue overdue',
        trailing: '$assignSubmitted submitted',
        icon: Icons.task_alt,
        gradient: const [Color(0xFFFDE8E8), Color(0xFFFFD2E0)],
        iconColor: const Color(0xFFB82E4A),
        onTap: () => Navigator.pushNamed(context, '/assignments'),
      ),
      _slideCard(
        title: 'Fees',
        subtitle: 'Due: ${currencyFormat.format(feeTotalDue)}',
        trailing: 'Transport: ${currencyFormat.format(feeVanDue)}',
        icon: Icons.attach_money,
        gradient: const [Color(0xFFE8F9EC), Color(0xFFDAF4D9)],
        iconColor: const Color(0xFF0F7A3A),
        onTap: () => Navigator.pushNamed(context, '/fee-details'),
      ),
      _slideCard(
        title: 'Diary',
        subtitle: '$diaryTotal entries • $diaryUnack pending',
        trailing: 'Open diary',
        icon: Icons.menu_book,
        gradient: const [Color(0xFFFFF3D9), Color(0xFFFFE3B5)],
        iconColor: const Color(0xFFB86B00),
        onTap: () => Navigator.pushNamed(context, '/diaries'),
      ),
    ];

    slideCount = slides.length;

    return Column(
      children: [
        SizedBox(
          height: 150,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: slides.length,
            itemBuilder: (context, index) => slides[index],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(slideCount, (i) {
            final active = i == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: active ? 18 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: active ? kAccent : Colors.black.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _slideCard({
    required String title,
    required String subtitle,
    required String trailing,
    required IconData icon,
    required List<Color> gradient,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 14,
              offset: const Offset(0, 8),
            )
          ],
          border: Border.all(color: Colors.black.withOpacity(0.03)),
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 6),
                  )
                ],
              ),
              child: Icon(icon, color: iconColor, size: 32),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.black54, fontSize: 13)),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.black.withOpacity(0.05)),
                    ),
                    child: Text(
                      trailing,
                      style: const TextStyle(
                          color: Colors.black87, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.black26),
          ],
        ),
      ),
    );
  }

  // ------------------------- Today card -------------------------
  Widget _todayCardNoClock() {
    final dateStr = DateFormat.yMMMMEEEEd().format(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFFFFFFFF), Color(0xFFF7FAFF)]),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 6))
        ],
        border: Border.all(color: Colors.black.withOpacity(0.03)),
      ),
      child: Row(
        children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Today',
                  style: TextStyle(
                      color: Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(dateStr,
                  style: const TextStyle(color: Colors.black54, fontSize: 14)),
              const SizedBox(height: 6),
              Text(
                isTeacher
                    ? 'Quick overview of your teacher day'
                    : 'Quick overview of your day',
                style: const TextStyle(color: Colors.black45, fontSize: 12),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [kAccent, Color(0xFF9B8CFF)]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 6))
              ],
            ),
            child: const Center(
              child: Icon(Icons.today, size: 36, color: Colors.white),
            ),
          )
        ],
      ),
    );
  }

  // ------------------------- Quick actions -------------------------
  Widget _quickActionsGrid() {
    final items = <Map<String, dynamic>>[
      {
        'label': isTeacher ? 'My Attendance' : 'Attendance',
        'icon': Icons.calendar_today,
        'route': isTeacher ? '/my-attendance-calendar' : '/attendance',
        'badge': isTeacher ? 'Calendar' : '${presencePct()}%',
      },
      {
        'label': 'Assignments',
        'icon': Icons.task_alt,
        'route': '/assignments',
        'badge': '$assignOverdue overdue'
      },
      {
        'label': 'Diary',
        'icon': Icons.menu_book,
        'route': '/diaries',
        'badge': '$diaryUnack pending'
      },
      {
        'label': 'Circulars',
        'icon': Icons.campaign,
        'route': '/circulars',
        'badge': '${recentCirculars.length} new'
      },
      {
        'label': 'Timetable',
        'icon': Icons.schedule,
        'route': '/timetable',
        'badge': '${todayPeriods.length} periods'
      },
      {
        'label': 'Fees',
        'icon': Icons.attach_money,
        'route': '/fee-details',
        'badge': currencyFormat.format(feeVanDue)
      },
    ];

    if (isTeacher) {
      items.add({
        'label': 'Substitutions',
        'icon': Icons.swap_horiz,
        'route': '/teacher/substitutions',
        'badge': '—',
      });
      items.add({
        'label': 'My Timetable',
        'icon': Icons.table_view,
        'route': '/teacher-timetable-display',
        'badge': 'Open',
      });
    }

    final w = MediaQuery.of(context).size.width;
    final cross = w > 900 ? 4 : (w > 600 ? 3 : 2);

    return GridView.count(
      crossAxisCount: cross,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 3 / 2,
      children: items.map((it) {
        return GestureDetector(
          onTap: () => Navigator.pushNamed(context, it['route'] as String),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 6))
              ],
              border: Border.all(color: Colors.black.withOpacity(0.03)),
            ),
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFeef3ff), Color(0xFFf9f5ff)]),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black.withOpacity(0.03)),
                  ),
                  child: Icon(it['icon'] as IconData, color: kAccent),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.black.withOpacity(0.03)),
                  ),
                  child: Text(
                    (it['badge'] as String?) ?? '',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),
              ]),
              const Spacer(),
              Text(
                it['label'] as String,
                style: const TextStyle(
                    color: Colors.black87, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                'Tap to open',
                style: TextStyle(
                    color: Colors.black.withOpacity(0.45), fontSize: 11),
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }

  // ------------------------- Assignments panel -------------------------
  Widget _assignmentsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 6))
        ],
      ),
      child: Column(
        children: [
          _panelHeader(Icons.assignment, 'Upcoming Assignments', kAccent),
          Padding(
            padding: const EdgeInsets.all(8),
            child: _assignmentsCard(),
          ),
        ],
      ),
    );
  }

  Widget _assignmentsCard() {
    if (loading) return _skeleton();
    if (assignNext3.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          Icon(Icons.check_circle_outline, size: 48, color: Colors.black26),
          const SizedBox(height: 12),
          const Text('No upcoming assignments',
              style: TextStyle(color: Colors.black54)),
        ]),
      );
    }
    return Column(
      children: assignNext3.map((a) {
        final due = a['due']?.toString();
        final dueF = due != null
            ? DateFormat.yMMMd().format(DateTime.tryParse(due) ?? DateTime.now())
            : '—';
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFFF3F4FF)),
            child: const Icon(Icons.task_alt, color: kAccent),
          ),
          title: Text(a['title']?.toString() ?? 'Untitled',
              style: const TextStyle(color: Colors.black87)),
          subtitle: Text('Due: $dueF',
              style: const TextStyle(color: Colors.black54, fontSize: 12)),
          trailing: ElevatedButton(
            onPressed: () => Navigator.pushNamed(context, '/assignments'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
            child: const Text('Open'),
          ),
        );
      }).toList(),
    );
  }

  // ------------------------- Timetable -------------------------
  Widget _timetableSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 6))
        ],
      ),
      child: Column(
        children: [
          ListTile(
            title: const Text("Today's Timetable",
                style: TextStyle(
                    color: Colors.black87, fontWeight: FontWeight.bold)),
            trailing: TextButton(
              onPressed: () => Navigator.pushNamed(context, '/timetable'),
              child:
                  const Text('Open', style: TextStyle(color: Colors.black54)),
            ),
          ),
          if (todayPeriods.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text("No periods today",
                  style: TextStyle(color: Colors.black54)),
            )
          else
            Column(
              children: todayPeriods.map((p) {
                final now = DateTime.now();
                final startStr = p['start_time'];
                final endStr = p['end_time'];
                bool isCurrent = false;

                if (startStr != null &&
                    endStr != null &&
                    startStr is String &&
                    endStr is String) {
                  try {
                    final startParts = startStr.split(':');
                    final endParts = endStr.split(':');
                    final start = DateTime(
                        now.year,
                        now.month,
                        now.day,
                        int.parse(startParts[0]),
                        int.parse(startParts.length > 1 ? startParts[1] : '0'));
                    final end = DateTime(
                        now.year,
                        now.month,
                        now.day,
                        int.parse(endParts[0]),
                        int.parse(endParts.length > 1 ? endParts[1] : '0'));
                    isCurrent = now.isAfter(start) && now.isBefore(end);
                  } catch (_) {}
                }

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFF3F4FF),
                    child: const Icon(Icons.book, color: kAccent),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          (p['subject'] ?? "-").toString(),
                          style: const TextStyle(color: Colors.black87),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text((p['teacher'] ?? "-").toString(),
                      style: const TextStyle(color: Colors.black54)),
                  trailing: Text((p['time'] ?? "").toString(),
                      style: const TextStyle(color: Colors.black54)),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // ------------------------- Circulars -------------------------
  Widget _recentCircularsFullWidth() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 6))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.campaign, color: Color(0xFF0F9D58)),
          const SizedBox(width: 8),
          const Text('Recent Circulars',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87)),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/circulars'),
            child:
                const Text('See all', style: TextStyle(color: Colors.black54)),
          )
        ]),
        const SizedBox(height: 8),
        if (loading)
          _skeleton()
        else if (recentCirculars.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No recent circulars',
                style: TextStyle(color: Colors.black54)),
          )
        else
          Column(
            children: recentCirculars.map((c) {
              final title = c['title'] ?? 'Untitled';
              final created = DateTime.tryParse(c['createdAt']?.toString() ?? '') ??
                  DateTime.now();
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7FAFF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black.withOpacity(0.03)),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title.toString(),
                              style: const TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(DateFormat.yMMMd().format(created),
                              style: const TextStyle(
                                  color: Colors.black54, fontSize: 12)),
                        ]),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.pushNamed(context, '/circulars'),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.black.withOpacity(0.06)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Text('View',
                        style: TextStyle(color: Colors.black87)),
                  )
                ]),
              );
            }).toList(),
          )
      ]),
    );
  }

  // ------------------------- Hero section -------------------------
  Widget _heroSection() {
    final initials = _initialsFor(studentName ?? username);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [kAccent, Color(0xFF9B8CFF)]),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 14,
              offset: const Offset(0, 8))
        ],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _avatar(initials),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              isTeacher ? 'Welcome, ${_displayName()}' : 'Welcome, ${_displayName()}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              isTeacher ? 'Have a great day in school! ★' : 'Have a great day at school! ★',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.95), fontSize: 13),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (className != null) _chip("Class", className!, textColor: Colors.white),
                if (sectionName != null) _chip("Section", sectionName!, textColor: Colors.white),
                if (!isTeacher && admissionNumber != null)
                  _chip("Adm", admissionNumber!, textColor: Colors.white),
                _chip(
                  isTeacher ? "Role" : "Attendance",
                  isTeacher ? "Teacher" : "${presencePct()}%",
                  textColor: Colors.white,
                ),
                // ✅ extra small info
                if (!isTeacher && (bloodGroup ?? '').trim().isNotEmpty)
                  _chip("Blood", bloodGroup!.trim(), textColor: Colors.white),
              ],
            ),
          ]),
        ),
        IconButton(
          onPressed: _openNotifications,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications, color: Colors.white70),
              if (notifications.isNotEmpty)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        color: Colors.redAccent, shape: BoxShape.circle),
                    constraints:
                        const BoxConstraints(minWidth: 20, minHeight: 20),
                    child: Text(
                      '${notifications.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _avatar(String initials) {
    final u = (photoUrl ?? '').trim();
    if (u.isNotEmpty) {
      return CircleAvatar(
        radius: 34,
        backgroundColor: Colors.white,
        backgroundImage: NetworkImage(u),
        onBackgroundImageError: (_, __) {},
        child: Container(),
      );
    }

    return CircleAvatar(
      radius: 34,
      backgroundColor: Colors.white,
      child: Text(
        initials.isNotEmpty ? initials : 'S',
        style: const TextStyle(
            color: kAccent, fontWeight: FontWeight.w900, fontSize: 24),
      ),
    );
  }

  String _initialsFor(String s) {
    final t = s.trim();
    if (t.isEmpty) return 'S';
    final parts = t
        .split(RegExp(r'\s+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'S';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  String _displayName() {
    final name = (studentName ?? username ?? 'Student').toString();
    return name.isEmpty ? 'Student' : name;
  }

  int presencePct() => totalDays > 0
      ? ((present / (totalDays > 0 ? totalDays : 1)) * 100).round()
      : 0;

  Widget _chip(String label, String value, {Color textColor = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Text("$label: $value",
          style: TextStyle(color: textColor, fontSize: 12)),
    );
  }

  // helpers
  Widget _panelHeader(IconData icon, String title, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient:
            LinearGradient(colors: [color.withOpacity(0.12), Colors.transparent]),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                color: Colors.black87, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _skeleton() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(children: [
        Container(
            height: 16,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            margin: const EdgeInsets.symmetric(vertical: 6)),
        Container(
            height: 14,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            margin: const EdgeInsets.symmetric(vertical: 6)),
        Container(
            height: 14,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            margin: const EdgeInsets.symmetric(vertical: 6)),
      ]),
    );
  }

  void _openNotifications() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 24),
          child: Container(
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Text('Notifications',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.black54),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('notifications');
                    if (!mounted) return;
                    setState(() => notifications.clear());
                    Navigator.pop(context);
                  },
                ),
              ]),
              if (notifications.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No notifications',
                      style: TextStyle(color: Colors.black54)),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemBuilder: (_, i) => ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: kAccent,
                        child: Icon(Icons.info, color: Colors.white),
                      ),
                      title: Text(notifications[i],
                          style: const TextStyle(color: Colors.black87)),
                      subtitle: const Text('Just now',
                          style: TextStyle(color: Colors.black54)),
                    ),
                    separatorBuilder: (_, __) =>
                        Divider(color: Colors.black.withOpacity(0.06)),
                    itemCount: notifications.length,
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }
}
