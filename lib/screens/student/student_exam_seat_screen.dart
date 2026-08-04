import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/exam_seating_api.dart';
import '../../widgets/student_drawer_menu.dart';

class StudentExamSeatScreen extends StatefulWidget {
  const StudentExamSeatScreen({super.key});

  @override
  State<StudentExamSeatScreen> createState() => _StudentExamSeatScreenState();
}

class _StudentExamSeatScreenState extends State<StudentExamSeatScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _seats = [];

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
      final seats = await ExamSeatingApi.mySeats(upcoming: false);
      if (!mounted) return;
      setState(() => _seats = seats);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _date(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    return parsed == null ? (raw?.toString() ?? '') : DateFormat('EEE, d MMM yyyy').format(parsed);
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return Colors.green;
      case 'absent':
        return Colors.red;
      case 'late':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  Widget _seatCard(Map<String, dynamic> seat) {
    final plan = _map(seat['plan']);
    final exam = _map(plan['exam']);
    final planRoom = _map(seat['planRoom']);
    final room = _map(planRoom['room']);
    final schedule = _map(seat['schedule']);
    final subject = _map(schedule['subject']);
    final status = (seat['attendance_status'] ?? 'pending').toString();
    final remark = (seat['attendance_remark'] ?? '').toString().trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.event_seat_rounded, color: Colors.indigo, size: 30),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject['name']?.toString() ?? exam['name']?.toString() ?? 'Examination',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_date(plan['exam_date'])} · ${plan['start_time'] ?? ''}–${plan['end_time'] ?? ''}',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(status.toUpperCase()),
                  labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                  backgroundColor: _statusColor(status),
                ),
              ],
            ),
            const Divider(height: 28),
            Row(
              children: [
                Expanded(child: _detail('Room', room['name'] ?? room['room_code'] ?? '-')),
                Expanded(child: _detail('Seat', seat['seat_number'] ?? '-')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _detail('Exam', exam['name'] ?? plan['name'] ?? '-')),
                Expanded(child: _detail('Reporting', plan['start_time'] ?? '-')),
              ],
            ),
            if (remark.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Text('Remark: $remark'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, dynamic value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 3),
          Text(value?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Exam Seat'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      drawer: const StudentDrawerMenu(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _StateMessage(icon: Icons.error_outline, title: 'Unable to load', message: _error!, onRetry: _load)
              : _seats.isEmpty
                  ? _StateMessage(icon: Icons.event_seat_outlined, title: 'No published seating plan', message: 'Your room and seat will appear here after the Examination Department publishes the plan.', onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: _seats.map(_seatCard).toList(),
                      ),
                    ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({required this.icon, required this.title, required this.message, required this.onRetry});
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 58, color: Colors.grey.shade500),
              const SizedBox(height: 14),
              Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
              const SizedBox(height: 18),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Refresh')),
            ],
          ),
        ),
      );
}
