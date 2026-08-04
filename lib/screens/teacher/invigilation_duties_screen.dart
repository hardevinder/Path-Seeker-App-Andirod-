import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/exam_seating_api.dart';
import '../../widgets/teacher_drawer_menu.dart';
import 'invigilation_room_attendance_screen.dart';

class InvigilationDutiesScreen extends StatefulWidget {
  const InvigilationDutiesScreen({super.key});

  @override
  State<InvigilationDutiesScreen> createState() => _InvigilationDutiesScreenState();
}

class _InvigilationDutiesScreenState extends State<InvigilationDutiesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _duties = [];

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final duties = await ExamSeatingApi.myDuties(upcoming: false);
      if (mounted) setState(() => _duties = duties);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _date(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    return parsed == null ? (raw?.toString() ?? '') : DateFormat('EEE, d MMM yyyy').format(parsed);
  }

  Future<void> _acknowledge(Map<String, dynamic> duty, String status) async {
    String? reason;
    if (status == 'declined') {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reason for declining'),
          content: TextField(controller: controller, maxLines: 3, autofocus: true, decoration: const InputDecoration(hintText: 'Enter reason', border: OutlineInputBorder())),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Submit')),
          ],
        ),
      );
      if (reason == null || reason.trim().isEmpty) return;
    }

    try {
      await ExamSeatingApi.acknowledgeDuty(
        int.parse(duty['id'].toString()),
        status: status,
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status == 'accepted' ? 'Duty accepted.' : 'Duty declined.')));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString()), backgroundColor: Colors.red.shade700));
    }
  }

  Widget _card(Map<String, dynamic> duty) {
    final plan = _map(duty['plan']);
    final exam = _map(plan['exam']);
    final planRoom = _map(duty['planRoom']);
    final room = _map(planRoom['room']);
    final status = (duty['status'] ?? 'assigned').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(radius: 26, child: Icon(Icons.assignment_ind_rounded)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(exam['name']?.toString() ?? plan['name']?.toString() ?? 'Examination Duty', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text('${_date(plan['exam_date'])} · ${plan['start_time'] ?? ''}–${plan['end_time'] ?? ''}'),
                    ],
                  ),
                ),
                Chip(label: Text(status.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
              ],
            ),
            const Divider(height: 28),
            Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                _detail(Icons.meeting_room_rounded, 'Room', room['name'] ?? room['room_code'] ?? '-'),
                _detail(Icons.badge_outlined, 'Duty', duty['duty_role'] ?? 'main'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (status == 'assigned') ...[
                  Expanded(child: OutlinedButton(onPressed: () => _acknowledge(duty, 'declined'), child: const Text('Unable to attend'))),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton(onPressed: () => _acknowledge(duty, 'accepted'), child: const Text('Accept duty'))),
                ] else
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: status == 'declined'
                          ? null
                          : () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => InvigilationRoomAttendanceScreen(
                                    assignmentId: int.parse(duty['id'].toString()),
                                  ),
                                ),
                              );
                              await _load();
                            },
                      icon: const Icon(Icons.how_to_reg_rounded),
                      label: const Text('Open room attendance'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(IconData icon, String label, dynamic value) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: Colors.indigo),
          const SizedBox(width: 7),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)), Text(value?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w700))]),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Invigilation Duties'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      drawer: const TeacherDrawerMenu(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : _duties.isEmpty
                  ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No invigilation duty has been assigned.', textAlign: TextAlign.center)))
                  : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: _duties.map(_card).toList())),
    );
  }
}
