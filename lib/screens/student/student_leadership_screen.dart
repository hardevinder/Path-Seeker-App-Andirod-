import 'package:flutter/material.dart';

import '../../services/student_leadership_api.dart';
import '../../widgets/student_drawer_menu.dart';

class StudentLeadershipScreen extends StatefulWidget {
  const StudentLeadershipScreen({super.key});

  @override
  State<StudentLeadershipScreen> createState() =>
      _StudentLeadershipScreenState();
}

class _StudentLeadershipScreenState extends State<StudentLeadershipScreen> {
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
      final data = await StudentLeadershipApi.myLeadership();
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

  Widget _card(Map<String, dynamic> a, {bool history = false}) {
    final position = Map<String, dynamic>.from((a['position'] as Map?) ?? {});
    final wing = Map<String, dynamic>.from((a['wing'] as Map?) ?? {});
    final house =
        Map<String, dynamic>.from((a['leadershipHouse'] as Map?) ?? {});
    final session = Map<String, dynamic>.from((a['session'] as Map?) ?? {});
    final duties = (a['duties'] as List?) ?? [];
    final scope = [wing['name'], house['house_name']]
        .where((v) => v != null && v.toString().trim().isNotEmpty)
        .join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: history
            ? const LinearGradient(
                colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)])
            : const LinearGradient(
                colors: [Color(0xFF312E81), Color(0xFF6366F1)]),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.06),
              blurRadius: 14,
              offset: const Offset(0, 6))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    color: history
                        ? Colors.indigo.withOpacity(.10)
                        : Colors.white.withOpacity(.16),
                    borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.workspace_premium_rounded,
                    color: history ? Colors.indigo : Colors.white, size: 28)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(_text(position['name'], 'Leadership Position'),
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: history
                              ? const Color(0xFF111827)
                              : Colors.white)),
                  if (scope.isNotEmpty)
                    Text(scope,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: history ? Colors.indigo : Colors.white70)),
                ])),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                    color: history
                        ? Colors.grey.shade200
                        : Colors.white.withOpacity(.16),
                    borderRadius: BorderRadius.circular(999)),
                child: Text(_text(a['status']).toUpperCase(),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: history ? Colors.black54 : Colors.white))),
          ]),
          const SizedBox(height: 12),
          Text('Session ${_text(session['name'])}',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: history ? Colors.black87 : Colors.white)),
          const SizedBox(height: 4),
          Text(
              'Tenure: ${_text(a['start_date'])}${a['end_date'] != null ? ' – ${_text(a['end_date'])}' : ''}',
              style: TextStyle(
                  fontSize: 12,
                  color: history ? Colors.black54 : Colors.white70)),
          if (_text(a['appointment_note'], '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_text(a['appointment_note']),
                style: TextStyle(
                    fontSize: 13,
                    color: history
                        ? Colors.black87
                        : Colors.white.withOpacity(.92)))
          ],
          if (duties.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('My Responsibilities',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: history ? Colors.black87 : Colors.white)),
            const SizedBox(height: 7),
            ...duties.take(6).map((raw) {
              final d = Map<String, dynamic>.from(raw as Map);
              return Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                            d['status'] == 'completed'
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_checked_rounded,
                            size: 16,
                            color: history ? Colors.indigo : Colors.white70),
                        const SizedBox(width: 7),
                        Expanded(
                            child: Text(
                                '${_text(d['title'])} • ${_text(d['status'])}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: history
                                        ? Colors.black87
                                        : Colors.white.withOpacity(.92))))
                      ]));
            }),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const StudentDrawerMenu(),
      appBar: AppBar(title: const Text('My Leadership')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 120),
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: Colors.red.shade300),
                    const SizedBox(height: 12),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Text(_error!, textAlign: TextAlign.center)),
                    const SizedBox(height: 14),
                    Center(
                        child: FilledButton(
                            onPressed: _load, child: const Text('Retry')))
                  ])
                : ListView(padding: const EdgeInsets.all(16), children: [
                    Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(16)),
                        child: const Row(children: [
                          Icon(Icons.emoji_events_rounded,
                              color: Color(0xFF4338CA)),
                          SizedBox(width: 10),
                          Expanded(
                              child: Text(
                                  'Leadership positions, responsibilities and completed tenures assigned by your school.',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF312E81))))
                        ])),
                    const SizedBox(height: 18),
                    const Text('Current Leadership',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    if (_active.isEmpty)
                      Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(16)),
                          child: const Text(
                              'No active leadership position is currently assigned.',
                              textAlign: TextAlign.center)),
                    ..._active.map(
                        (raw) => _card(Map<String, dynamic>.from(raw as Map))),
                    if (_history.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Text('Leadership History',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      ..._history.map((raw) => _card(
                          Map<String, dynamic>.from(raw as Map),
                          history: true)),
                    ],
                  ]),
      ),
    );
  }
}
