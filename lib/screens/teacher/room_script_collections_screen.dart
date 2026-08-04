import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/answer_script_api.dart';
import '../../widgets/teacher_drawer_menu.dart';

class RoomScriptCollectionsScreen extends StatefulWidget {
  const RoomScriptCollectionsScreen({super.key});

  @override
  State<RoomScriptCollectionsScreen> createState() =>
      _RoomScriptCollectionsScreenState();
}

class _RoomScriptCollectionsScreenState
    extends State<RoomScriptCollectionsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _collections = const [];

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
      final rows = await AnswerScriptApi.myRoomCollections();
      if (mounted) setState(() => _collections = rows);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _date(dynamic raw) {
    final value = raw?.toString() ?? '';
    final parsed = DateTime.tryParse(value);
    return parsed == null ? value : DateFormat('EEE, d MMM yyyy').format(parsed);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'received':
      case 'reconciled':
      case 'sorted':
        return Colors.green;
      case 'count_mismatch':
        return Colors.red;
      case 'collected':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  Widget _card(Map<String, dynamic> collection) {
    final plan = _map(collection['plan']);
    final exam = _map(plan['exam']);
    final planRoom = _map(collection['planRoom']);
    final room = _map(planRoom['room']);
    final status = (collection['status'] ?? 'pending').toString();
    final expected = int.tryParse('${collection['expected_count'] ?? 0}') ?? 0;
    final collected = int.tryParse('${collection['collected_count'] ?? 0}') ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RoomScriptCollectionDetailScreen(
                collectionId: int.parse(collection['id'].toString()),
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
                    child: Icon(Icons.inventory_2_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room['name']?.toString() ??
                              room['room_code']?.toString() ??
                              'Exam Room',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          exam['name']?.toString() ??
                              plan['name']?.toString() ??
                              'Examination',
                        ),
                        Text(
                          '${_date(plan['exam_date'])} · ${plan['start_time'] ?? ''}–${plan['end_time'] ?? ''}',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                  Chip(
                    backgroundColor: _statusColor(status).withValues(alpha: .12),
                    label: Text(
                      status.replaceAll('_', ' ').toUpperCase(),
                      style: TextStyle(
                        color: _statusColor(status),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 28),
              Row(
                children: [
                  Expanded(child: _count('Expected', expected)),
                  Expanded(child: _count('Collected', collected)),
                  Expanded(child: _count('Difference', collected - expected)),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RoomScriptCollectionDetailScreen(
                          collectionId:
                              int.parse(collection['id'].toString()),
                        ),
                      ),
                    );
                    await _load();
                  },
                  icon: const Icon(Icons.fact_check_rounded),
                  label: Text(
                    collection['handed_over_at'] == null
                        ? 'Record and hand over scripts'
                        : 'View collection record',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _count(String label, int value) => Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Room Script Collections'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      drawer: const TeacherDrawerMenu(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _StateMessage(
                  icon: Icons.error_outline,
                  title: 'Unable to load collections',
                  message: _error!,
                  onRetry: _load,
                )
              : _collections.isEmpty
                  ? _StateMessage(
                      icon: Icons.inventory_2_outlined,
                      title: 'No room collection assigned',
                      message:
                          'Answer-script collection records will appear after the Examination Department generates them.',
                      onRetry: _load,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: _collections.map(_card).toList(),
                      ),
                    ),
    );
  }
}

class RoomScriptCollectionDetailScreen extends StatefulWidget {
  const RoomScriptCollectionDetailScreen({
    super.key,
    required this.collectionId,
  });

  final int collectionId;

  @override
  State<RoomScriptCollectionDetailScreen> createState() =>
      _RoomScriptCollectionDetailScreenState();
}

class _RoomScriptCollectionDetailScreenState
    extends State<RoomScriptCollectionDetailScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _collection = {};
  final _collectedController = TextEditingController();
  final _damagedController = TextEditingController();
  final _extraController = TextEditingController();
  final _remarksController = TextEditingController();
  final Map<int, TextEditingController> _groupCounts = {};
  final Map<int, TextEditingController> _groupRemarks = {};

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

  @override
  void dispose() {
    _collectedController.dispose();
    _damagedController.dispose();
    _extraController.dispose();
    _remarksController.dispose();
    for (final controller in [..._groupCounts.values, ..._groupRemarks.values]) {
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
      final record = await AnswerScriptApi.roomCollection(widget.collectionId);
      for (final controller in [..._groupCounts.values, ..._groupRemarks.values]) {
        controller.dispose();
      }
      _groupCounts.clear();
      _groupRemarks.clear();
      for (final group in _list(record['groups'])) {
        final id = int.parse(group['id'].toString());
        _groupCounts[id] = TextEditingController(
          text: '${group['collected_count'] ?? group['expected_count'] ?? 0}',
        );
        _groupRemarks[id] =
            TextEditingController(text: group['remarks']?.toString() ?? '');
      }
      _collectedController.text = '${record['collected_count'] ?? 0}';
      _damagedController.text = '${record['damaged_count'] ?? 0}';
      _extraController.text = '${record['extra_sheet_count'] ?? 0}';
      _remarksController.text = record['invigilator_remarks']?.toString() ?? '';
      if (mounted) setState(() => _collection = record);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _number(TextEditingController controller) =>
      int.tryParse(controller.text.trim()) ?? 0;

  List<Map<String, dynamic>> _groupPayload() => _list(_collection['groups'])
      .map((group) {
        final id = int.parse(group['id'].toString());
        return {
          'id': id,
          'collected_count': _number(_groupCounts[id]!),
          'remarks': _groupRemarks[id]!.text.trim(),
        };
      })
      .toList();

  int get _groupTotal => _groupCounts.values.fold<int>(
        0,
        (sum, controller) => sum + _number(controller),
      );

  Future<bool> _save({bool showMessage = true}) async {
    setState(() => _saving = true);
    try {
      final groups = _groupPayload();
      final record = await AnswerScriptApi.saveRoomCollection(
        widget.collectionId,
        collectedCount: groups.isEmpty ? _number(_collectedController) : _groupTotal,
        damagedCount: _number(_damagedController),
        extraSheetCount: _number(_extraController),
        invigilatorRemarks: _remarksController.text.trim(),
        groups: groups,
      );
      if (!mounted) return false;
      setState(() => _collection = record);
      if (showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Collection record saved.')),
        );
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handover() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hand over answer scripts?'),
        content: Text(
          'Expected: ${_collection['expected_count'] ?? 0}\n'
          'Collected: ${_groupCounts.isEmpty ? _number(_collectedController) : _groupTotal}\n\n'
          'This will record the handover time for the Examination Department.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm handover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!await _save(showMessage: false)) return;

    setState(() => _saving = true);
    try {
      await AnswerScriptApi.handoverRoomCollection(
        widget.collectionId,
        collectedCount:
            _groupCounts.isEmpty ? _number(_collectedController) : _groupTotal,
        damagedCount: _number(_damagedController),
        extraSheetCount: _number(_extraController),
        remarks: _remarksController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Answer scripts handed over.')),
      );
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

  Widget _groupCard(Map<String, dynamic> group) {
    final id = int.parse(group['id'].toString());
    final classValue = _map(group['class']);
    final section = _map(group['section']);
    final subject = _map(group['subject']);
    final schedule = _map(group['schedule']);
    final scheduleClass = _map(schedule['class']);
    final scheduleSection = _map(schedule['section']);
    final scheduleSubject = _map(schedule['subject']);
    final className = classValue['class_name'] ?? scheduleClass['class_name'] ?? '-';
    final sectionName = section['section_name'] ?? scheduleSection['section_name'] ?? '';
    final subjectName = subject['name'] ?? scheduleSubject['name'] ?? '-';

    return Card(
      color: Colors.grey.shade50,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$className${sectionName.toString().isEmpty ? '' : ' – $sectionName'} · $subjectName',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text('Expected scripts: ${group['expected_count'] ?? 0}'),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _groupCounts[id],
                    keyboardType: TextInputType.number,
                    enabled: _collection['handed_over_at'] == null,
                    decoration: const InputDecoration(
                      labelText: 'Collected',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: TextField(
                    controller: _groupRemarks[id],
                    enabled: _collection['handed_over_at'] == null,
                    decoration: const InputDecoration(
                      labelText: 'Optional remark',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Room Collection')),
        body: _StateMessage(
          icon: Icons.error_outline,
          title: 'Unable to load collection',
          message: _error!,
          onRetry: _load,
        ),
      );
    }

    final planRoom = _map(_collection['planRoom']);
    final room = _map(planRoom['room']);
    final groups = _list(_collection['groups']);
    final locked = _collection['handed_over_at'] != null;
    final expected = int.tryParse('${_collection['expected_count'] ?? 0}') ?? 0;
    final currentCollected = groups.isEmpty ? _number(_collectedController) : _groupTotal;

    return Scaffold(
      appBar: AppBar(
        title: Text(room['name']?.toString() ?? 'Room Collection'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: locked ? Colors.green.shade50 : Colors.indigo.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    locked ? Icons.verified_rounded : Icons.inventory_2_rounded,
                    size: 34,
                    color: locked ? Colors.green : Colors.indigo,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          locked ? 'Handed over' : 'Room answer-script count',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Expected $expected · Collected $currentCollected · Difference ${currentCollected - expected}',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (groups.isNotEmpty) ...[
            const Text(
              'Class / section / subject breakup',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            ...groups.map(_groupCard),
          ] else ...[
            TextField(
              controller: _collectedController,
              keyboardType: TextInputType.number,
              enabled: !locked,
              decoration: const InputDecoration(
                labelText: 'Total collected answer scripts',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _damagedController,
                  keyboardType: TextInputType.number,
                  enabled: !locked,
                  decoration: const InputDecoration(
                    labelText: 'Damaged scripts',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _extraController,
                  keyboardType: TextInputType.number,
                  enabled: !locked,
                  decoration: const InputDecoration(
                    labelText: 'Extra sheets',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _remarksController,
            enabled: !locked,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Invigilator remarks (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (!locked)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _save(),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save draft'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _handover,
                    icon: const Icon(Icons.handshake_rounded),
                    label: const Text('Hand over'),
                  ),
                ),
              ],
            )
          else
            FilledButton.icon(
              onPressed: null,
              icon: const Icon(Icons.lock_rounded),
              label: const Text('Collection handed over to Examination Department'),
            ),
          if (_saving) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(),
          ],
        ],
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
