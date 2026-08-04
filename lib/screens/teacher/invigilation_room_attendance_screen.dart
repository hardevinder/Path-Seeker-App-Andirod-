import 'package:flutter/material.dart';

import '../../services/exam_seating_api.dart';

class InvigilationRoomAttendanceScreen extends StatefulWidget {
  const InvigilationRoomAttendanceScreen({super.key, required this.assignmentId});
  final int assignmentId;

  @override
  State<InvigilationRoomAttendanceScreen> createState() => _InvigilationRoomAttendanceScreenState();
}

class _InvigilationRoomAttendanceScreenState extends State<InvigilationRoomAttendanceScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _duty = {};
  List<Map<String, dynamic>> _seats = [];
  final Map<int, String> _statuses = {};
  final Map<int, TextEditingController> _remarks = {};
  final Map<int, TextEditingController> _internalRemarks = {};

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [..._remarks.values, ..._internalRemarks.values]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ExamSeatingApi.dutyRoom(widget.assignmentId);
      final seats = (data['seats'] as List<Map<String, dynamic>>);
      for (final controller in [..._remarks.values, ..._internalRemarks.values]) {
        controller.dispose();
      }
      _remarks.clear();
      _internalRemarks.clear();
      _statuses.clear();
      for (final seat in seats) {
        final id = int.parse(seat['id'].toString());
        final current = (seat['attendance_status'] ?? 'pending').toString();
        _statuses[id] = current;
        _remarks[id] = TextEditingController(text: seat['attendance_remark']?.toString() ?? '');
        _internalRemarks[id] = TextEditingController(text: seat['internal_remark']?.toString() ?? '');
      }
      if (!mounted) return;
      setState(() {
        _duty = Map<String, dynamic>.from(data['duty'] as Map);
        _seats = seats;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _markAllPresent() {
    setState(() {
      for (final seat in _seats) {
        _statuses[int.parse(seat['id'].toString())] = 'present';
      }
    });
  }

  Future<void> _save() async {
    final pending = _statuses.values.where((status) => status == 'pending').length;
    if (pending > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Mark all students first. $pending attendance record(s) are pending.'), backgroundColor: Colors.orange.shade800));
      return;
    }
    setState(() => _saving = true);
    try {
      final records = _seats.map((seat) {
        final id = int.parse(seat['id'].toString());
        return {
          'seat_assignment_id': id,
          'status': _statuses[id],
          'remark': _remarks[id]?.text.trim() ?? '',
          'internal_remark': _internalRemarks[id]?.text.trim() ?? '',
        };
      }).toList();
      final result = await ExamSeatingApi.saveAttendance(widget.assignmentId, records);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Attendance saved. ${result['notifications_sent'] ?? 0} student notification(s) sent.')));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString()), backgroundColor: Colors.red.shade700));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _studentTile(Map<String, dynamic> seat) {
    final id = int.parse(seat['id'].toString());
    final student = _map(seat['student']);
    final studentClass = _map(student['Class']);
    final section = _map(student['Section']);
    final schedule = _map(seat['schedule']);
    final subject = _map(schedule['subject']);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: CircleAvatar(child: Text(seat['seat_number']?.toString() ?? '-')),
        title: Text(student['name']?.toString() ?? 'Student', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${studentClass['class_name'] ?? ''} ${section['section_name'] ?? ''} · ${subject['name'] ?? ''}\nAdm: ${student['admission_number'] ?? '-'}'),
        trailing: SizedBox(
          width: 108,
          child: DropdownButtonFormField<String>(
            value: _statuses[id],
            isDense: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
            items: const [
              DropdownMenuItem(value: 'pending', child: Text('Pending')),
              DropdownMenuItem(value: 'present', child: Text('Present')),
              DropdownMenuItem(value: 'absent', child: Text('Absent')),
              DropdownMenuItem(value: 'late', child: Text('Late')),
            ],
            onChanged: (value) => setState(() => _statuses[id] = value ?? 'pending'),
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          TextField(
            controller: _remarks[id],
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Student-visible remark (optional)', hintText: 'Arrived 10 minutes late', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _internalRemarks[id],
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Internal examination remark (optional)', hintText: 'Visible only to authorised staff', border: OutlineInputBorder()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final planRoom = _map(_duty['planRoom']);
    final room = _map(planRoom['room']);
    return Scaffold(
      appBar: AppBar(title: Text('Room ${room['room_code'] ?? room['name'] ?? ''} Attendance')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : Column(
                  children: [
                    Material(
                      color: Colors.indigo.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(child: Text('${_seats.length} assigned student(s)', style: const TextStyle(fontWeight: FontWeight.w700))),
                            OutlinedButton.icon(onPressed: _markAllPresent, icon: const Icon(Icons.done_all), label: const Text('Mark all present')),
                          ],
                        ),
                      ),
                    ),
                    Expanded(child: ListView(padding: const EdgeInsets.all(12), children: _seats.map(_studentTile).toList())),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded), label: const Text('Save room attendance'))),
                      ),
                    ),
                  ],
                ),
    );
  }
}
