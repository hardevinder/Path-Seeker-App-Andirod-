// lib/screens/teacher/teacher_dashboard.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'teacher_circulars_screen.dart';
import 'substitution_listing.dart';
import 'substituted_listing.dart';
import 'teacher_timetable_display.dart';
import 'teacher_leave_requests.dart';
import '../../constants/constants.dart';
import '../../widgets/teacher_app_bar.dart';
import '../../services/api_service.dart';
import 'teacher_digital_diary_screen.dart';
import 'teacher_my_leave_requests_screen.dart';


/// Teacher Dashboard Screen
/// Displays key performance indicators, quick actions, and recent activities for teachers.
///
/// ✅ Update in this version:
/// - Shows a highlighted banner on dashboard when there are pending leave requests
///   (no popup / no snackbar / nothing else)
class TeacherDashboard extends StatefulWidget {
  const TeacherDashboard({super.key});

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  // Global Keys
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Loading States
  bool _isLoading = true;
  bool _isRecentDiariesLoading = true;

  // User Profile Data
  late String _username;
  String? _teacherName;
  String? _email;
  String? _phone;
  String? _schoolName;
  String? _profilePhotoUrl;

  // KPI Metrics
  int _todaysClasses = 0;
  int _pendingLeave = 0;
  int _newCircularsCount = 0;

  // ✅ NEW: dashboard highlight flag (no alerts/popup)
  bool _showLeaveHighlight = false;

  // Data Collections
  List<dynamic> _periods = [];
  List<dynamic> _todayClasses = [];
  List<dynamic> _inchargeStudents = [];
  bool? _attendanceMarked;
  List<dynamic> _recentCirculars = [];
  List<dynamic> _substitutionsTook = [];
  List<dynamic> _substitutionsFreed = [];
  List<Map<String, dynamic>> _recentDiaries = [];

  // UI Toggles
  bool _showRemarks = true;
  bool _showCoScholastic = false;

  // Local Notifications
  List<Map<String, dynamic>> _notifications = [];

  // Chat Metrics
  int _chatUnread = 0;

  // Formatters
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
  final DateFormat _niceFormat = DateFormat.yMMMMEEEEd();

  // Timers and Controllers
  Timer? _refreshTimer;
  final PageController _kpiPageController =
      PageController(viewportFraction: 0.88);
  int _kpiPageIndex = 0;

  @override
  void initState() {
    super.initState();
    _kpiPageController.addListener(() {
      final pageIndex = (_kpiPageController.page ?? 0).round();
      if (pageIndex != _kpiPageIndex) {
        setState(() => _kpiPageIndex = pageIndex);
      }
    });
    _initializeData();
    _startPeriodicRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _kpiPageController.dispose();
    super.dispose();
  }

