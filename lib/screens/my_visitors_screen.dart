import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/role_manager.dart';
import '../services/visitor_api.dart';

class MyVisitorsScreen extends StatefulWidget {
  const MyVisitorsScreen({super.key});
  @override
  State<MyVisitorsScreen> createState() => _MyVisitorsScreenState();
}

class _MyVisitorsScreenState extends State<MyVisitorsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  bool _frontOffice = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _frontOffice = AppRoles.normalize(prefs.getString('activeRole')) == AppRoles.frontoffice);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try { _rows = await VisitorApi.myVisitors(); }
    catch (e) { _error = '$e'; }
    if (mounted) setState(() => _loading = false);
  }

  String _date(dynamic raw) {
    final value = DateTime.tryParse('${raw ?? ''}')?.toLocal();
    return value == null ? '—' : DateFormat('dd MMM yyyy, hh:mm a').format(value);
  }

  Future<void> _act(Map<String, dynamic> row, String action, {String? decision}) async {
    try {
      await VisitorApi.action(int.parse('${row['id']}'), action, decision: decision);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _viewId(Map<String, dynamic> row) async {
    try {
      final bytes = await VisitorApi.idProof(int.parse('${row['id']}'));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700, maxHeight: 750),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppBar(
                  automaticallyImplyLeading: false,
                  title: Text('${row['name'] ?? 'Visitor'} — ID Proof'),
                  actions: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Flexible(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5,
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Visitors')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_error!))])
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _rows.length,
                    itemBuilder: (_, index) {
                      final v = _rows[index];
                      final approval = '${v['approval_status'] ?? 'PENDING'}';
                      final pending = approval == 'PENDING';
                      final accepted = approval == 'ACCEPTED';
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text('${v['name'] ?? 'Visitor'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                              Chip(label: Text(approval)),
                            ]),
                            Text('${v['purpose'] ?? ''}'),
                            const SizedBox(height: 6),
                            Text('Arrived: ${_date(v['check_in_at'])}'),
                            if (v['meeting_started_at'] != null) Text('Meeting started: ${_date(v['meeting_started_at'])}'),
                            if (v['meeting_ended_at'] != null) Text('Meeting completed: ${_date(v['meeting_ended_at'])}'),
                            const SizedBox(height: 10),
                            if (_frontOffice && v['has_id_proof'] == true)
                              OutlinedButton.icon(
                                onPressed: () => _viewId(v),
                                icon: const Icon(Icons.badge_outlined),
                                label: const Text('View ID Proof'),
                              ),
                            if (!_frontOffice && pending) Row(children: [
                              Expanded(child: FilledButton.icon(onPressed: () => _act(v, 'respond', decision: 'ACCEPTED'), icon: const Icon(Icons.check), label: const Text('Accept'))),
                              const SizedBox(width: 8),
                              Expanded(child: OutlinedButton.icon(onPressed: () => _act(v, 'respond', decision: 'DECLINED'), icon: const Icon(Icons.close), label: const Text('Decline'))),
                            ]),
                            if (!_frontOffice && accepted && v['meeting_started_at'] == null)
                              FilledButton(onPressed: () => _act(v, 'start'), child: const Text('Start Meeting')),
                            if (!_frontOffice && accepted && v['meeting_started_at'] != null && v['meeting_ended_at'] == null)
                              FilledButton(onPressed: () => _act(v, 'end'), child: const Text('Complete Meeting')),
                          ]),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
