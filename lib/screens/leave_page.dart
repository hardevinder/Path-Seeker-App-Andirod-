import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/constants.dart'; // ✅ correct path

class LeavePage extends StatefulWidget {
  const LeavePage({super.key});

  @override
  State<LeavePage> createState() => _LeavePageState();
}

class _LeavePageState extends State<LeavePage> {
  // ✅ IMPORTANT: use same base as main.dart
  final String apiUrl = Constants.apiBase;

  List<dynamic> leaveRequests = [];

  String selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String? token;

  bool isLoading = false;
  bool isSubmitting = false;

  final TextEditingController reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadToken();
  }

  @override
  void dispose() {
    reasonController.dispose();
    super.dispose();
  }

  String api(String path) {
    final base = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return '$base$p';
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Color _statusColor(String s) {
    final v = s.toLowerCase();
    if (v.contains("approve")) return Colors.green;
    if (v.contains("reject") || v.contains("decline")) return Colors.red;
    return Colors.orange;
  }

  String _prettyDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      return DateFormat("dd MMM yyyy").format(d);
    } catch (_) {
      return iso;
    }
  }

  String _safeStr(dynamic v) => (v == null) ? "" : v.toString();

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final storedToken = prefs.getString("authToken");

    if (storedToken == null || storedToken.trim().isEmpty) {
      token = null;
      _toast("Login token missing. Please login again.");
      return;
    }

    setState(() => token = storedToken.trim());
    await fetchLeaveRequests();
  }

  Future<void> fetchLeaveRequests() async {
    if (token == null) return;

    setState(() => isLoading = true);
    try {
      final uri = Uri.parse(api("/leave/student/me"));
      final response = await http.get(
        uri,
        headers: {
          "Authorization": "Bearer $token",
          "Accept": "application/json",
          "Connection": "close",
        },
      ).timeout(Duration(milliseconds: Constants.apiTimeoutMs));

      debugPrint("📥 GET $uri -> ${response.statusCode}");
      debugPrint("📥 BODY: ${response.body}");

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        List<dynamic> list = [];
        if (decoded is List) {
          list = decoded;
        } else if (decoded is Map) {
          final d = decoded["data"] ?? decoded["leaves"] ?? decoded["leaveRequests"];
          if (d is List) list = d;
        }

        list.sort((a, b) {
          final ad = _safeStr(a["date"]);
          final bd = _safeStr(b["date"]);
          try {
            return DateTime.parse(bd).compareTo(DateTime.parse(ad));
          } catch (_) {
            return 0;
          }
        });

        setState(() => leaveRequests = list);
      } else if (response.statusCode == 401) {
        _toast("Session expired. Please login again.");
      } else {
        _toast("Could not fetch leaves (${response.statusCode}).");
      }
    } catch (e) {
      debugPrint("❌ fetchLeaveRequests error: $e");
      _toast("Could not fetch leave requests (network/timeout).");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> handleCreateLeave() async {
    final r = reasonController.text.trim();

    if (token == null) {
      _toast("Not logged in. Please login again.");
      return;
    }
    if (r.isEmpty) {
      _toast("Please enter reason.");
      return;
    }
    if (isSubmitting) return;

    FocusScope.of(context).unfocus();
    setState(() => isSubmitting = true);

    try {
      final uri = Uri.parse(api("/leave"));
      final payload = {"date": selectedDate, "reason": r};

      debugPrint("📤 POST $uri");
      debugPrint("📤 PAYLOAD: ${jsonEncode(payload)}");

      final response = await http
          .post(
            uri,
            headers: {
              "Authorization": "Bearer $token",
              "Content-Type": "application/json",
              "Accept": "application/json",
              "Connection": "close",
            },
            body: jsonEncode(payload),
          )
          .timeout(Duration(milliseconds: Constants.apiTimeoutMs));

      debugPrint("📥 POST RESP ${response.statusCode}");
      debugPrint("📥 POST BODY: ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        _toast("✅ Leave request submitted");
        setState(() {
          reasonController.clear();
          selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
        });
        await fetchLeaveRequests();
      } else {
        String msg = "Failed (${response.statusCode})";
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map && decoded["error"] != null) {
            msg = decoded["error"].toString();
          } else if (decoded is Map && decoded["message"] != null) {
            msg = decoded["message"].toString();
          }
        } catch (_) {}

        if (response.statusCode == 401) msg = "Session expired. Please login again.";
        _toast(msg);
      }
    } catch (e) {
      debugPrint("❌ handleCreateLeave error: $e");
      _toast("Failed to create leave request (network/timeout).");
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  void showCalendarBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Pick a date",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TableCalendar(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: DateTime.parse(selectedDate),
              selectedDayPredicate: (day) =>
                  DateFormat('yyyy-MM-dd').format(day) == selectedDate,
              onDaySelected: (selected, focused) {
                setState(() {
                  selectedDate = DateFormat('yyyy-MM-dd').format(selected);
                });
                Navigator.pop(context);
              },
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.25),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: const BoxDecoration(
                  color: Colors.deepPurple,
                  shape: BoxShape.circle,
                ),
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topCard() {
    final datePretty = _prettyDate(selectedDate);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: Colors.deepPurple.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.event_note, color: Colors.deepPurple),
              SizedBox(width: 8),
              Text(
                "Leave Application",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: showCalendarBottomSheet,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.deepPurple.withOpacity(0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 18, color: Colors.deepPurple),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            datePretty,
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: isSubmitting ? null : showCalendarBottomSheet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Change"),
              )
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: reasonController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: "Write reason…",
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.edit_note, color: Colors.deepPurple),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.deepPurple.withOpacity(0.25)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.deepPurple, width: 1.2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isSubmitting ? null : handleCreateLeave,
              icon: isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(isSubmitting ? "Submitting..." : "Submit Leave Request"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentList() {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 18),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (leaveRequests.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.deepPurple.withOpacity(0.15)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.deepPurple),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "No leave requests yet. Submit one above.",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final latest = leaveRequests.take(6).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text("Recent Requests",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton.icon(
                onPressed: fetchLeaveRequests,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text("Refresh"),
              )
            ],
          ),
          const SizedBox(height: 8),
          ...latest.map((item) {
            final date = _prettyDate(_safeStr(item["date"]));
            final reason = _safeStr(item["reason"]);
            final status = _safeStr(item["status"]).isEmpty ? "Pending" : _safeStr(item["status"]);
            final color = _statusColor(status);

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
                border: Border.all(color: Colors.deepPurple.withOpacity(0.12)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.event, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(date, style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          reason.isEmpty ? "No reason" : reason,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: color.withOpacity(0.35)),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = LinearGradient(
      colors: [Colors.deepPurple.shade50, Colors.white],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        title: const Text("Leave Requests",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: "Refresh",
            onPressed: isLoading ? null : fetchLeaveRequests,
            icon: const Icon(Icons.refresh, color: Colors.white),
          )
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: bg),
        child: RefreshIndicator(
          onRefresh: fetchLeaveRequests,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _topCard(),
              _recentList(),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }
}
