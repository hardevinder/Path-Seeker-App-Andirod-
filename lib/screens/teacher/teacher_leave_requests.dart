import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../../constants/constants.dart'; // ✅ uses Constants.apiBase

/// Teacher Leave Requests
/// - Loads token safely (supports token/authToken/accessToken)
/// - Uses Constants.apiBase + endpoints
/// - Handles 401 properly (session expired)
/// - RefreshIndicator + manual refresh
/// - Better error parsing + timeouts

class LeaveRequest {
  final int id;
  final String studentName;
  final String date; // yyyy-MM-dd or ISO
  final String reason;
  final String status;

  LeaveRequest({
    required this.id,
    required this.studentName,
    required this.date,
    required this.reason,
    required this.status,
  });

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    final student = json['Student'];
    final name = (student is Map ? student['name'] : null) ??
        json['student_name'] ??
        json['studentName'] ??
        'Unknown';

    return LeaveRequest(
      id: (json['id'] is int) ? json['id'] : int.tryParse('${json['id']}') ?? 0,
      studentName: name.toString(),
      date: (json['date'] ?? '').toString(),
      reason: (json['reason'] ?? '').toString(),
      status: (json['status'] ?? 'pending').toString().trim().toLowerCase(),
    );
  }
}

class TeacherLeaveRequestsScreen extends StatefulWidget {
  const TeacherLeaveRequestsScreen({Key? key}) : super(key: key);

  @override
  State<TeacherLeaveRequestsScreen> createState() =>
      _TeacherLeaveRequestsScreenState();
}

class _TeacherLeaveRequestsScreenState extends State<TeacherLeaveRequestsScreen> {
  // ✅ Endpoints (adjust if your backend differs)
  static const String leaveListEndpoint = '/leave';
  static String leaveUpdateEndpoint(int id) => '/leave/$id';

  List<LeaveRequest> _requests = [];
  bool _loading = true;
  bool _refreshing = false;

  String? _token;

  final DateFormat _niceDate = DateFormat.yMMMd();

  @override
  void initState() {
    super.initState();
    _loadTokenAndFetch();
  }

