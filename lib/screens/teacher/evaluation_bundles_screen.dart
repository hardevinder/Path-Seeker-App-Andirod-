import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/answer_script_api.dart';
import '../../widgets/teacher_drawer_menu.dart';

class EvaluationBundlesScreen extends StatefulWidget {
  const EvaluationBundlesScreen({super.key});

  @override
  State<EvaluationBundlesScreen> createState() =>
      _EvaluationBundlesScreenState();
}

class _EvaluationBundlesScreenState extends State<EvaluationBundlesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _assignments = const [];

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
      final rows = await AnswerScriptApi.myAssignments();
      if (mounted) setState(() => _assignments = rows);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
      case 'returned':
        return Colors.green;
      case 'declined':
      case 'cancelled':
        return Colors.red;
      case 'accepted':
      case 'checking':
        return Colors.indigo;
      default:
        return Colors.orange;
    }
  }

  String _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return value?.toString() ?? '-';
    return DateFormat('d MMM yyyy, h:mm a').format(parsed.toLocal());
  }

  Widget _card(Map<String, dynamic> assignment) {
    final bundle = _map(assignment['bundle']);
    final classValue = _map(bundle['class']);
    final section = _map(bundle['section']);
    final subject = _map(bundle['subject']);
    final status = (assignment['status'] ?? 'assigned').toString();
    final total = int.tryParse('${bundle['script_count'] ?? 0}') ?? 0;
    final checked = int.tryParse('${assignment['checked_count'] ?? 0}') ?? 0;
    final progress = total <= 0
        ? 0.0
        : (checked / total).clamp(0.0, 1.0).toDouble();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EvaluationBundleDetailScreen(
                assignmentId: int.parse(assignment['id'].toString()),
              ),
            ),
          );
          await _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 25,
                    child: Icon(Icons.fact_check_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bundle['bundle_number']?.toString() ?? 'Evaluation Bundle',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${classValue['class_name'] ?? '-'}${section['section_name'] == null ? '' : ' – ${section['section_name']}'} · ${subject['name'] ?? '-'}',
                        ),
                        Text(
                          '${assignment['assignment_type'] == 'rechecking' ? 'Rechecking' : 'Evaluation'} · Due ${_date(assignment['due_at'])}',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                  Chip(
                    backgroundColor: _statusColor(status).withValues(alpha: .12),
                    label: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        color: _statusColor(status),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$checked / $total scripts checked',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text('${(progress * 100).round()}%'),
                ],
              ),
              const SizedBox(height: 7),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EvaluationBundleDetailScreen(
                          assignmentId: int.parse(assignment['id'].toString()),
                        ),
                      ),
                    );
                    await _load();
                  },
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open bundle record'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Evaluation Bundles'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      drawer: const TeacherDrawerMenu(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _StateMessage(
                  icon: Icons.error_outline,
                  title: 'Unable to load bundles',
                  message: _error!,
                  onRetry: _load,
                )
              : _assignments.isEmpty
                  ? _StateMessage(
                      icon: Icons.fact_check_outlined,
                      title: 'No evaluation bundle assigned',
                      message:
                          'Bundles issued by the Examination Department will appear here.',
                      onRetry: _load,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: _assignments.map(_card).toList(),
                      ),
                    ),
    );
  }
}

class EvaluationBundleDetailScreen extends StatefulWidget {
  const EvaluationBundleDetailScreen({
    super.key,
    required this.assignmentId,
  });

  final int assignmentId;

  @override
  State<EvaluationBundleDetailScreen> createState() =>
      _EvaluationBundleDetailScreenState();
}

