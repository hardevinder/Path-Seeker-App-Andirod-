import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/daily_readiness_api.dart';

class DailyReadinessScreen extends StatefulWidget {
  const DailyReadinessScreen({super.key});
  @override
  State<DailyReadinessScreen> createState() => _DailyReadinessScreenState();
}

class _DailyReadinessScreenState extends State<DailyReadinessScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _cap = {};
  List<dynamic> _classes = [];
  Map<String, dynamic>? _pair;
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _mine = {};
  DateTime _date = DateTime.now();

  bool get _family => _cap['is_student_or_parent'] == true;
  String get _dateText => '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
  String get _monthText => '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}';

  @override
  void initState() { super.initState(); _load(); }

  Map<String, dynamic> _blank(dynamic studentId, {bool ok = false}) => {
    'student_id': studentId,
    'uniform_overall': ok ? 'ok' : 'not_checked',
    'shirt_status': ok ? 'ok' : 'not_checked',
    'bottom_status': ok ? 'ok' : 'not_checked',
    'belt_status': ok ? 'ok' : 'not_checked',
    'socks_status': ok ? 'ok' : 'not_checked',
    'shoes_status': ok ? 'ok' : 'not_checked',
    'headwear_status': ok ? 'na' : 'not_checked',
    'cleanliness_status': ok ? 'ok' : 'not_checked',
    'tiffin_brought_status': ok ? 'yes' : 'not_checked',
    'tiffin_hygiene_status': ok ? 'ok' : 'not_checked',
    'tiffin_taken_status': 'not_observed',
    'water_bottle_status': ok ? 'yes' : 'not_checked',
    'general_observation': 'normal',
    'internal_note': '',
    'family_note': '',
    'family_visible': true,
  };

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      _cap = await DailyReadinessApi.capabilities();
      if (_family) {
        _mine = await DailyReadinessApi.myRecord(month: _monthText);
      } else {
        _classes = await DailyReadinessApi.classes();
        if (_classes.isNotEmpty) {
          _pair = Map<String, dynamic>.from(_classes.first as Map);
          await _loadDay();
        }
      }
    } catch (e) { _error = e.toString(); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _loadDay() async {
    if (_pair == null) return;
    final c = int.tryParse('${_pair!['class_id']}');
    final s = int.tryParse('${_pair!['section_id']}');
    if (c == null || s == null) return;
    final data = await DailyReadinessApi.classDay(c, s, _dateText);
    final list = (data['students'] is List) ? List<dynamic>.from(data['students']) : <dynamic>[];
    _rows = list.map((raw) {
      final x = Map<String, dynamic>.from(raw as Map);
      final student = Map<String, dynamic>.from(x['student'] as Map);
      final record = <String, dynamic>{..._blank(student['id']), if (x['record'] is Map) ...Map<String, dynamic>.from(x['record'] as Map)};
      return {'student': student, 'record': record};
    }).toList();
    if (mounted) setState(() {});
  }

  String? _photo(dynamic raw) {
    final s = raw?.toString().trim() ?? '';
    if (s.isEmpty) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    return '${ApiService.baseUrl}${s.startsWith('/') ? '' : '/'}$s';
  }

  int _concerns(Map<String, dynamic> r) {
    var n = 0;
    final detailIssues = ['shirt_status','bottom_status','belt_status','socks_status','shoes_status','headwear_status'].where((f) => r[f] == 'issue').length;
    n += detailIssues > 0 ? detailIssues : (r['uniform_overall'] == 'issue' ? 1 : 0);
    if (r['cleanliness_status'] == 'issue') n++;
    if (r['tiffin_brought_status'] == 'no') n++;
    if (r['tiffin_hygiene_status'] == 'concern') n++;
    if (r['tiffin_taken_status'] == 'not_taken') n++;
    if (r['water_bottle_status'] == 'no') n++;
    if (r['general_observation'] == 'needs_attention') n++;
    return n;
  }

  void _markOk() {
    for (final row in _rows) {
      final student = Map<String, dynamic>.from(row['student'] as Map);
      final old = Map<String, dynamic>.from(row['record'] as Map);
      final fresh = _blank(student['id'], ok: true);
      fresh['headwear_status'] = ['ok','issue'].contains(old['headwear_status']) ? old['headwear_status'] : 'na';
      fresh['tiffin_taken_status'] = old['tiffin_taken_status'] ?? 'not_observed';
      fresh['internal_note'] = old['internal_note'] ?? '';
      fresh['family_note'] = old['family_note'] ?? '';
      fresh['family_visible'] = old['family_visible'] ?? true;
      row['record'] = fresh;
    }
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Readiness marked OK. Edit only exceptions.')));
  }

  void _markTiffinTaken() {
    for (final row in _rows) { (row['record'] as Map)['tiffin_taken_status'] = 'taken'; }
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tiffin marked Taken for all. Change exceptions if needed.')));
  }

  Future<void> _save() async {
    if (_pair == null || _rows.isEmpty) return;
    setState(() { _saving = true; _error = null; });
    try {
      final payload = {
        'class_id': _pair!['class_id'], 'section_id': _pair!['section_id'], 'date': _dateText,
        'records': _rows.map((x) => Map<String, dynamic>.from(x['record'] as Map)).toList(),
      };
      final r = await DailyReadinessApi.saveClassDay(payload);
      await _loadDay();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r['message']?.toString() ?? 'Daily readiness saved.')));
    } catch (e) { _error = e.toString(); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 30)));
    if (picked == null) return;
    _date = picked;
    if (_family) _mine = await DailyReadinessApi.myRecord(month: _monthText); else await _loadDay();
    if (mounted) setState(() {});
  }



  Future<void> _editRow(Map<String, dynamic> row) async {
    final student = Map<String, dynamic>.from(row['student'] as Map);
    final r = Map<String, dynamic>.from(row['record'] as Map);
    final internal = TextEditingController(text: r['internal_note']?.toString() ?? '');
    final family = TextEditingController(text: r['family_note']?.toString() ?? '');
    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      Widget d(String label, String field, List<String> vals) => Padding(padding: const EdgeInsets.only(bottom: 10), child: DropdownButtonFormField<String>(
        value: r[field]?.toString(), decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        items: vals.map((v) => DropdownMenuItem(value: v, child: Text(v.replaceAll('_', ' ')))).toList(), onChanged: (v) => setLocal(() => r[field] = v),
      ));
      return AlertDialog(
        title: Text(student['name']?.toString() ?? 'Student'),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(children: [
          d('Uniform overall','uniform_overall',['ok','issue','not_checked']),
          d('Shirt','shirt_status',['ok','issue','na','not_checked']), d('Trousers / Skirt','bottom_status',['ok','issue','na','not_checked']),
          d('Belt','belt_status',['ok','issue','na','not_checked']), d('Socks','socks_status',['ok','issue','na','not_checked']),
          d('Shoes','shoes_status',['ok','issue','na','not_checked']), d('Turban / Headwear (as applicable)','headwear_status',['ok','issue','na','not_checked']),
          d('Cleanliness','cleanliness_status',['ok','issue','not_checked']), d('Tiffin brought','tiffin_brought_status',['yes','no','not_checked']),
          d('Tiffin hygiene','tiffin_hygiene_status',['ok','concern','not_checked']), d('Tiffin taken','tiffin_taken_status',['taken','not_taken','not_observed']),
          d('Water bottle','water_bottle_status',['yes','no','not_checked']), d('General observation','general_observation',['positive','normal','needs_attention']),
          TextField(controller: internal, maxLines: 2, decoration: const InputDecoration(labelText: 'Internal note', border: OutlineInputBorder())), const SizedBox(height: 10),
          TextField(controller: family, maxLines: 2, decoration: const InputDecoration(labelText: 'Family note', border: OutlineInputBorder())),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Visible to student / parent'), value: r['family_visible'] != false, onChanged: (v) => setLocal(() => r['family_visible'] = v)),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () { r['internal_note'] = internal.text.trim(); r['family_note'] = family.text.trim(); row['record'] = r; Navigator.pop(ctx); setState(() {}); }, child: const Text('Done'))],
      );
    }));
    internal.dispose(); family.dispose();
  }

  Widget _teacherView() {
    return RefreshIndicator(onRefresh: _loadDay, child: ListView(padding: const EdgeInsets.all(16), children: [
      DropdownButtonFormField<String>(
        value: _pair == null ? null : '${_pair!['class_id']}:${_pair!['section_id']}',
        decoration: const InputDecoration(labelText: 'Class / Section', border: OutlineInputBorder()),
        items: _classes.map((raw) { final p = Map<String, dynamic>.from(raw as Map); return DropdownMenuItem(value: '${p['class_id']}:${p['section_id']}', child: Text('${p['class_name']} - ${p['section_name']}')); }).toList(),
        onChanged: (v) async { final hit = _classes.cast<Map>().firstWhere((x) => '${x['class_id']}:${x['section_id']}' == v); _pair = Map<String,dynamic>.from(hit); await _loadDay(); },
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_month), label: Text(_dateText)),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _rows.isEmpty ? null : _markOk, icon: const Icon(Icons.done_all), label: const Text('Readiness OK'))), const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: _rows.isEmpty ? null : _markTiffinTaken, icon: const Icon(Icons.restaurant), label: const Text('Tiffin Taken')))]),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _saving || _rows.isEmpty ? null : _save, icon: _saving ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.save), label: Text(_saving ? 'Saving...' : 'Save Full Class'))),
      const SizedBox(height: 12),
      if (_error != null) Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!))),
      ..._rows.map((row) {
        final s = Map<String,dynamic>.from(row['student'] as Map); final r = Map<String,dynamic>.from(row['record'] as Map); final issues = _concerns(r); final url = _photo(s['photo_url'] ?? s['photo']);
        return Card(child: ListTile(
          leading: CircleAvatar(backgroundImage: url == null ? null : NetworkImage(url), child: url == null ? Text((s['name']?.toString() ?? 'S').substring(0,1)) : null),
          title: Text(s['name']?.toString() ?? 'Student'),
          subtitle: Text('Uniform: ${r['uniform_overall']} • Cleanliness: ${r['cleanliness_status']}\nTiffin: ${r['tiffin_brought_status']} • Taken: ${r['tiffin_taken_status']}'),
          isThreeLine: true,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [if (issues > 0) Text('$issues ', style: const TextStyle(fontWeight: FontWeight.bold)), const Icon(Icons.edit_outlined)]),
          onTap: () => _editRow(row),
        ));
      }),
      const SizedBox(height: 60),
    ]));
  }

  Widget _familyView() {
    final students = _mine['students'] is List ? List<dynamic>.from(_mine['students']) : <dynamic>[];
    return RefreshIndicator(onRefresh: () async { _mine = await DailyReadinessApi.myRecord(month: _monthText); setState(() {}); }, child: ListView(padding: const EdgeInsets.all(16), children: [
      OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_month), label: Text('Month $_monthText')),
      const SizedBox(height: 12),
      const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('This view shows school-shared readiness, hygiene and tiffin observations. Food quantity is not rated or compared.'))),
      ...students.map((raw) {
        final item = Map<String,dynamic>.from(raw as Map); final s = Map<String,dynamic>.from(item['student'] as Map); final recs = item['records'] is List ? List<dynamic>.from(item['records']) : <dynamic>[]; final sum = item['summary'] is Map ? Map<String,dynamic>.from(item['summary']) : <String,dynamic>{};
        return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s['name']?.toString() ?? 'Student', style: Theme.of(context).textTheme.titleMedium),
          Text('${sum['days_recorded'] ?? 0} recorded days • ${sum['concern_days'] ?? 0} concern days • ${sum['positive_days'] ?? 0} positive days', style: Theme.of(context).textTheme.bodySmall),
          const Divider(),
          if (recs.isEmpty) const Text('No shared records this month.'),
          ...recs.take(31).map((rr) { final r = Map<String,dynamic>.from(rr as Map); final issues = _concerns(r); return ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(child: Icon(issues > 0 ? Icons.info_outline : Icons.check)), title: Text(r['record_date']?.toString() ?? ''), subtitle: Text('Uniform ${r['uniform_overall']} • Cleanliness ${r['cleanliness_status']} • Tiffin ${r['tiffin_brought_status']} / ${r['tiffin_taken_status']}${(r['family_note']?.toString() ?? '').isNotEmpty ? '\n${r['family_note']}' : ''}'), isThreeLine: (r['family_note']?.toString() ?? '').isNotEmpty); }),
        ])));
      }),
      const SizedBox(height: 50),
    ]));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_family ? 'My Daily Readiness' : 'Daily Readiness & Hygiene')),
    body: _loading ? const Center(child: CircularProgressIndicator()) : _family ? _familyView() : _teacherView(),
  );
}
