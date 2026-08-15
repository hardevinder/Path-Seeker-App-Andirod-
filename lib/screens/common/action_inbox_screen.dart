import 'package:flutter/material.dart';
import '../../services/action_inbox_api.dart';

class ActionInboxScreen extends StatefulWidget {
  const ActionInboxScreen({super.key});
  @override
  State<ActionInboxScreen> createState() => _ActionInboxScreenState();
}

class _ActionInboxScreenState extends State<ActionInboxScreen> {
  bool _loading = true;
  String _error = '';
  Map<String, dynamic> _data = <String, dynamic>{};
  String _category = 'all';

  Future<void> _load() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final data = await ActionInboxApi.list(category: _category);
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<dynamic> get _actions => _data['actions'] is List ? List<dynamic>.from(_data['actions']) : <dynamic>[];
  Map<String, dynamic> get _summary => _data['summary'] is Map ? Map<String, dynamic>.from(_data['summary']) : <String, dynamic>{};

  Color _priorityColor(String p) {
    switch (p) {
      case 'urgent': return Colors.red.shade700;
      case 'high': return Colors.orange.shade800;
      case 'low': return Colors.blueGrey;
      default: return Colors.blue.shade700;
    }
  }

  IconData _icon(String source) {
    switch (source) {
      case 'parent_consent_scan': return Icons.draw_rounded;
      case 'document_verification': return Icons.verified_user_rounded;
      case 'lost_found_claim': return Icons.search_rounded;
      case 'assessment_review': return Icons.fact_check_rounded;
      case 'syllabus_approval': return Icons.menu_book_rounded;
      case 'employee_leave': return Icons.event_available_rounded;
      case 'department_task': return Icons.task_alt_rounded;
      case 'exam_recheck': return Icons.replay_rounded;
      case 'health_followup': return Icons.health_and_safety_rounded;
      case 'discipline_review': return Icons.report_problem_rounded;
      default: return Icons.inbox_rounded;
    }
  }

  String? _mobileRoute(String source) {
    switch (source) {
      case 'parent_consent_scan': return '/parent-consents';
      case 'document_verification': return '/document-vault';
      case 'lost_found_claim': return '/lost-found';
      case 'assessment_review': return '/assessments';
      case 'syllabus_approval': return '/coordinator/syllabus-approvals';
      case 'department_task': return '/department-management';
      case 'health_followup': return '/student-health';
      default: return null;
    }
  }

  Widget _stat(String label, dynamic value, IconData icon) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 14)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: Colors.indigo), const SizedBox(height: 8), Text('${value ?? 0}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)), Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54))]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Actions & Approvals'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
      backgroundColor: const Color(0xFFF5F7FB),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Row(children: [_stat('Pending', _summary['total'], Icons.inbox_rounded), const SizedBox(width: 10), _stat('Approvals', _summary['approvals'], Icons.check_circle_outline_rounded), const SizedBox(width: 10), _stat('High priority', _summary['high_priority'], Icons.priority_high_rounded)]),
            const SizedBox(height: 14),
            SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
              for (final c in const [
                {'value':'all','label':'All'}, {'value':'approval','label':'Approvals'}, {'value':'review','label':'Reviews'}, {'value':'task','label':'My Tasks'}, {'value':'follow_up','label':'Follow-ups'}
              ])
                Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(c['label']!), selected: _category == c['value'], onSelected: (_) { setState(() => _category = c['value']!); _load(); })),
            ])),
            const SizedBox(height: 10),
            if (_error.isNotEmpty) Card(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(12), child: Text(_error, style: TextStyle(color: Colors.red.shade800)))),
            if (_loading && _actions.isEmpty) const Padding(padding: EdgeInsets.all(50), child: Center(child: CircularProgressIndicator())),
            if (!_loading && _actions.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 60), child: Column(children: [Icon(Icons.check_circle_rounded, size: 62, color: Colors.green.shade500), const SizedBox(height: 12), const Text('Inbox clear', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)), const SizedBox(height: 5), const Text('No pending actions in this view.', style: TextStyle(color: Colors.black54))])),
            ..._actions.map((raw) {
              final item = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
              final source = item['source']?.toString() ?? '';
              final priority = item['priority']?.toString() ?? 'normal';
              final route = _mobileRoute(source);
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Color(0xFFE5EAF2))),
                child: InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onTap: route == null ? null : () => Navigator.of(context).pushNamed(route),
                  child: Padding(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 42, height: 42, decoration: BoxDecoration(color: _priorityColor(priority).withOpacity(.1), borderRadius: BorderRadius.circular(12)), child: Icon(_icon(source), color: _priorityColor(priority))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 6, runSpacing: 5, children: [
                        _pill(item['source_label']?.toString() ?? source, Colors.indigo),
                        _pill(priority.toUpperCase(), _priorityColor(priority)),
                      ]),
                      const SizedBox(height: 8),
                      Text(item['title']?.toString() ?? 'Action required', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      if ((item['subtitle']?.toString() ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(item['subtitle'].toString(), style: const TextStyle(color: Colors.black54, fontSize: 12))),
                      if ((item['description']?.toString() ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(item['description'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black87, fontSize: 12))),
                      if (route == null) const Padding(padding: EdgeInsets.only(top: 7), child: Text('Open this action on the web portal.', style: TextStyle(color: Colors.deepOrange, fontSize: 11, fontWeight: FontWeight.w700))),
                    ])),
                    if (route != null) const Icon(Icons.chevron_right_rounded, color: Colors.black38),
                  ])),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(.09), borderRadius: BorderRadius.circular(99)), child: Text(text, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color)));
}
