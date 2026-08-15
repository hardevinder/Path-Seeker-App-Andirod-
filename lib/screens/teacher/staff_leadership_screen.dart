import 'package:flutter/material.dart';

import '../../services/staff_leadership_api.dart';
import '../../widgets/teacher_drawer_menu.dart';

class StaffLeadershipScreen extends StatefulWidget {
  const StaffLeadershipScreen({super.key});

  @override
  State<StaffLeadershipScreen> createState() => _StaffLeadershipScreenState();
}

class _StaffLeadershipScreenState extends State<StaffLeadershipScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _active = [];
  List<dynamic> _history = [];

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
      final data = await StaffLeadershipApi.myLeadership();
      if (!mounted) return;
      setState(() {
        _active = (data['active'] as List?) ?? [];
        _history = (data['history'] as List?) ?? [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _text(dynamic v, [String fallback = '-']) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? fallback : s;
  }

  Future<void> _updateDuty(Map<String, dynamic> duty, String status) async {
    final id = int.tryParse(duty['id']?.toString() ?? '');
    if (id == null) return;
    try {
      await StaffLeadershipApi.updateDuty(id, status);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(status == 'completed' ? 'Duty marked complete.' : 'Duty acknowledged.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Widget _card(Map<String, dynamic> a, {bool history = false}) {
    final position = Map<String, dynamic>.from((a['position'] as Map?) ?? {});
    final wing = Map<String, dynamic>.from((a['wing'] as Map?) ?? {});
    final house = Map<String, dynamic>.from((a['leadershipHouse'] as Map?) ?? {});
    final session = Map<String, dynamic>.from((a['session'] as Map?) ?? {});
    final duties = (a['duties'] as List?) ?? [];
    final linked = (a['linked_student_leaders'] as List?) ?? [];
    final scope = [wing['name'], house['house_name']]
        .where((v) => v != null && v.toString().trim().isNotEmpty)
        .join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: history
            ? const LinearGradient(colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)])
            : const LinearGradient(colors: [Color(0xFF134E4A), Color(0xFF0F766E)]),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: history ? Colors.teal.withOpacity(.10) : Colors.white.withOpacity(.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.groups_3_rounded,
                    color: history ? Colors.teal : Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _text(position['name'], 'Leadership Responsibility'),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: history ? const Color(0xFF111827) : Colors.white,
                        ),
                      ),
                      if (scope.isNotEmpty)
                        Text(
                          scope,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: history ? Colors.teal : Colors.white70,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Session ${_text(session['name'])}',
              style: TextStyle(fontWeight: FontWeight.w700, color: history ? Colors.black87 : Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              'Tenure: ${_text(a['start_date'])}${a['end_date'] != null ? ' – ${_text(a['end_date'])}' : ''}',
              style: TextStyle(fontSize: 12, color: history ? Colors.black54 : Colors.white70),
            ),
            if (linked.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Student Leaders Linked With You',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: history ? Colors.black87 : Colors.white),
              ),
              const SizedBox(height: 7),
              ...linked.take(8).map((raw) {
                final item = Map<String, dynamic>.from(raw as Map);
                final student = Map<String, dynamic>.from((item['student'] as Map?) ?? {});
                final studentPosition = Map<String, dynamic>.from((item['position'] as Map?) ?? {});
                return Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    '• ${_text(student['name'])} — ${_text(studentPosition['name'])}',
                    style: TextStyle(fontSize: 12, color: history ? Colors.black87 : Colors.white.withOpacity(.92)),
                  ),
                );
              }),
            ],
            if (duties.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'My Responsibilities',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: history ? Colors.black87 : Colors.white),
              ),
              const SizedBox(height: 7),
              ...duties.take(8).map((raw) {
                final d = Map<String, dynamic>.from(raw as Map);
                final status = _text(d['status']);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: history ? Colors.white : Colors.white.withOpacity(.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _text(d['title']),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: history ? Colors.black87 : Colors.white),
                      ),
                      if (_text(d['description'], '').isNotEmpty)
                        Text(
                          _text(d['description']),
                          style: TextStyle(fontSize: 11, color: history ? Colors.black54 : Colors.white70),
                        ),
                      if (!history && ['assigned', 'acknowledged'].contains(status)) ...[
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (status == 'assigned')
                              OutlinedButton(
                                onPressed: () => _updateDuty(d, 'acknowledged'),
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                                child: const Text('Acknowledge'),
                              ),
                            FilledButton(
                              onPressed: () => _updateDuty(d, 'completed'),
                              child: const Text('Mark Complete'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const TeacherDrawerMenu(),
      appBar: AppBar(title: const Text('My Leadership & Responsibilities')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade300),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                      const SizedBox(height: 14),
                      Center(child: FilledButton(onPressed: _load, child: const Text('Retry'))),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: const Color(0xFFCCFBF1), borderRadius: BorderRadius.circular(16)),
                        child: const Row(
                          children: [
                            Icon(Icons.groups_3_rounded, color: Color(0xFF0F766E)),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'School, wing and house responsibilities, linked student leaders and assigned duties.',
                                style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF134E4A)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text('Current Responsibilities', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      if (_active.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16)),
                          child: const Text('No active staff leadership responsibility is currently assigned.', textAlign: TextAlign.center),
                        ),
                      ..._active.map((raw) => _card(Map<String, dynamic>.from(raw as Map))),
                      if (_history.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const Text('Responsibility History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        ..._history.map((raw) => _card(Map<String, dynamic>.from(raw as Map), history: true)),
                      ],
                    ],
                  ),
      ),
    );
  }
}