  /// Initializes user data and fetches all required data.
  Future<void> _initializeData() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    await _loadUserPreferences();
    await _loadLocalNotifications();
    await _fetchAllData();

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  /// Loads user preferences from SharedPreferences.
  Future<void> _loadUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _username = prefs.getString('username') ?? prefs.getString('userId') ?? '';
    _teacherName = prefs.getString('name') ?? prefs.getString('teacherName');
    _schoolName = prefs.getString('schoolName') ?? appName;
  }

  /// Loads local notifications from SharedPreferences.
  Future<void> _loadLocalNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('pits_notifications');
    if (stored != null) {
      try {
        final parsed = jsonDecode(stored) as List<dynamic>;
        _notifications =
            parsed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {
        _notifications = [];
      }
    }
  }

  /// Saves notifications to SharedPreferences.
  Future<void> _saveNotificationsLocally() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pits_notifications', jsonEncode(_notifications));
  }

  /// Adds a new notification and saves locally.
  Future<void> _addNotification(Map<String, dynamic> notification) async {
    if (!mounted) return;

    setState(() {
      _notifications.insert(0, notification);
    });
    await _saveNotificationsLocally();
  }

  /// Fetches all dashboard data in parallel.
  Future<void> _fetchAllData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final teacherId = await _getTeacherId();

    await Future.wait([
      _fetchPeriods(),
      _fetchTimetable(teacherId),
      _fetchInchargeAndAttendance(teacherId),
      _fetchPendingLeaves(),
      _fetchRecentCirculars(),
      _fetchSubstitutions(teacherId),
      _fetchRecentDiaries(),
    ].map((future) => future.catchError((_) {})));

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  /// Starts periodic data refresh every 3 minutes.
  void _startPeriodicRefresh() {
    _refreshTimer =
        Timer.periodic(const Duration(minutes: 3), (_) => _fetchAllData());
  }

  /// Retrieves the teacher ID from SharedPreferences.
  Future<String?> _getTeacherId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('teacherId') ??
        prefs.getString('userId') ??
        prefs.getString('username');
  }

  // API Fetch Methods

  /// Fetches school periods.
  Future<void> _fetchPeriods() async {
    try {
      final response = await ApiService.rawGet('/periods');
      if (response.statusCode == 200 && mounted) {
        final json = jsonDecode(response.body);
        final periods = (json is List) ? json : (json['periods'] ?? <dynamic>[]);
        setState(() => _periods = periods.cast<dynamic>());
      }
    } catch (_) {
      // Silently handle errors
    }
  }

  /// Fetches today's timetable.
  Future<void> _fetchTimetable(String? teacherId) async {
    try {
      final endpoint = teacherId != null
          ? '/period-class-teacher-subject/timetable-teacher?teacherId=$teacherId'
          : '/period-class-teacher-subject/timetable-teacher';
      final response = await ApiService.rawGet(endpoint);
      if (response.statusCode == 200 && mounted) {
        final json = jsonDecode(response.body);
        List<dynamic> timetable = [];
        if (json is List) {
          timetable = json;
        } else if (json is Map && json['timetable'] is List) {
          timetable = json['timetable'] as List<dynamic>;
        }
        final todayName = DateFormat('EEEE').format(DateTime.now());
        final todayClasses = timetable.where((record) {
          final day =
              (record is Map && record['day'] != null) ? record['day'].toString() : '';
          return _normalizeDayName(day).toLowerCase() == todayName.toLowerCase();
        }).toList();
        setState(() {
          _todayClasses = todayClasses;
          _todaysClasses = todayClasses.length;
        });
      }
    } catch (_) {
      // Silently handle errors
    }
  }

  /// Fetches incharge students and today's attendance status.
  Future<void> _fetchInchargeAndAttendance(String? teacherId) async {
    try {
      final inchargeResponse = await ApiService.rawGet('/incharges/students');
      if (inchargeResponse.statusCode == 200 && mounted) {
        final json = jsonDecode(inchargeResponse.body);
        final students = json['students'] ?? json;
        setState(() => _inchargeStudents = (students as List).cast<dynamic>());

        if (_inchargeStudents.isNotEmpty) {
          final firstStudent = _inchargeStudents.first;
          final classId = _extractClassId(firstStudent);
          if (classId != null) {
            final todayString = _dateFormat.format(DateTime.now());
            final attendanceResponse =
                await ApiService.rawGet('/attendance/date/$todayString/$classId');
            if (attendanceResponse.statusCode == 200 && mounted) {
              final attendanceJson = jsonDecode(attendanceResponse.body);
              final rows = attendanceJson is List
                  ? attendanceJson
                  : (attendanceJson['rows'] ?? <dynamic>[]);
              setState(() => _attendanceMarked = (rows as List).isNotEmpty);
            } else {
              setState(() => _attendanceMarked = false);
            }
          } else {
            setState(() => _attendanceMarked = false);
          }
        } else {
          setState(() => _attendanceMarked = false);
        }
      } else {
        setState(() => _attendanceMarked = false);
      }
    } catch (_) {
      setState(() => _attendanceMarked = false);
    }
  }

  /// ✅ Fetches pending leave requests + toggles dashboard highlight
  Future<void> _fetchPendingLeaves() async {
    try {
      final response = await ApiService.rawGet('/leave');
      if (response.statusCode == 200 && mounted) {
        final json = jsonDecode(response.body);
        final data = json is List ? json : (json['data'] ?? <dynamic>[]);
        final pendingCount = (data as List).where((leave) {
          if (leave is! Map) return false;
          final status = (leave['status'] ?? '').toString().toLowerCase();
          return status == 'pending';
        }).length;

        setState(() {
          _pendingLeave = pendingCount;
          _showLeaveHighlight = pendingCount > 0;
        });
      } else if (mounted) {
        // If API fails, don't show highlight
        setState(() {
          _pendingLeave = 0;
          _showLeaveHighlight = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _pendingLeave = 0;
          _showLeaveHighlight = false;
        });
      }
    }
  }

  /// Fetches recent circulars and counts new ones.
  Future<void> _fetchRecentCirculars() async {
    try {
      final response = await ApiService.rawGet('/circulars');
      if (response.statusCode == 200 && mounted) {
        final json = jsonDecode(response.body);
        final circulars = json['circulars'] ?? json;
        final list = (circulars as List).cast<Map<String, dynamic>>();
        list.sort((a, b) => _compareDates(b['createdAt'], a['createdAt']));
        final now = DateTime.now();
        final newCount = list.where((circular) {
          final created =
              DateTime.tryParse(circular['createdAt']?.toString() ?? '') ?? now;
          return now.difference(created).inHours < 48;
        }).length;
        setState(() {
          _recentCirculars = list.take(5).toList();
          _newCircularsCount = newCount;
        });
      }
    } catch (_) {
      // Silently handle errors
    }
  }

  /// Fetches today's substitutions.
  Future<void> _fetchSubstitutions(String? teacherId) async {
    try {
      final todayString = _dateFormat.format(DateTime.now());
      final paramPrefix = teacherId != null ? '&teacherId=$teacherId' : '';
      final results = await Future.wait([
        ApiService.rawGet(
            '/substitutions/by-date/original?date=$todayString$paramPrefix'),
        ApiService.rawGet(
            '/substitutions/by-date/substituted?date=$todayString$paramPrefix'),
      ]);
      final tookResponse = results[0];
      final freedResponse = results[1];

      if (tookResponse.statusCode == 200 && mounted) {
        final json = jsonDecode(tookResponse.body);
        setState(() => _substitutionsTook =
            (json is List) ? json : (json['rows'] ?? <dynamic>[]));
      }
      if (freedResponse.statusCode == 200 && mounted) {
        final json = jsonDecode(freedResponse.body);
        setState(() => _substitutionsFreed =
            (json is List) ? json : (json['rows'] ?? <dynamic>[]));
      }
    } catch (_) {
      // Silently handle errors
    }
  }

  /// Fetches recent digital diaries.
  Future<void> _fetchRecentDiaries() async {
    if (!mounted) return;
    setState(() => _isRecentDiariesLoading = true);

    try {
      final response = await ApiService.rawGet('/diaries?page=1&pageSize=20');
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final rawData = json is Map && json['data'] is List
            ? json['data'] as List
            : (json is List ? json : json['diaries'] ?? <dynamic>[]);
        final list = (rawData as List).cast<dynamic>();
        final grouped = _groupDiaries(list);
        if (mounted) {
          setState(() => _recentDiaries = grouped.take(10).toList());
        }
      } else {
        if (mounted) setState(() => _recentDiaries = []);
      }
    } catch (_) {
      if (mounted) setState(() => _recentDiaries = []);
    } finally {
      if (mounted) setState(() => _isRecentDiariesLoading = false);
    }
  }

  // Utility Methods

  /// Normalizes day names for comparison.
  String _normalizeDayName(String value) {
    if (value.isEmpty) return '';
    final normalized = value.trim().toLowerCase();
    const dayMap = {
      'sun': 'Sunday',
      'sunday': 'Sunday',
      'mon': 'Monday',
      'monday': 'Monday',
      'tue': 'Tuesday',
      'tues': 'Tuesday',
      'tuesday': 'Tuesday',
      'wed': 'Wednesday',
      'wednesday': 'Wednesday',
      'thu': 'Thursday',
      'thur': 'Thursday',
      'thurs': 'Thursday',
      'thursday': 'Thursday',
      'fri': 'Friday',
      'friday': 'Friday',
      'sat': 'Saturday',
      'saturday': 'Saturday',
    };
    return dayMap[normalized] ??
        (normalized.isNotEmpty
            ? normalized[0].toUpperCase() + normalized.substring(1)
            : normalized);
  }

  /// Extracts class ID from student record.
  String? _extractClassId(dynamic student) {
    if (student is! Map) return null;
    return student['class_id']?.toString() ?? student['classId']?.toString();
  }

  /// Compares two dates for sorting (descending).
  int _compareDates(dynamic dateA, dynamic dateB) {
    final timeA = DateTime.tryParse(dateA?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final timeB = DateTime.tryParse(dateB?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return timeB.compareTo(timeA);
  }

  /// Groups diary entries by key.
  List<Map<String, dynamic>> _groupDiaries(List<dynamic> items) {
    final Map<String, Map<String, dynamic>> grouped = {};
    for (final item in items) {
      if (item is! Map) continue;
      if (item['targets'] is List && (item['targets'] as List).isNotEmpty) {
        grouped['targets-${item['id']}'] = Map<String, dynamic>.from(item);
        continue;
      }
      final date = (item['date'] ?? '').toString().split('T').first;
      final key = [
        date,
        item['type'] ?? '',
        (item['title'] ?? '').toString().trim(),
        (item['content'] ?? '').toString().trim(),
        item['subjectId']?.toString() ?? '',
      ].join('|');

      final target = {
        'classId':
            item['classId'] ?? (item['class'] is Map ? item['class']['id'] : null),
        'sectionId': item['sectionId'] ??
            (item['section'] is Map ? item['section']['id'] : null),
        'class': item['class'] ?? (item['Class'] ?? null),
        'section': item['section'] ?? (item['Section'] ?? null),
      };

      final existing = grouped[key];
      if (existing == null) {
        final copy = Map<String, dynamic>.from(item);
        copy['targets'] = [target];
        copy['_sourceIds'] = [item['id']];
        copy['_counts'] = {
          'views': (item['views'] is List)
              ? (item['views'] as List).length
              : (item['_counts']?['views'] ?? 0),
          'acks': (item['acknowledgements'] is List)
              ? (item['acknowledgements'] as List).length
              : (item['_counts']?['acks'] ?? 0),
        };
        grouped[key] = copy;
      } else {
        final exists = (existing['targets'] as List).any((t) =>
            (t['classId']?.toString() ?? '') ==
                (target['classId']?.toString() ?? '') &&
            (t['sectionId']?.toString() ?? '') ==
                (target['sectionId']?.toString() ?? ''));
        if (!exists) {
          (existing['targets'] as List).add(target);
        }
        (existing['_sourceIds'] as List).add(item['id']);
        existing['_counts'] ??= {'views': 0, 'acks': 0};
        final addViews = (item['views'] is List) ? (item['views'] as List).length : 0;
        final addAcks = (item['acknowledgements'] is List)
            ? (item['acknowledgements'] as List).length
            : 0;
        existing['_counts']['views'] =
            (existing['_counts']['views'] ?? 0) + addViews;
        existing['_counts']['acks'] =
            (existing['_counts']['acks'] ?? 0) + addAcks;
      }
    }

    final output = grouped.values.map((map) {
      map['seenCount'] = (map['_counts']?['views']) ?? map['seenCount'] ?? 0;
      map['ackCount'] = (map['_counts']?['acks']) ?? map['ackCount'] ?? 0;
      return map;
    }).toList();

    output.sort((a, b) =>
        _compareDates(a['createdAt'] ?? a['date'], b['createdAt'] ?? b['date']));

    return output.cast<Map<String, dynamic>>();
  }

  /// Formats relative time for display.
  String _formatRelativeTime(String? dateString) {
    if (dateString == null) return '';
    try {
      final dateTime = DateTime.parse(dateString);
      final difference = DateTime.now().difference(dateTime);
      if (difference.inHours < 24) {
        if (difference.inHours < 1) return '${difference.inMinutes}m ago';
        return '${difference.inHours}h ago';
      }
      return DateFormat('dd MMM, HH:mm').format(dateTime);
    } catch (_) {
      return '';
    }
  }

  /// Removes a notification by ID.
  void _removeNotification(String id) {
    if (!mounted) return;
    setState(() {
      _notifications.removeWhere((notification) => notification['id'] == id);
    });
    _saveNotificationsLocally();
  }

  /// Clears all notifications.
  void _clearAllNotifications() {
    if (!mounted) return;
    setState(() => _notifications.clear());
    _saveNotificationsLocally();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All notifications cleared')),
      );
    }
  }

  /// Handles user logout.
  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('authToken');
    await prefs.remove('activeRole');
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: TeacherAppBar(
        scaffoldKey: _scaffoldKey,
        parentContext: context,
        teacherName: _teacherName,
        onLogout: _handleLogout,
      ),
      drawer: _buildDrawer(),
      endDrawer: _buildNotificationsDrawer(),
      floatingActionButton: _buildChatFab(),
      body: RefreshIndicator(
        onRefresh: _fetchAllData,
        color: const Color(0xFF6C63FF),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          children: [
            _buildHeroSection(),

            // ✅ NEW: Highlight banner (ONLY UI, nothing else)
            if (_showLeaveHighlight) ...[
              const SizedBox(height: 10),
              _buildLeaveHighlightBanner(),
            ],

            const SizedBox(height: 14),
            _buildKpiSlider(),
            const SizedBox(height: 12),
            _buildQuickActionsCard(),
            const SizedBox(height: 12),
            _buildTwoColumnPanels(),
            const SizedBox(height: 12),
            _buildRecentCircularsCard(),
            const SizedBox(height: 12),
            if (_showCoScholastic) _buildCoScholasticCard(),
            if (_showRemarks) _buildRemarksCard(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  // ✅ NEW: highlighted banner widget
  Widget _buildLeaveHighlightBanner() {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/teacher/leave-requests'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.22),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.notifications_active,
                  color: Colors.orange.shade800, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$_pendingLeave pending leave request${_pendingLeave == 1 ? '' : 's'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              'View',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, color: Colors.orange.shade900),
          ],
        ),
      ),
    );
  }

  // Drawer Widgets

  /// Builds the main navigation drawer.
  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            _buildDrawerHeader('Menu'),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildDrawerListTile(
                      Icons.dashboard_rounded, 'Dashboard', _navigateToDashboard),
                  _buildDrawerListTile(Icons.calendar_today, 'Timetable',
                      () => _navigateTo('/teacher-timetable-display')),
                  _buildDrawerListTile(Icons.campaign, 'Circulars',
                      () => _navigateTo('/view-circulars')),
                  const Divider(),
                  _buildDrawerListTile(Icons.logout, 'Logout', _handleLogout),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the notifications drawer.
  Widget _buildNotificationsDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            _buildDrawerHeader('Notifications',
                trailing: IconButton(
                  icon: const Icon(Icons.clear_all),
                  onPressed: _clearAllNotifications,
                )),
            Expanded(
              child: _notifications.isEmpty
                  ? const Center(child: Text('No notifications yet.'))
                  : ListView.builder(
                      itemCount: _notifications.length,
                      itemBuilder: (context, index) {
                        final notification = _notifications[index];
                        return _buildNotificationListTile(notification);
                      },
                    ),
            ),
            _buildDrawerListTile(Icons.logout, 'Logout', _handleLogout),
          ],
        ),
      ),
    );
  }

  /// Builds a drawer header with title and optional trailing widget.
  Widget _buildDrawerHeader(String title, {Widget? trailing}) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      trailing: trailing ??
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
    );
  }

  /// Builds a list tile for the drawer.
  Widget _buildDrawerListTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
    );
  }

  /// Builds a notification list tile.
  Widget _buildNotificationListTile(Map<String, dynamic> notification) {
    return ListTile(
      leading: Text(
        notification['tag'] == 'chat' ? '💬' : '🔔',
        style: const TextStyle(fontSize: 20),
      ),
      title: Text(notification['title'] ?? ''),
      subtitle: Text(notification['message'] ?? ''),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _removeNotification(notification['id']?.toString() ?? ''),
      ),
    );
  }

  // Floating Action Button

  /// Builds the chat FAB with unread badge.
  Widget _buildChatFab() {
    return FloatingActionButton(
      onPressed: () => _navigateTo('/chat'),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.chat_bubble_outline),
          if (_chatUnread > 0) _buildUnreadBadge(_chatUnread),
        ],
      ),
    );
  }

  /// Builds an unread count badge.
  Widget _buildUnreadBadge(int count) {
    return Positioned(
      right: 0,
      top: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          count > 99 ? '99+' : count.toString(),
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
      ),
    );
  }

  // Navigation Helpers

  /// Navigates to dashboard.
  void _navigateToDashboard() {
    Navigator.pushReplacementNamed(context, '/teacher');
  }

  /// Navigates to a named route.
  void _navigateTo(String route) {
    Navigator.pushNamed(context, route);
  }

  // UI Sections

  /// Builds the hero section with greeting and profile.
  Widget _buildHeroSection() {
    final displayName = _teacherName ?? _username;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF6C63FF), Color(0xFF9B8CFF)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _buildProfileAvatar(displayName),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good ${_getGreeting()}, ${displayName.isNotEmpty ? displayName.split(' ').first : 'Teacher'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _schoolName ?? appName,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  _niceFormat.format(DateTime.now()),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () =>
                setState(() => _showCoScholastic = !_showCoScholastic),
            icon: Icon(
              _showCoScholastic ? Icons.toggle_on : Icons.toggle_off,
              color: Colors.white,
              size: 36,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the profile avatar.
  Widget _buildProfileAvatar(String displayName) {
    return CircleAvatar(
      radius: 34,
      backgroundColor: Colors.white,
      backgroundImage:
          _profilePhotoUrl != null ? NetworkImage(_profilePhotoUrl!) : null,
      child: _profilePhotoUrl == null
          ? Text(
              displayName.isNotEmpty ? displayName[0].toUpperCase() : 'T',
              style: const TextStyle(
                color: Color(0xFF6C63FF),
                fontWeight: FontWeight.bold,
                fontSize: 28,
              ),
            )
          : null,
    );
  }

  /// Gets the appropriate greeting based on time.
  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }

  /// Builds the KPI slider with pagination.
  Widget _buildKpiSlider() {
    final kpis = [
      {
        'icon': Icons.table_chart,
        'label': "Today's Classes",
        'value': _todaysClasses.toString(),
        'tone': null
      },
      {
        'icon': Icons.inbox,
        'label': 'Pending Leave',
        'value': _pendingLeave.toString(),
        'tone': Colors.orange
      },
      {
        'icon': Icons.campaign,
        'label': 'New Circulars',
        'value': _newCircularsCount.toString(),
        'tone': Colors.blueAccent
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 110,
          child: PageView.builder(
            controller: _kpiPageController,
            itemCount: kpis.length,
            padEnds: false,
            itemBuilder: (context, index) {
              final kpi = kpis[index];
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: _buildKpiCard(
                  icon: kpi['icon'] as IconData,
                  label: kpi['label'] as String,
                  value: kpi['value'] as String,
                  tone: kpi['tone'] as Color?,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(kpis.length, (index) {
            final isActive = index == _kpiPageIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: isActive ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF6C63FF)
                    : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(8),
              ),
            );
          }),
        ),
      ],
    );
  }

  /// Builds an individual KPI card.
  Widget _buildKpiCard({
    required IconData icon,
    required String label,
    required String value,
    Color? tone,
  }) {
    final backgroundColor =
        tone != null ? tone.withOpacity(0.08) : Colors.grey.withOpacity(0.06);
    final iconColor = tone ?? const Color(0xFF6C63FF);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds the quick actions grid.
  Widget _buildQuickActionsCard() {
    final actions = [
      {
        'label': 'Mark Attendance',
        'icon': Icons.check_box_outlined,
        'route': '/teacher/attendance'
      },
      {
        'label': 'Timetable',
        'icon': Icons.table_chart,
        'route': '/teacher-timetable-display'
      },
      {
        'label': 'Substitutions',
        'icon': Icons.swap_horiz,
        'route': '/teacher/substitutions'
      },
      {
        'label': 'Substituted (me)',
        'icon': Icons.person_off,
        'route': '/teacher/substituted'
      },
      {'label': 'Circulars', 'icon': Icons.campaign, 'route': '/view-circulars'},
      {
        'label': 'Manage Leave Requests',
        'icon': Icons.beach_access,
        'route': '/teacher/leave-requests'
      },
      {
          'label': 'My Leave', // ✅ NEW TAB
          'icon': Icons.event_note,
          'route': '/teacher/my-leaves'
        },
      {
        'label': 'Digital Diary',
        'icon': Icons.book,
        'route': '/teacher/digital-diary'
      },
      {
        'label': 'My Attendance',
        'icon': Icons.calendar_today,
        'route': '/my-attendance-calendar'
      },
    ];

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Quick Actions',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: () {}, // Placeholder for expansion
                child:
                    const Text('Tap to open', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount =
                  (constraints.maxWidth / 120).floor().clamp(2, 4);
              return GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: actions.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.1, // Slightly increased to prevent overflow
                ),
                itemBuilder: (context, index) {
                  final action = actions[index];
                  return _buildActionTile(action);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  /// Builds an individual action tile.
  Widget _buildActionTile(Map<String, dynamic> action) {
    return GestureDetector(
      onTap: () => _handleActionTap(action['route'] as String),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFF8FAFF), Color(0xFFFFFFFF)]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withOpacity(0.03)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(action['icon'] as IconData,
                  color: const Color(0xFF6C63FF)),
            ),
            const Spacer(),
            Expanded(
              child: Text(
                action['label'] as String,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Handles tap on quick action.
  void _handleActionTap(String route) {
    switch (route) {
      case '/view-circulars':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TeacherCircularsScreen()),
        );
        break;
      case '/teacher-timetable-display':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TeacherTimetableDisplayScreen()),
        );
        break;
      case '/teacher/leave-requests':
        Navigator.pushNamed(context, '/teacher/leave-requests');
        break;
      case '/teacher/digital-diary':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TeacherDigitalDiaryScreen()),
        );
        break;
      case '/teacher/my-leaves': // ✅ ADD THIS
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TeacherMyLeaveRequestsScreen()),
        );
        break;
      default:
        Navigator.pushNamed(context, route);
    }
  }

  /// Builds the two-column layout for panels.
  Widget _buildTwoColumnPanels() {
    final isWideScreen = MediaQuery.of(context).size.width > 720;
    if (isWideScreen) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildTodayTimetableCard()),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                _buildAttendanceCard(),
                const SizedBox(height: 12),
                _buildSubstitutionCard(),
                const SizedBox(height: 12),
                _buildSubstitutedCard(),
                const SizedBox(height: 12),
                _buildRecentDiariesCard(),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        _buildTodayTimetableCard(),
        const SizedBox(height: 12),
        _buildAttendanceCard(),
        const SizedBox(height: 12),
        _buildSubstitutionCard(),
        const SizedBox(height: 12),
        _buildSubstitutedCard(),
        const SizedBox(height: 12),
        _buildRecentDiariesCard(),
      ],
    );
  }

  /// Builds the today's timetable card.
  Widget _buildTodayTimetableCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            title: const Text("Today's Timetable",
                style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: SizedBox(
              width: 96,
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const TeacherTimetableDisplayScreen()),
                ),
                child: const Text('See All'),
              ),
            ),
          ),
          _buildTimetableContent(),
        ],
      ),
    );
  }

  /// Builds the content for timetable card.
  Widget _buildTimetableContent() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_todayClasses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No classes scheduled today.',
            style: TextStyle(color: Colors.black54)),
      );
    }
    return Column(
      children:
          _todayClasses.map((record) => _buildTimetableListTile(record)).toList(),
    );
  }

  /// Builds a list tile for a timetable entry.
  Widget _buildTimetableListTile(dynamic record) {
    final data = record is Map ? record : <String, dynamic>{};
    final period =
        (data['Period']?['name'] ?? data['period_name'] ?? data['period'] ?? '-')
            .toString();
    final className =
        (data['Class']?['class_name'] ?? data['Class'] ?? data['class'] ?? '-')
            .toString();
    final subject =
        (data['Subject']?['name'] ?? data['Subject'] ?? data['subject'] ?? '-')
            .toString();
    final room = (data['room'] ?? data['room_no'] ?? '-').toString();
    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFF3F4FF),
        child: Icon(Icons.schedule, color: Color(0xFF6C63FF)),
      ),
      title: Text(subject),
      subtitle: Text('$className • $period'),
      trailing: SizedBox(
        width: 84,
        child: Text(room, textAlign: TextAlign.right),
      ),
    );
  }

  /// Builds the attendance card.
  Widget _buildAttendanceCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Attendance (Today)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              SizedBox(
                width: 110,
                child: ElevatedButton(
                  onPressed: () => _navigateTo('/teacher/attendance'),
                  child: Text(_attendanceMarked == true ? 'Update' : 'Mark Now'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildAttendanceStatus(),
        ],
      ),
    );
  }

  /// Builds the attendance status row.
  Widget _buildAttendanceStatus() {
    if (_attendanceMarked == null) {
      return const Text('Checking attendance status…',
          style: TextStyle(color: Colors.black54));
    }
    if (_attendanceMarked == true) {
      return const Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green),
          SizedBox(width: 8),
          Text('Attendance marked for today.'),
        ],
      );
    }
    if (_inchargeStudents.isNotEmpty) {
      return const Row(
        children: [
          Icon(Icons.warning, color: Colors.orange),
          SizedBox(width: 8),
          Text('Not marked for today.'),
        ],
      );
    }
    return const Text('You are not an incharge for any class.',
        style: TextStyle(color: Colors.black54));
  }

  /// Builds the substitutions card.
  Widget _buildSubstitutionCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('My Substitutions (Today)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              SizedBox(
                width: 96,
                child: TextButton(
                  onPressed: () => _navigateTo('/teacher/substitutions'),
                  child: const Text('View All'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Chip(label: Text('Covering: ${_substitutionsTook.length}')),
              Chip(label: Text('Freed: ${_substitutionsFreed.length}')),
            ],
          ),
          const SizedBox(height: 8),
          if (_substitutionsTook.isNotEmpty || _substitutionsFreed.isNotEmpty)
            Column(
              children: [
                ..._substitutionsTook
                    .take(3)
                    .map((s) => _buildSubstitutionText(s,
                        isCovering: true, isSubstituted: false)),
                if (_substitutionsTook.isNotEmpty && _substitutionsFreed.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Divider(),
                  ),
                ..._substitutionsFreed
                    .take(3)
                    .map((s) => _buildSubstitutionText(s,
                        isCovering: false, isSubstituted: false)),
              ],
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('No substitutions today.',
                  style: TextStyle(color: Colors.black54)),
            ),
        ],
      ),
    );
  }

  /// Builds the substituted card.
  Widget _buildSubstitutedCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text("I've been Substituted (Today)",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              SizedBox(
                width: 120,
                child: TextButton(
                  onPressed: () => _navigateTo('/teacher/substituted'),
                  child: const Text('View All'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Chip(label: Text('Substituted: ${_substitutionsFreed.length}')),
            ],
          ),
          const SizedBox(height: 8),
          if (_substitutionsFreed.isNotEmpty)
            Column(
              children: _substitutionsFreed
                  .take(3)
                  .map((s) => _buildSubstitutionText(s,
                      isCovering: false, isSubstituted: true))
                  .toList(),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('No one has substituted you today.',
                  style: TextStyle(color: Colors.black54)),
            ),
        ],
      ),
    );
  }

  /// Builds text for a substitution entry.
  Widget _buildSubstitutionText(dynamic sub,
      {required bool isCovering, required bool isSubstituted}) {
    final data = sub is Map ? sub : <String, dynamic>{};
    final className =
        (data['Class']?['class_name'] ?? data['class'] ?? data['className'] ?? '-')
            .toString();
    final subject =
        (data['Subject']?['name'] ?? data['subject'] ?? '-').toString();
    final prefix = isSubstituted ? 'Substituted' : (isCovering ? 'Covering' : 'Freed');
    final coveredBy = isSubstituted
        ? ((data['Teacher'] is Map
                    ? data['Teacher']['name'] ?? ''
                    : (data['coveredBy'] ?? data['covered_by'] ?? ''))
                .toString())
        : '';
    final text = '$prefix $className — $subject${coveredBy.isNotEmpty ? ' by $coveredBy' : ''}';
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(text),
    );
  }

  /// Builds the recent diaries card.
  Widget _buildRecentDiariesCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            title: const Text('Recent Digital Diaries',
                style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: const SizedBox(width: 116), // Placeholder
          ),
          _buildDiariesContent(),
        ],
      ),
    );
  }

  /// Builds the content for diaries card.
  Widget _buildDiariesContent() {
    if (_isRecentDiariesLoading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_recentDiaries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child:
            Text('No diary notes yet.', style: TextStyle(color: Colors.black54)),
      );
    }
    return SizedBox(
      height: 220,
      child: ListView.builder(
        itemCount: _recentDiaries.length,
        itemBuilder: (context, index) {
          final diary = _recentDiaries[index];
          final title = diary['title'] ?? diary['subjectName'] ?? '';
          final content = (diary['content'] ?? '').toString();
          final dateString =
              diary['date']?.toString() ?? diary['createdAt']?.toString() ?? '';
          return ListTile(
            onTap: () {}, // Placeholder
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(content, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: SizedBox(
              width: 96,
              child: Text(_formatRelativeTime(dateString), textAlign: TextAlign.right),
            ),
          );
        },
      ),
    );
  }

  /// Builds the recent circulars card.
  Widget _buildRecentCircularsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            title: const Text('Recent Circulars',
                style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: SizedBox(
              width: 96,
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TeacherCircularsScreen()),
                ),
                child: const Text('See All'),
              ),
            ),
          ),
          _buildCircularsContent(),
        ],
      ),
    );
  }

  /// Builds the content for circulars card.
  Widget _buildCircularsContent() {
    if (_recentCirculars.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child:
            Text('No circulars yet.', style: TextStyle(color: Colors.black54)),
      );
    }
    return Column(
      children: _recentCirculars.map((circular) => _buildCircularListTile(circular)).toList(),
    );
  }

  /// Builds a list tile for a circular.
  Widget _buildCircularListTile(dynamic circular) {
    final data = circular is Map ? circular : <String, dynamic>{};
    final title = data['title'] ?? '';
    final created = (data['createdAt'] ?? data['date'] ?? '').toString();
    final fileUrl = (data['fileUrl'] ?? data['url'] ?? '').toString();
    return ListTile(
      onTap: fileUrl.isNotEmpty ? () {} : null, // Placeholder
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFF3F4FF),
        child: Icon(Icons.note, color: Color(0xFF6C63FF)),
      ),
      title: Text(title),
      subtitle: Text(created),
      trailing: const SizedBox(width: 40, child: Icon(Icons.open_in_new)),
    );
  }

  /// Builds the co-scholastic card.
  Widget _buildCoScholasticCard() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            title: const Text('🧩 Co-Scholastic Entry',
                style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: SizedBox(
              width: 40,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _showCoScholastic = false),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Co-Scholastic entry area — plug your widget here',
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the remarks card.
  Widget _buildRemarksCard() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            title: const Text('📝 Student Remarks Entry',
                style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: SizedBox(
              width: 40,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _showRemarks = false),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Student Remarks entry area — plug your widget here',
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}