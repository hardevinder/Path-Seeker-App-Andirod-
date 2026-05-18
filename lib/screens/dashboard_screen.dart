// lib/screens/dashboard_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/constants.dart';
import '../widgets/student_app_bar.dart';
import '../widgets/student_drawer_menu.dart';
import 'student_messages_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // -------------------- State --------------------
  bool loading = true;
  String username = '';
  String selectedAdmissionNumber = '';
  int? studentId;

  // Sibling switcher
  bool siblingsLoading = false;
  List<Map<String, dynamic>> siblingStudents = [];

  // Basic identity
  String? studentName;
  String? admissionNumber;
  String? dateOfBirth;
  String? bloodGroup;

  // Academic
  String? className;
  String? sectionName;
  String? sessionName;

  // Contact / family
  String? fatherName;
  String? motherName;
  String? fatherPhone;
  String? motherPhone;
  String? address;

  // Transport
  int? routeId;
  String? routeName;
  num? routeCost;

  // Photo
  String? photoUrl;

  // Role flag
  bool isTeacher = false;

  // KPI state
  int present = 0;
  int absent = 0;
  int leaveCount = 0;
  int totalDays = 0;

  int assignTotal = 0;
  int assignSubmitted = 0;
  int assignGraded = 0;
  int assignOverdue = 0;

  double feeTotalDue = 0;
  double feeVanDue = 0;

  int diaryTotal = 0;
  int diaryUnack = 0;

  // Messages
  int messageTotal = 0;
  int messageUnread = 0;
  String latestMessagePreview = '';

  // Lists
  List<Map<String, dynamic>> assignNext3 = [];
  List<Map<String, dynamic>> recentCirculars = [];
  List<Map<String, dynamic>> todayPeriods = [];
  List<String> notifications = [];

  late NumberFormat currencyFormat;

  // Auto-scrolling highlights
  late PageController _pageController;
  Timer? _pageTimer;
  int _currentPage = 0;
  int slideCount = 4;

  final Duration slideInterval = const Duration(seconds: 5);
  final Duration slideDuration = const Duration(milliseconds: 550);

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // -------------------- Theme Tokens --------------------
  static const Color kAccent = Color(0xFF5B5FEF);
  static const Color kAccent2 = Color(0xFF8B5CF6);
  static const Color kBgTop = Color(0xFFF8FAFF);
  static const Color kBgBottom = Color(0xFFF1F5FF);
  static const Color kCard = Colors.white;
  static const Color kText = Color(0xFF111827);
  static const Color kMuted = Color(0xFF6B7280);
  static const Color kSoftBorder = Color(0xFFE8ECF5);
  static const Color kGreen = Color(0xFF0F9D58);
  static const Color kOrange = Color(0xFFF59E0B);
  static const Color kRed = Color(0xFFEF4444);
  static const Color kBlue = Color(0xFF2563EB);

  @override
  void initState() {
    super.initState();
    currencyFormat = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    );
    _pageController = PageController(viewportFraction: 0.92);
    _startAutoSlide();
    _loadInitial();
  }

  @override
  void dispose() {
    _pageTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoSlide() {
    _pageTimer?.cancel();
    _pageTimer = Timer.periodic(slideInterval, (_) {
      if (!_pageController.hasClients || slideCount <= 1) return;
      _currentPage = (_currentPage + 1) % slideCount;
      _pageController.animateToPage(
        _currentPage,
        duration: slideDuration,
        curve: Curves.easeInOut,
      );
      if (mounted) setState(() {});
    });
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authToken');
  }

  Future<void> _loadInitial() async {
    if (mounted) setState(() => loading = true);

    final prefs = await SharedPreferences.getInstance();
    username = prefs.getString('username') ?? prefs.getString('userId') ?? '';
    selectedAdmissionNumber =
        prefs.getString('selectedStudentAdmissionNumber') ?? username;
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
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    // Profile is fetched first because sibling switcher depends on studentId.
    await _fetchStudentProfile(headers).catchError((_) {});

    await Future.wait([
      _fetchSiblingStudents(headers),
      _fetchAttendance(headers),
      _fetchAssignments(headers),
      _fetchFees(headers),
      _fetchDiarySummary(headers),
      _fetchMessagesSummary(headers),
      _fetchTodayTimetable(headers),
      _fetchCirculars(headers),
    ].map((future) => future.catchError((_) {})));

    slideCount = 5;
    _startAutoSlide();
  }

  // -------------------- API Helpers --------------------
  String? _stringValue(dynamic v) {
    if (v == null) return null;
    final text = v.toString().trim();
    return text.isEmpty ? null : text;
  }

  int? _intValue(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  num? _numValue(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString().replaceAll(',', ''));
  }

  double _doubleValue(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '')) ?? 0.0;
  }

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  List<dynamic> _asList(dynamic v) {
    if (v is List) return v;
    return <dynamic>[];
  }

  dynamic _firstStudentAssignment(dynamic assignment) {
    final map = _asMap(assignment);
    final list = _asList(map?['StudentAssignments']);
    if (list.isEmpty) return null;
    return list.first;
  }

  String? photoUrlSafe(String? url) {
    final text = url?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  // -------------------- API Calls --------------------
  Future<void> _fetchStudentProfile(Map<String, String> headers) async {
    try {
      final activeAdmission = _activeAdmissionNumber();
      if (activeAdmission.isEmpty) return;

      final res = await http.get(
        Uri.parse('$baseUrl/students/admission/$activeAdmission'),
        headers: headers,
      );

      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      final json = _asMap(decoded);
      if (json == null) return;

      final cls = _asMap(json['Class']);
      final sec = _asMap(json['Section']);
      final ses = _asMap(json['Session']);
      final trans = _asMap(json['Transportation']);

      final dob = _stringValue(json['Date_Of_Birth']) ??
          _stringValue(json['date_of_birth']) ??
          _stringValue(json['dob']);

      final bg = _stringValue(json['b_group']) ??
          _stringValue(json['blood_group']) ??
          _stringValue(json['bloodGroup']);

      final photo = _stringValue(json['photo_url']) ?? _stringValue(json['photoUrl']);

      if (!mounted) return;
      setState(() {
        studentId = _intValue(json['id']) ?? studentId;
        studentName = _stringValue(json['name']) ?? studentName;
        admissionNumber = _stringValue(json['admission_number']) ??
            _stringValue(json['admissionNumber']) ??
            admissionNumber;

        dateOfBirth = dob ?? dateOfBirth;
        bloodGroup = bg ?? bloodGroup;

        className = _stringValue(cls?['class_name']) ??
            _stringValue(json['class_name']) ??
            className;
        sectionName = _stringValue(sec?['section_name']) ??
            _stringValue(json['section_name']) ??
            sectionName;
        sessionName = _stringValue(ses?['name']) ?? sessionName;

        fatherName = _stringValue(json['father_name']) ?? fatherName;
        motherName = _stringValue(json['mother_name']) ?? motherName;
        fatherPhone = _stringValue(json['father_phone']) ?? fatherPhone;
        motherPhone = _stringValue(json['mother_phone']) ?? motherPhone;
        address = _stringValue(json['address']) ?? address;

        routeId = _intValue(json['route_id']) ?? routeId;
        routeName = _stringValue(trans?['RouteName']) ?? routeName;
        routeCost = _numValue(trans?['Cost']) ?? routeCost;

        photoUrl = photoUrlSafe(photo ?? photoUrl);
      });
    } catch (e, st) {
      debugPrint('Error fetching student profile: $e\n$st');
    }
  }

  Future<void> _fetchSiblingStudents(Map<String, String> headers) async {
    if (isTeacher || studentId == null) {
      if (mounted) setState(() => siblingStudents = []);
      return;
    }

    if (mounted) setState(() => siblingsLoading = true);

    try {
      final current = <String, dynamic>{
        'id': studentId,
        'name': studentName ?? 'Current Student',
        'admission_number': admissionNumber ?? _activeAdmissionNumber(),
        'class_text': _classSectionText(),
        'photo_url': photoUrl,
        'is_current': true,
      };

      final res = await http.get(
        Uri.parse('$baseUrl/students/$studentId/siblings-with-due'),
        headers: headers,
      );

      final items = <Map<String, dynamic>>[current];

      if (res.statusCode == 200) {
        final json = _asMap(jsonDecode(res.body));
        final siblings = _asList(json?['siblings']);

        for (final item in siblings) {
          final map = _asMap(item);
          if (map == null) continue;

          final adm = _stringValue(map['admission_number']);
          if (adm == null || adm == current['admission_number']) continue;

          final route = _asMap(map['route']);
          final totals = _asMap(map['totals']);

          items.add({
            'id': map['id'],
            'name': _stringValue(map['name']) ?? 'Sibling',
            'admission_number': adm,
            'class_text':
                map['class_id'] != null ? "Class ID: ${map['class_id']}" : 'Sibling',
            'route_name': _stringValue(route?['route_name']),
            'grand_total_due': _doubleValue(totals?['grandTotal']),
            'is_current': false,
          });
        }
      }

      if (!mounted) return;
      setState(() {
        siblingStudents = items;
        siblingsLoading = false;
      });
    } catch (e, st) {
      debugPrint('Error fetching siblings: $e\n$st');
      if (!mounted) return;
      setState(() {
        siblingStudents = [
          {
            'id': studentId,
            'name': studentName ?? 'Current Student',
            'admission_number': admissionNumber ?? _activeAdmissionNumber(),
            'class_text': _classSectionText(),
            'photo_url': photoUrl,
            'is_current': true,
          }
        ];
        siblingsLoading = false;
      });
    }
  }

  Future<void> _fetchAttendance(Map<String, String> headers) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/attendance/student/me'),
        headers: headers,
      );
      if (res.statusCode != 200) return;

      final rows = _asList(jsonDecode(res.body));
      final now = DateTime.now();
      final monthRows = rows.where((r) {
        final map = _asMap(r);
        final d = DateTime.tryParse(map?['date']?.toString() ?? '') ?? DateTime(1970);
        return d.month == now.month && d.year == now.year;
      }).toList();

      final p = monthRows.where((r) {
        final map = _asMap(r);
        return (map?['status'] ?? '').toString().toLowerCase() == 'present';
      }).length;

      final a = monthRows.where((r) {
        final map = _asMap(r);
        return (map?['status'] ?? '').toString().toLowerCase() == 'absent';
      }).length;

      final l = monthRows.where((r) {
        final map = _asMap(r);
        return (map?['status'] ?? '').toString().toLowerCase() == 'leave';
      }).length;

      if (!mounted) return;
      setState(() {
        present = p;
        absent = a;
        leaveCount = l;
        totalDays = monthRows.length;
      });
    } catch (_) {}
  }

  Future<void> _fetchAssignments(Map<String, String> headers) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/student-assignments/student'),
        headers: headers,
      );
      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      final json = _asMap(decoded);
      final list = _asList(json?['assignments']);

      int submitted = 0;
      int graded = 0;
      int overdue = 0;
      final upcoming = <dynamic>[];

      for (final item in list) {
        final sa = _asMap(_firstStudentAssignment(item));
        final status = (sa?['status'] ?? '').toString().toLowerCase();

        if (status == 'submitted') submitted++;
        if (status == 'graded') graded++;

        final dueStr = sa?['dueDate'] ?? sa?['due_date'];
        final due = dueStr != null ? DateTime.tryParse(dueStr.toString()) : null;
        final isDone = ['submitted', 'graded'].contains(status);

        if (due != null && !isDone) {
          if (DateTime.now().isAfter(due.add(const Duration(days: 1)))) {
            overdue++;
          } else {
            upcoming.add(item);
          }
        }
      }

      upcoming.sort((a, b) {
        final sa = _asMap(_firstStudentAssignment(a));
        final sb = _asMap(_firstStudentAssignment(b));
        final da = DateTime.tryParse((sa?['dueDate'] ?? sa?['due_date'] ?? '').toString());
        final db = DateTime.tryParse((sb?['dueDate'] ?? sb?['due_date'] ?? '').toString());
        return (da ?? DateTime(9999)).compareTo(db ?? DateTime(9999));
      });

      final next3 = <Map<String, dynamic>>[];
      for (final item in upcoming.take(3)) {
        final map = _asMap(item) ?? <String, dynamic>{};
        final sa = _asMap(_firstStudentAssignment(item)) ?? <String, dynamic>{};
        next3.add({
          'id': map['id'],
          'title': map['title'] ?? 'Untitled',
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
    } catch (_) {}
  }

  Future<void> _fetchFees(Map<String, String> headers) async {
    try {
      final activeAdmission = _activeAdmissionNumber();
      if (activeAdmission.isEmpty) return;

      final res = await http.get(
        Uri.parse('$baseUrl/StudentsApp/admission/$activeAdmission/fees'),
        headers: headers,
      );
      if (res.statusCode != 200) return;

      final json = _asMap(jsonDecode(res.body));
      if (json == null) return;

      final fees = _asList(json['feeDetails']);
      final totalDue = fees.fold<double>(0.0, (sum, f) {
        final map = _asMap(f) ?? <String, dynamic>{};
        return sum + _doubleValue(map['finalAmountDue'] ?? map['final_amount_due']);
      });

      final vanObj = _asMap(json['vanFee']) ?? <String, dynamic>{};
      final vanCost = _doubleValue(vanObj['perHeadTotalDue'] ?? vanObj['transportCost']);
      final vanRecv = _doubleValue(vanObj['totalVanFeeReceived']);
      final vanCon = _doubleValue(vanObj['totalVanFeeConcession']);
      final vanDueNum = (vanCost - (vanRecv + vanCon)).clamp(0, double.infinity).toDouble();

      if (!mounted) return;
      setState(() {
        feeTotalDue = totalDue;
        feeVanDue = vanDueNum;
      });
    } catch (_) {}
  }

  Future<void> _fetchDiarySummary(Map<String, String> headers) async {
    try {
      final latestRes = await http.get(
        Uri.parse('$baseUrl/diaries/student/feed/list?page=1&pageSize=5&order=date:DESC'),
        headers: headers,
      );
      if (latestRes.statusCode != 200) return;

      final latestJson = _asMap(jsonDecode(latestRes.body));
      final latestItems = _asList(latestJson?['data']);
      final latestPagination = _asMap(latestJson?['pagination']);
      final total = int.tryParse((latestPagination?['total'] ?? latestItems.length).toString()) ?? latestItems.length;

      final unackRes = await http.get(
        Uri.parse('$baseUrl/diaries/student/feed/list?page=1&pageSize=1&order=date:DESC&onlyUnacknowledged=true'),
        headers: headers,
      );

      int unack = 0;
      if (unackRes.statusCode == 200) {
        final unackJson = _asMap(jsonDecode(unackRes.body));
        final unackPagination = _asMap(unackJson?['pagination']);
        unack = int.tryParse((unackPagination?['total'] ?? 0).toString()) ?? 0;
      }

      if (!mounted) return;
      setState(() {
        diaryTotal = total;
        diaryUnack = unack;
      });
    } catch (_) {}
  }

  Future<void> _fetchCirculars(Map<String, String> headers) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/circulars'), headers: headers);
      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      final json = _asMap(decoded);
      final list = json != null ? _asList(json['circulars']) : _asList(decoded);

      final filtered = list.where((item) {
        final map = _asMap(item);
        final audience = (map?['audience'] ?? '').toString().toLowerCase();
        return audience == 'student' || audience == 'both' || audience.isEmpty;
      }).toList();

      filtered.sort((a, b) {
        final ma = _asMap(a);
        final mb = _asMap(b);
        final da = DateTime.tryParse(ma?['createdAt']?.toString() ?? '') ?? DateTime(1970);
        final db = DateTime.tryParse(mb?['createdAt']?.toString() ?? '') ?? DateTime(1970);
        return db.compareTo(da);
      });

      if (!mounted) return;
      setState(() {
        recentCirculars = filtered
            .take(5)
            .map((e) => Map<String, dynamic>.from(_asMap(e) ?? <String, dynamic>{}))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _fetchMessagesSummary(Map<String, String> headers) async {
    try {
      final uri = Uri.parse('$baseUrl/api/messages/me').replace(
        queryParameters: {
          'page': '1',
          'limit': '5',
          'unreadOnly': 'false',
        },
      );

      final res = await http.get(uri, headers: headers);
      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      final json = _asMap(decoded);
      final rows = _asList(json?['data']);
      final pagination = _asMap(json?['pagination']);

      final total = _intValue(pagination?['total']) ?? rows.length;
      int unread = 0;
      String preview = '';

      for (final row in rows) {
        final map = _asMap(row);
        if (map == null) continue;

        if (map['lastReadAt'] == null && map['last_read_at'] == null) {
          unread++;
        }

        if (preview.isEmpty) {
          final thread = _asMap(map['thread']);
          final messages = _asList(thread?['messages']);
          final latest = messages.isNotEmpty ? _asMap(messages.first) : null;
          final body = _stringValue(latest?['body']);
          final subject = _stringValue(thread?['subject']);

          preview = body ?? subject ?? '';
        }
      }

      if (!mounted) return;
      setState(() {
        messageTotal = total;
        messageUnread = unread;
        latestMessagePreview = preview;
      });
    } catch (e, st) {
      debugPrint('Error fetching message summary: $e\n$st');
    }
  }

  Future<void> _fetchTodayTimetable(Map<String, String> headers) async {
    try {
      final pRes = await http.get(Uri.parse('$baseUrl/periods'), headers: headers);
      final tRes = await http.get(
        Uri.parse('$baseUrl/period-class-teacher-subject/student/timetable'),
        headers: headers,
      );
      if (pRes.statusCode != 200 || tRes.statusCode != 200) return;

      final periods = _asList(jsonDecode(pRes.body));
      final ttbRaw = jsonDecode(tRes.body);
      final timetable = ttbRaw is List ? ttbRaw : _asList(_asMap(ttbRaw)?['timetable']);

      const days = [
        'Sunday',
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
      ];
      final todayName = days[DateTime.now().weekday % 7];

      final mapByPeriod = <dynamic, dynamic>{};
      for (final row in timetable) {
        final map = _asMap(row);
        if (map?['day'] == todayName) {
          mapByPeriod[map?['periodId']] = map;
        }
      }

      final items = <Map<String, dynamic>>[];
      for (final period in periods) {
        final pMap = _asMap(period) ?? <String, dynamic>{};
        final id = pMap['id'];
        final row = _asMap(mapByPeriod[id]);
        if (row == null) continue;

        final subject = _asMap(row['Subject']);
        final teacher = _asMap(row['Teacher']);
        final startTime = pMap['start_time'];
        final endTime = pMap['end_time'];

        items.add({
          'period': pMap['period_name'] ?? pMap['name'],
          'time': (startTime != null && endTime != null) ? '$startTime–$endTime' : '',
          'subject': subject?['name'] ?? row['subjectId'] ?? '—',
          'teacher': teacher?['name'] ?? '—',
          'start_time': startTime,
          'end_time': endTime,
        });
      }

      items.sort((a, b) => _minutes(a['start_time']).compareTo(_minutes(b['start_time'])));

      if (!mounted) return;
      setState(() => todayPeriods = items);
    } catch (_) {}
  }

  int _minutes(dynamic time) {
    final text = time?.toString();
    if (text == null || text.isEmpty) return 999999;
    final parts = text.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    return h * 60 + m;
  }

  // -------------------- UI --------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: kBgTop,
      appBar: StudentAppBar(
        parentContext: context,
        scaffoldKey: _scaffoldKey,
        title: 'Pathseekers',
      ),
      drawer: StudentDrawerMenu(),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kBgTop, kBgBottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async => _fetchAll(),
            color: kAccent,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
              children: [
                _heroSection(),
                const SizedBox(height: 14),
                if (!isTeacher) ...[
                  _siblingSwitcherCard(),
                  const SizedBox(height: 14),
                  _studentProfileCard(),
                  const SizedBox(height: 14),
                ],
                _overviewStatsGrid(),
                const SizedBox(height: 14),
                _slidesPanel(presencePct()),
                const SizedBox(height: 14),
                _todayCard(),
                const SizedBox(height: 14),
                _quickActionsGrid(),
                const SizedBox(height: 14),
                _recentCircularsFullWidth(),
                const SizedBox(height: 14),
                _assignmentsPanel(),
                const SizedBox(height: 14),
                _timetableSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(14),
    BorderRadius? radius,
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: radius ?? BorderRadius.circular(22),
        border: Border.all(color: kSoftBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    String actionText = 'View all',
  }) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: kAccent.withOpacity(0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: kAccent, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: kText,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: kMuted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        if (onTap != null)
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: kAccent,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
            ),
            child: Text(
              actionText,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
      ],
    );
  }

  // -------------------- Hero --------------------
  Widget _heroSection() {
    final initials = _initialsFor(studentName ?? username);
    final name = _displayName();
    final subtitle = isTeacher ? 'Teacher Dashboard' : _classSectionText();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kAccent, kAccent2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: kAccent.withOpacity(0.25),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(initials),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back,',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.82),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.88),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _notificationButton(),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _heroChip(
                  icon: isTeacher ? Icons.badge_outlined : Icons.show_chart,
                  label: isTeacher ? 'Role' : 'Attendance',
                  value: isTeacher ? 'Teacher' : '${presencePct()}%',
                ),
                if (!isTeacher && (admissionNumber ?? '').trim().isNotEmpty)
                  _heroChip(
                    icon: Icons.confirmation_number_outlined,
                    label: 'Adm No',
                    value: admissionNumber!,
                  ),
                if ((sessionName ?? '').trim().isNotEmpty)
                  _heroChip(
                    icon: Icons.school_outlined,
                    label: 'Session',
                    value: sessionName!,
                  ),
                if (messageUnread > 0)
                  _heroChip(
                    icon: Icons.mark_chat_unread_outlined,
                    label: 'Messages',
                    value: '$messageUnread unread',
                  ),
                if (!isTeacher && (bloodGroup ?? '').trim().isNotEmpty)
                  _heroChip(
                    icon: Icons.bloodtype_outlined,
                    label: 'Blood',
                    value: bloodGroup!.trim(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String initials) {
    final url = (photoUrl ?? '').trim();

    if (url.isNotEmpty) {
      return Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.85), width: 3),
        ),
        child: ClipOval(
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _avatarFallback(initials),
          ),
        ),
      );
    }

    return _avatarFallback(initials);
  }

  Widget _avatarFallback(String initials) {
    return Container(
      width: 62,
      height: 62,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials.isNotEmpty ? initials : 'S',
          style: const TextStyle(
            color: kAccent,
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        ),
      ),
    );
  }

  Widget _notificationButton() {
    return InkWell(
      onTap: _openNotifications,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.16),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.20)),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Center(
              child: Icon(Icons.notifications_none_rounded, color: Colors.white),
            ),
            if (notifications.isNotEmpty)
              Positioned(
                right: -4,
                top: -5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: kRed,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    '${notifications.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _heroChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.white.withOpacity(0.76),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------- Sibling Switcher --------------------
  String _activeAdmissionNumber() {
    final selected = selectedAdmissionNumber.trim();
    if (selected.isNotEmpty) return selected;
    return username.trim();
  }

  Widget _siblingSwitcherCard() {
    final showSwitcher = siblingsLoading || siblingStudents.length > 1;
    if (!showSwitcher) return const SizedBox.shrink();

    return _card(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.switch_account_rounded,
            title: 'Sibling Switcher',
            subtitle: 'Select student to view profile and dues',
          ),
          const SizedBox(height: 12),
          if (siblingsLoading)
            _skeleton(lines: 2)
          else
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: siblingStudents.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final item = siblingStudents[index];
                  final adm = _stringValue(item['admission_number']) ?? '';
                  final isActive = adm == _activeAdmissionNumber();
                  return _siblingStudentChip(item, isActive);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _siblingStudentChip(Map<String, dynamic> item, bool isActive) {
    final adm = _stringValue(item['admission_number']) ?? '';
    final name = _stringValue(item['name']) ?? 'Student';
    final classText = _stringValue(item['class_text']) ?? 'Student';
    final due = _doubleValue(item['grand_total_due']);
    final initials = _initialsFor(name);

    return InkWell(
      onTap: isActive || adm.isEmpty ? null : () => _switchStudent(adm),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 238,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isActive ? kAccent.withOpacity(0.10) : const Color(0xFFF8FAFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? kAccent.withOpacity(0.55) : kSoftBorder,
            width: isActive ? 1.3 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isActive
                    ? const LinearGradient(colors: [kAccent, kAccent2])
                    : LinearGradient(
                        colors: [
                          kAccent.withOpacity(0.12),
                          kAccent2.withOpacity(0.09),
                        ],
                      ),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    color: isActive ? Colors.white : kAccent,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: kText,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: kAccent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Active',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Adm: $adm • $classText',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    due > 0 ? 'Due: ${currencyFormat.format(due)}' : 'Tap to switch',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: due > 0 ? kOrange : kAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _switchStudent(String admissionNo) async {
    final selected = admissionNo.trim();
    if (selected.isEmpty || selected == _activeAdmissionNumber()) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedStudentAdmissionNumber', selected);

    if (!mounted) return;
    setState(() {
      selectedAdmissionNumber = selected;
      loading = true;
      studentId = null;
      studentName = null;
      admissionNumber = selected;
      dateOfBirth = null;
      bloodGroup = null;
      className = null;
      sectionName = null;
      sessionName = null;
      fatherName = null;
      motherName = null;
      fatherPhone = null;
      motherPhone = null;
      address = null;
      routeId = null;
      routeName = null;
      routeCost = null;
      photoUrl = null;
      feeTotalDue = 0;
      feeVanDue = 0;
      siblingStudents = [];
    });

    await _fetchAll();

    if (!mounted) return;
    setState(() => loading = false);
  }

  // -------------------- Student Profile --------------------
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

    if (!hasAny && loading) {
      return _card(child: _skeleton(lines: 4));
    }

    final dobPretty = _formatDobPretty(dateOfBirth);
    final ageText = _ageFromDob(dateOfBirth);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.account_circle_outlined,
            title: 'Student Profile',
            subtitle: 'Basic details at one place',
            onTap: () => Navigator.pushNamed(context, '/fee-details'),
            actionText: 'Fees',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if ((admissionNumber ?? '').trim().isNotEmpty)
                _infoPill('Adm No', admissionNumber!),
              if ((sessionName ?? '').trim().isNotEmpty)
                _infoPill('Session', sessionName!),
              if ((dobPretty ?? '').trim().isNotEmpty)
                _infoPill('DOB', dobPretty!),
              if ((ageText ?? '').trim().isNotEmpty)
                _infoPill('Age', ageText!),
              if ((bloodGroup ?? '').trim().isNotEmpty)
                _infoPill('Blood', bloodGroup!.trim()),
              if ((routeName ?? '').trim().isNotEmpty)
                _infoPill(
                  'Route',
                  routeId != null ? '${routeName!} (#$routeId)' : routeName!,
                ),
              if (routeCost != null)
                _infoPill('Route Fee', currencyFormat.format(routeCost)),
            ],
          ),
          const SizedBox(height: 14),
          _profileLine(Icons.person_outline_rounded, 'Father', _join2(fatherName, fatherPhone)),
          const SizedBox(height: 10),
          _profileLine(Icons.person_2_outlined, 'Mother', _join2(motherName, motherPhone)),
          if ((address ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _profileLine(Icons.home_outlined, 'Address', address!.trim()),
          ],
        ],
      ),
    );
  }

  Widget _infoPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kSoftBorder),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: kText,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _profileLine(IconData icon, String label, String value) {
    final text = value.trim().isEmpty ? '—' : value.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: kAccent.withOpacity(0.09),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: kAccent, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: kMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                text,
                style: const TextStyle(
                  color: kText,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -------------------- Overview --------------------
  Widget _overviewStatsGrid() {
    final items = <_DashStat>[
      _DashStat(
        title: isTeacher ? 'Attendance' : 'Present',
        value: isTeacher ? 'Calendar' : '$present/$totalDays',
        subtitle: isTeacher ? 'Open attendance' : '${presencePct()}% this month',
        icon: Icons.calendar_month_rounded,
        color: kBlue,
        route: isTeacher ? '/my-attendance-calendar' : '/attendance',
      ),
      _DashStat(
        title: 'Assignments',
        value: '$assignOverdue',
        subtitle: 'Overdue of $assignTotal',
        icon: Icons.assignment_turned_in_outlined,
        color: assignOverdue > 0 ? kRed : kGreen,
        route: '/assignments',
      ),
      _DashStat(
        title: 'Fees Due',
        value: currencyFormat.format(feeTotalDue),
        subtitle: 'Transport: ${currencyFormat.format(feeVanDue)}',
        icon: Icons.payments_outlined,
        color: feeTotalDue > 0 ? kOrange : kGreen,
        route: '/fee-details',
      ),
      _DashStat(
        title: 'Diary',
        value: '$diaryUnack',
        subtitle: '$diaryTotal total entries',
        icon: Icons.menu_book_outlined,
        color: diaryUnack > 0 ? kOrange : kGreen,
        route: '/diaries',
      ),
      _DashStat(
        title: 'Messages',
        value: messageUnread > 0 ? '$messageUnread' : '$messageTotal',
        subtitle: messageUnread > 0
            ? 'Unread of $messageTotal'
            : '$messageTotal total messages',
        icon: Icons.mark_chat_unread_outlined,
        color: messageUnread > 0 ? kRed : kBlue,
        route: '/messages',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        final crossAxisCount = isWide ? 4 : 2;
        final aspect = isWide ? 1.35 : 1.28;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: aspect,
          ),
          itemBuilder: (context, index) => _statCard(items[index]),
        );
      },
    );
  }

  Widget _statCard(_DashStat stat) {
    return InkWell(
      onTap: () => stat.route == '/messages'
          ? _openMessages()
          : Navigator.pushNamed(context, stat.route),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kSoftBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: stat.color.withOpacity(0.11),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(stat.icon, color: stat.color, size: 20),
                ),
                const Spacer(),
                Icon(Icons.arrow_forward_ios_rounded, size: 13, color: kMuted.withOpacity(0.65)),
              ],
            ),
            const Spacer(),
            Text(
              stat.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kText,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              stat.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kText,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              stat.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------- Highlights Slider --------------------
  Widget _slidesPanel(int presencePct) {
    final slides = [
      _highlightSlide(
        title: isTeacher ? 'My Attendance' : 'Attendance',
        subtitle: isTeacher ? 'Check your calendar view' : '$presencePct% attendance this month',
        trailing: isTeacher ? 'Open Calendar' : '$present / $totalDays days',
        icon: Icons.calendar_today_rounded,
        colors: const [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
        iconColor: kBlue,
        onTap: () => Navigator.pushNamed(
          context,
          isTeacher ? '/my-attendance-calendar' : '/attendance',
        ),
      ),
      _highlightSlide(
        title: 'Assignments',
        subtitle: '$assignSubmitted submitted • $assignGraded graded',
        trailing: '$assignOverdue overdue',
        icon: Icons.task_alt_rounded,
        colors: const [Color(0xFFFFF1F2), Color(0xFFFFE4E6)],
        iconColor: kRed,
        onTap: () => Navigator.pushNamed(context, '/assignments'),
      ),
      _highlightSlide(
        title: 'Fees',
        subtitle: 'School due: ${currencyFormat.format(feeTotalDue)}',
        trailing: 'Van: ${currencyFormat.format(feeVanDue)}',
        icon: Icons.account_balance_wallet_outlined,
        colors: const [Color(0xFFF0FDF4), Color(0xFFDCFCE7)],
        iconColor: kGreen,
        onTap: () => Navigator.pushNamed(context, '/fee-details'),
      ),
      _highlightSlide(
        title: 'Messages',
        subtitle: latestMessagePreview.trim().isNotEmpty
            ? latestMessagePreview
            : 'Fee reminders & teacher replies',
        trailing: messageUnread > 0 ? '$messageUnread unread' : '$messageTotal total',
        icon: Icons.mark_chat_unread_rounded,
        colors: const [Color(0xFFEFF6FF), Color(0xFFEDE9FE)],
        iconColor: messageUnread > 0 ? kRed : kBlue,
        onTap: _openMessages,
      ),
      _highlightSlide(
        title: 'Diary',
        subtitle: '$diaryTotal entries available',
        trailing: '$diaryUnack pending',
        icon: Icons.auto_stories_outlined,
        colors: const [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
        iconColor: kOrange,
        onTap: () => Navigator.pushNamed(context, '/diaries'),
      ),
    ];

    slideCount = slides.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _smallHeading('Highlights'),
        const SizedBox(height: 8),
        SizedBox(
          height: 136,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: slides.length,
            itemBuilder: (context, index) => slides[index],
          ),
        ),
        const SizedBox(height: 9),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(slideCount, (i) {
            final active = i == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 18 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: active ? kAccent : const Color(0xFFD5DAE7),
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _highlightSlide({
    required String title,
    required String subtitle,
    required String trailing,
    required IconData icon,
    required List<Color> colors,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.72)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.055),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.88),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: iconColor, size: 30),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kText,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.70),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      trailing,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: kText,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: kMuted),
          ],
        ),
      ),
    );
  }

  // -------------------- Today Card --------------------
  Widget _todayCard() {
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, d MMMM yyyy').format(now);
    final nextPeriod = _nextPeriodText();

    return _card(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Today',
                  style: TextStyle(
                    color: kText,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  dateStr,
                  style: const TextStyle(color: kMuted, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: kAccent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    nextPeriod,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kAccent, kAccent2]),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(Icons.today_rounded, color: Colors.white, size: 34),
          ),
        ],
      ),
    );
  }

  String _nextPeriodText() {
    if (todayPeriods.isEmpty) return isTeacher ? 'No timetable for today' : 'No periods today';

    final now = DateTime.now();
    for (final period in todayPeriods) {
      final start = _timeToday(period['start_time']);
      final end = _timeToday(period['end_time']);
      if (start == null || end == null) continue;

      if (now.isAfter(start) && now.isBefore(end)) {
        return 'Now: ${(period['subject'] ?? 'Class').toString()}';
      }
      if (now.isBefore(start)) {
        return 'Next: ${(period['subject'] ?? 'Class').toString()}';
      }
    }

    return 'All periods completed';
  }

  DateTime? _timeToday(dynamic value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    final parts = text.split(':');
    if (parts.isEmpty) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0');
    if (h == null || m == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, h, m);
  }

  // -------------------- Quick Actions --------------------
  Widget _quickActionsGrid() {
    final items = <Map<String, dynamic>>[
      {
        'label': isTeacher ? 'My Attendance' : 'Attendance',
        'icon': Icons.calendar_today_rounded,
        'route': isTeacher ? '/my-attendance-calendar' : '/attendance',
        'badge': isTeacher ? 'Calendar' : '${presencePct()}%',
      },
      {
        'label': 'Assignments',
        'icon': Icons.task_alt_rounded,
        'route': '/assignments',
        'badge': '$assignOverdue',
      },
      {
        'label': 'Diary',
        'icon': Icons.menu_book_rounded,
        'route': '/diaries',
        'badge': '$diaryUnack',
      },
      {
        'label': 'Messages',
        'icon': Icons.mark_chat_unread_rounded,
        'route': '/messages',
        'badge': messageUnread > 0 ? '$messageUnread' : 'Open',
        'highlight': true,
        'color': messageUnread > 0 ? kRed : kBlue,
      },
      {
        'label': 'Circulars',
        'icon': Icons.campaign_rounded,
        'route': '/circulars',
        'badge': '${recentCirculars.length}',
      },
      {
        'label': 'Timetable',
        'icon': Icons.schedule_rounded,
        'route': '/timetable',
        'badge': '${todayPeriods.length}',
      },
      {
        'label': 'Fees',
        'icon': Icons.payments_rounded,
        'route': '/fee-details',
        'badge': feeTotalDue > 0 ? 'Due' : 'OK',
      },
    ];

    if (isTeacher) {
      items.addAll([
        {
          'label': 'Substitution',
          'icon': Icons.swap_horiz_rounded,
          'route': '/teacher/substitutions',
          'badge': 'Open',
        },
        {
          'label': 'My Table',
          'icon': Icons.table_view_rounded,
          'route': '/teacher-timetable-display',
          'badge': 'Open',
        },
      ]);
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.grid_view_rounded,
            title: 'Quick Actions',
            subtitle: 'Most used options',
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final cross = constraints.maxWidth >= 700 ? 4 : 3;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cross,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.92,
                ),
                itemBuilder: (context, index) => _quickActionTile(items[index]),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _quickActionTile(Map<String, dynamic> item) {
    final route = (item['route'] ?? '').toString();
    final isHighlighted = item['highlight'] == true;
    final tileColor = item['color'] is Color ? item['color'] as Color : kAccent;
    final badgeText = (item['badge'] ?? '').toString();

    return InkWell(
      onTap: () => route == '/messages'
          ? _openMessages()
          : Navigator.pushNamed(context, route),
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          gradient: isHighlighted
              ? LinearGradient(
                  colors: [
                    tileColor,
                    kAccent2,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isHighlighted ? null : const Color(0xFFF8FAFF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isHighlighted ? Colors.white.withOpacity(0.45) : kSoftBorder,
            width: isHighlighted ? 1.4 : 1,
          ),
          boxShadow: isHighlighted
              ? [
                  BoxShadow(
                    color: tileColor.withOpacity(0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isHighlighted ? Colors.white.withOpacity(0.18) : null,
                    gradient: isHighlighted
                        ? null
                        : LinearGradient(
                            colors: [
                              kAccent.withOpacity(0.13),
                              kAccent2.withOpacity(0.10),
                            ],
                          ),
                    borderRadius: BorderRadius.circular(16),
                    border: isHighlighted
                        ? Border.all(color: Colors.white.withOpacity(0.22))
                        : null,
                  ),
                  child: Icon(
                    item['icon'] as IconData,
                    color: isHighlighted ? Colors.white : kAccent,
                    size: 22,
                  ),
                ),
                if (badgeText.isNotEmpty)
                  Positioned(
                    right: -7,
                    top: -7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: isHighlighted
                            ? (messageUnread > 0 ? kRed : Colors.white)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isHighlighted
                              ? Colors.white.withOpacity(0.85)
                              : kSoftBorder,
                        ),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          color: isHighlighted
                              ? (messageUnread > 0 ? Colors.white : tileColor)
                              : kAccent,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              (item['label'] ?? '').toString(),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isHighlighted ? Colors.white : kText,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                height: 1.15,
              ),
            ),
            if (isHighlighted) ...[
              const SizedBox(height: 4),
              Text(
                messageUnread > 0 ? 'Unread messages' : 'Tap to open',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.86),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // -------------------- Assignments --------------------
  Widget _assignmentsPanel() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.assignment_outlined,
            title: 'Upcoming Assignments',
            subtitle: assignNext3.isEmpty ? 'No pending work' : 'Nearest due dates first',
            onTap: () => Navigator.pushNamed(context, '/assignments'),
            actionText: 'Open',
          ),
          const SizedBox(height: 12),
          _assignmentsCard(),
        ],
      ),
    );
  }

  Widget _assignmentsCard() {
    if (loading) return _skeleton(lines: 3);

    if (assignNext3.isEmpty) {
      return _emptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'All clear',
        message: 'No upcoming assignments right now.',
      );
    }

    return Column(
      children: assignNext3.map((assignment) {
        final due = assignment['due']?.toString();
        final dueDate = due != null ? DateTime.tryParse(due) : null;
        final dueText = dueDate != null ? DateFormat('d MMM yyyy').format(dueDate) : '—';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kSoftBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: kAccent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.task_alt_rounded, color: kAccent),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assignment['title']?.toString() ?? 'Untitled',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: kText,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Due: $dueText',
                      style: const TextStyle(color: kMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _tinyButton(
                label: 'Open',
                onTap: () => Navigator.pushNamed(context, '/assignments'),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // -------------------- Timetable --------------------
  Widget _timetableSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.schedule_outlined,
            title: "Today's Timetable",
            subtitle: todayPeriods.isEmpty ? 'No classes scheduled' : '${todayPeriods.length} periods today',
            onTap: () => Navigator.pushNamed(context, '/timetable'),
            actionText: 'Open',
          ),
          const SizedBox(height: 12),
          if (loading)
            _skeleton(lines: 3)
          else if (todayPeriods.isEmpty)
            _emptyState(
              icon: Icons.event_available_outlined,
              title: 'No periods today',
              message: 'Your timetable is free for today.',
            )
          else
            Column(
              children: todayPeriods.take(5).map((period) {
                final current = _isCurrentPeriod(period);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: current ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: current ? kGreen.withOpacity(0.35) : kSoftBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: current ? kGreen.withOpacity(0.12) : kAccent.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          current ? Icons.play_circle_outline_rounded : Icons.book_outlined,
                          color: current ? kGreen : kAccent,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    (period['subject'] ?? '—').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: kText,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                if (current) _liveBadge(),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              (period['teacher'] ?? '—').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: kMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        (period['time'] ?? '').toString(),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: kMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          if (todayPeriods.length > 5)
            Center(
              child: TextButton(
                onPressed: () => Navigator.pushNamed(context, '/timetable'),
                child: Text(
                  '+${todayPeriods.length - 5} more periods',
                  style: const TextStyle(color: kAccent, fontWeight: FontWeight.w900),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _isCurrentPeriod(Map<String, dynamic> period) {
    final now = DateTime.now();
    final start = _timeToday(period['start_time']);
    final end = _timeToday(period['end_time']);
    if (start == null || end == null) return false;
    return now.isAfter(start) && now.isBefore(end);
  }

  Widget _liveBadge() {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kGreen,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'LIVE',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  // -------------------- Circulars --------------------
  Widget _recentCircularsFullWidth() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.campaign_outlined,
            title: 'Recent Circulars',
            subtitle: recentCirculars.isEmpty ? 'School notices' : 'Latest school notices',
            onTap: () => Navigator.pushNamed(context, '/circulars'),
            actionText: 'See all',
          ),
          const SizedBox(height: 12),
          if (loading)
            _skeleton(lines: 3)
          else if (recentCirculars.isEmpty)
            _emptyState(
              icon: Icons.notifications_none_rounded,
              title: 'No circulars',
              message: 'No recent circulars are available.',
            )
          else
            Column(
              children: recentCirculars.map((circular) {
                final title = circular['title'] ?? 'Untitled';
                final created = DateTime.tryParse(circular['createdAt']?.toString() ?? '') ?? DateTime.now();

                return InkWell(
                  onTap: () => Navigator.pushNamed(context, '/circulars'),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFF),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: kSoftBorder),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: kGreen.withOpacity(0.11),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: const Icon(Icons.campaign_rounded, color: kGreen),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title.toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: kText,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat('d MMM yyyy').format(created),
                                style: const TextStyle(color: kMuted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: kMuted),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // -------------------- Reusable UI --------------------
  Widget _tinyButton({required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: kAccent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: kAccent.withOpacity(0.20),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kSoftBorder),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: kMuted.withOpacity(0.55)),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: kText,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _skeleton({int lines = 3}) {
    return Column(
      children: List.generate(lines, (index) {
        return Container(
          width: double.infinity,
          height: index == 0 ? 18 : 14,
          margin: EdgeInsets.only(bottom: index == lines - 1 ? 0 : 10),
          decoration: BoxDecoration(
            color: const Color(0xFFE9EDF7),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }

  Widget _smallHeading(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        title,
        style: const TextStyle(
          color: kText,
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  // -------------------- Misc Helpers --------------------
  String _initialsFor(String input) {
    final text = input.trim();
    if (text.isEmpty) return 'S';

    final parts = text.split(RegExp(r'\s+')).where((p) => p.trim().isNotEmpty).toList();
    if (parts.isEmpty) return 'S';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();

    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  String _displayName() {
    final name = (studentName ?? username).toString().trim();
    return name.isEmpty ? (isTeacher ? 'Teacher' : 'Student') : name;
  }

  String _classSectionText() {
    final cls = (className ?? '').trim();
    final sec = (sectionName ?? '').trim();

    if (cls.isEmpty && sec.isEmpty) return 'Student Dashboard';
    if (cls.isNotEmpty && sec.isNotEmpty) return 'Class $cls • Section $sec';
    if (cls.isNotEmpty) return 'Class $cls';
    return 'Section $sec';
  }

  int presencePct() {
    if (totalDays <= 0) return 0;
    return ((present / totalDays) * 100).round();
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
    final text = (raw ?? '').trim();
    if (text.isEmpty) return null;

    final dt = DateTime.tryParse(text);
    if (dt == null) return text;
    return DateFormat('d MMM yyyy').format(dt);
  }

  String? _ageFromDob(String? raw) {
    final text = (raw ?? '').trim();
    final dob = DateTime.tryParse(text);
    if (dob == null) return null;

    final now = DateTime.now();
    int years = now.year - dob.year;
    final hadBirthdayThisYear = now.month > dob.month || (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthdayThisYear) years -= 1;
    if (years < 0) return null;

    return '$years yrs';
  }

  void _openMessages() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const StudentMessagesScreen(),
      ),
    ).then((_) => _fetchAll());
  }

  void _openNotifications() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Text(
                          'Notifications',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: kText,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Clear all',
                          icon: const Icon(Icons.delete_outline_rounded, color: kMuted),
                          onPressed: () async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.remove('notifications');
                            if (!mounted) return;
                            setState(() => notifications.clear());
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (notifications.isEmpty)
                      _emptyState(
                        icon: Icons.notifications_none_rounded,
                        title: 'No notifications',
                        message: 'You are all caught up.',
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: notifications.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, index) {
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFF),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: kSoftBorder),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: kAccent.withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    child: const Icon(Icons.info_outline_rounded, color: kAccent),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          notifications[index],
                                          style: const TextStyle(
                                            color: kText,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        const Text(
                                          'Just now',
                                          style: TextStyle(color: kMuted, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DashStat {
  const _DashStat({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.route,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String route;
}