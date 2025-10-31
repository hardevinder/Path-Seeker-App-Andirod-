// lib/screens/student_fee_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../constants/constants.dart'; // baseUrl, etc.

Map<String, dynamic>? parseJwt(String token) {
  try {
    List<String> parts = token.split('.');
    if (parts.length != 3) {
      return null;
    }
    String payload = parts[1];
    // Add padding
    while (payload.length % 4 != 0) {
      payload += '=';
    }
    // Replace url-safe
    payload = payload.replaceAll('-', '+').replaceAll('_', '/');
    String jsonString = utf8.decode(base64Url.decode(payload));
    return json.decode(jsonString);
  } catch (e) {
    debugPrint('parseJwt error: $e');
    return null;
  }
}

String normalizeRole(String r) => r.toLowerCase().trim();

String normalizeAdmission(String s) => s.replaceAll('/', '-').trim();

class StudentFeeScreen extends StatefulWidget {
  const StudentFeeScreen({super.key});

  @override
  State<StudentFeeScreen> createState() => _StudentFeeScreenState();
}

class _StudentFeeScreenState extends State<StudentFeeScreen> with SingleTickerProviderStateMixin {
  bool loading = true;
  String? error;

  Map<String, dynamic>? studentDetails;
  List<dynamic> transactionHistory = [];
  Map<int, Map<String, dynamic>> vanByHead = {};
  List<bool> _expandedFees = [];

  late TabController _tabController;
  Timer? _pollTimer;

  // auto scroll chips
  final ScrollController _chipScrollController = ScrollController();
  Timer? _chipTimer;
  final double _chipScrollStep = 160.0;
  final Duration _chipInterval = const Duration(seconds: 3);
  final Duration _chipAnim = const Duration(milliseconds: 600);

  // KPI PageView auto-scroll
  PageController? _kpiPageController;
  Timer? _kpiPageTimer;
  int _kpiPage = 0;
  final Duration _kpiPageInterval = const Duration(seconds: 4);
  final Duration _kpiPageAnim = const Duration(milliseconds: 500);

  // Student switcher
  Map<String, dynamic>? family;
  String activeAdmission = '';
  List<Map<String, dynamic>> studentsList = [];
  List<String> _roles = [];
  bool canSeeStudentSwitcher = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    _kpiPageController = PageController(viewportFraction: 0.72);

