import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

// A mobile-friendly Flutter screen to view and approve/reject leave requests.
// Usage: Navigator.push(context, MaterialPageRoute(builder: (_) => TeacherLeaveRequestsScreen()));

class LeaveRequest {
  final int id;
  final String studentName;
  final String date; // ISO date string from server
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
    return LeaveRequest(
      id: json['id'],
      studentName: json['Student'] != null
          ? (json['Student']['name'] ?? 'Unknown')
          : (json['student_name'] ?? 'Unknown'),
      date: json['date'] ?? '',
      reason: json['reason'] ?? '',
      status: json['status'] ?? 'pending',
    );
  }
}

class TeacherLeaveRequestsScreen extends StatefulWidget {
  const TeacherLeaveRequestsScreen({Key? key}) : super(key: key);

  @override
  State<TeacherLeaveRequestsScreen> createState() => _TeacherLeaveRequestsScreenState();
}

class _TeacherLeaveRequestsScreenState extends State<TeacherLeaveRequestsScreen> {
  List<LeaveRequest> _requests = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _token;

  @override
  void initState() {
    super.initState();
    _loadTokenAndFetch();
  }

  Future<void> _loadTokenAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _token = prefs.getString('token');
    });
    await _fetchLeaveRequests();
  }

  Future<void> _fetchLeaveRequests() async {
    if (_token == null) {
      _showMessage('Not authenticated. Please login.');
      setState(() => _loading = false);
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final uri = Uri.parse('https://your-api.example.com/leave'); // <-- replace with your API base
      final resp = await http.get(uri, headers: {"Authorization": 'Bearer $_token'});
      if (resp.statusCode == 200) {
        final List data = json.decode(resp.body);
        setState(() {
          _requests = data.map((e) => LeaveRequest.fromJson(e)).toList();
        });
      } else {
        _showMessage('Failed to load requests (${resp.statusCode})');
      }
    } catch (e) {
      _showMessage('Error fetching leave requests.');
    } finally {
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _updateLeaveStatus(int id, String newStatus) async {
    if (_token == null) return _showMessage('Not authenticated.');

    try {
      final uri = Uri.parse('https://your-api.example.com/leave/$id'); // <-- replace
      final resp = await http.put(
        uri,
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'status': newStatus}),
      );

      if (resp.statusCode == 200 || resp.statusCode == 204) {
        _showMessage(newStatus == 'accepted' ? 'Approved' : 'Rejected');
        // Optimistically update local list for snappier UI
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
      } else {
        _showMessage('Failed to update leave (${resp.statusCode}).');
      }
    } catch (e) {
      _showMessage('Network error while updating leave.');
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirmReject(int id) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Leave'),
        content: const Text('Are you sure you want to reject this leave request?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Reject')),
        ],
      ),
    );

    if (res == true) {
      await _updateLeaveStatus(id, 'rejected');
    }
  }

  Widget _buildStatusChip(String status) {
    Color color;
    String label = status;
    if (status == 'pending') {
      color = Colors.orange.shade700;
    } else if (status == 'accepted') {
      color = Colors.green.shade700;
    } else {
      color = Colors.red.shade700;
    }

    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return DateFormat.yMMMd().format(dt);
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Leave Requests'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      child: Text(req.studentName.isNotEmpty ? req.studentName[0] : '?'),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(req.studentName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 4),
                                          Text(_formatDate(req.date), style: const TextStyle(fontSize: 13, color: Colors.black54)),
                                        ],
                                      ),
                                    ),
                                    _buildStatusChip(req.status),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(req.reason, style: const TextStyle(fontSize: 14)),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (req.status == 'pending') ...[
                                      ElevatedButton.icon(
                                        onPressed: () => _updateLeaveStatus(req.id, 'accepted'),
                                        icon: const Icon(Icons.check),
                                        label: const Text('Accept'),
                                        style: ElevatedButton.styleFrom(
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        onPressed: () => _confirmReject(req.id),
                                        icon: const Icon(Icons.close),
                                        label: const Text('Reject'),
                                        style: OutlinedButton.styleFrom(
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        ),
                                      ),
                                    ] else ...[
                                      Text('No actions available', style: TextStyle(color: Colors.grey.shade600)),
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