class _EvaluationBundleDetailScreenState
    extends State<EvaluationBundleDetailScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _assignment = {};
  final _checkedController = TextEditingController();
  final _remarksController = TextEditingController();

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _checkedController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final record = await AnswerScriptApi.assignment(widget.assignmentId);
      _checkedController.text = '${record['checked_count'] ?? 0}';
      _remarksController.text = record['evaluator_remarks']?.toString() ?? '';
      if (mounted) setState(() => _assignment = record);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _action(Future<void> Function() request, String message) async {
    setState(() => _saving = true);
    try {
      await request();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _decline() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reason for declining'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Enter reason',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) return;
    await _action(
      () => AnswerScriptApi.declineAssignment(widget.assignmentId, reason),
      'Bundle assignment declined.',
    );
  }

  int get _checked => int.tryParse(_checkedController.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Evaluation Bundle')),
        body: _StateMessage(
          icon: Icons.error_outline,
          title: 'Unable to load bundle',
          message: _error!,
          onRetry: _load,
        ),
      );
    }

    final bundle = _map(_assignment['bundle']);
    final plan = _map(bundle['plan']);
    final exam = _map(plan['exam']);
    final classValue = _map(bundle['class']);
    final section = _map(bundle['section']);
    final subject = _map(bundle['subject']);
    final status = (_assignment['status'] ?? 'assigned').toString();
    final total = int.tryParse('${bundle['script_count'] ?? 0}') ?? 0;
    final canEdit = {'accepted', 'checking'}.contains(status);

    return Scaffold(
      appBar: AppBar(
        title: Text(bundle['bundle_number']?.toString() ?? 'Evaluation Bundle'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exam['name']?.toString() ?? plan['name']?.toString() ?? 'Examination',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  _row('Class / Section',
                      '${classValue['class_name'] ?? '-'}${section['section_name'] == null ? '' : ' – ${section['section_name']}'}'),
                  _row('Subject', subject['name'] ?? '-'),
                  _row('Scripts', total),
                  _row('Assignment',
                      _assignment['assignment_type'] == 'rechecking' ? 'Rechecking' : 'Evaluation'),
                  _row('Status', status.replaceAll('_', ' ').toUpperCase()),
                  _row('Issued at', _formatDate(_assignment['issued_at'])),
                  _row('Deadline', _formatDate(_assignment['due_at'])),
                  if ((bundle['evaluator_instructions'] ?? '').toString().trim().isNotEmpty)
                    _row('Instructions', bundle['evaluator_instructions']),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _checkedController,
            enabled: canEdit,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Scripts checked (maximum $total)',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _remarksController,
            enabled: canEdit,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Evaluator remarks (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (status == 'assigned')
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : _decline,
                    child: const Text('Unable to evaluate'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving
                        ? null
                        : () => _action(
                              () => AnswerScriptApi.acceptAssignment(
                                widget.assignmentId,
                              ),
                              'Evaluation bundle accepted.',
                            ),
                    child: const Text('Accept bundle'),
                  ),
                ),
              ],
            ),
          if (canEdit) ...[
            OutlinedButton.icon(
              onPressed: _saving || _checked > total
                  ? null
                  : () => _action(
                        () => AnswerScriptApi.updateProgress(
                          widget.assignmentId,
                          checkedCount: _checked,
                          remarks: _remarksController.text.trim(),
                        ),
                        'Checking progress updated.',
                      ),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save checking progress'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _saving || _checked != total
                  ? null
                  : () => _action(
                        () => AnswerScriptApi.completeAssignment(
                          widget.assignmentId,
                          checkedCount: _checked,
                          remarks: _remarksController.text.trim(),
                        ),
                        'Checking marked complete.',
                      ),
              icon: const Icon(Icons.task_alt_rounded),
              label: Text(
                _checked == total
                    ? 'Complete checking'
                    : 'Check all $total scripts to complete',
              ),
            ),
          ],
          if (status == 'completed')
            FilledButton.icon(
              onPressed: _saving
                  ? null
                  : () => _action(
                        () => AnswerScriptApi.returnAssignment(
                          widget.assignmentId,
                          remarks: _remarksController.text.trim(),
                        ),
                        'Bundle returned to Examination Department.',
                      ),
              icon: const Icon(Icons.assignment_return_rounded),
              label: const Text('Return bundle'),
            ),
          if ({'returned', 'declined', 'cancelled'}.contains(status))
            Card(
              color: status == 'returned' ? Colors.green.shade50 : Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  status == 'returned'
                      ? 'This bundle has been returned to the Examination Department.'
                      : 'This assignment is ${status.replaceAll('_', ' ')}.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          if (_saving) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, dynamic value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Text(label, style: TextStyle(color: Colors.grey.shade700)),
            ),
            Expanded(
              child: Text(
                value?.toString() ?? '-',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );

  String _formatDate(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return value?.toString() ?? '-';
    return DateFormat('d MMM yyyy, h:mm a').format(parsed.toLocal());
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
