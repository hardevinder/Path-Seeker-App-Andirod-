import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/role_manager.dart';
import '../constants/constants.dart';
import '../services/api_service.dart';
import '../widgets/teacher_app_bar.dart';
import '../widgets/teacher_drawer_menu.dart';

class CoordinatorDashboard extends StatefulWidget {
  const CoordinatorDashboard({super.key});

  @override
  State<CoordinatorDashboard> createState() => _CoordinatorDashboardState();
}

class _CoordinatorDashboardState extends State<CoordinatorDashboard> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final DateFormat _apiDateFormat = DateFormat('yyyy-MM-dd');
  final DateFormat _displayDateFormat = DateFormat('dd MMM yyyy');
  final DateFormat _timeFormat = DateFormat('hh:mm a');

  String _displayName = 'Coordinator';
  String _schoolName = appName;
  DateTime _selectedDate = DateTime.now();
  DateTime _lastRefreshed = DateTime.now();

  bool _loadingAttendance = true;
  bool _loadingCalendar = false;
  bool _loadingSyllabus = false;

  String? _attendanceError;
  String? _calendarError;
  String? _syllabusError;

  Map<String, dynamic>? _attendanceSummary;
  Map<String, dynamic>? _calendarMini;
  int? _pendingSyllabusCount;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadProfile();
    await _refreshAll();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _displayName = prefs.getString('name') ??
          prefs.getString('teacherName') ??
          prefs.getString('username') ??
          'Coordinator';
      _schoolName = prefs.getString('schoolName') ?? appName;
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _fetchAttendanceSummary(),
      _fetchCalendarMini(),
      _fetchSyllabusPending(),
    ]);
  }

  String get _selectedDateString => _apiDateFormat.format(_selectedDate);

  Future<void> _fetchAttendanceSummary() async {
    if (!mounted) return;
    setState(() {
      _loadingAttendance = true;
      _attendanceError = null;
    });

    try {
      final response =
          await ApiService.rawGet('/attendance/summary/$_selectedDateString');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          _attendanceSummary = decoded is Map
              ? Map<String, dynamic>.from(decoded)
              : <String, dynamic>{};
          _lastRefreshed = DateTime.now();
        });
      } else {
        throw Exception(_extractError(response.body, 'Failed to load'));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _attendanceSummary = null;
        _attendanceError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loadingAttendance = false);
    }
  }

  Future<void> _fetchCalendarMini() async {
    if (!mounted) return;
    setState(() {
      _loadingCalendar = true;
      _calendarError = null;
    });

    try {
      final response =
          await ApiService.rawGet('/academic-calendars/summary-by-month');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        final data = decoded is Map ? decoded : <String, dynamic>{};
        final calendar = data['calendar'];
        final summary = data['summary'] is List ? data['summary'] as List : [];

        if (calendar is! Map) {
          if (!mounted) return;
          setState(() => _calendarMini = null);
          return;
        }

        final totals = <String, int>{
          'working_days': 0,
          'holidays': 0,
          'vacations': 0,
          'exams': 0,
          'ptm': 0,
          'activities': 0,
          'events': 0,
          'others': 0,
        };

        for (final item in summary) {
          if (item is! Map) continue;
          for (final key in totals.keys) {
            totals[key] = totals[key]! + _asInt(item[key]);
          }
        }

        if (!mounted) return;
        setState(() {
          _calendarMini = {
            ...Map<String, dynamic>.from(calendar),
            ...totals,
            'months': summary.length,
          };
        });
      } else {
        throw Exception(
            _extractError(response.body, 'Failed to load calendar'));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _calendarMini = null;
        _calendarError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loadingCalendar = false);
    }
  }

  Future<void> _fetchSyllabusPending() async {
    if (!mounted) return;
    setState(() {
      _loadingSyllabus = true;
      _syllabusError = null;
    });

    try {
      final response = await ApiService.rawGet('/syllabus-breakdowns/pending');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        final raw =
            decoded is Map ? (decoded['data'] ?? decoded['rows']) : decoded;
        final rows = raw is List ? raw : <dynamic>[];
        if (!mounted) return;
        setState(() => _pendingSyllabusCount = rows.length);
      } else {
        throw Exception(
          _extractError(response.body, 'Failed to load pending approvals'),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pendingSyllabusCount = null;
        _syllabusError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loadingSyllabus = false);
    }
  }

  List<Map<String, dynamic>> get _sections {
    final rows = _attendanceSummary?['summary'];
    if (rows is! List) return [];
    return rows
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  int get _totalStudents =>
      _sections.fold(0, (sum, item) => sum + _asInt(item['total']));

  int get _absentStudents =>
      _sections.fold(0, (sum, item) => sum + _asInt(item['absent']));

  int get _leaveStudents =>
      _sections.fold(0, (sum, item) => sum + _asInt(item['leave']));

  int get _presentStudents =>
      (_totalStudents - _absentStudents - _leaveStudents).clamp(0, 1 << 31);

  int _percentage(int value, int total) {
    if (total <= 0) return 0;
    return ((value / total) * 100).round();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  String _extractError(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final message =
            decoded['message'] ?? decoded['error'] ?? decoded['sqlMessage'];
        if (message != null && message.toString().trim().isNotEmpty) {
          return message.toString();
        }
      }
    } catch (_) {}
    return fallback;
  }

  Future<void> _handleLogout() async {
    await ApiService.clearLocalSession();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  void _shiftDay(int delta) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: delta)));
    _fetchAttendanceSummary();
  }

  void _goToday() {
    setState(() => _selectedDate = DateTime.now());
    _fetchAttendanceSummary();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    _fetchAttendanceSummary();
  }

  void _openRouteOrNotice(String title, String? routeName) {
    if (routeName != null) {
      Navigator.pushNamed(context, routeName);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('$title is available on web. Mobile page is not added yet.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = AppRoles.label(AppRoles.coordinator);
    return Scaffold(
      key: _scaffoldKey,
      appBar: TeacherAppBar(
        scaffoldKey: _scaffoldKey,
        parentContext: context,
        teacherName: _displayName,
        roleLabel: roleLabel,
        onLogout: _handleLogout,
      ),
      drawer: const TeacherDrawerMenu(activeRole: AppRoles.coordinator),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        color: const Color(0xFF2563EB),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
          children: [
            _buildHero(),
            const SizedBox(height: 14),
            _buildQuickActions(),
            const SizedBox(height: 14),
            _buildAttendanceState(),
          ],
        ),
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withOpacity(0.24),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.24)),
                ),
                child: Text(
                  _initials(_displayName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back, $_displayName',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_schoolName • Academic operations dashboard',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _heroBadge(_selectedDateString),
                        _heroBadge(
                            'Updated ${_timeFormat.format(_lastRefreshed)}'),
                        _heroBadge('academic_coordinator'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _heroButton(
                  Icons.chevron_left_rounded, 'Prev', () => _shiftDay(-1)),
              _heroButton(Icons.today_rounded, 'Today', _goToday),
              _heroButton(
                  Icons.chevron_right_rounded, 'Next', () => _shiftDay(1)),
              _heroButton(Icons.calendar_month_rounded,
                  _displayDateFormat.format(_selectedDate), _pickDate),
              _heroButton(Icons.refresh_rounded, 'Refresh', _refreshAll),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _heroButton(IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withOpacity(0.38)),
        backgroundColor: Colors.white.withOpacity(0.10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final first = parts.isNotEmpty ? parts.first[0] : 'C';
    final second = parts.length > 1 ? parts.elementAt(1)[0] : '';
    return '$first$second'.toUpperCase();
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Coordinator Quick Access',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 700;
            final count = isWide ? 3 : 1;
            return GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              crossAxisCount: count,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: isWide ? 1.42 : 1.65,
              children: [
                _quickCard(
                  icon: Icons.fact_check_rounded,
                  eyebrow: 'Attendance',
                  title: 'Class Wise Summary',
                  body:
                      'Open the dedicated class-section attendance summary with date controls.',
                  chips: const ['Present', 'Absent', 'Leaves'],
                  colors: const [Color(0xFFF0FDF4), Color(0xFFECFEFF)],
                  iconColor: const Color(0xFF16A34A),
                  actionLabel: 'Open',
                  onTap: () => _openRouteOrNotice(
                    'Class Wise Attendance',
                    '/coordinator/attendance-summary',
                  ),
                ),
                _quickCard(
                  icon: Icons.school_rounded,
                  eyebrow: 'Students',
                  title: 'Students View',
                  body:
                      'View student profiles with class, session, status and sibling filters.',
                  chips: const ['Read Only', 'Profiles'],
                  colors: const [Color(0xFFF0FDFA), Color(0xFFEFF6FF)],
                  iconColor: const Color(0xFF0F766E),
                  actionLabel: 'Open',
                  onTap: () => _openRouteOrNotice(
                    'Students View',
                    '/coordinator/students',
                  ),
                ),
                _quickCard(
                  icon: Icons.calendar_month_rounded,
                  eyebrow: 'Academic Calendar',
                  title: _loadingCalendar
                      ? 'Loading...'
                      : (_calendarMini?['title']?.toString() ??
                          'Academic Calendar'),
                  body: _calendarSubtitle(),
                  chips: _calendarChips(),
                  colors: const [Color(0xFFFFFFFF), Color(0xFFEEF2FF)],
                  iconColor: const Color(0xFF1D4ED8),
                  actionLabel: 'Open',
                  onTap: () => _openRouteOrNotice(
                    'Academic Calendar',
                    '/coordinator/academic-calendar',
                  ),
                  onRefresh: _fetchCalendarMini,
                  loadingRefresh: _loadingCalendar,
                ),
                _quickCard(
                  icon: Icons.table_chart_rounded,
                  eyebrow: 'Timetable',
                  title: 'Timetable Assignment',
                  body:
                      'Review class-wise and teacher-wise timetable assignments.',
                  chips: const ['Class Wise', 'Teacher Wise'],
                  colors: const [Color(0xFFFFFBEB), Color(0xFFF0F9FF)],
                  iconColor: const Color(0xFFD97706),
                  actionLabel: 'Open',
                  onTap: () => _openRouteOrNotice(
                    'Timetable Assignment',
                    '/coordinator/timetable',
                  ),
                ),
                _quickCard(
                  icon: Icons.supervisor_account_rounded,
                  eyebrow: 'Incharge',
                  title: 'Incharge Assignment',
                  body:
                      'Assign class-section incharges and manage teacher ownership.',
                  chips: const ['Class', 'Section', 'Teacher'],
                  colors: const [Color(0xFFEFF6FF), Color(0xFFF0FDFA)],
                  iconColor: const Color(0xFF2563EB),
                  actionLabel: 'Open',
                  onTap: () => _openRouteOrNotice(
                    'Incharge Assignment',
                    '/coordinator/incharge-assignment',
                  ),
                ),
                _quickCard(
                  icon: Icons.swap_horiz_rounded,
                  eyebrow: 'Substitution',
                  title: 'Substitution Assignment',
                  body:
                      'Select teacher, period and available substitute with workload visibility.',
                  chips: const ['Assign', 'Workload'],
                  colors: const [Color(0xFFF0FDFA), Color(0xFFFFFBEB)],
                  iconColor: const Color(0xFF0F766E),
                  actionLabel: 'Open',
                  onTap: () => _openRouteOrNotice(
                    'Substitution Assignment',
                    '/coordinator/substitution-assignment',
                  ),
                ),
                _quickCard(
                  icon: Icons.forum_rounded,
                  eyebrow: 'Communication',
                  title: 'Messages',
                  body:
                      'Open student and parent messages, fee reminders, and replies.',
                  chips: const ['Fee Reminders', 'Replies'],
                  colors: const [Color(0xFFEFF6FF), Color(0xFFF5F3FF)],
                  iconColor: const Color(0xFF4F46E5),
                  actionLabel: 'Open',
                  onTap: () => _openRouteOrNotice(
                    'Messages',
                    '/teacher/messages',
                  ),
                ),
                _quickCard(
                  icon: Icons.campaign_rounded,
                  eyebrow: 'Communication',
                  title: 'Circular Management',
                  body:
                      'Create circulars for teachers, students, all users or selected classes.',
                  chips: const ['Audience', 'Classes', 'Files'],
                  colors: const [Color(0xFFF5F3FF), Color(0xFFECFEFF)],
                  iconColor: const Color(0xFF4F46E5),
                  actionLabel: 'Open',
                  onTap: () => _openRouteOrNotice(
                    'Circular Management',
                    '/coordinator/circulars',
                  ),
                ),
                _quickCard(
                  icon: Icons.account_tree_rounded,
                  eyebrow: 'Syllabus Module',
                  title: 'Assign Syllabus Teacher',
                  body: 'Assign Class + Subject to teacher for syllabus work.',
                  chips: const [
                    'One teacher per Class+Subject',
                    'Replace allowed'
                  ],
                  colors: const [Color(0xFFFFF7ED), Color(0xFFFFFBEB)],
                  iconColor: const Color(0xFFB45309),
                  actionLabel: 'Open',
                  onTap: () =>
                      _openRouteOrNotice('Assign Syllabus Teacher', null),
                ),
                _quickCard(
                  icon: Icons.menu_book_rounded,
                  eyebrow: 'Academics',
                  title: 'Subjects',
                  body:
                      'Create, categorize, search and manage subject records.',
                  chips: const ['Scholastic', 'Co-Scholastic'],
                  colors: const [Color(0xFFFFFBEB), Color(0xFFEFF6FF)],
                  iconColor: const Color(0xFFB45309),
                  actionLabel: 'Open',
                  onTap: () => _openRouteOrNotice(
                    'Subjects',
                    '/coordinator/subjects',
                  ),
                ),
                _quickCard(
                  icon: Icons.fact_check_rounded,
                  eyebrow: 'Syllabus Workflow',
                  title: 'Syllabus Approvals',
                  body: _syllabusError == null
                      ? 'Review submissions and approve or return with remarks.'
                      : _syllabusError!,
                  chips: [
                    'Pending: ${_loadingSyllabus ? '...' : (_pendingSyllabusCount?.toString() ?? '-')}',
                    'PDF Preview',
                  ],
                  colors: const [Color(0xFFECFEFF), Color(0xFFF0FDFA)],
                  iconColor: const Color(0xFF047857),
                  actionLabel: 'Open',
                  onTap: () => _openRouteOrNotice(
                    'Syllabus Approvals',
                    '/coordinator/syllabus-approvals',
                  ),
                  onRefresh: _fetchSyllabusPending,
                  loadingRefresh: _loadingSyllabus,
                ),
                _quickCard(
                  icon: Icons.menu_book_rounded,
                  eyebrow: 'Digital Diary',
                  title: 'View Digital Diaries',
                  body:
                      'Monitor teacher diary notes by date, class, section, session and type.',
                  chips: const ['Teacher Wise', 'Acknowledgements'],
                  colors: const [Color(0xFFF0F9FF), Color(0xFFEEF2FF)],
                  iconColor: const Color(0xFF1D4ED8),
                  actionLabel: 'Open',
                  onTap: () => _openRouteOrNotice(
                    'View Digital Diaries',
                    '/coordinator/digital-diary',
                  ),
                ),
                _quickCard(
                  icon: Icons.person_search_rounded,
                  eyebrow: 'Admission Workflow',
                  title: 'Admission Syllabus Assignee',
                  body:
                      'Assign Applying Class + Subject to user for admission syllabus work.',
                  chips: const ['Admission Class Based', 'Status + Remarks'],
                  colors: const [Color(0xFFF5F3FF), Color(0xFFEEF2FF)],
                  iconColor: const Color(0xFF6D28D9),
                  actionLabel: 'Open',
                  onTap: () =>
                      _openRouteOrNotice('Admission Syllabus Assignee', null),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  String _calendarSubtitle() {
    if (_loadingCalendar) return 'Fetching latest published calendar...';
    if (_calendarMini != null) {
      final session = _calendarMini!['academic_session']?.toString() ?? '-';
      final status = _calendarMini!['status']?.toString() ?? '-';
      return 'Session: $session • $status';
    }
    if (_calendarError != null) return _calendarError!;
    return 'No calendar found yet.';
  }

  List<String> _calendarChips() {
    final item = _calendarMini;
    if (item == null)
      return const ['Working: -', 'Holidays: -', 'Vacations: -'];
    return [
      'Working: ${_asInt(item['working_days'])}',
      'Holidays: ${_asInt(item['holidays'])}',
      'Vacations: ${_asInt(item['vacations'])}',
    ];
  }

  Widget _quickCard({
    required IconData icon,
    required String eyebrow,
    required String title,
    required String body,
    required List<String> chips,
    required List<Color> colors,
    required Color iconColor,
    required String actionLabel,
    required VoidCallback onTap,
    VoidCallback? onRefresh,
    bool loadingRefresh = false,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: iconColor.withOpacity(0.16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, color: iconColor),
                  ),
                  const Spacer(),
                  if (onRefresh != null)
                    IconButton(
                      onPressed: loadingRefresh ? null : onRefresh,
                      icon: loadingRefresh
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      tooltip: 'Reload',
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                eyebrow.toUpperCase(),
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: chips.map(_chip).toList(),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: iconColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(actionLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildAttendanceState() {
    if (_loadingAttendance) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_attendanceError != null) {
      return _stateCard(
        icon: Icons.warning_rounded,
        title: 'Failed to load attendance for $_selectedDateString',
        message: _attendanceError!,
        actionLabel: 'Retry',
        onAction: _fetchAttendanceSummary,
      );
    }

    if (_attendanceSummary == null || _sections.isEmpty) {
      return _stateCard(
        icon: Icons.info_rounded,
        title: 'No summary available',
        message: 'No attendance summary is available for $_selectedDateString.',
        actionLabel: 'Refresh',
        onAction: _fetchAttendanceSummary,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAttendanceOverview(),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Class & Section Breakdown',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Detailed attendance progress for each class-section',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              flex: 0,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                runSpacing: 4,
                children: [
                  _chip('${_sections.length} sections'),
                  TextButton.icon(
                    onPressed: () => _openRouteOrNotice(
                      'Class Wise Attendance',
                      '/coordinator/attendance-summary',
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Full Report'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._sections.map(_breakdownCard),
      ],
    );
  }

  Widget _stateCard({
    required IconData icon,
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2563EB), size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(message, style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }

  Widget _buildAttendanceOverview() {
    final total = _totalStudents;
    final present = _presentStudents;
    final absent = _absentStudents;
    final leave = _leaveStudents;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 720;
        final metrics = Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _metricCard(
                    title: 'Total Students',
                    value: total,
                    subtitle: 'All students counted',
                    color: const Color(0xFF64748B),
                    icon: Icons.groups_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metricCard(
                    title: 'Present',
                    value: present,
                    subtitle: '${_percentage(present, total)}% of total',
                    color: const Color(0xFF16A34A),
                    icon: Icons.check_circle_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _metricCard(
                    title: 'Absent',
                    value: absent,
                    subtitle: '${_percentage(absent, total)}% of total',
                    color: const Color(0xFFDC2626),
                    icon: Icons.cancel_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metricCard(
                    title: 'Leaves',
                    value: leave,
                    subtitle: '${_percentage(leave, total)}% of total',
                    color: const Color(0xFFD97706),
                    icon: Icons.event_busy_rounded,
                  ),
                ),
              ],
            ),
          ],
        );

        final chart = _attendanceChart(total, present, absent, leave);

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: metrics),
              const SizedBox(width: 12),
              Expanded(child: chart),
            ],
          );
        }

        return Column(
          children: [
            metrics,
            const SizedBox(height: 12),
            chart,
          ],
        );
      },
    );
  }

  Widget _metricCard({
    required String title,
    required int value,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.16),
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
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$value',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _attendanceChart(int total, int present, int absent, int leave) {
    return Container(
      height: 274,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overall Attendance - $_selectedDateString',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: total <= 0
                ? const Center(child: Text('No attendance data'))
                : PieChart(
                    PieChartData(
                      centerSpaceRadius: 48,
                      sectionsSpace: 2,
                      sections: [
                        PieChartSectionData(
                          value: present.toDouble(),
                          color: const Color(0xFF22C55E),
                          title: '${_percentage(present, total)}%',
                          radius: 52,
                          titleStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                        PieChartSectionData(
                          value: absent.toDouble(),
                          color: const Color(0xFFEF4444),
                          title: '${_percentage(absent, total)}%',
                          radius: 52,
                          titleStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                        PieChartSectionData(
                          value: leave.toDouble(),
                          color: const Color(0xFFF59E0B),
                          title: '${_percentage(leave, total)}%',
                          radius: 52,
                          titleStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: const [
              _LegendDot(color: Color(0xFF22C55E), label: 'Present'),
              _LegendDot(color: Color(0xFFEF4444), label: 'Absent'),
              _LegendDot(color: Color(0xFFF59E0B), label: 'Leaves'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _breakdownCard(Map<String, dynamic> item) {
    final total = _asInt(item['total']);
    final absent = _asInt(item['absent']);
    final leave = _asInt(item['leave']);
    final present = (total - absent - leave).clamp(0, 1 << 31);
    final presentPct = _percentage(present, total);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Class ${item['class_name'] ?? '-'} - Section ${item['section_name'] ?? '-'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Total Students: $total',
                      style:
                          const TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _chip('$presentPct% Present'),
            ],
          ),
          const SizedBox(height: 12),
          _progressStat('Present', present, total, const Color(0xFF16A34A)),
          _progressStat('Absent', absent, total, const Color(0xFFDC2626)),
          _progressStat('Leaves', leave, total, const Color(0xFFD97706)),
        ],
      ),
    );
  }

  Widget _progressStat(String label, int value, int total, Color color) {
    final pct = _percentage(value, total);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                '$value ($pct%)',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: total <= 0 ? 0 : value / total,
              color: color,
              backgroundColor: color.withOpacity(0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
