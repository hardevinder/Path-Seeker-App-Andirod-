import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/answer_script_api.dart';
import '../../widgets/student_drawer_menu.dart';

class StudentAnswerScriptStatusScreen extends StatefulWidget {
  const StudentAnswerScriptStatusScreen({super.key});

  @override
  State<StudentAnswerScriptStatusScreen> createState() =>
      _StudentAnswerScriptStatusScreenState();
}

class _StudentAnswerScriptStatusScreenState
    extends State<StudentAnswerScriptStatusScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _students = const [];

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<Map<String, dynamic>> _list(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

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
      final rows = await AnswerScriptApi.myStudentStatuses();
      if (mounted) setState(() => _students = rows);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _label(String status) {
    switch (status) {
      case 'received':
        return 'Received by Examination Department';
      case 'under_checking':
        return 'Under checking';
      case 'checked':
        return 'Checking completed';
      case 'rechecking':
        return 'Under rechecking';
      case 'completed':
        return 'Finalized';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  Color _color(String status) {
    switch (status) {
      case 'completed':
      case 'checked':
        return Colors.green;
      case 'rechecking':
        return Colors.deepOrange;
      case 'under_checking':
        return Colors.indigo;
      default:
        return Colors.blueGrey;
    }
  }

  Widget _bundleCard(Map<String, dynamic> bundle) {
    final plan = _map(bundle['plan']);
    final exam = _map(plan['exam']);
    final subject = _map(bundle['subject']);
    final status = (bundle['public_status'] ?? 'received').toString();
    final updated = DateTime.tryParse(bundle['updatedAt']?.toString() ?? '');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: _color(status).withValues(alpha: .12),
              child: Icon(Icons.description_rounded, color: _color(status)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject['name']?.toString() ?? 'Answer Script',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(exam['name']?.toString() ?? plan['name']?.toString() ?? 'Examination'),
                  const SizedBox(height: 8),
                  Text(
                    _label(status),
                    style: TextStyle(
                      color: _color(status),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (updated != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Updated ${DateFormat('d MMM yyyy, h:mm a').format(updated.toLocal())}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recheckCard(Map<String, dynamic> request) {
    final bundle = _map(request['bundle']);
    final subject = _map(bundle['subject']);
    final status = (request['status'] ?? 'requested').toString();
    final visibleRemark = request['student_visible_remark']?.toString().trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${subject['name'] ?? 'Answer Script'} – Rechecking',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            Text('Status: ${status.replaceAll('_', ' ').toUpperCase()}'),
            if (visibleRemark != null && visibleRemark.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(visibleRemark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _studentBlock(Map<String, dynamic> record) {
    final student = _map(record['student']);
    final bundles = _list(record['bundles']);
    final rechecks = _list(record['rechecks']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_students.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${student['name'] ?? 'Student'} · ${student['admission_number'] ?? ''}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
        if (bundles.isEmpty && rechecks.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey.shade600),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'No answer-script status has been published yet.',
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          ...bundles.map(_bundleCard),
          if (rechecks.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(top: 6, bottom: 8),
              child: Text(
                'Rechecking requests',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ),
            ...rechecks.map(_recheckCard),
          ],
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Answer Script Status'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      drawer: const StudentDrawerMenu(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _StateMessage(
                  icon: Icons.error_outline,
                  title: 'Unable to load status',
                  message: _error!,
                  onRetry: _load,
                )
              : _students.isEmpty
                  ? _StateMessage(
                      icon: Icons.description_outlined,
                      title: 'No answer-script status',
                      message:
                          'Published checking and rechecking updates will appear here.',
                      onRetry: _load,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: _students.map(_studentBlock).toList(),
                      ),
                    ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
  });

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
              Text(
                title,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
}
