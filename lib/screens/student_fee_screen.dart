import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:hypersdkflutter/hypersdkflutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/constants.dart';

/* =========================================================
  JWT + Helpers
========================================================= */

Map<String, dynamic>? parseJwt(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;

    String payload = parts[1];
    while (payload.length % 4 != 0) {
      payload += '=';
    }
    payload = payload.replaceAll('-', '+').replaceAll('_', '/');

    final jsonString = utf8.decode(base64Url.decode(payload));
    return json.decode(jsonString);
  } catch (e) {
    debugPrint('parseJwt error: $e');
    return null;
  }
}

String normalizeRole(String r) => r.toLowerCase().trim();
String normalizeAdmissionForPath(String s) => s.replaceAll('/', '-').trim();
String normalizeAdmissionRaw(String s) => s.trim();

/* =========================================================
  Screen
========================================================= */

class StudentFeeScreen extends StatefulWidget {
  const StudentFeeScreen({super.key});

  @override
  State<StudentFeeScreen> createState() => _StudentFeeScreenState();
}

class _StudentFeeScreenState extends State<StudentFeeScreen>
    with SingleTickerProviderStateMixin {
  bool loading = true;
  String? error;

  Map<String, dynamic>? studentDetails;
  List<dynamic> transactionHistory = [];
  Map<int, Map<String, dynamic>> vanByHead = {};
  List<bool> _expandedFees = [];
  bool _expandedPrevBalance = true;

  late TabController _tabController;
  Timer? _pollTimer;

  final ScrollController _chipScrollController = ScrollController();
  Timer? _chipTimer;
  final double _chipScrollStep = 160.0;
  final Duration _chipInterval = const Duration(seconds: 3);
  final Duration _chipAnim = const Duration(milliseconds: 600);

  PageController? _kpiPageController;
  Timer? _kpiPageTimer;
  int _kpiPage = 0;
  final Duration _kpiPageInterval = const Duration(seconds: 4);
  final Duration _kpiPageAnim = const Duration(milliseconds: 500);

  Map<String, dynamic>? family;
  String activeAdmission = '';
  String loggedInAdmission = '';

  List<Map<String, dynamic>> studentsList = [];
  int? _currentStudentId;
  bool siblingsLoading = false;
  List<String> _roles = [];
  bool canSeeStudentSwitcher = false;

  final HyperSDK _hyperSDK = HyperSDK();
  bool _hyperInitiated = false;
  bool _hyperOpening = false;

  static const String _hyperEnv = 'sandbox';
  static const String _hyperClientId = 'hdfcmaster';

  final Map<String, bool> _slipDownloading = {};

  static const Color _indigo = Color(0xFF4F46E5);
  static const Color _cyan = Color(0xFF06B6D4);
  static const Color _emerald = Color(0xFF10B981);
  static const Color _slate = Color(0xFF0F172A);
  static const Color _softBg = Color(0xFFF6F9FF);

  int? _activeSessionId;
  int? _prevBalanceHeadId;
  double _prevBalanceDue = 0.0;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 3, vsync: this);
    _kpiPageController = PageController(viewportFraction: 0.78);

    _loadFamilyAndActive();

    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _loadPartial();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startChipAutoScroll();
      _startKpiPageAutoScroll();
      _initHyperSDK();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pollTimer?.cancel();
    _chipTimer?.cancel();
    _kpiPageTimer?.cancel();
    _chipScrollController.dispose();
    _kpiPageController?.dispose();

    try {
      _hyperSDK.terminate();
    } catch (_) {}

    super.dispose();
  }

  /* =========================================================
    Storage
  ========================================================= */

  Future<String> _getActiveAdmission() async {
    final prefs = await SharedPreferences.getInstance();

    final storedActive = prefs.getString('selectedStudentAdmissionNumber') ??
        prefs.getString('activeStudentAdmission');
    if (storedActive != null && storedActive.trim().isNotEmpty) {
      return normalizeAdmissionRaw(storedActive);
    }

    final stored =
        prefs.getString('username') ?? prefs.getString('admissionNumber');
    if (stored != null) return normalizeAdmissionRaw(stored);

    final token = prefs.getString('authToken') ?? prefs.getString('token');
    if (token != null) {
      final payload = parseJwt(token);
      final adm = payload?['admission_number'] ?? payload?['username'];
      if (adm != null) return normalizeAdmissionRaw(adm.toString());
    }
    return '';
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authToken') ?? prefs.getString('token');
  }

  Future<String> _getLoggedInAdmission() async {
    final prefs = await SharedPreferences.getInstance();

    final stored =
        prefs.getString('username') ?? prefs.getString('admissionNumber');
    if (stored != null && stored.trim().isNotEmpty) {
      return normalizeAdmissionRaw(stored);
    }

    final token = prefs.getString('authToken') ?? prefs.getString('token');
    if (token != null && token.trim().isNotEmpty) {
      final payload = parseJwt(token);
      final adm = payload?['admission_number'] ??
          payload?['admissionNumber'] ??
          payload?['username'] ??
          payload?['sub'];

      if (adm != null && adm.toString().trim().isNotEmpty) {
        return normalizeAdmissionRaw(adm.toString());
      }
    }

    return '';
  }


  void _buildStudentsListFromFamily() {
    studentsList = <Map<String, dynamic>>[];

    if (family?['student'] != null) {
      final self = Map<String, dynamic>.from(family!['student']);
      self['isSelf'] = true;
      studentsList.add(self);
    }

    final siblingsList = family?['siblings'] as List? ?? [];
    for (final s in siblingsList) {
      final sib = Map<String, dynamic>.from(s);
      sib['isSelf'] = false;
      studentsList.add(sib);
    }
  }

  Future<void> _loadFamilyAndActive() async {
    final prefs = await SharedPreferences.getInstance();
    final familyJson = prefs.getString('family');
    if (familyJson != null) {
      try {
        family = json.decode(familyJson);
      } catch (e) {
        debugPrint('Failed to parse family: $e');
        family = null;
      }
    }

    activeAdmission = await _getActiveAdmission();
    loggedInAdmission = await _getLoggedInAdmission();
    _buildStudentsListFromFamily();

    await _loadRoles();
    if (mounted) setState(() {});

    if (activeAdmission.isNotEmpty) {
      final token = await _getToken();
      if (token != null && mounted) {
        await _loadAllForAdmission(activeAdmission, token);
      } else if (mounted) {
        setState(() {
          loading = false;
          error = 'Missing auth token. Please login.';
        });
      }
    } else if (mounted) {
      setState(() {
        loading = false;
        error = 'No active student found.';
      });
    }
  }

  Future<void> _loadRoles() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('roles');
    if (stored != null) {
      try {
        final list = json.decode(stored) as List;
        _roles = list.map((r) => normalizeRole(r.toString())).toList();
      } catch (e) {
        debugPrint('Failed to parse roles: $e');
      }
    }

    if (_roles.isEmpty) {
      final single = prefs.getString('userRole');
      if (single != null) _roles = [normalizeRole(single)];
    }

    if (_roles.isEmpty) {
      final tokenStr = prefs.getString('authToken') ?? prefs.getString('token');
      if (tokenStr != null) {
        final payload = parseJwt(tokenStr);
        if (payload != null) {
          if (payload['roles'] is List) {
            _roles = (payload['roles'] as List)
                .map((r) => normalizeRole(r.toString()))
                .toList();
          } else if (payload['role'] != null) {
            _roles = [normalizeRole(payload['role'].toString())];
          }
        }
      }
    }

    final activeRole =
        (prefs.getString('activeRole') ?? '').toLowerCase().trim();
    final isTeacherRole =
        activeRole == 'teacher' || _roles.any((r) => r == 'teacher');

    canSeeStudentSwitcher = !isTeacherRole;
  }

  Future<void> handleStudentSwitch(String newAdmission) async {
    final raw = normalizeAdmissionRaw(newAdmission);
    if (raw == activeAdmission) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('activeStudentAdmission', raw);
    await prefs.setString('selectedStudentAdmissionNumber', raw);

    if (mounted) {
      setState(() => activeAdmission = raw);
    }

    final token = await _getToken();
    if (token != null && mounted) {
      await _loadAllForAdmission(raw, token);
    }
  }

  /* =========================================================
    Helpers
  ========================================================= */

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

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  List<dynamic> _asList(dynamic v) {
    if (v is List) return v;
    return <dynamic>[];
  }

  String _classTextFromAny(Map<String, dynamic> student) {
    final className = _stringValue(student['class_name']) ??
        _stringValue(_asMap(student['Class'])?['class_name']) ??
        _stringValue(_asMap(student['class'])?['name']) ??
        _stringValue(_asMap(student['class'])?['class_name']) ??
        '';
    final sectionName = _stringValue(student['section_name']) ??
        _stringValue(_asMap(student['Section'])?['section_name']) ??
        _stringValue(_asMap(student['section'])?['name']) ??
        _stringValue(_asMap(student['section'])?['section_name']) ??
        '';

    if (className.isEmpty && sectionName.isEmpty) return '';
    if (sectionName.isEmpty) return className;
    if (className.isEmpty) return sectionName;
    return '$className-$sectionName';
  }

  String _studentSwitcherLabel(Map<String, dynamic> student) {
    final admission = _stringValue(student['admission_number']) ?? '';
    final classText = _classTextFromAny(student);
    final name = ((student['isSelf'] ?? false) == true)
        ? 'Me'
        : (_stringValue(student['name']) ?? 'Student');

    if (classText.isNotEmpty) return '$name · $classText';
    if (admission.isNotEmpty) return '$name · $admission';
    return name;
  }

  Future<void> _fetchSiblingStudentsForAdmission(
    String token,
    String admissionNumberRaw,
  ) async {
    if (!canSeeStudentSwitcher) {
      if (mounted) {
        setState(() {
          siblingsLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => siblingsLoading = true);
    }

    try {
      final admissionForPath = normalizeAdmissionForPath(admissionNumberRaw);
      final profileRes = await http.get(
        Uri.parse('$baseUrl/students/admission/$admissionForPath'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (profileRes.statusCode != 200) {
        throw Exception('student profile fetch failed');
      }

      final profileJson = jsonDecode(profileRes.body);
      final profile = _asMap(profileJson) ?? <String, dynamic>{};
      final currentStudentId = _intValue(profile['id']);
      _currentStudentId = currentStudentId;

      final currentAdmission = _stringValue(profile['admission_number']) ??
          _stringValue(profile['admissionNumber']) ??
          admissionNumberRaw;

      final currentStudent = <String, dynamic>{
        'id': currentStudentId,
        'name': _stringValue(profile['name']) ??
            _stringValue(studentDetails?['name']) ??
            'Current Student',
        'admission_number': currentAdmission,
        'class_name': _stringValue(_asMap(profile['Class'])?['class_name']) ??
            _stringValue(profile['class_name']) ??
            _stringValue(studentDetails?['class_name']),
        'section_name': _stringValue(_asMap(profile['Section'])?['section_name']) ??
            _stringValue(profile['section_name']) ??
            _stringValue(studentDetails?['section_name']),
        'photo_url': _stringValue(profile['photo_url']) ??
            _stringValue(profile['photoUrl']),
        'isSelf': normalizeAdmissionRaw(currentAdmission) == loggedInAdmission,
        'is_current': true,
      };

      final items = <Map<String, dynamic>>[currentStudent];

      if (currentStudentId != null) {
        final siblingsRes = await http.get(
          Uri.parse('$baseUrl/students/$currentStudentId/siblings-with-due'),
          headers: {'Authorization': 'Bearer $token'},
        );

        if (siblingsRes.statusCode == 200) {
          final siblingsJson = _asMap(jsonDecode(siblingsRes.body)) ?? {};
          final siblings = _asList(siblingsJson['siblings']);

          for (final item in siblings) {
            final map = _asMap(item);
            if (map == null) continue;

            final adm = _stringValue(map['admission_number']);
            if (adm == null || normalizeAdmissionRaw(adm) == normalizeAdmissionRaw(currentAdmission)) {
              continue;
            }

            items.add({
              'id': map['id'],
              'name': _stringValue(map['name']) ?? 'Sibling',
              'admission_number': adm,
              'class_name': _stringValue(_asMap(map['Class'])?['class_name']) ??
                  _stringValue(map['class_name']) ??
                  _stringValue(_asMap(map['class'])?['name']) ??
                  _stringValue(_asMap(map['class'])?['class_name']),
              'section_name': _stringValue(_asMap(map['Section'])?['section_name']) ??
                  _stringValue(map['section_name']) ??
                  _stringValue(_asMap(map['section'])?['name']) ??
                  _stringValue(_asMap(map['section'])?['section_name']),
              'isSelf': normalizeAdmissionRaw(adm) == loggedInAdmission,
              'is_current': false,
            });
          }
        }
      }

      if (mounted) {
        setState(() {
          studentsList = items;
          siblingsLoading = false;
        });
      }
    } catch (e) {
      debugPrint('fetchSiblingStudentsForAdmission error: $e');
      _buildStudentsListFromFamily();
      if (studentDetails != null) {
        final currentAdmission = _stringValue(studentDetails?['admissionNumber']) ??
            _stringValue(studentDetails?['admission_number']) ??
            admissionNumberRaw;

        if (!studentsList.any((s) =>
            normalizeAdmissionRaw(_stringValue(s['admission_number']) ?? '') ==
            normalizeAdmissionRaw(currentAdmission))) {
          studentsList.insert(0, {
            'name': _stringValue(studentDetails?['name']) ?? 'Student',
            'admission_number': currentAdmission,
            'class_name': _stringValue(studentDetails?['class_name']),
            'section_name': _stringValue(studentDetails?['section_name']),
            'isSelf': normalizeAdmissionRaw(currentAdmission) == loggedInAdmission,
            'is_current': true,
          });
        }
      }

      if (mounted) {
        setState(() => siblingsLoading = false);
      }
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  String formatINR(dynamic v) {
    final n = (v == null)
        ? 0.0
        : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);
    final f =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    return f.format(n);
  }

  double _num(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  String _safeStr(dynamic v) => v == null ? '' : v.toString().trim();

  /* =========================================================
    Fine helpers
  ========================================================= */

  double _feeFineTotal(dynamic fee) {
    if (fee is! Map) return 0.0;
    final raw = fee['fineAmount'] ??
        fee['fine_due'] ??
        fee['lateFee'] ??
        fee['LateFee'] ??
        fee['Fine'] ??
        fee['FineAmount'] ??
        fee['Fine_Amount'] ??
        0;
    return _num(raw);
  }

  double _feeFinePaid(dynamic fee) {
    if (fee is! Map) return 0.0;
    final raw = fee['fineReceived'] ??
        fee['totalFineReceived'] ??
        fee['FineReceived'] ??
        0;
    return _num(raw);
  }

  double _feeFineDue(dynamic fee) {
    final due = _feeFineTotal(fee) - _feeFinePaid(fee);
    return due > 0 ? due : 0.0;
  }

  double _txnFine(dynamic txn) {
    if (txn is! Map) return 0.0;
    final raw = txn['Fine'] ??
        txn['fine'] ??
        txn['LateFee'] ??
        txn['lateFee'] ??
        txn['FineAmount'] ??
        txn['fineAmount'] ??
        txn['fine_due'] ??
        0;
    return _num(raw);
  }

  /* =========================================================
    Session + Previous Balance
  ========================================================= */

  Future<void> _fetchActiveSessionId(String token) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/sessions'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode != 200) {
        _activeSessionId = null;
        return;
      }

      final jsonObj = jsonDecode(res.body);
      List list = [];
      if (jsonObj is List) list = jsonObj;
      if (jsonObj is Map && jsonObj['data'] is List) list = jsonObj['data'];

      Map? active;
      for (final s in list) {
        if (s is Map && s['is_active'] == true) {
          active = s;
          break;
        }
      }
      active ??= (list.isNotEmpty && list.first is Map) ? list.first : null;

      if (active != null) {
        _activeSessionId = int.tryParse(active['id'].toString());
      } else {
        _activeSessionId = null;
      }
    } catch (e) {
      debugPrint('fetchActiveSessionId failed: $e');
      _activeSessionId = null;
    }
  }

  Future<void> _ensurePrevBalanceHeadId(String token) async {
    if (_prevBalanceHeadId != null) return;
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/fee-headings'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) return;

      final jsonObj = jsonDecode(res.body);
      List list = [];
      if (jsonObj is List) list = jsonObj;
      if (jsonObj is Map && jsonObj['data'] is List) list = jsonObj['data'];

      for (final h in list) {
        if (h is! Map) continue;
        final name = (h['fee_heading'] ?? h['FeeHeading'] ?? '')
            .toString()
            .toLowerCase()
            .trim();
        if (name == 'previous balance') {
          _prevBalanceHeadId = int.tryParse(h['id'].toString());
          break;
        }
      }
    } catch (e) {
      debugPrint('ensurePrevBalanceHeadId failed: $e');
    }
  }

  Future<void> _fetchOpeningBalanceOutstanding(String token, String admission) async {
    try {
      if (_activeSessionId == null) {
        _prevBalanceDue = 0;
        return;
      }

      final uri = Uri.parse('$baseUrl/opening-balances/outstanding').replace(
        queryParameters: {
          'session_id': _activeSessionId.toString(),
          'admissionNumber': admission,
          'selectedAdmissionNumber': admission,
          'targetAdmissionNumber': admission,
        },
      );

      final res = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode != 200) {
        _prevBalanceDue = 0;
        return;
      }

      final jsonObj = jsonDecode(res.body);
      final val = (jsonObj is Map)
          ? (jsonObj['outstanding'] ??
              (jsonObj['data'] is Map ? jsonObj['data']['outstanding'] : null) ??
              jsonObj['totalOutstanding'])
          : null;

      final n = _num(val);
      _prevBalanceDue = n.isFinite ? (n > 0 ? n : 0) : 0;
    } catch (e) {
      debugPrint('OB fetch failed: $e');
      _prevBalanceDue = 0;
    }
  }

  /* =========================================================
    Transport helpers
  ========================================================= */

  bool _isTransportApplicableForFee(Map fee) {
    final raw = fee['transportApplicable'] ??
        fee['transport_applicable'] ??
        fee['is_transport_applicable'] ??
        fee['TransportApplicable'] ??
        fee['isTransportApplicable'];

    if (raw == false || raw == 0 || raw == '0') return false;
    if (raw == true || raw == 1 || raw == '1') return true;
    if (fee['transport'] != null) return true;
    return false;
  }

  Map<String, dynamic>? getVanForHeadFromMap(dynamic feeHeadId) {
    if (feeHeadId == null) return null;
    final id = int.tryParse(feeHeadId.toString()) ??
        (feeHeadId is int ? feeHeadId : null);
    if (id == null) return null;

    final v = vanByHead[id];
    if (v == null) return null;

    final cost = _num(v['transportCost']);
    final received = _num(v['totalVanFeeReceived']);
    final concession = _num(v['totalVanFeeConcession']);
    final pending = (cost - (received + concession)).clamp(0, double.infinity);

    return {
      'cost': cost,
      'received': received,
      'concession': concession,
      'pending': pending,
      'due': cost,
      'source': 'map',
    };
  }

  Map<String, dynamic>? getTransportBreakdown(dynamic feeRaw) {
    if (feeRaw == null || feeRaw is! Map) return null;
    final fee = Map<String, dynamic>.from(feeRaw);

    if (!_isTransportApplicableForFee(fee)) return null;

    if (fee['transport'] != null) {
      try {
        final t = Map<String, dynamic>.from(fee['transport']);
        final due = _num(t['transportDue']);
        final received = _num(t['transportReceived']);
        final concession = _num(t['transportConcession']);
        final pending = _num(t['transportPending']);
        final cost = due + received + concession;

        return {
          'cost': cost,
          'due': due,
          'received': received,
          'concession': concession,
          'pending': pending,
          'source': 'api',
        };
      } catch (_) {}
    }

    return getVanForHeadFromMap(fee['fee_heading_id'] ?? fee['feeHeadId']);
  }

  bool _transportEnabled() {
    final sd = studentDetails;
    if (sd == null) return false;

    final global = sd['transportApplicable'] ??
        sd['transport_applicable'] ??
        sd['is_transport_applicable'];
    if (global == false || global == 0 || global == '0') return false;

    final fees = (sd['feeDetails'] as List?) ?? [];
    final anyHead =
        fees.any((f) => f is Map && _isTransportApplicableForFee(Map.from(f)));

    final v = sd['vanFee'];
    final cost = _num((v is Map) ? (v['perHeadTotalDue'] ?? v['transportCost']) : 0);
    final rec = _num((v is Map) ? v['totalVanFeeReceived'] : 0);
    final con = _num((v is Map) ? v['totalVanFeeConcession'] : 0);

    return anyHead || cost > 0 || rec > 0 || con > 0;
  }

  /* =========================================================
    Previous slabs auto inclusion
  ========================================================= */

  Map<String, dynamic> _computePreviousSlabsTotals(int untilIndex) {
    final feesList = (studentDetails?['feeDetails'] as List?) ?? [];
    double prevAcademic = 0, prevFine = 0, prevVan = 0;
    final List<Map<String, dynamic>> items = [];

    for (int i = 0; i < untilIndex; i++) {
      final f0 = feesList[i];
      if (f0 is! Map) continue;
      final f = Map<String, dynamic>.from(f0);

      final acadDue = _num(f['finalAmountDue']);
      final fineDue = _feeFineDue(f);
      final t = getTransportBreakdown(f);
      final vanDue = _num(t?['pending']);
      final headDue = acadDue + fineDue + vanDue;

      if (headDue > 0) {
        prevAcademic += acadDue;
        prevFine += fineDue;
        prevVan += vanDue;
        items.add({
          'feeHeading': f['fee_heading'] ?? '',
          'feeHeadId': f['fee_heading_id'],
          'academicDue': acadDue,
          'fineDue': fineDue,
          'vanDue': vanDue,
          'total': headDue,
        });
      }
    }

    return {
      'items': items,
      'totalAcademic': prevAcademic,
      'totalFine': prevFine,
      'totalVan': prevVan,
      'total': prevAcademic + prevFine + prevVan,
      'count': items.length,
    };
  }

  /* =========================================================
    API Loads
  ========================================================= */

  Future<void> _loadAllForAdmission(String admission, String token) async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      await _fetchActiveSessionId(token);
      await _ensurePrevBalanceHeadId(token);

      await Future.wait([
        _fetchStudentDetails(admission, token),
        _fetchTransactionHistory(admission, token),
        _fetchVanFeeByHead(token, admission: admission),
        _fetchSiblingStudentsForAdmission(token, admission),
      ]);

      await _fetchOpeningBalanceOutstanding(token, admission);
    } catch (e, st) {
      debugPrint('loadAllForAdmission error $e\n$st');
      if (mounted) setState(() => error = 'Failed to load data');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadPartial() async {
    final admission = await _getActiveAdmission();
    if (admission.isEmpty) return;
    final token = await _getToken();
    if (token == null) return;

    try {
      await Future.wait([
        _fetchStudentDetails(admission, token),
        _fetchTransactionHistory(admission, token),
        _fetchVanFeeByHead(token, admission: admission),
      ]);
      await _fetchOpeningBalanceOutstanding(token, admission);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('partial refresh failed: $e');
    }
  }

  Future<void> _fetchStudentDetails(String admissionNumberRaw, String token) async {
    try {
      final admissionForPath = normalizeAdmissionForPath(admissionNumberRaw);

      final res = await http.get(
        Uri.parse('$baseUrl/StudentsApp/admission/$admissionForPath/fees'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        final jsonObj = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            if (jsonObj is Map && jsonObj.containsKey('data')) {
              studentDetails = Map<String, dynamic>.from(jsonObj['data']);
            } else if (jsonObj is Map) {
              studentDetails = Map<String, dynamic>.from(jsonObj);
            } else {
              studentDetails = {};
            }

            if (studentDetails?['feeDetails'] is List) {
              final len = (studentDetails!['feeDetails'] as List).length;
              _expandedFees = List<bool>.filled(len, false);
            } else {
              _expandedFees = [];
            }

            error = null;
          });
        }
      } else {
        debugPrint('student details fetch failed: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      debugPrint('fetchStudentDetails error: $e');
    }
  }

  Future<void> _fetchTransactionHistory(String admissionNumberRaw, String token) async {
    try {
      final admissionForPath = normalizeAdmissionForPath(admissionNumberRaw);

      final res = await http.get(
        Uri.parse('$baseUrl/StudentsApp/feehistory/$admissionForPath'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        final jsonObj = jsonDecode(res.body);
        if (mounted) {
          if (jsonObj is Map &&
              jsonObj['success'] == true &&
              jsonObj['data'] is List) {
            setState(() =>
                transactionHistory = List<dynamic>.from(jsonObj['data']));
          } else if (jsonObj is List) {
            setState(() => transactionHistory = List<dynamic>.from(jsonObj));
          } else {
            setState(() => transactionHistory = []);
          }
        }
      } else {
        debugPrint('txn history fetch failed: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('fetchTransactionHistory error: $e');
    }
  }

  Future<void> _fetchVanFeeByHead(String token, {required String admission}) async {
    try {
      final normalizedAdmission = normalizeAdmissionRaw(admission);
      final uri = normalizedAdmission.isNotEmpty
          ? Uri.parse('$baseUrl/transactions/vanfee/me').replace(
              queryParameters: {'admission_number': normalizedAdmission},
            )
          : Uri.parse('$baseUrl/transactions/vanfee/me');

      final res = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        final jsonObj = jsonDecode(res.body);
        List rows = [];
        if (jsonObj is Map && jsonObj['data'] is List) {
          rows = List.from(jsonObj['data']);
        } else if (jsonObj is List) {
          rows = List.from(jsonObj);
        }

        final Map<int, Map<String, dynamic>> map = {};
        for (final r0 in rows) {
          if (r0 is! Map) continue;
          final r = Map<String, dynamic>.from(r0);

          final id = int.tryParse((r['Fee_Head'] ?? '').toString()) ??
              (r['Fee_Head'] is int ? r['Fee_Head'] : null);
          if (id == null) continue;

          map[id] = {
            'transportCost': _num(r['TransportCost']),
            'totalVanFeeReceived': _num(r['TotalVanFeeReceived']),
            'totalVanFeeConcession': _num(r['TotalVanFeeConcession']),
          };
        }

        if (mounted) setState(() => vanByHead = map);
      } else {
        debugPrint('vanfee fetch failed: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('fetchVanFeeByHead error: $e');
    }
  }

  /* =========================================================
    HyperSDK
  ========================================================= */

  Future<void> _initHyperSDK() async {
    try {
      final already = await _hyperSDK.isInitialised();
      if (already == true) {
        _hyperInitiated = true;
        return;
      }
    } catch (e) {
      debugPrint('HyperSDK check error: $e');
    }

    final initiatePayload = {
      'requestId': DateTime.now().millisecondsSinceEpoch.toString(),
      'service': 'in.juspay.hyperpay',
      'payload': {
        'clientId': _hyperClientId,
        'environment': _hyperEnv,
      }
    };

    try {
      await _hyperSDK.initiate(initiatePayload, (MethodCall call) {
        debugPrint('HyperSDK initiate cb: ${call.method} ${call.arguments}');
      });

      final ok = await _hyperSDK.isInitialised();
      _hyperInitiated = ok == true;
    } catch (e, st) {
      debugPrint('HyperSDK initiate FAILED: $e\n$st');
      _hyperInitiated = false;
    }
  }

  Future<void> _openUrlExternal(String url) async {
    try {
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _showSnack('Could not open link');
    } catch (e) {
      debugPrint('openUrlExternal error: $e');
      _showSnack('Invalid link');
    }
  }

  Future<void> _openHyperPayment({
    required String admission,
    required double amount,
    String? feeHeadId,
    required Map<String, dynamic> extraBody,
  }) async {
    if (_hyperOpening) return;
    _hyperOpening = true;

    try {
      final token = await _getToken();
      if (token == null || token.isEmpty) {
        _showSnack('Missing auth token. Please login again.');
        return;
      }

      final uri = Uri.parse('$baseUrl/student-fee/create-order?mode=sdk');

      final payerAdmission =
          loggedInAdmission.isNotEmpty ? loggedInAdmission : admission;
      final isSiblingPayment = payerAdmission != admission;

      final body = <String, dynamic>{
        'admissionNumber': admission,
        'targetAdmissionNumber': admission,
        'selectedAdmissionNumber': admission,
        'payerAdmissionNumber': payerAdmission,
        'loggedInAdmissionNumber': payerAdmission,
        'isSiblingPayment': isSiblingPayment,
        'amount': amount,
        'clientComputedDueAmount': amount,
        'feeHeadId': (feeHeadId != null && feeHeadId.trim().isNotEmpty)
            ? feeHeadId.trim()
            : 'VAN_FEE',
        'gateway': 'hdfc',
        ...extraBody,
      };

      final res = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'x-client': 'flutter',
        },
        body: jsonEncode(body),
      );

      if (res.statusCode != 200) {
        debugPrint('Create order failed: ${res.statusCode} ${res.body}');
        String msg = 'Failed to create payment order';
        try {
          final errJson = jsonDecode(res.body);
          if (errJson is Map) {
            msg =
                (errJson['message'] ?? errJson['error'] ?? errJson['details'] ?? msg)
                    .toString();
          }
        } catch (_) {}
        _showSnack(msg);
        return;
      }

      final jsonObj = jsonDecode(res.body);

      dynamic processPayload =
          (jsonObj is Map ? jsonObj['processPayload'] : null) ??
              (jsonObj is Map && jsonObj['data'] is Map
                  ? (jsonObj['data'] as Map)['processPayload']
                  : null) ??
              (jsonObj is Map ? jsonObj['payload'] : null) ??
              (jsonObj is Map && jsonObj['data'] is Map
                  ? (jsonObj['data'] as Map)['payload']
                  : null);

      if (processPayload == null &&
          jsonObj is Map &&
          jsonObj['data'] is Map &&
          (jsonObj['data']['process_payload'] != null)) {
        processPayload = (jsonObj['data'] as Map)['process_payload'];
      }

      String paymentPageUrl = '';
      if (jsonObj is Map) {
        paymentPageUrl = (jsonObj['paymentPageUrl'] ?? '').toString().trim();
        if (paymentPageUrl.isEmpty && jsonObj['data'] is Map) {
          paymentPageUrl =
              ((jsonObj['data'] as Map)['paymentPageUrl'] ?? '').toString().trim();
        }
      }

      if (processPayload == null) {
        if (paymentPageUrl.isNotEmpty) {
          await _openUrlExternal(paymentPageUrl);
          if (mounted) await _loadPartial();
          return;
        }
        _showSnack('Invalid payment payload from server');
        return;
      }

      if (!_hyperInitiated) await _initHyperSDK();
      if (!_hyperInitiated) {
        if (paymentPageUrl.isNotEmpty) {
          await _openUrlExternal(paymentPageUrl);
          if (mounted) await _loadPartial();
          return;
        }
        _showSnack('Payment SDK not initialized');
        return;
      }

      await _hyperSDK.processWithActivity(processPayload, (MethodCall call) async {
        debugPrint('HyperSDK cb: ${call.method} ${call.arguments}');
        if (mounted) await _loadPartial();
      });
    } catch (e, st) {
      debugPrint('_openHyperPayment error: $e\n$st');
      _showSnack('Payment failed to start');
    } finally {
      _hyperOpening = false;
    }
  }

  /* =========================================================
    Slip Download / Open
  ========================================================= */

  Future<Uint8List?> _fetchSlipPdfBytes(String slipId) async {
    final token = await _getToken();
    if (token == null || token.isEmpty) return null;

    final selectedAdmission = activeAdmission.isNotEmpty
        ? normalizeAdmissionRaw(activeAdmission)
        : normalizeAdmissionRaw(await _getActiveAdmission());

    final uri = selectedAdmission.isNotEmpty
        ? Uri.parse('$baseUrl/transactions/slip/$slipId/me').replace(
            queryParameters: {'admission_number': selectedAdmission},
          )
        : Uri.parse('$baseUrl/transactions/slip/$slipId/me');

    final res = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/pdf',
      },
    );

    final ct = (res.headers['content-type'] ?? '').toLowerCase();
    final bytes = res.bodyBytes;

    final startsWithPdf = bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46;

    if (res.statusCode == 200 &&
        (ct.contains('application/pdf') || startsWithPdf)) {
      return bytes;
    }

    debugPrint('Slip NOT pdf. status=${res.statusCode} ct=$ct');
    return null;
  }

  Future<File?> _writeBytesToTempPdf(Uint8List bytes, String filename) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (e) {
      debugPrint('write temp pdf error: $e');
      return null;
    }
  }

  Future<void> _openSlip(String slipId) async {
    if ((_slipDownloading[slipId] ?? false) == true) return;

    setState(() => _slipDownloading[slipId] = true);
    try {
      final bytes = await _fetchSlipPdfBytes(slipId);
      if (bytes == null) {
        _showSnack('Slip not available / invalid PDF from server');
        return;
      }

      final file = await _writeBytesToTempPdf(bytes, 'fee_slip_$slipId.pdf');
      if (file == null) {
        _showSnack('Unable to save slip');
        return;
      }

      await OpenFilex.open(file.path);
    } catch (e, st) {
      debugPrint('_openSlip error: $e\n$st');
      _showSnack('Failed to open slip');
    } finally {
      if (mounted) setState(() => _slipDownloading[slipId] = false);
    }
  }

  Future<void> _downloadSlipToDevice(String slipId) async {
    if ((_slipDownloading[slipId] ?? false) == true) return;

    setState(() => _slipDownloading[slipId] = true);
    try {
      final bytes = await _fetchSlipPdfBytes(slipId);
      if (bytes == null) {
        _showSnack('Slip not available / invalid PDF from server');
        return;
      }

      final tempFile =
          await _writeBytesToTempPdf(bytes, 'fee_slip_$slipId.pdf');
      if (tempFile == null) {
        _showSnack('Unable to save slip');
        return;
      }

      final params = SaveFileDialogParams(
        sourceFilePath: tempFile.path,
        fileName: 'fee_slip_$slipId.pdf',
        mimeTypesFilter: const ['application/pdf'],
      );

      final savedPath = await FlutterFileDialog.saveFile(params: params);
      if (savedPath == null) return;

      _showSnack('Slip saved');
    } catch (e, st) {
      debugPrint('_downloadSlipToDevice error: $e\n$st');
      _showSnack('Failed to download slip');
    } finally {
      if (mounted) setState(() => _slipDownloading[slipId] = false);
    }
  }

  /* =========================================================
    Payment handlers
  ========================================================= */

  Future<bool> _confirmPaymentDialog({
    required String title,
    required List<Map<String, String>> rows,
    required String totalText,
  }) async {
    if (!mounted) return false;

    return (await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (_) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title:
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Breakup',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    ...rows.map((r) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: Text(r['k'] ?? '')),
                            const SizedBox(width: 10),
                            Text(r['v'] ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w900)),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total',
                            style: TextStyle(fontWeight: FontWeight.w900)),
                        Text(totalText,
                            style: const TextStyle(fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _indigo,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Pay Now'),
                ),
              ],
            );
          },
        )) ??
        false;
  }

  Future<void> handlePayFee(Map<String, dynamic> fee, int feeIndex) async {
    final academicDue = _num(fee['finalAmountDue']);
    final fineDue = _feeFineDue(fee);

    final t = getTransportBreakdown(fee);
    final vanDueHead = _num(t?['pending']);

    final prev = _computePreviousSlabsTotals(feeIndex);
    final prevTotal = _num(prev['total']);
    final prevCount = (prev['count'] as int?) ?? 0;

    final openingBalanceDue = _prevBalanceDue;
    final dueAmount =
        academicDue + fineDue + vanDueHead + prevTotal + openingBalanceDue;

    if (!dueAmount.isFinite || dueAmount <= 0) {
      _showSnack('Nothing due to pay');
      return;
    }

    final rows = <Map<String, String>>[
      {'k': 'Academic (this head)', 'v': formatINR(academicDue)},
      {'k': 'Fine (this head)', 'v': formatINR(fineDue)},
      {'k': 'Transport (this head)', 'v': formatINR(vanDueHead)},
    ];

    if (prevCount > 0) {
      rows.add({'k': 'Prev Heads ($prevCount)', 'v': formatINR(prevTotal)});
      rows.add({'k': 'Prev Academic', 'v': formatINR(prev['totalAcademic'])});
      rows.add({'k': 'Prev Fine', 'v': formatINR(prev['totalFine'])});
      rows.add({'k': 'Prev Transport', 'v': formatINR(prev['totalVan'])});
    }

    if (openingBalanceDue > 0) {
      rows.add({'k': 'Previous Balance', 'v': formatINR(openingBalanceDue)});
    }

    final ok = await _confirmPaymentDialog(
      title: 'Proceed to pay ${formatINR(dueAmount)}?',
      rows: rows,
      totalText: formatINR(dueAmount),
    );

    if (!ok) return;

    final feeHeadId =
        (fee['fee_heading_id'] ?? fee['feeHeadId'] ?? '').toString().trim();

    await _openHyperPayment(
      admission: activeAdmission,
      amount: dueAmount,
      feeHeadId: feeHeadId.isNotEmpty ? feeHeadId : null,
      extraBody: {
        'fineAmount': fineDue,
        'vanFeeAmount': vanDueHead,
        'openingBalanceAmount': openingBalanceDue,
        'openingBalanceHeadId': _prevBalanceHeadId,
        'previousSlabs': prev['items'] ?? [],
        'previousSlabsTotal': prevTotal,
        'breakdown': {
          'academicDue': academicDue,
          'fineDue': fineDue,
          'vanDueHead': vanDueHead,
          'openingBalanceDue': openingBalanceDue,
          'previous': {
            'total': prevTotal,
            'academic': _num(prev['totalAcademic']),
            'fine': _num(prev['totalFine']),
            'van': _num(prev['totalVan']),
            'count': prevCount,
            'items': prev['items'] ?? [],
          }
        },
      },
    );
  }

  Future<void> handlePayVanFee() async {
    final van = (studentDetails?['vanFee'] is Map)
        ? Map<String, dynamic>.from(studentDetails!['vanFee'])
        : <String, dynamic>{};

    final vanCost = _num(van['perHeadTotalDue'] ?? van['transportCost']);
    final received = _num(van['totalVanFeeReceived']);
    final concession = _num(van['totalVanFeeConcession']);
    final vanDueOnly =
        (vanCost - (received + concession)).clamp(0, double.infinity);

    final openingBalanceDue = _prevBalanceDue;
    final totalToPay = vanDueOnly + openingBalanceDue;

    if (totalToPay <= 0) {
      _showSnack("You're all clear on Van Fee and Previous Balance.");
      return;
    }

    final ok = await _confirmPaymentDialog(
      title: 'Pay ${formatINR(totalToPay)}?',
      rows: [
        {'k': 'Van Fee', 'v': formatINR(vanDueOnly)},
        {'k': 'Previous Balance', 'v': formatINR(openingBalanceDue)},
      ],
      totalText: formatINR(totalToPay),
    );

    if (!ok) return;

    await _openHyperPayment(
      admission: activeAdmission,
      amount: totalToPay,
      feeHeadId: 'VAN_FEE',
      extraBody: {
        'openingBalanceAmount': openingBalanceDue,
        'openingBalanceHeadId': _prevBalanceHeadId,
        'breakdown': {
          'vanDue': vanDueOnly,
          'openingBalanceDue': openingBalanceDue,
        },
      },
    );
  }

  Future<void> handlePayPreviousBalanceOnly() async {
    final openingBalanceDue = _prevBalanceDue;

    if (openingBalanceDue <= 0) {
      _showSnack('No previous balance due');
      return;
    }

    final ok = await _confirmPaymentDialog(
      title: 'Pay ${formatINR(openingBalanceDue)}?',
      rows: [
        {'k': 'Previous Balance', 'v': formatINR(openingBalanceDue)},
      ],
      totalText: formatINR(openingBalanceDue),
    );

    if (!ok) return;

    await _openHyperPayment(
      admission: activeAdmission,
      amount: openingBalanceDue,
      feeHeadId: _prevBalanceHeadId?.toString(),
      extraBody: {
        'openingBalanceAmount': openingBalanceDue,
        'openingBalanceHeadId': _prevBalanceHeadId,
        'breakdown': {
          'openingBalanceDue': openingBalanceDue,
        },
      },
    );
  }

  /* =========================================================
    Totals
  ========================================================= */

  Map<String, double> _calcTotals() {
    double totalOriginal = 0,
        totalEffective = 0,
        totalDue = 0,
        totalReceived = 0,
        totalConcession = 0,
        totalFineRemaining = 0;

    final fees = (studentDetails?['feeDetails'] as List?) ?? [];
    for (final f0 in fees) {
      if (f0 is! Map) continue;
      final f = Map<String, dynamic>.from(f0);

      totalOriginal += _num(f['originalFeeDue']);
      totalEffective += _num(f['effectiveFeeDue']);
      totalDue += _num(f['finalAmountDue']);
      totalReceived += _num(f['totalFeeReceived']);
      totalConcession += _num(f['totalConcessionReceived']);
      totalFineRemaining += _feeFineDue(f);
    }

    final van = (studentDetails?['vanFee'] is Map)
        ? Map<String, dynamic>.from(studentDetails!['vanFee'])
        : <String, dynamic>{};

    final vanCost = _num(van['perHeadTotalDue'] ?? van['transportCost']);
    final vanReceived = _num(van['totalVanFeeReceived']);
    final vanConcession = _num(van['totalVanFeeConcession']);

    return {
      'original': totalOriginal,
      'effective': totalEffective,
      'due': totalDue,
      'received': totalReceived,
      'concession': totalConcession,
      'fineRemaining': totalFineRemaining,
      'prevBalanceDue': _prevBalanceDue,
      'vanCost': vanCost,
      'vanReceived': vanReceived,
      'vanConcession': vanConcession,
      'vanDue':
          (vanCost - (vanReceived + vanConcession)).clamp(0, double.infinity),
    };
  }

  Map<String, double> _calcPayableSummary() {
    final totals = _calcTotals();

    final academicDue = totals['due'] ?? 0.0;
    final fineDue = totals['fineRemaining'] ?? 0.0;
    final vanDue = totals['vanDue'] ?? 0.0;
    final prevBalanceDue = totals['prevBalanceDue'] ?? 0.0;

    return {
      'academicDue': academicDue,
      'fineDue': fineDue,
      'vanDue': vanDue,
      'prevBalanceDue': prevBalanceDue,
      'totalPayable': academicDue + fineDue + vanDue + prevBalanceDue,
    };
  }

  /* =========================================================
    Charts + KPI
  ========================================================= */

  Widget _feeHeadsPieChart() {
    final fees = (studentDetails?['feeDetails'] as List?) ?? [];
    if (fees.isEmpty) {
      return const SizedBox(
          height: 220, child: Center(child: Text('No data for chart')));
    }

    final List<PieChartSectionData> sections = [];
    final colors = [
      Colors.blue.shade400,
      Colors.green.shade400,
      Colors.orange.shade400,
      Colors.purple.shade400,
      Colors.red.shade400,
      Colors.teal.shade400,
      Colors.indigo.shade400,
      Colors.cyan.shade400,
    ];

    int colorIndex = 0;
    for (int i = 0; i < fees.length; i++) {
      final f0 = fees[i];
      if (f0 is! Map) continue;
      final f = Map<String, dynamic>.from(f0);

      final val = _num(f['effectiveFeeDue']);
      if (val <= 0) continue;

      final title = (f['fee_heading'] ?? '').toString();
      final color = colors[colorIndex % colors.length];
      colorIndex++;

      sections.add(
        PieChartSectionData(
          value: val,
          color: color,
          title:
              '${title.length > 14 ? title.substring(0, 14) : title}\n${NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹').format(val)}',
          radius: 74,
          titleStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );
    }

    if (sections.isEmpty) {
      return const SizedBox(
          height: 220, child: Center(child: Text('No positive values')));
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 320,
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 46,
              sectionsSpace: 4,
              pieTouchData: PieTouchData(enabled: true),
            ),
          ),
        ),
      ),
    );
  }

  List<PieChartSectionData> _makePieSections(Map<String, double> totals) {
    final vals = [
      totals['due'] ?? 0,
      totals['received'] ?? 0,
      totals['concession'] ?? 0,
      totals['fineRemaining'] ?? 0,
      totals['vanDue'] ?? 0,
    ];
    final colors = [
      Colors.red.shade400,
      Colors.blue.shade400,
      Colors.amber.shade600,
      Colors.orange.shade500,
      Colors.green.shade400,
    ];

    final List<PieChartSectionData> list = [];
    for (int i = 0; i < vals.length; i++) {
      final v = vals[i];
      if (v <= 0) {
        list.add(PieChartSectionData(
          value: 0.0001,
          color: colors[i],
          showTitle: false,
          radius: 40,
        ));
      } else {
        list.add(
          PieChartSectionData(
            value: v,
            color: colors[i],
            title: formatINR(v),
            radius: 52,
            titleStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        );
      }
    }
    return list;
  }

  List<Map<String, dynamic>> _kpiItemsForTotals(Map<String, double> totals) {
    final payable = _calcPayableSummary();
    return [
      {'title': 'Total Payable', 'value': formatINR(payable['totalPayable'] ?? 0)},
      {'title': 'Academic Due', 'value': formatINR(payable['academicDue'] ?? 0)},
      {'title': 'Fine Due', 'value': formatINR(payable['fineDue'] ?? 0)},
      {'title': 'Transport Due', 'value': formatINR(payable['vanDue'] ?? 0)},
      {'title': 'Previous Balance', 'value': formatINR(payable['prevBalanceDue'] ?? 0)},
      {'title': 'Received', 'value': formatINR(totals['received'] ?? 0)},
    ];
  }

  /* =========================================================
    Auto-scroll
  ========================================================= */

  void _startChipAutoScroll() {
    _chipTimer?.cancel();
    _chipTimer = Timer.periodic(_chipInterval, (_) async {
      try {
        if (!mounted) return;
        if (!_chipScrollController.hasClients) return;
        if (_chipScrollController.positions.isEmpty) return;

        final max = _chipScrollController.position.maxScrollExtent;
        final current = _chipScrollController.offset;
        if (max <= 0) return;

        final next = current + _chipScrollStep;

        if (next >= max) {
          await _chipScrollController.animateTo(
            max,
            duration: _chipAnim,
            curve: Curves.easeInOut,
          );
          await Future.delayed(const Duration(milliseconds: 250));
          if (!mounted) return;
          if (!_chipScrollController.hasClients) return;
          await _chipScrollController.animateTo(
            0,
            duration: _chipAnim,
            curve: Curves.easeInOut,
          );
        } else {
          await _chipScrollController.animateTo(
            next,
            duration: _chipAnim,
            curve: Curves.easeInOut,
          );
        }
      } catch (e) {
        debugPrint('chip auto-scroll ignored error: $e');
      }
    });
  }

  void _startKpiPageAutoScroll() {
    _kpiPageTimer?.cancel();
    _kpiPageTimer = Timer.periodic(_kpiPageInterval, (_) {
      try {
        final controller = _kpiPageController;
        if (controller == null || !controller.hasClients) return;

        final itemCount = _kpiItemsForTotals(_calcTotals()).length;
        if (itemCount == 0) return;

        _kpiPage = (_kpiPage + 1) % itemCount;
        controller.animateToPage(
          _kpiPage,
          duration: _kpiPageAnim,
          curve: Curves.easeInOut,
        );
      } catch (e) {
        debugPrint('kpi page auto-scroll ignored: $e');
      }
    });
  }

  /* =========================================================
    UI Widgets
  ========================================================= */

  PreferredSizeWidget _gradientAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      title: const Text('Fees', style: TextStyle(fontWeight: FontWeight.w900)),
      centerTitle: false,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_indigo, _cyan, _emerald],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => _loadFamilyAndActive(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  Widget _hero() {
    final sd = studentDetails ?? {};
    final totals = _calcTotals();
    final payable = _calcPayableSummary();
    final transportEnabled = _transportEnabled();
    final kpiItems = _kpiItemsForTotals(totals);

    final totalPayable = payable['totalPayable'] ?? 0.0;
    final vanDue = payable['vanDue'] ?? 0.0;
    final prevDue = payable['prevBalanceDue'] ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_indigo, _cyan, _emerald],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.24)),
                ),
                child: const Icon(Icons.school_rounded,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fees overview',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.88),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (sd['name'] ?? 'Student').toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 21,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _softBadge('Adm', sd['admissionNumber'] ?? activeAdmission),
                        if (sd['class_name'] != null)
                          _softBadge('Class', sd['class_name']),
                        if (sd['section_name'] != null)
                          _softBadge('Sec', sd['section_name']),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (canSeeStudentSwitcher && (siblingsLoading || studentsList.isNotEmpty)) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.14),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.20)),
              ),
              child: siblingsLoading
                  ? const SizedBox(
                      height: 48,
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.3,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: studentsList.map((s) {
                          final admRaw =
                              (_stringValue(s['admission_number']) ?? '').trim();
                          final isActive = admRaw == activeAdmission;
                          final label = _studentSwitcherLabel(s);

                          return Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: InkWell(
                              onTap: admRaw.isEmpty
                                  ? null
                                  : () => handleStudentSwitch(admRaw),
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: isActive
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.20),
                                  ),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isActive
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color:
                                        isActive ? Colors.black87 : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ],

          const SizedBox(height: 16),
          _payableHighlightCard(totalPayable, payable),
          const SizedBox(height: 14),

          SizedBox(
            height: 56,
            child: ListView(
              controller: _chipScrollController,
              scrollDirection: Axis.horizontal,
              children: [
                const SizedBox(width: 6),
                _chipRowItem(
                  Icons.receipt_long_rounded,
                  'Academic Due',
                  formatINR(payable['academicDue'] ?? 0),
                  Colors.white.withOpacity(0.16),
                ),
                const SizedBox(width: 8),
                _chipRowItem(
                  Icons.warning_amber_rounded,
                  'Fine Due',
                  formatINR(payable['fineDue'] ?? 0),
                  Colors.white.withOpacity(0.16),
                ),
                const SizedBox(width: 8),
                if (transportEnabled)
                  _chipRowItem(
                    Icons.local_shipping,
                    'Transport Due',
                    formatINR(vanDue),
                    Colors.white.withOpacity(0.18),
                    valueColor: vanDue > 0 ? Colors.yellowAccent : Colors.white,
                  ),
                if (transportEnabled) const SizedBox(width: 8),
                _chipRowItem(
                  Icons.account_balance_wallet_outlined,
                  'Previous Balance',
                  formatINR(prevDue),
                  Colors.white.withOpacity(0.22),
                  valueColor: prevDue > 0 ? Colors.yellowAccent : Colors.white,
                ),
                const SizedBox(width: 10),
              ],
            ),
          ),

          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: prevDue > 0 ? handlePayPreviousBalanceOnly : null,
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('Pay Prev. Balance'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _slate,
                    disabledBackgroundColor: Colors.white.withOpacity(0.22),
                    disabledForegroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              if (transportEnabled) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (vanDue + prevDue) > 0 ? handlePayVanFee : null,
                    icon: const Icon(Icons.credit_card),
                    label: const Text('Pay Van / OB'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _slate,
                      disabledBackgroundColor: Colors.white.withOpacity(0.22),
                      disabledForegroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 14),
          SizedBox(
            height: 108,
            child: Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _kpiPageController,
                    itemCount: kpiItems.length,
                    onPageChanged: (p) => setState(() => _kpiPage = p),
                    itemBuilder: (context, i) {
                      final it = kpiItems[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: _kpiCardWrapped(
                          (it['title'] ?? '').toString(),
                          (it['value'] ?? '').toString(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(kpiItems.length, (i) {
                    final active = i == _kpiPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 18 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white
                            : Colors.white.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _payableHighlightCard(
      double totalPayable, Map<String, double> payable) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Outstanding Amount',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formatINR(totalPayable),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: totalPayable > 0 ? _slate : Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            totalPayable > 0
                ? 'Includes academic, fine, transport and previous balance.'
                : 'All dues cleared.',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _miniInfoTile(
                    'Academic', formatINR(payable['academicDue'] ?? 0)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child:
                    _miniInfoTile('Fine', formatINR(payable['fineDue'] ?? 0)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _miniInfoTile(
                    'Transport', formatINR(payable['vanDue'] ?? 0)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _miniInfoTile(
                    'Previous Bal.', formatINR(payable['prevBalanceDue'] ?? 0)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniInfoTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _softBadge(String label, dynamic value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Flexible(
            child: Text(
              '$value',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipRowItem(
    IconData icon,
    String label,
    String value,
    Color bg, {
    Color valueColor = Colors.white,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w900, color: valueColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiCardWrapped(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white70,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /* =========================================================
    Fee Cards
  ========================================================= */

  Widget _feeCardsGrid() {
    final fees = (studentDetails?['feeDetails'] as List?) ?? [];
    final hasPrevBalance = _prevBalanceDue > 0;

    if (fees.isEmpty && !hasPrevBalance) {
      return const Center(child: Text('No fee details available.'));
    }

    return Column(
      children: [
        if (hasPrevBalance) ...[
          _previousBalanceFeeCard(),
          const SizedBox(height: 12),
        ],
        if (fees.isNotEmpty)
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: fees.length,
            itemBuilder: (context, idx) {
              final fee = Map<String, dynamic>.from(fees[idx]);
              final t = getTransportBreakdown(fee);

              final academicDue = _num(fee['finalAmountDue']);
              final fineDue = _feeFineDue(fee);
              final totalInclVanFine = academicDue + fineDue + _num(t?['pending']);

              final received = _num(fee['totalFeeReceived']);
              final concession = _num(fee['totalConcessionReceived']);
              final effective = _num(fee['effectiveFeeDue']);

              final paidPct =
                  effective > 0 ? ((received + concession) / effective) * 100 : 0.0;

              final vanPaidPct = (t != null && _num(t['cost']) > 0)
                  ? ((_num(t['received']) + _num(t['concession'])) /
                          (_num(t['cost'])) *
                          100.0)
                  : 0.0;

              final prev = _computePreviousSlabsTotals(idx);
              final prevCount = (prev['count'] as int?) ?? 0;
              final isExpanded = _expandedFees.length > idx ? _expandedFees[idx] : false;

              final canPay = (academicDue > 0) ||
                  (fineDue > 0) ||
                  (_num(t?['pending']) > 0) ||
                  (prevCount > 0) ||
                  (_prevBalanceDue > 0);

              return Card(
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    InkWell(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(16)),
                      onTap: () {
                        setState(() {
                          if (_expandedFees.length > idx) {
                            _expandedFees[idx] = !_expandedFees[idx];
                          }
                        });
                      },
                      child: Container(
                        width: double.infinity,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.indigo.shade50, Colors.cyan.shade50],
                          ),
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                (fee['fee_heading'] ?? 'Fee').toString(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                            const SizedBox(width: 10),
                            if (academicDue + fineDue > 0)
                              _pill('Due', formatINR(academicDue + fineDue),
                                  bg: Colors.red.shade50, fg: Colors.red.shade700)
                            else
                              _pill('Clear', '0',
                                  bg: Colors.green.shade50,
                                  fg: Colors.green.shade700),
                            const SizedBox(width: 8),
                            Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                          ],
                        ),
                      ),
                    ),
                    if (isExpanded)
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _smallRow('Original', formatINR(fee['originalFeeDue'] ?? 0)),
                            _smallRow('Effective', formatINR(fee['effectiveFeeDue'] ?? 0)),
                            _smallRow('Received', formatINR(received)),
                            _smallRow('Concession', formatINR(concession)),
                            _smallRow('Fine (remaining)', formatINR(fineDue)),
                            const SizedBox(height: 8),
                            _progressRow(
                              label: 'Academic Paid',
                              percent: paidPct.toDouble(),
                              color: Colors.blue,
                            ),
                            if (prevCount > 0) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.orange.shade200),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Previous heads pending',
                                      style: TextStyle(fontWeight: FontWeight.w900),
                                    ),
                                    const SizedBox(height: 6),
                                    _tinyRow('Heads Count', '$prevCount'),
                                    _tinyRow('Prev Academic', formatINR(prev['totalAcademic'])),
                                    _tinyRow('Prev Fine', formatINR(prev['totalFine'])),
                                    _tinyRow('Prev Transport', formatINR(prev['totalVan'])),
                                  ],
                                ),
                              ),
                            ],
                            if (t != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: Colors.blue.shade50,
                                  border: Border.all(color: Colors.blue.shade100),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.local_shipping, size: 16),
                                        const SizedBox(width: 8),
                                        const Expanded(
                                          child: Text('Transport',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w900)),
                                        ),
                                        Text(
                                          formatINR(t['pending'] ?? 0),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: _num(t['pending']) > 0
                                                ? Colors.red
                                                : Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    _tinyRow('Due (Head)', formatINR(t['due'] ?? 0)),
                                    _tinyRow('Received (Head)', formatINR(t['received'] ?? 0)),
                                    _tinyRow('Concession (Head)', formatINR(t['concession'] ?? 0)),
                                    _tinyRow(
                                      'Pending (Head)',
                                      formatINR(t['pending'] ?? 0),
                                      valueIsDanger: _num(t['pending']) > 0,
                                    ),
                                    const SizedBox(height: 8),
                                    _progressRow(
                                      label: 'Transport Paid',
                                      percent: vanPaidPct.toDouble(),
                                      color: Colors.teal,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: Colors.grey.shade50,
                                border: Border.all(color: Colors.black12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _smallRow('Academic Due', formatINR(academicDue)),
                                  _smallRow('Fine Due', formatINR(fineDue)),
                                  if (t != null)
                                    _smallRow(
                                        'Transport Pending', formatINR(t['pending'] ?? 0)),
                                  const Divider(height: 18),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        t != null
                                            ? 'Total Due (incl. Fine + Transport)'
                                            : 'Total Due (incl. Fine)',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900),
                                      ),
                                      Text(
                                        formatINR(totalInclVanFine),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: totalInclVanFine > 0
                                              ? Colors.red
                                              : Colors.green,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: canPay ? () => handlePayFee(fee, idx) : null,
                                icon: const Icon(Icons.credit_card),
                                label: Text(
                                  canPay
                                      ? 'Pay (Acad + Fine${t != null ? ' + TR' : ''}${prevCount > 0 ? ' + Prev Heads' : ''}${_prevBalanceDue > 0 ? ' + OB' : ''})'
                                      : 'Paid',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: canPay ? _indigo : Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _previousBalanceFeeCard() {
    final isExpanded = _expandedPrevBalance;
    final canPay = _prevBalanceDue > 0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            onTap: () => setState(() => _expandedPrevBalance = !_expandedPrevBalance),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange.shade50, Colors.red.shade50],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Previous Balance',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (canPay)
                    _pill('Due', formatINR(_prevBalanceDue),
                        bg: Colors.red.shade50, fg: Colors.red.shade700)
                  else
                    _pill('Clear', '0',
                        bg: Colors.green.shade50, fg: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _smallRow('Outstanding', formatINR(_prevBalanceDue)),
                  if (_activeSessionId != null)
                    _smallRow('Active Session', _activeSessionId.toString()),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.orange.shade100),
                    ),
                    child: const Text(
                      'This is the carry-forward balance from previous dues and is now shown as the first fee heading.',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: Colors.grey.shade50,
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _smallRow('Previous Balance Due', formatINR(_prevBalanceDue)),
                        const Divider(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total Due',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              formatINR(_prevBalanceDue),
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: canPay ? Colors.red : Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: canPay ? handlePayPreviousBalanceOnly : null,
                      icon: const Icon(Icons.credit_card),
                      label: Text(canPay ? 'Pay Previous Balance' : 'Paid'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canPay ? _indigo : Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _pill(String title, String value,
      {required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Text('$title ',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
          Text(value,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w900, color: fg)),
        ],
      ),
    );
  }

  Widget _progressRow(
      {required String label,
      required double percent,
      required Color color}) {
    final p = percent.clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$label ${p.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            Text(p >= 99.9 ? '✅' : '', style: const TextStyle(fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (p / 100),
              minHeight: 9,
              color: color,
              backgroundColor: Colors.black.withOpacity(0.06),
            ),
          ),
        ),
      ],
    );
  }

  Widget _smallRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tinyRow(String label, String value, {bool valueIsDanger = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: valueIsDanger ? Colors.red : Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  /* =========================================================
    Summary Pie + History
  ========================================================= */

  Widget _overallPie() {
    final totals = _calcTotals();
    final sections = _makePieSections(totals);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 320,
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 46,
              sectionsSpace: 2,
              pieTouchData: PieTouchData(enabled: true),
            ),
          ),
        ),
      ),
    );
  }

  String _extractFeeHeading(Map<String, dynamic> txn) {
    final fh = txn['FeeHeading'];
    if (fh is Map) {
      final name = fh['fee_heading'] ?? fh['FeeHeading'] ?? fh['name'];
      if (name != null) return name.toString();
    }
    final direct = txn['FeeHeading'] ?? txn['fee_heading'] ?? txn['feeHeading'];
    if (direct != null) return direct.toString();
    return 'N/A';
  }

  DateTime? _extractTxnDate(Map<String, dynamic> txn) {
    final raw =
        txn['createdAt'] ?? txn['created_at'] ?? txn['date'] ?? txn['Date'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  String _extractPaymentMode(Map<String, dynamic> txn) {
    final m = txn['PaymentMode'] ?? txn['paymentMode'] ?? txn['mode'];
    return _safeStr(m);
  }

  String _extractOrderId(Map<String, dynamic> txn) {
    final v = txn['Order_ID'] ??
        txn['order_id'] ??
        txn['vendorOrderId'] ??
        txn['orderId'];
    return _safeStr(v);
  }

  String _extractTxnId(Map<String, dynamic> txn) {
    final v = txn['Transaction_ID'] ??
        txn['transaction_id'] ??
        txn['txnId'] ??
        txn['transactionId'];
    return _safeStr(v);
  }

  String _extractSerial(Map<String, dynamic> txn) {
    final v = txn['Serial'] ?? txn['serial'];
    return _safeStr(v);
  }

  String _extractSlipId(Map<String, dynamic> txn) {
    final v = txn['Slip_ID'] ?? txn['slip_id'] ?? txn['slipId'];
    return _safeStr(v);
  }

  Widget _historyTable() {
    final rows = transactionHistory;
    if (rows.isEmpty) {
      return const Center(child: Text('No transaction history available.'));
    }

    final list = List<Map<String, dynamic>>.from(
      rows.map((e) => Map<String, dynamic>.from(e)),
    );

    list.sort((a, b) {
      final ad = _extractTxnDate(a);
      final bd = _extractTxnDate(b);
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final txn in list) {
      final dt = _extractTxnDate(txn);
      final key = dt != null ? DateFormat('MMMM yyyy').format(dt) : 'Unknown Date';
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(txn);
    }

    final groupKeys = grouped.keys.toList();
    groupKeys.sort((a, b) {
      DateTime? ad, bd;
      final la = grouped[a];
      final lb = grouped[b];
      if (la != null && la.isNotEmpty) ad = _extractTxnDate(la.first);
      if (lb != null && lb.isNotEmpty) bd = _extractTxnDate(lb.first);
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: const [
                Icon(Icons.history, size: 18),
                SizedBox(width: 8),
                Text('History',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 10),
            Column(
              children: groupKeys.map((gk) {
                final items = grouped[gk] ?? [];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          gk,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Column(
                        children: items.map((txn) {
                          final feeHeading = _extractFeeHeading(txn);
                          final dt = _extractTxnDate(txn);
                          final dtStr = (dt != null)
                              ? DateFormat('dd MMM yyyy, hh:mm a').format(dt)
                              : (_safeStr(txn['createdAt']).isEmpty
                                  ? '—'
                                  : _safeStr(txn['createdAt']));

                          final paymentMode = _extractPaymentMode(txn);
                          final orderId = _extractOrderId(txn);
                          final txnId = _extractTxnId(txn);
                          final serial = _extractSerial(txn);
                          final slipId = _extractSlipId(txn);

                          final fee = formatINR(txn['Fee_Recieved'] ?? 0);
                          final conc = formatINR(txn['Concession'] ?? 0);
                          final fine = formatINR(_txnFine(txn));
                          final van = formatINR(txn['VanFee'] ?? 0);

                          final isOnline = paymentMode.toUpperCase() == 'ONLINE';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: isOnline
                                              ? const [_indigo, _cyan]
                                              : [
                                                  Colors.grey.shade600,
                                                  Colors.grey.shade400,
                                                ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(Icons.payments,
                                          color: Colors.white),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            feeHeading,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w900),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Paid on: $dtStr',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: isOnline
                                            ? Colors.blue.shade50
                                            : Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(
                                            color:
                                                Colors.black.withOpacity(0.06)),
                                      ),
                                      child: Text(
                                        paymentMode.isEmpty ? '—' : paymentMode,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                        child:
                                            _miniKV('Serial', serial.isEmpty ? '—' : serial)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: _miniKV(
                                            'Slip ID', slipId.isEmpty ? '—' : slipId)),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _amountChip('Fee', fee),
                                    _amountChip('Concession', conc),
                                    _amountChip('Fine', fine),
                                    _amountChip('Van', van),
                                  ],
                                ),
                                if (orderId.isNotEmpty || txnId.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  if (orderId.isNotEmpty)
                                    _miniKV('Order ID', orderId),
                                  if (txnId.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _miniKV('Transaction ID', txnId),
                                  ],
                                ],
                                if (slipId.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: (_slipDownloading[slipId] ?? false)
                                              ? null
                                              : () => _openSlip(slipId),
                                          icon: (_slipDownloading[slipId] ?? false)
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              : const Icon(Icons.open_in_new),
                                          label: const Text('Open Slip'),
                                          style: OutlinedButton.styleFrom(
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: (_slipDownloading[slipId] ?? false)
                                              ? null
                                              : () => _downloadSlipToDevice(slipId),
                                          icon: const Icon(Icons.download_rounded),
                                          label: const Text('Download Slip'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _indigo,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniKV(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _amountChip(String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87),
          children: [
            TextSpan(
              text: '$title: ',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  /* =========================================================
    Tabs Card
  ========================================================= */

  Widget _tabsCard() {
    final totals = _calcTotals();
    final transportEnabled = _transportEnabled();
    final payable = _calcPayableSummary();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(999),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.black87,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(colors: [_indigo, _emerald]),
                ),
                onTap: (_) => setState(() {}),
                tabs: const [
                  Tab(text: 'Fee Details'),
                  Tab(text: 'Summary'),
                  Tab(text: 'History'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (error != null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'Failed to load data',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              )
            else
              IndexedStack(
                index: _tabController.index,
                children: [
                  Column(
                    children: [
                      _feeCardsGrid(),
                      const SizedBox(height: 12),
                      _feeHeadsPieChart(),
                    ],
                  ),
                  Column(
                    children: [
                      _overallPie(),
                      const SizedBox(height: 12),
                      Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            children: [
                              _sectionTitle('Overview Summary'),
                              const SizedBox(height: 12),
                              _sumRow('Original Fee', formatINR(totals['original'] ?? 0)),
                              const Divider(),
                              _sumRow('Effective Fee', formatINR(totals['effective'] ?? 0)),
                              const Divider(),
                              _sumRow('Total Received', formatINR(totals['received'] ?? 0)),
                              const Divider(),
                              _sumRow('Total Concession', formatINR(totals['concession'] ?? 0)),
                              const Divider(),
                              _sumRow('Academic Due', formatINR(payable['academicDue'] ?? 0)),
                              const Divider(),
                              _sumRow('Fine Due', formatINR(payable['fineDue'] ?? 0)),
                              const Divider(),
                              _sumRow('Previous Balance', formatINR(payable['prevBalanceDue'] ?? 0),
                                  valueColor: (payable['prevBalanceDue'] ?? 0) > 0
                                      ? Colors.red
                                      : Colors.green),
                              if (transportEnabled) ...[
                                const Divider(),
                                _sumRow('Van Received', formatINR(totals['vanReceived'] ?? 0)),
                                const Divider(),
                                _sumRow('Transport Due', formatINR(payable['vanDue'] ?? 0),
                                    valueColor: (payable['vanDue'] ?? 0) > 0
                                        ? Colors.red
                                        : Colors.green),
                              ],
                              const Divider(),
                              _sumRowBold(
                                'Total Payable',
                                formatINR(payable['totalPayable'] ?? 0),
                                valueColor: (payable['totalPayable'] ?? 0) > 0
                                    ? _slate
                                    : Colors.green,
                              ),
                              const SizedBox(height: 14),
                              if (transportEnabled) ...[
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: ((totals['vanDue'] ?? 0) +
                                                (totals['prevBalanceDue'] ?? 0)) >
                                            0
                                        ? handlePayVanFee
                                        : null,
                                    icon: const Icon(Icons.credit_card),
                                    label: Text((totals['prevBalanceDue'] ?? 0) > 0
                                        ? 'Pay Van Fee (incl. OB)'
                                        : 'Pay Van Fee'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _emerald,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14)),
                                      padding:
                                          const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  _historyTable(),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: _indigo,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }

  Widget _sumRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sumRowBold(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }

  /* =========================================================
    Build
  ========================================================= */

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (Platform.isAndroid) {
          try {
            final res = await _hyperSDK.onBackPress();
            return res.toString().toLowerCase() != 'true';
          } catch (_) {
            return true;
          }
        }
        return true;
      },
      child: Scaffold(
        appBar: _gradientAppBar(),
        backgroundColor: _softBg,
        body: RefreshIndicator(
          onRefresh: () async => _loadFamilyAndActive(),
          color: _indigo,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _hero(),
                const SizedBox(height: 16),
                _tabsCard(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}