    _loadFamilyAndActive();

    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _loadPartial();
    });

    // start auto-scrolls after first frame, but we also verify controllers have clients before using positions
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startChipAutoScroll();
      _startKpiPageAutoScroll();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pollTimer?.cancel();
    _chipTimer?.cancel();
    _chipScrollController.dispose();
    _kpiPageTimer?.cancel();
    _kpiPageController?.dispose();
    super.dispose();
  }

  Future<String> _getActiveAdmission() async {
    final prefs = await SharedPreferences.getInstance();
    String? storedActive = prefs.getString('activeStudentAdmission');
    if (storedActive != null) return normalizeAdmission(storedActive);
    String? stored = prefs.getString('username') ?? prefs.getString('admissionNumber');
    if (stored != null) return normalizeAdmission(stored);
    final token = prefs.getString('authToken') ?? prefs.getString('token');
    if (token != null) {
      final payload = parseJwt(token);
      final adm = payload?['admission_number'] ?? payload?['username'];
      if (adm != null) return normalizeAdmission(adm.toString());
    }
    return '';
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authToken') ?? prefs.getString('token');
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
    studentsList = <Map<String, dynamic>>[];
    if (family?['student'] != null) {
      var self = Map<String, dynamic>.from(family!['student']);
      self['isSelf'] = true;
      studentsList.add(self);
    }
    final siblingsList = family?['siblings'] as List? ?? [];
    for (var s in siblingsList) {
      var sib = Map<String, dynamic>.from(s);
      sib['isSelf'] = false;
      studentsList.add(sib);
    }
    await _loadRoles();
    if (mounted) {
      setState(() {});
    }
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
    String? stored = prefs.getString('roles');
    if (stored != null) {
      try {
        final list = json.decode(stored) as List;
        _roles = list.map((r) => normalizeRole(r.toString())).toList();
      } catch (e) {
        debugPrint('Failed to parse roles: $e');
      }
    }
    if (_roles.isEmpty) {
      String? single = prefs.getString('userRole');
      if (single != null) _roles = [normalizeRole(single)];
    }
    if (_roles.isEmpty) {
      final tokenStr = prefs.getString('authToken') ?? prefs.getString('token');
      if (tokenStr != null) {
        final payload = parseJwt(tokenStr);
        if (payload != null) {
          if (payload['roles'] is List) {
            _roles = (payload['roles'] as List).map((r) => normalizeRole(r.toString())).toList();
          } else if (payload['role'] != null) {
            _roles = [normalizeRole(payload['role'].toString())];
          }
        }
      }
    }
    canSeeStudentSwitcher = _roles.any((r) => r == 'student' || r == 'parent');
  }

  Future<void> _loadAllForAdmission(String admission, String token) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await Future.wait([
        _fetchStudentDetails(admission, token),
        _fetchTransactionHistory(admission, token),
        _fetchVanFeeByHead(token),
      ]);
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
        _fetchVanFeeByHead(token),
      ]);
    } catch (e) {
      debugPrint('partial refresh failed: $e');
    }
  }

  Future<void> _fetchStudentDetails(String admissionNumber, String token) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/StudentsApp/admission/$admissionNumber/fees'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            if (json is Map && json.containsKey('data')) {
              studentDetails = Map<String, dynamic>.from(json['data']);
            } else if (json is Map) {
              studentDetails = Map<String, dynamic>.from(json);
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

  Future<void> _fetchTransactionHistory(String admissionNumber, String token) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/StudentsApp/feehistory/$admissionNumber'), headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (mounted) {
          if (json is Map && json['success'] == true && json['data'] is List) {
            setState(() => transactionHistory = List<dynamic>.from(json['data']));
          } else if (json is List) {
            setState(() => transactionHistory = List<dynamic>.from(json));
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

  Future<void> _fetchVanFeeByHead(String token) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/transactions/vanfee/me'), headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        List rows = [];
        if (json is Map && json['data'] is List) rows = List.from(json['data']);
        else if (json is List) rows = List.from(json);
        final Map<int, Map<String, dynamic>> map = {};
        for (final r in rows) {
          final id = int.tryParse((r['Fee_Head'] ?? '').toString()) ?? (r['Fee_Head'] is int ? r['Fee_Head'] : null);
          if (id == null) continue;
          map[id] = {
            'transportCost': (r['TransportCost'] ?? 0).toDouble(),
            'totalVanFeeReceived': (r['TotalVanFeeReceived'] ?? 0).toDouble(),
            'totalVanFeeConcession': (r['TotalVanFeeConcession'] ?? 0).toDouble(),
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

  Future<void> handleStudentSwitch(String newAdmission) async {
    final norm = normalizeAdmission(newAdmission);
    if (norm == activeAdmission) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('activeStudentAdmission', norm);
    if (mounted) {
      setState(() {
        activeAdmission = norm;
      });
    }
    final token = await _getToken();
    if (token != null && mounted) {
      await _loadAllForAdmission(norm, token);
    }
  }

  // Auto-scroll chip row — robust checks
  void _startChipAutoScroll() {
    _chipTimer?.cancel();
    _chipTimer = Timer.periodic(_chipInterval, (_) async {
      try {
        if (!_chipScrollController.hasClients) return;
        if (_chipScrollController.positions.isEmpty) return;
        final max = _chipScrollController.position.maxScrollExtent;
        final current = _chipScrollController.offset;
        double next = current + _chipScrollStep;
        if (next >= max) {
          await _chipScrollController.animateTo(max, duration: _chipAnim, curve: Curves.easeInOut);
          await Future.delayed(const Duration(milliseconds: 250));
          if (!_chipScrollController.hasClients) return;
          await _chipScrollController.animateTo(0, duration: _chipAnim, curve: Curves.easeInOut);
        } else {
          await _chipScrollController.animateTo(next, duration: _chipAnim, curve: Curves.easeInOut);
        }
      } catch (e) {
        debugPrint('chip auto-scroll ignored error: $e');
      }
    });
  }

  // KPI PageView auto-scroll (one page at a time). Start only when controller has clients.
  void _startKpiPageAutoScroll() {
    _kpiPageTimer?.cancel();
    _kpiPageTimer = Timer.periodic(_kpiPageInterval, (_) {
      try {
        final controller = _kpiPageController;
        if (controller == null) return;
        if (!controller.hasClients) {
          // attempt to delay start until it has clients
          return;
        }
        final itemCount = _kpiItemsForTotals(_calcTotals()).length;
        if (itemCount == 0) return;
        _kpiPage = (_kpiPage + 1) % itemCount;
        controller.animateToPage(_kpiPage, duration: _kpiPageAnim, curve: Curves.easeInOut);
        if (mounted) setState(() {});
      } catch (e) {
        debugPrint('kpi page auto-scroll ignored: $e');
      }
    });
  }

  // Helpers
  String formatINR(dynamic v) {
    final n = (v == null) ? 0.0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);
    final f = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    return f.format(n);
  }

  Map<String, dynamic>? getVanForHeadFromMap(dynamic feeHeadId) {
    if (feeHeadId == null) return null;
    final id = int.tryParse(feeHeadId.toString()) ?? (feeHeadId is int ? feeHeadId : null);
    if (id == null) return null;
    final v = vanByHead[id];
    if (v == null) return null;
    final cost = (v['transportCost'] ?? 0.0).toDouble();
    final received = (v['totalVanFeeReceived'] ?? 0.0).toDouble();
    final concession = (v['totalVanFeeConcession'] ?? 0.0).toDouble();
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

  Map<String, dynamic>? getTransportBreakdown(dynamic fee) {
    if (fee == null) return null;
    try {
      if (fee is Map && fee['transportApplicable'] == true && fee['transport'] != null) {
        final t = Map<String, dynamic>.from(fee['transport']);
        final cost = (t['transportDue'] ?? 0) + (t['transportReceived'] ?? 0) + (t['transportConcession'] ?? 0);
        return {
          'cost': cost.toDouble(),
          'due': (t['transportDue'] ?? 0).toDouble(),
          'received': (t['transportReceived'] ?? 0).toDouble(),
          'concession': (t['transportConcession'] ?? 0).toDouble(),
          'pending': (t['transportPending'] ?? 0).toDouble(),
          'source': 'api',
        };
      }
      return getVanForHeadFromMap(fee['fee_heading_id'] ?? fee['feeHeadId']);
    } catch (e) {
      return getVanForHeadFromMap((fee is Map) ? fee['fee_heading_id'] : null);
    }
  }

  Future<void> handlePayFee(Map<String, dynamic> fee) async {
    final due = double.tryParse((fee['finalAmountDue'] ?? '0').toString()) ?? 0.0;
    if (due <= 0) {
      _showSnack('No due amount to pay');
      return;
    }
    _showSnack('Initiate payment for ${formatINR(due)} (implement SDK)');
  }

  Future<void> handlePayVanFee() async {
    final van = studentDetails?['vanFee'] ?? {};
    final vanCost = (van['perHeadTotalDue'] ?? van['transportCost'] ?? 0).toDouble();
    final received = (van['totalVanFeeReceived'] ?? 0).toDouble();
    final concession = (van['totalVanFeeConcession'] ?? 0).toDouble();
    final due = (vanCost - (received + concession)).clamp(0, double.infinity);
    if (due <= 0) {
      _showSnack('No van fee due');
      return;
    }
    _showSnack('Initiate van fee payment: ${formatINR(due)} (implement SDK)');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Map<String, double> _calcTotals() {
    double totalOriginal = 0, totalEffective = 0, totalDue = 0, totalReceived = 0, totalConcession = 0;
    final fees = (studentDetails?['feeDetails'] as List?) ?? [];
    for (final f in fees) {
      totalOriginal += (double.tryParse((f['originalFeeDue'] ?? 0).toString()) ?? 0);
      totalEffective += (double.tryParse((f['effectiveFeeDue'] ?? 0).toString()) ?? 0);
      totalDue += (double.tryParse((f['finalAmountDue'] ?? 0).toString()) ?? 0);
      totalReceived += (double.tryParse((f['totalFeeReceived'] ?? 0).toString()) ?? 0);
      totalConcession += (double.tryParse((f['totalConcessionReceived'] ?? 0).toString()) ?? 0);
    }
    final van = studentDetails?['vanFee'] ?? {};
    final vanCost = (double.tryParse((van['perHeadTotalDue'] ?? van['transportCost'] ?? 0).toString()) ?? 0);
    final vanReceived = (double.tryParse((van['totalVanFeeReceived'] ?? 0).toString()) ?? 0);
    final vanConcession = (double.tryParse((van['totalVanFeeConcession'] ?? 0).toString()) ?? 0);

    return {
      'original': totalOriginal,
      'effective': totalEffective,
      'due': totalDue,
      'received': totalReceived,
      'concession': totalConcession,
      'vanCost': vanCost,
      'vanReceived': vanReceived,
      'vanConcession': vanConcession,
      'vanDue': (vanCost - (vanReceived + vanConcession)).clamp(0, double.infinity),
    };
  }

  // Pie chart for fee heads (replaces bar chart)
  Widget _feeHeadsPieChart() {
    final fees = (studentDetails?['feeDetails'] as List?) ?? [];
    if (fees.isEmpty) {
      return const SizedBox(height: 200, child: Center(child: Text('No data for chart')));
    }

    // Build sections: each fee heading uses effectiveFeeDue as the slice value.
    final List<PieChartSectionData> sections = [];
    final colors = [
      Colors.blue.shade400,
      Colors.green.shade400,
      Colors.orange.shade400,
      Colors.purple.shade400,
      Colors.red.shade400,
      Colors.teal.shade400,
      Colors.indigo.shade400,
      Colors.cyan.shade400
    ];
    double total = 0;
    for (final f in fees) {
      total += (double.tryParse((f['effectiveFeeDue'] ?? 0).toString()) ?? 0);
    }
    int colorIndex = 0;
    for (int i = 0; i < fees.length; i++) {
      final f = fees[i];
      final val = (double.tryParse((f['effectiveFeeDue'] ?? 0).toString()) ?? 0);
      final color = colors[colorIndex % colors.length];
      colorIndex++;
      if (val <= 0) continue;
      sections.add(PieChartSectionData(
        value: val,
        color: color,
        title: '${f['fee_heading']?.toString().splitMapJoin(RegExp(r'\s+'), onMatch: (m) => '\n', onNonMatch: (s) => s).split('\n').take(2).join(' ')}\n${NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹').format(val)}',
        radius: 70,
        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
      ));
    }

    if (sections.isEmpty) {
      return const SizedBox(height: 200, child: Center(child: Text('No positive values for chart')));
    }

    return SizedBox(
      height: 360,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: PieChart(PieChartData(
                  sections: sections,
                  centerSpaceRadius: 40,
                  sectionsSpace: 4,
                  pieTouchData: PieTouchData(enabled: true),
                )),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: fees.map<Widget>((f) {
                      final val = (double.tryParse((f['effectiveFeeDue'] ?? 0).toString()) ?? 0);
                      if (val <= 0) return const SizedBox.shrink();
                      final idx = fees.indexOf(f);
                      final color = colors[idx % colors.length];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(f['fee_heading']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                                Text(NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(val), style: const TextStyle(color: Colors.black54)),
                              ]),
                            )
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              )
            ],
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
      totals['vanDue'] ?? 0,
      totals['vanReceived'] ?? 0,
    ];
    final colors = [Colors.red.shade400, Colors.blue.shade400, Colors.amber.shade600, Colors.green.shade400, Colors.purple.shade400];

    List<PieChartSectionData> list = [];
    for (int i = 0; i < vals.length; i++) {
      final v = vals[i];
      if (v <= 0) {
        list.add(PieChartSectionData(value: 0.0001, color: colors[i], showTitle: false, radius: 40));
      } else {
        list.add(PieChartSectionData(
          value: v,
          color: colors[i],
          title: formatINR(v),
          radius: 50,
          titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
        ));
      }
    }
    return list;
  }

  // kpi items to render
  List<Map<String, dynamic>> _kpiItemsForTotals(Map<String, double> totals) {
    return [
      {'title': 'Total Effective', 'value': formatINR(totals['effective'] ?? 0)},
      {'title': 'Received', 'value': formatINR(totals['received'] ?? 0)},
      {'title': 'Concession', 'value': formatINR(totals['concession'] ?? 0)},
      {'title': 'Total Due', 'value': formatINR(totals['due'] ?? 0)},
    ];
  }

Widget _hero() {
  final sd = studentDetails ?? {};
  final totals = _calcTotals();
  final vanDue = totals['vanDue'] ?? 0.0;
  final kpiItems = _kpiItemsForTotals(totals);

  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF4F46E5), Color(0xFF06B6D4), Color(0xFF10B981)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---- Row: Name + Buttons ----
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Welcome,',
                      style: TextStyle(color: Colors.white.withOpacity(0.9))),
                  const SizedBox(height: 4),
                  Text(sd['name'] ?? 'Student',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 20),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    _softBadge('Adm No', sd['admissionNumber'] ?? '—'),
                    if (sd['class_name'] != null)
                      _softBadge('Class', sd['class_name']),
                    if (sd['section_name'] != null)
                      _softBadge('Section', sd['section_name']),
                    if (sd['concession'] != null &&
                        sd['concession']['name'] != null)
                      _softBadge('Concession', sd['concession']['name']),
                  ]),
                ],
              ),
            ),
            Column(
              children: [
                ElevatedButton.icon(
                  onPressed: () => setState(() => _tabController.index = 0),
                  icon: const Icon(Icons.grid_view),
                  label: const Text('Fee Details'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _tabController.index = 1),
                  icon: const Icon(Icons.pie_chart),
                  label: const Text('Summary'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                ),
              ],
            ),
          ],
        ),

        // ---- NEW: Full-width Student Switcher ----
        if (canSeeStudentSwitcher && studentsList.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: studentsList.map((s) {
                  final isActive =
                      (s['admission_number']?.toString() == activeAdmission);
                  final name = (s['isSelf'] ?? false)
                      ? 'Me'
                      : (s['name']?.toString() ?? 'Student');
                  final cls = s['class']?['name']?.toString() ?? '';
                  final sec = s['section']?['name']?.toString() ?? '';
                  final label = cls.isNotEmpty
                      ? '$name · $cls${sec.isNotEmpty ? '-$sec' : ''}'
                      : name;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: ElevatedButton(
                      onPressed: () => handleStudentSwitch(
                          s['admission_number']?.toString() ?? ''),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isActive
                            ? Colors.white
                            : Colors.white.withOpacity(0.2),
                        foregroundColor:
                            isActive ? Colors.black87 : Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.normal),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],

        const SizedBox(height: 14),
        // ---- Auto-scrolling chips + KPI below (unchanged) ----
        SizedBox(
          height: 56,
          child: NotificationListener<ScrollNotification>(
            onNotification: (_) => false,
            child: ListView(
              controller: _chipScrollController,
              scrollDirection: Axis.horizontal,
              children: [
                const SizedBox(width: 8),
                _chipRowItem(Icons.place, 'Route',
                    sd['transport']?['villages'] ?? '—', Colors.purple.shade100),
                const SizedBox(width: 8),
                _chipRowItem(Icons.local_shipping, 'Transport Due',
                    formatINR(totals['vanCost'] ?? 0), Colors.amber.shade100),
                const SizedBox(width: 8),
                _chipRowItem(Icons.account_balance_wallet, 'Van Received',
                    formatINR(totals['vanReceived'] ?? 0), Colors.blue.shade100),
                const SizedBox(width: 8),
                _chipRowItem(Icons.confirmation_num, 'Van Concession',
                    formatINR(totals['vanConcession'] ?? 0),
                    Colors.orange.shade100),
                const SizedBox(width: 8),
                _chipRowItem(Icons.money, 'Van Due', formatINR(vanDue),
                    vanDue > 0
                        ? Colors.red.shade100
                        : Colors.green.shade100),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: ElevatedButton.icon(
                    onPressed: (vanDue > 0) ? handlePayVanFee : null,
                    icon: const Icon(Icons.credit_card),
                    label: const Text('Pay Van Fee'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor:
                            vanDue > 0 ? Colors.green : Colors.grey),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // KPI PageView (unchanged)
        SizedBox(
          height: 110,
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
                      child: _kpiCardWrapped(it['title'], it['value']),
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
                            : Colors.white.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(8)),
                  );
                }),
              )
            ],
          ),
        ),
      ],
    ),
  );
}


  Widget _softBadge(String label, dynamic value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
      child: Row(children: [
        Text('$label: ', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        SizedBox(
          width: 110,
          child: Text('$value', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }

  Widget _chipRowItem(IconData icon, String label, String value, Color bg) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.black12)),
      child: Row(children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Flexible(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 6),
        Flexible(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  // Kpi card that wraps title into max 2 lines
  Widget _kpiCardWrapped(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFE6F7EC), Color(0xFFDFF4FF)]),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Title: allow wrapping into 2 lines
        Text(
          title,
          style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w700),
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.ellipsis,
        ),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  Widget _kpiCard(String title, String value, Color bg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  // Fixed-height, non-overflowing cards
  Widget _feeCardsGrid() {
    final fees = (studentDetails?['feeDetails'] as List?) ?? [];
    if (fees.isEmpty) {
      return const Center(child: Text('No fee details available.'));
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: fees.length,
      itemBuilder: (context, idx) {
        final fee = Map<String, dynamic>.from(fees[idx]);
        final t = getTransportBreakdown(fee);
        final academicDue = double.tryParse((fee['finalAmountDue'] ?? 0).toString()) ?? 0;
        final totalInclVan = academicDue + (t != null ? (t['pending'] ?? 0.0) : 0.0);
        final received = double.tryParse((fee['totalFeeReceived'] ?? 0).toString()) ?? 0.0;
        final concession = double.tryParse((fee['totalConcessionReceived'] ?? 0).toString()) ?? 0.0;
        final effective = double.tryParse((fee['effectiveFeeDue'] ?? 0).toString()) ?? 0.0;
        final paidPct = effective > 0 ? ((received + concession) / effective) * 100 : 0;
        final vanPaidPct = (t != null && (t['cost'] ?? 0) > 0) ? ((t['received'] ?? 0) + (t['concession'] ?? 0)) / (t['cost'] ?? 1) * 100 : 0.0;
        final isExpanded = _expandedFees.length > idx ? _expandedFees[idx] : false;

        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: academicDue > 0 ? Colors.red.shade100 : Colors.green.shade100),
          ),
          elevation: 2,
          child: Column(
            children: [
              // Header
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (_expandedFees.length > idx) {
                      _expandedFees[idx] = !_expandedFees[idx];
                    }
                  });
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.indigo.shade50, Colors.cyan.shade50]),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          fee['fee_heading'] ?? 'Fee',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (t != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: (t['pending'] ?? 0) > 0 ? Colors.amber.shade100 : Colors.green.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            (t['pending'] ?? 0) > 0 ? 'TR Pending: ${formatINR(t['pending'])}' : 'TR Clear',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('No Transport'),
                        ),
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
                      // Academic details
                      _smallRow('Received', formatINR(fee['totalFeeReceived'] ?? 0)),
                      _smallRow('Concession', formatINR(fee['totalConcessionReceived'] ?? 0)),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 8,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (paidPct.clamp(0, 100) / 100),
                            minHeight: 8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Academic Paid ${paidPct.toStringAsFixed(1)}%',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      if (t != null) ...[
                        const SizedBox(height: 12),
                        // Transport header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.blue.shade50,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.local_shipping, size: 14),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Transport',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                              Text(formatINR(t['pending'] ?? 0)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Transport tiny rows
                        _tinyRow('Due (Head)', formatINR(t['due'] ?? 0)),
                        _tinyRow('Received (Head)', formatINR(t['received'] ?? 0)),
                        _tinyRow('Concession (Head)', formatINR(t['concession'] ?? 0)),
                        _tinyRow(
                          'Pending (Head)',
                          formatINR(t['pending'] ?? 0),
                          valueIsDanger: (t['pending'] ?? 0) > 0,
                        ),
                        if ((t['cost'] ?? 0) > 0) ...[
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 8,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: (vanPaidPct.clamp(0, 100) / 100),
                                minHeight: 8,
                                color: Colors.lightBlue,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Transport Paid ${vanPaidPct.toStringAsFixed(1)}%',
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ],
                      const SizedBox(height: 12),
                      // Totals aligned to the right
                      Align(
                        alignment: Alignment.centerRight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Academic Due',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              formatINR(academicDue),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: academicDue > 0 ? Colors.red : Colors.green,
                              ),
                            ),
                            if (t != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Transport Pending',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                formatINR(t['pending'] ?? 0),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: (t['pending'] ?? 0) > 0 ? Colors.red : Colors.green,
                                ),
                              ),
                              const SizedBox(height: 6),
                            ],
                            Text(
                              'Total Due (incl. Transport)',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              formatINR(totalInclVan),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: totalInclVan > 0 ? Colors.red : Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: (academicDue > 0 || (t != null && (t['pending'] ?? 0) > 0))
                              ? () => handlePayFee(fee)
                              : null,
                          child: Text(
                            (academicDue > 0)
                                ? 'Pay'
                                : (t != null && (t['pending'] ?? 0) > 0)
                                    ? 'Transport Pending'
                                    : 'Paid',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: (academicDue > 0) ? Colors.blue : Colors.green,
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
    );
  }

  Widget _smallRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
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
                fontWeight: FontWeight.w700,
                color: valueIsDanger ? Colors.red : Colors.black,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _overallPie() {
    final totals = _calcTotals();
    final sections = _makePieSections(totals);
    return SizedBox(
      height: 360,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: PieChart(PieChartData(sections: sections, centerSpaceRadius: 40, sectionsSpace: 2, pieTouchData: PieTouchData(enabled: true))),
        ),
      ),
    );
  }

  Widget _historyTable() {
    final rows = transactionHistory;
    if (rows.isEmpty) {
      return const Center(child: Text('No transaction history available.'));
    }
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Fee Heading')),
            DataColumn(label: Text('Serial')),
            DataColumn(label: Text('Slip ID')),
            DataColumn(label: Text('Date & Time')),
            DataColumn(label: Text('Payment Mode')),
            DataColumn(label: Text('Fee Received')),
            DataColumn(label: Text('Concession')),
            DataColumn(label: Text('Van Fee')),
          ],
          rows: rows.map<DataRow>((txn) {
            final feeHeading = (txn['FeeHeading'] is Map) ? (txn['FeeHeading']['fee_heading'] ?? 'N/A') : (txn['FeeHeading'] ?? 'N/A');
            final dt = txn['createdAt'] != null ? DateTime.tryParse(txn['createdAt'].toString()) : null;
            final dtStr = dt != null ? DateFormat('dd MMM yyyy, hh:mm a').format(dt) : (txn['createdAt']?.toString() ?? '');
            final paymentMode = txn['PaymentMode'] ?? '';
            return DataRow(cells: [
              DataCell(SizedBox(width: 140, child: Text('$feeHeading', overflow: TextOverflow.ellipsis))),
              DataCell(Text('${txn['Serial'] ?? ''}')),
              DataCell(Text('${txn['Slip_ID'] ?? ''}')),
              DataCell(Text(dtStr)),
              DataCell(Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), decoration: BoxDecoration(color: paymentMode == 'ONLINE' ? Colors.blue.shade100 : Colors.grey.shade200, borderRadius: BorderRadius.circular(6)), child: Text('$paymentMode'))),
              DataCell(Text(formatINR(txn['Fee_Recieved'] ?? 0))),
              DataCell(Text(formatINR(txn['Concession'] ?? 0))),
              DataCell(Text(formatINR(txn['VanFee'] ?? 0))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totals = _calcTotals();
    return Scaffold(
      appBar: AppBar(title: const Text('Fees'), backgroundColor: const Color(0xFF6C63FF)),
      backgroundColor: const Color(0xFFF6F9FF),
      body: RefreshIndicator(
        onRefresh: () async => await _loadFamilyAndActive(),
        color: const Color(0xFF6C63FF),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _hero(),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(children: [
                  TabBar(
                    controller: _tabController,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.black87,
                    indicator: BoxDecoration(borderRadius: BorderRadius.circular(999), gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF10B981)])),
                    tabs: const [
                      Tab(text: 'Fee Details'),
                      Tab(text: 'Summary'),
                      Tab(text: 'History'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (loading)
                    const Center(child: CircularProgressIndicator())
                  else if (error != null)
                    Center(child: Text(error!, style: const TextStyle(color: Colors.red)))
                  else
                    IndexedStack(
                      index: _tabController.index,
                      children: [
                        Column(children: [
                          _feeCardsGrid(),
                          const SizedBox(height: 12),
                          // replaced bar chart with fee-heads pie chart
                          _feeHeadsPieChart(),
                        ]),
                        Column(children: [
                          _overallPie(),
                          const SizedBox(height: 12),
                          Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(children: [
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  const Text('Original Fee'),
                                  Text(formatINR(totals['original'] ?? 0)),
                                ]),
                                const Divider(),
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  const Text('Effective Fee'),
                                  Text(formatINR(totals['effective'] ?? 0)),
                                ]),
                                const Divider(),
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  const Text('Total Received'),
                                  Text(formatINR(totals['received'] ?? 0)),
                                ]),
                                const Divider(),
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  const Text('Total Concession'),
                                  Text(formatINR(totals['concession'] ?? 0)),
                                ]),
                                const Divider(),
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  const Text('Total Due', style: TextStyle(fontWeight: FontWeight.w800)),
                                  Text(formatINR(totals['due'] ?? 0), style: const TextStyle(fontWeight: FontWeight.w800)),
                                ]),
                                const SizedBox(height: 12),
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  const Text('Van Received'),
                                  Text(formatINR(totals['vanReceived'] ?? 0)),
                                ]),
                                const Divider(),
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  const Text('Van Due'),
                                  Text(formatINR(totals['vanDue'] ?? 0), style: TextStyle(fontWeight: FontWeight.w800, color: (totals['vanDue'] ?? 0) > 0 ? Colors.red : Colors.green)),
                                ]),
                              ]),
                            ),
                          ),
                        ]),
                        _historyTable(),
                      ],
                    ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}