import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/constants.dart'; // ✅ Constants.apiBase

// =======================
// Models
// =======================

class LeaveType {
  final int id;
  final String name;

  LeaveType({required this.id, required this.name});

  factory LeaveType.fromJson(Map<String, dynamic> json) {
    return LeaveType(
      id: (json['id'] is int) ? json['id'] : int.tryParse('${json['id']}') ?? 0,
      name: (json['name'] ?? '').toString(),
    );
  }
}

class EmployeeLeaveRequest {
  final int id;
  final int leaveTypeId;
  final String startDate; // yyyy-MM-dd / ISO
  final String endDate;
  final String reason;
  final bool isWithoutPay;
  final String status; // pending/approved/rejected OR accepted/rejected
  final String? createdAt;

  EmployeeLeaveRequest({
    required this.id,
    required this.leaveTypeId,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.isWithoutPay,
    required this.status,
    required this.createdAt,
  });

  factory EmployeeLeaveRequest.fromJson(Map<String, dynamic> json) {
    return EmployeeLeaveRequest(
      id: (json['id'] is int) ? json['id'] : int.tryParse('${json['id']}') ?? 0,
      leaveTypeId: (json['leave_type_id'] is int)
          ? json['leave_type_id']
          : int.tryParse('${json['leave_type_id']}') ?? 0,
      startDate: (json['start_date'] ?? '').toString(),
      endDate: (json['end_date'] ?? '').toString(),
      reason: (json['reason'] ?? '').toString(),
      isWithoutPay: json['is_without_pay'] == true ||
          json['is_without_pay'] == 1 ||
          '${json['is_without_pay']}'.toLowerCase() == 'true',
      status: (json['status'] ?? 'pending').toString().trim().toLowerCase(),
      createdAt: json['createdAt']?.toString(),
    );
  }
}

// =======================
// Screen
// =======================

class TeacherMyLeaveRequestsScreen extends StatefulWidget {
  const TeacherMyLeaveRequestsScreen({Key? key}) : super(key: key);

  @override
  State<TeacherMyLeaveRequestsScreen> createState() =>
      _TeacherMyLeaveRequestsScreenState();
}

