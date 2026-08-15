import 'package:flutter/material.dart';
import '../../services/house_duty_api.dart';

class HouseDutyScreen extends StatefulWidget {
  const HouseDutyScreen({super.key});
  @override
  State<HouseDutyScreen> createState() => _HouseDutyScreenState();
}

class _HouseDutyScreenState extends State<HouseDutyScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

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
      final d = await HouseDutyApi.myDuties();
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(int id, String status) async {
    try {
      await HouseDutyApi.updateDuty(id, status);
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update duty: $e')));
    }
  }

  String _slotLabel(dynamic value) {
    final raw = (value ?? 'custom').toString().replaceAll('_', ' ');
    return raw.isEmpty ? 'Custom' : raw[0].toUpperCase() + raw.substring(1);
  }

  String _timeLabel(dynamic start, dynamic end) {
    String short(dynamic v) {
      final t = (v ?? '').toString();
      return t.length >= 5 ? t.substring(0, 5) : t;
    }

    final s = short(start);
    final e = short(end);
    if (s.isEmpty) return '';
    return e.isEmpty ? s : '$s–$e';
  }

  Color _statusColor(String value) {
    switch (value.toLowerCase()) {
      case 'present':
        return Colors.green;
      case 'absent':
        return Colors.red;
      case 'excused':
        return Colors.orange;
      case 'completed':
        return Colors.teal;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final duties = List<Map<String, dynamic>>.from((_data?['duties'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map)) ??
        const []);
    final summary =
        Map<String, dynamic>.from((_data?['summary'] as Map?) ?? const {});
    return Scaffold(
      appBar: AppBar(title: const Text('My House Duties & Assembly')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(
                children: const [
                  SizedBox(height: 220),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null
                ? ListView(children: [
                    Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.red)))
                  ])
                : ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Expanded(
                                  child: _metric(
                                      'Duties', '${summary['total'] ?? 0}')),
                              Expanded(
                                  child: _metric(
                                      'Rated', '${summary['rated'] ?? 0}')),
                              Expanded(
                                  child: _metric(
                                      'Average',
                                      summary['average_rating'] == null
                                          ? '—'
                                          : '${summary['average_rating']}/5')),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (duties.isEmpty)
                        const Card(
                            child: Padding(
                                padding: EdgeInsets.all(22),
                                child: Text(
                                    'No House / Assembly duties assigned.'))),
                      ...duties.map((d) {
                        final week = Map<String, dynamic>.from(
                            (d['week'] as Map?) ?? const {});
                        final house = Map<String, dynamic>.from(
                            (week['house'] as Map?) ?? const {});
                        final dutyType = Map<String, dynamic>.from(
                            (d['dutyType'] as Map?) ?? const {});
                        final attendance =
                            '${d['attendance_status'] ?? 'not_marked'}';
                        final status = '${d['status'] ?? 'assigned'}';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                      child: Text(
                                          '${d['title'] ?? dutyType['name'] ?? 'House Duty'}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16))),
                                  Chip(
                                      label:
                                          Text(attendance.replaceAll('_', ' ')),
                                      side: BorderSide.none,
                                      backgroundColor: _statusColor(attendance)
                                          .withOpacity(.12),
                                      labelStyle: TextStyle(
                                          color: _statusColor(attendance))),
                                ]),
                                Text(
                                    '${d['duty_date'] ?? ''} • ${house['house_name'] ?? ''} • ${_slotLabel(d['time_slot'])}${d['location'] == null ? '' : ' • ${d['location']}'}${_timeLabel(d['start_time'], d['end_time']).isEmpty ? '' : ' • ${_timeLabel(d['start_time'], d['end_time'])}'}',
                                    style:
                                        TextStyle(color: Colors.grey.shade700)),
                                if (d['supervisor'] is Map)
                                  Text(
                                      'Supervisor: ${(d['supervisor'] as Map)['name'] ?? ''}',
                                      style: TextStyle(
                                          color: Colors.grey.shade700)),
                                if (d['overall_rating'] != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                      'Performance: ${d['overall_rating']}/5 ⭐',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  if ((d['performance_remark'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    Text('${d['performance_remark']}'),
                                ],
                                if (status == 'assigned') ...[
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                      onPressed: () => _setStatus(
                                          d['id'] as int, 'acknowledged'),
                                      icon: const Icon(
                                          Icons.check_circle_outline),
                                      label: const Text('Acknowledge Duty')),
                                ],
                                if (status == 'acknowledged') ...[
                                  const SizedBox(height: 10),
                                  FilledButton.icon(
                                      onPressed: () => _setStatus(
                                          d['id'] as int, 'completed'),
                                      icon: const Icon(Icons.task_alt),
                                      label: const Text('Mark Complete')),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
      ),
    );
  }

  Widget _metric(String label, String value) => Column(children: [
        Text(value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(fontSize: 12))
      ]);
}
