import 'package:flutter/material.dart';

import '../../services/department_management_api.dart';
import '../../widgets/student_drawer_menu.dart';

class StudentDepartmentActivitiesScreen extends StatefulWidget {
  const StudentDepartmentActivitiesScreen({super.key});

  @override
  State<StudentDepartmentActivitiesScreen> createState() =>
      _StudentDepartmentActivitiesScreenState();
}

class _StudentDepartmentActivitiesScreenState
    extends State<StudentDepartmentActivitiesScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _participations = const [];
  List<dynamic> _achievements = const [];

  Map<String, dynamic> _map(dynamic value) =>
      value is Map<String, dynamic> ? value : <String, dynamic>{};

  String _text(dynamic value, [String fallback = '—']) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await DepartmentManagementApi.studentActivities();
      if (!mounted) return;
      setState(() {
        _participations = data['participations'] is List
            ? data['participations'] as List
            : const [];
        _achievements = data['achievements'] is List
            ? data['achievements'] as List
            : const [];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Widget _empty(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(text, style: const TextStyle(color: Colors.black54)),
    );
  }

  Widget _status(dynamic value) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(
        _text(value, 'RECORDED').replaceAll('_', ' '),
        style: const TextStyle(fontSize: 10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Activities & Achievements'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      drawer: const StudentDrawerMenu(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _summaryCard(
                              'Participations',
                              _participations.length,
                              Icons.groups_rounded,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _summaryCard(
                              'Achievements',
                              _achievements.length,
                              Icons.emoji_events_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Events & Competitions',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      if (_participations.isEmpty)
                        _empty('No department event participation recorded yet.')
                      else
                        ..._participations.map((raw) {
                          final participation = _map(raw);
                          final event = _map(participation['event']);
                          final department = _map(event['department']);
                          return Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.event_available_rounded),
                              ),
                              title: Text(_text(event['title'])),
                              subtitle: Text(
                                '${_text(department['name'], 'School')} • ${_text(event['start_date'])}\n'
                                '${_text(participation['participant_role'], 'PARTICIPANT').replaceAll('_', ' ')} • ${_text(participation['position'], _text(participation['result'], 'Result pending'))}',
                              ),
                              isThreeLine: true,
                              trailing: _status(participation['participation_status']),
                            ),
                          );
                        }),
                      const SizedBox(height: 18),
                      const Text(
                        'My Achievements',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      if (_achievements.isEmpty)
                        _empty('No verified achievement recorded yet.')
                      else
                        ..._achievements.map((raw) {
                          final achievement = _map(raw);
                          final department = _map(achievement['department']);
                          return Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.emoji_events_rounded),
                              ),
                              title: Text(_text(achievement['title'])),
                              subtitle: Text(
                                '${_text(department['name'], 'School')} • ${_text(achievement['achievement_date'])}\n'
                                '${_text(achievement['level'], 'SCHOOL')} • ${_text(achievement['position'], 'Achievement')}',
                              ),
                              isThreeLine: true,
                              trailing: _status(achievement['status']),
                            ),
                          );
                        }),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
    );
  }

  Widget _summaryCard(String label, int value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.indigo, size: 30),
          const SizedBox(height: 6),
          Text(
            '$value',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          Text(label, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}