  // =========================
  // Auth + Networking helpers
  // =========================

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    // ✅ support multiple keys so it never fails silently
    return prefs.getString('authToken') ??
        prefs.getString('token') ??
        prefs.getString('accessToken') ??
        prefs.getString('jwt');
  }

  Uri _buildUri(String pathWithQuery) {
    final base = Constants.apiBase.replaceAll(RegExp(r"/+$"), "");
    final p = pathWithQuery.startsWith('/') ? pathWithQuery : '/$pathWithQuery';
    return Uri.parse('$base$p');
  }

  Map<String, String> _buildAuthHeaders(String? token) {
    final t = (token ?? '').trim();
    // ✅ Some backends read lowercase, some read x-access-token
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
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
    // Optional: you can navigate to login screen if you want.
    // Navigator.pushReplacementNamed(context, '/login');
  }

  // =========================
  // Loading
  // =========================

  Future<void> _loadTokenAndFetch() async {
    setState(() {
      _loading = true;
      _refreshing = false;
    });

    final token = await _getToken();
    if (!mounted) return;

    setState(() => _token = token);

    if (_token == null || _token!.trim().isEmpty) {
      setState(() => _loading = false);
      _showMessage('Not authenticated. Please login.');
      return;
    }

    await _fetchLeaveRequests();
  }

  Future<void> _fetchLeaveRequests() async {
    final token = _token;

    if (token == null || token.trim().isEmpty) {
      _showMessage('Not authenticated. Please login.');
      if (mounted) setState(() => _loading = false);
      return;
    }

    if (mounted) {
      setState(() => _loading = !_refreshing); // keep UI stable on pull-to-refresh
    }

    try {
      final uri = _buildUri(leaveListEndpoint);
      final resp = await http
          .get(uri, headers: _buildAuthHeaders(token))
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);

        // ✅ support both [ ... ] and { data: [...] }
        final List list = (decoded is List)
            ? decoded
            : (decoded is Map && decoded['data'] is List)
                ? decoded['data'] as List
                : <dynamic>[];

        final items = list
            .where((e) => e is Map)
            .map((e) => LeaveRequest.fromJson(Map<String, dynamic>.from(e)))
            .toList();

        setState(() => _requests = items);
      } else if (resp.statusCode == 401) {
        _handleUnauthorized();
        setState(() => _requests = []);
      } else {
        final msg = _extractErrorMessage(resp);
        _showMessage(
          msg.isNotEmpty
              ? 'Failed to load requests (${resp.statusCode}): $msg'
              : 'Failed to load requests (${resp.statusCode})',
        );
      }
    } catch (_) {
      if (mounted) _showMessage('Network error while fetching leave requests.');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _updateLeaveStatus(int id, String newStatus) async {
    final token = _token;
    if (token == null || token.trim().isEmpty) {
      _showMessage('Not authenticated. Please login.');
      return;
    }

    try {
      final uri = _buildUri(leaveUpdateEndpoint(id));
      final resp = await http
          .put(
            uri,
            headers: _buildAuthHeaders(token),
            body: jsonEncode({'status': newStatus}),
          )
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;

      if (resp.statusCode == 200 || resp.statusCode == 204) {
        _showMessage(newStatus == 'accepted' ? 'Approved' : 'Rejected');

        // ✅ Optimistic local update
        setState(() {
          final idx = _requests.indexWhere((r) => r.id == id);
          if (idx != -1) {
            _requests[idx] = LeaveRequest(
              id: _requests[idx].id,
              studentName: _requests[idx].studentName,
              date: _requests[idx].date,
              reason: _requests[idx].reason,
              status: newStatus,
            );
          }
        });
      } else if (resp.statusCode == 401) {
        _handleUnauthorized();
      } else {
        final msg = _extractErrorMessage(resp);
        _showMessage(
          msg.isNotEmpty
              ? 'Failed to update leave (${resp.statusCode}): $msg'
              : 'Failed to update leave (${resp.statusCode}).',
        );
      }
    } catch (_) {
      if (mounted) _showMessage('Network error while updating leave.');
    }
  }

  // =========================
  // UI helpers
  // =========================

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _confirmReject(int id) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Leave'),
        content: const Text('Are you sure you want to reject this leave request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (res == true) {
      await _updateLeaveStatus(id, 'rejected');
    }
  }

  Widget _buildStatusChip(String status) {
    final s = status.trim().toLowerCase();
    final Color color;
    final String label;

    if (s == 'pending') {
      color = Colors.orange.shade700;
      label = 'Pending';
    } else if (s == 'accepted' || s == 'approved') {
      color = Colors.green.shade700;
      label = 'Accepted';
    } else if (s == 'rejected') {
      color = Colors.red.shade700;
      label = 'Rejected';
    } else {
      color = Colors.blueGrey.shade600;
      label = status;
    }

    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return _niceDate.format(dt);
    } catch (_) {
      return iso;
    }
  }

  // =========================
  // Build
  // =========================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Leave Requests'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: () async {
              setState(() => _refreshing = true);
              await _fetchLeaveRequests();
            },
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                setState(() => _refreshing = true);
                await _fetchLeaveRequests();
              },
              child: _requests.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 80),
                        Center(child: Text('No pending leave requests.')),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _requests.length,
                      itemBuilder: (context, index) {
                        final req = _requests[index];

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      child: Text(
                                        req.studentName.isNotEmpty
                                            ? req.studentName[0]
                                            : '?',
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            req.studentName,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatDate(req.date),
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    _buildStatusChip(req.status),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  req.reason,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (req.status.toLowerCase() == 'pending') ...[
                                      ElevatedButton.icon(
                                        onPressed: () => _updateLeaveStatus(req.id, 'accepted'),
                                        icon: const Icon(Icons.check),
                                        label: const Text('Accept'),
                                        style: ElevatedButton.styleFrom(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        onPressed: () => _confirmReject(req.id),
                                        icon: const Icon(Icons.close),
                                        label: const Text('Reject'),
                                        style: OutlinedButton.styleFrom(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                        ),
                                      ),
                                    ] else ...[
                                      Text(
                                        'No actions available',
                                        style: TextStyle(color: Colors.grey.shade600),
                                      ),
                                    ]
                                  ],
                                )
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