class _TeacherMyLeaveRequestsScreenState
    extends State<TeacherMyLeaveRequestsScreen> {
  // ✅ endpoints (adjust if needed)
  static const String leaveTypesEndpoint = '/employee-leave-types';
  static const String myLeavesEndpoint = '/employee-leave-requests';
  static String myLeaveUpdateEndpoint(int id) => '/employee-leave-requests/$id';

  final DateFormat _niceDate = DateFormat.yMMMd();
  String? _token;

  bool _loading = true;
  bool _refreshing = false;
  bool _submitting = false;

  List<LeaveType> _leaveTypes = [];
  List<EmployeeLeaveRequest> _requests = [];

  String _activeTab = 'pending'; // pending / approved / rejected

  // form
  int? _editingId;
  int? _leaveTypeId;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _withoutPay = false;
  final TextEditingController _reasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTokenAndFetch();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  // =========================
  // Auth + Networking helpers
  // =========================

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authToken') ??
        prefs.getString('token') ??
        prefs.getString('accessToken') ??
        prefs.getString('jwt');
  }

  Uri _buildUri(String path) {
    final base = Constants.apiBase.replaceAll(RegExp(r"/+$"), "");
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  Map<String, String> _buildAuthHeaders(String? token) {
    final t = (token ?? '').trim();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (t.isNotEmpty) {
      headers['Authorization'] = 'Bearer $t';
      headers['authorization'] = 'Bearer $t';
      headers['x-access-token'] = t;
    }
    return headers;
  }

  String _extractErrorMessage(http.Response resp) {
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map) {
        return (decoded['message'] ??
                decoded['error'] ??
                decoded['details'] ??
                decoded['msg'] ??
                '')
            .toString()
            .trim();
      }
    } catch (_) {}
    return resp.body.toString().trim();
  }

  void _handleUnauthorized() {
    _showMessage('Session expired. Please login again.');
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // =========================
  // Load data
  // =========================

  Future<void> _loadTokenAndFetch() async {
    setState(() {
      _loading = true;
      _refreshing = false;
    });

    final token = await _getToken();
    if (!mounted) return;

    _token = token;

    if (_token == null || _token!.trim().isEmpty) {
      setState(() => _loading = false);
      _showMessage('Not authenticated. Please login.');
      return;
    }

    await _fetchAll();
  }

  Future<void> _fetchAll() async {
    try {
      final t = _token!;
      final ltUri = _buildUri(leaveTypesEndpoint);
      final reqUri = _buildUri(myLeavesEndpoint);

      final responses = await Future.wait([
        http.get(ltUri, headers: _buildAuthHeaders(t)).timeout(
              const Duration(seconds: 20),
            ),
        http.get(reqUri, headers: _buildAuthHeaders(t)).timeout(
              const Duration(seconds: 20),
            ),
      ]);

      if (!mounted) return;

      final ltResp = responses[0];
      final reqResp = responses[1];

      if (ltResp.statusCode == 401 || reqResp.statusCode == 401) {
        _handleUnauthorized();
        setState(() {
          _leaveTypes = [];
          _requests = [];
          _loading = false;
          _refreshing = false;
        });
        return;
      }

      if (ltResp.statusCode == 200) {
        final decoded = jsonDecode(ltResp.body);
        final List list = (decoded is List)
            ? decoded
            : (decoded is Map && decoded['data'] is List)
                ? decoded['data'] as List
                : <dynamic>[];
        _leaveTypes = list
            .where((e) => e is Map)
            .map((e) => LeaveType.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } else {
        final msg = _extractErrorMessage(ltResp);
        _showMessage(msg.isNotEmpty
            ? 'Failed to load leave types: $msg'
            : 'Failed to load leave types.');
      }

      if (reqResp.statusCode == 200) {
        final decoded = jsonDecode(reqResp.body);
        final List list = (decoded is List)
            ? decoded
            : (decoded is Map && decoded['data'] is List)
                ? decoded['data'] as List
                : <dynamic>[];
        _requests = list
            .where((e) => e is Map)
            .map((e) => EmployeeLeaveRequest.fromJson(
                Map<String, dynamic>.from(e)))
            .toList()
          ..sort((a, b) {
            final ad = DateTime.tryParse(a.createdAt ?? a.startDate) ??
                DateTime(1970);
            final bd = DateTime.tryParse(b.createdAt ?? b.startDate) ??
                DateTime(1970);
            return bd.compareTo(ad);
          });
      } else {
        final msg = _extractErrorMessage(reqResp);
        _showMessage(msg.isNotEmpty
            ? 'Failed to load requests: $msg'
            : 'Failed to load requests.');
      }
    } catch (_) {
      if (mounted) _showMessage('Network error while loading data.');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await _fetchAll();
  }

  // =========================
  // Actions: create / update
  // =========================

  String _fmtYmd(DateTime d) {
    final x = DateTime(d.year, d.month, d.day);
    return DateFormat('yyyy-MM-dd').format(x);
  }

  Future<void> _submitLeave() async {
    final token = _token;
    if (token == null || token.trim().isEmpty) {
      _showMessage('Not authenticated. Please login.');
      return;
    }

    if (_leaveTypeId == null) {
      _showMessage('Please select leave type.');
      return;
    }
    if (_startDate == null || _endDate == null) {
      _showMessage('Please select start & end date.');
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      _showMessage('End date cannot be before start date.');
      return;
    }

    setState(() => _submitting = true);

    try {
      final body = {
        'leave_type_id': _leaveTypeId,
        'start_date': _fmtYmd(_startDate!),
        'end_date': _fmtYmd(_endDate!),
        'reason': _reasonCtrl.text.trim(),
        'is_without_pay': _withoutPay,
      };

      http.Response resp;
      if (_editingId != null) {
        final uri = _buildUri(myLeaveUpdateEndpoint(_editingId!));
        resp = await http
            .put(uri,
                headers: _buildAuthHeaders(token), body: jsonEncode(body))
            .timeout(const Duration(seconds: 20));
      } else {
        final uri = _buildUri(myLeavesEndpoint);
        resp = await http
            .post(uri,
                headers: _buildAuthHeaders(token), body: jsonEncode(body))
            .timeout(const Duration(seconds: 20));
      }

      if (!mounted) return;

      if (resp.statusCode == 401) {
        _handleUnauthorized();
        return;
      }

      if (resp.statusCode == 200 || resp.statusCode == 201 || resp.statusCode == 204) {
        _showMessage(_editingId != null ? 'Leave updated' : 'Leave submitted');
        Navigator.of(context).pop(); // close bottom sheet
        _clearForm();
        setState(() => _activeTab = 'pending');
        await _refresh();
      } else {
        final msg = _extractErrorMessage(resp);
        _showMessage(msg.isNotEmpty
            ? 'Failed: $msg'
            : 'Failed to submit leave (${resp.statusCode}).');
      }
    } catch (_) {
      if (mounted) _showMessage('Network error while submitting leave.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _clearForm() {
    _editingId = null;
    _leaveTypeId = null;
    _startDate = null;
    _endDate = null;
    _withoutPay = false;
    _reasonCtrl.text = '';
  }

  // =========================
  // UI helpers
  // =========================

  String _statusLabel(String s) {
    final x = s.trim().toLowerCase();
    if (x == 'accepted') return 'Approved';
    if (x == 'approved') return 'Approved';
    if (x == 'rejected') return 'Rejected';
    return 'Pending';
  }

  Color _statusColor(String s) {
    final x = s.trim().toLowerCase();
    if (x == 'accepted' || x == 'approved') return Colors.green.shade700;
    if (x == 'rejected') return Colors.red.shade700;
    return Colors.orange.shade700;
  }

  Widget _statusChip(String s) {
    return Chip(
      label: Text(_statusLabel(s), style: const TextStyle(color: Colors.white)),
      backgroundColor: _statusColor(s),
    );
  }

  String _typeName(int id) {
    return _leaveTypes.firstWhere(
      (t) => t.id == id,
      orElse: () => LeaveType(id: id, name: '—'),
    ).name;
  }

  String _formatNice(String iso) {
    try {
      return _niceDate.format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  List<EmployeeLeaveRequest> _filteredForTab() {
    final tab = _activeTab;
    return _requests.where((r) {
      final s = r.status.toLowerCase();
      if (tab == 'pending') return s == 'pending';
      if (tab == 'approved') return s == 'approved' || s == 'accepted';
      if (tab == 'rejected') return s == 'rejected';
      return true;
    }).toList();
  }

  Future<void> _pickDate({required bool start}) async {
    final initial = start
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? _startDate ?? DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );

    if (picked == null) return;

    setState(() {
      if (start) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  void _openApplySheet({EmployeeLeaveRequest? edit}) {
    if (edit != null) {
      _editingId = edit.id;
      _leaveTypeId = edit.leaveTypeId;
      _startDate = DateTime.tryParse(edit.startDate);
      _endDate = DateTime.tryParse(edit.endDate);
      _withoutPay = edit.isWithoutPay;
      _reasonCtrl.text = edit.reason;
    } else {
      _clearForm();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: bottom + 16),
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              // keep bottom-sheet responsive
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _editingId != null ? 'Edit Leave Request' : 'Apply for Leave',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        onPressed: _submitting ? null : () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                      )
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Leave type
                  const Text('Leave Type *', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    value: _leaveTypeId,
                    items: _leaveTypes
                        .map((t) => DropdownMenuItem<int>(
                              value: t.id,
                              child: Text(t.name),
                            ))
                        .toList(),
                    onChanged: _submitting
                        ? null
                        : (v) {
                            setState(() => _leaveTypeId = v);
                            setLocal(() {});
                          },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Select leave type',
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Dates row
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _submitting ? null : () => _pickDate(start: true),
                          icon: const Icon(Icons.date_range),
                          label: Text(_startDate == null
                              ? 'Start Date *'
                              : _fmtYmd(_startDate!)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _submitting ? null : () => _pickDate(start: false),
                          icon: const Icon(Icons.event),
                          label: Text(_endDate == null
                              ? 'End Date *'
                              : _fmtYmd(_endDate!)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Reason
                  const Text('Reason', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _reasonCtrl,
                    enabled: !_submitting,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Enter reason (optional)',
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Without pay
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _withoutPay,
                    onChanged: _submitting
                        ? null
                        : (v) {
                            setState(() => _withoutPay = v);
                            setLocal(() {});
                          },
                    title: const Text('Without Pay'),
                  ),

                  const SizedBox(height: 10),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submitLeave,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_editingId != null ? 'Update' : 'Submit'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  // =========================
  // Build
  // =========================

  @override
  Widget build(BuildContext context) {
    final list = _filteredForTab();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Leave Requests'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: _refreshing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: _refreshing ? null : _refresh,
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _leaveTypes.isEmpty ? null : () => _openApplySheet(),
        icon: const Icon(Icons.add),
        label: const Text('Apply'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: Column(
                children: [
                  // Tabs
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    child: Row(
                      children: [
                        _TabBtn(
                          label: 'Pending',
                          active: _activeTab == 'pending',
                          onTap: () => setState(() => _activeTab = 'pending'),
                        ),
                        const SizedBox(width: 8),
                        _TabBtn(
                          label: 'Approved',
                          active: _activeTab == 'approved',
                          onTap: () => setState(() => _activeTab = 'approved'),
                        ),
                        const SizedBox(width: 8),
                        _TabBtn(
                          label: 'Rejected',
                          active: _activeTab == 'rejected',
                          onTap: () => setState(() => _activeTab = 'rejected'),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // List
                  Expanded(
                    child: list.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 90),
                              Center(child: Text('No leave requests found.')),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: list.length,
                            itemBuilder: (ctx, i) {
                              final r = list[i];
                              final canEdit = r.status.toLowerCase() == 'pending';

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              _typeName(r.leaveTypeId),
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          _statusChip(r.status),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '${_formatNice(r.startDate)} → ${_formatNice(r.endDate)}',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Text(
                                            'Without Pay: ${r.isWithoutPay ? "Yes" : "No"}',
                                            style: const TextStyle(color: Colors.black54),
                                          ),
                                          const Spacer(),
                                          if (r.createdAt != null)
                                            Text(
                                              'Submitted ${_formatNice(r.createdAt!)}',
                                              style: const TextStyle(color: Colors.black54, fontSize: 12),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(r.reason.isEmpty ? '—' : r.reason),
                                      const SizedBox(height: 10),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: canEdit
                                            ? OutlinedButton.icon(
                                                onPressed: () => _openApplySheet(edit: r),
                                                icon: const Icon(Icons.edit),
                                                label: const Text('Edit'),
                                              )
                                            : Text(
                                                'No actions available',
                                                style: TextStyle(color: Colors.grey.shade600),
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

// =======================
// Small tab button widget
// =======================

class _TabBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabBtn({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? Theme.of(context).primaryColor : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
