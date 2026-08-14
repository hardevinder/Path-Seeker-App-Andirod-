import 'package:flutter/material.dart';
import '../../services/anecdotal_api.dart';
import '../../services/api_service.dart';

class AnecdotalRecordsScreen extends StatefulWidget {
  const AnecdotalRecordsScreen({super.key});

  @override
  State<AnecdotalRecordsScreen> createState() => _AnecdotalRecordsScreenState();
}

class _AnecdotalRecordsScreenState extends State<AnecdotalRecordsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _cap = {};
  List<dynamic> _dimensions = [];
  List<dynamic> _classes = [];
  List<dynamic> _students = [];
  List<dynamic> _observations = [];
  Map<String, dynamic> _mine = {};
  Map<String, dynamic>? _pair;
  Map<String, dynamic>? _student;

  final _observation = TextEditingController();
  final _context = TextEditingController();
  final _followUp = TextEditingController();
  String _category = 'Academic Progress';
  String _tone = 'positive';
  bool _share = false;
  bool _recognitionEligible = true;
  final Map<int, int?> _ratings = {};

  bool get _isStudent => _cap['is_student_or_parent'] == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _observation.dispose();
    _context.dispose();
    _followUp.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      _cap = await AnecdotalApi.capabilities();
      if (_cap['is_student_or_parent'] == true) {
        _mine = await AnecdotalApi.myRecord();
      } else {
        _dimensions = await AnecdotalApi.dimensions();
        _classes = await AnecdotalApi.classes();
        if (_classes.isNotEmpty) {
          _pair = Map<String, dynamic>.from(_classes.first as Map);
          await _loadStudents();
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadStudents() async {
    if (_pair == null) return;
    final classId = int.tryParse('${_pair!['class_id']}');
    final sectionId = int.tryParse('${_pair!['section_id']}');
    if (classId == null || sectionId == null) return;
    _students = await AnecdotalApi.students(classId, sectionId);
    _student = _students.isEmpty ? null : Map<String, dynamic>.from(_students.first as Map);
    await _loadObservations();
  }

  Future<void> _loadObservations() async {
    if (_pair == null) return;
    final classId = int.tryParse('${_pair!['class_id']}');
    final sectionId = int.tryParse('${_pair!['section_id']}');
    final studentId = _student == null ? null : int.tryParse('${_student!['id']}');
    if (classId == null || sectionId == null) return;
    _observations = await AnecdotalApi.observations(classId: classId, sectionId: sectionId, studentId: studentId);
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (_student == null || _observation.text.trim().length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a student and enter a specific observation.')));
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final ratings = _ratings.entries
          .where((e) => e.value != null)
          .map((e) => {'dimension_id': e.key, 'rating': e.value})
          .toList();
      await AnecdotalApi.createObservation({
        'student_id': _student!['id'],
        'category': _category,
        'tone': _tone,
        'observation_text': _observation.text.trim(),
        'context_text': _context.text.trim(),
        'follow_up_text': _followUp.text.trim(),
        'visible_to_student_parent': _share,
        'recognition_eligible': _recognitionEligible,
        'ratings': ratings,
      });
      _observation.clear();
      _context.clear();
      _followUp.clear();
      _ratings.clear();
      await _loadObservations();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Observation saved.')));
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _photo(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    return '${ApiService.baseUrl}${value.startsWith('/') ? '' : '/'}$value';
  }

  Widget _avatar(Map<String, dynamic>? s, {double radius = 24}) {
    final url = _photo(s?['photo_url'] ?? s?['photo']);
    return CircleAvatar(
      radius: radius,
      backgroundImage: url == null ? null : NetworkImage(url),
      child: url == null ? Text((s?['name']?.toString() ?? 'S').substring(0, 1).toUpperCase()) : null,
    );
  }

  Widget _mineView() {
    final recognitions = (_mine['recognitions'] is List) ? List<dynamic>.from(_mine['recognitions']) : <dynamic>[];
    final observations = (_mine['observations'] is List) ? List<dynamic>.from(_mine['observations']) : <dynamic>[];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const Icon(Icons.privacy_tip_outlined),
                const SizedBox(width: 10),
                Expanded(child: Text('Only observations shared by the school are visible here. Internal notes remain restricted.')),
              ]),
            ),
          ),
          if (recognitions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Recognition', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...recognitions.map((raw) {
              final r = Map<String, dynamic>.from(raw as Map);
              final title = (r['recognition_type']?.toString() ?? 'recognition').replaceAll('_', ' ');
              return Card(child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.emoji_events_outlined)),
                title: Text(title.toUpperCase()),
                subtitle: Text('${r['citation_text'] ?? ''}\n${r['period_month'] ?? ''}${r['period_month'] != null ? '/' : ''}${r['period_year'] ?? ''}'),
                isThreeLine: true,
              ));
            }),
          ],
          const SizedBox(height: 16),
          Text('Shared Observations', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (observations.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No shared observations yet.'))),
          ...observations.map((raw) {
            final o = Map<String, dynamic>.from(raw as Map);
            return Card(child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, children: [Chip(label: Text(o['category']?.toString() ?? 'Observation')), Chip(label: Text(o['tone']?.toString() ?? 'neutral'))]),
                const SizedBox(height: 6),
                Text(o['observation_text']?.toString() ?? ''),
                if ((o['follow_up_text']?.toString() ?? '').isNotEmpty) ...[const SizedBox(height: 8), Text('Follow-up: ${o['follow_up_text']}', style: const TextStyle(fontStyle: FontStyle.italic))],
                const SizedBox(height: 8),
                Text('By ${o['observer']?['name'] ?? 'Teacher'}', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ));
          }),
        ],
      ),
    );
  }

  Widget _teacherView() {
    final categories = (_cap['categories'] is List) ? List<String>.from(_cap['categories'].map((e) => e.toString())) : <String>['Academic Progress', 'Other'];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _pair == null ? null : '${_pair!['class_id']}:${_pair!['section_id']}',
            decoration: const InputDecoration(labelText: 'Class / Section', border: OutlineInputBorder()),
            items: _classes.map((raw) {
              final p = Map<String, dynamic>.from(raw as Map);
              return DropdownMenuItem(value: '${p['class_id']}:${p['section_id']}', child: Text('${p['class_name']} - ${p['section_name']}${p['incharge'] == true ? ' (Incharge)' : ''}'));
            }).toList(),
            onChanged: (value) async {
              final hit = _classes.cast<Map>().firstWhere((e) => '${e['class_id']}:${e['section_id']}' == value);
              _pair = Map<String, dynamic>.from(hit);
              setState(() {});
              await _loadStudents();
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _student?['id']?.toString(),
            decoration: const InputDecoration(labelText: 'Student', border: OutlineInputBorder()),
            items: _students.map((raw) {
              final s = Map<String, dynamic>.from(raw as Map);
              return DropdownMenuItem(value: s['id'].toString(), child: Text('${s['roll_number'] ?? ''}${s['roll_number'] != null ? '. ' : ''}${s['name']}'));
            }).toList(),
            onChanged: (value) async {
              final hit = _students.cast<Map>().firstWhere((e) => e['id'].toString() == value);
              _student = Map<String, dynamic>.from(hit);
              setState(() {});
              await _loadObservations();
            },
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [_avatar(_student), const SizedBox(width: 12), Expanded(child: Text(_student?['name']?.toString() ?? 'Select a student', style: Theme.of(context).textTheme.titleMedium))]),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(value: _category, decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()), items: categories.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(), onChanged: (v) => setState(() => _category = v ?? _category)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(value: _tone, decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'positive', child: Text('Positive')), DropdownMenuItem(value: 'neutral', child: Text('Neutral')), DropdownMenuItem(value: 'developmental', child: Text('Developmental')), DropdownMenuItem(value: 'concern', child: Text('Concern'))], onChanged: (v) => setState(() => _tone = v ?? _tone)),
                const SizedBox(height: 12),
                TextField(controller: _observation, maxLines: 4, decoration: const InputDecoration(labelText: 'Specific observation *', hintText: 'What exactly did you observe?', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: _context, decoration: const InputDecoration(labelText: 'Context', hintText: 'Science activity / assembly / sports...', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: _followUp, maxLines: 2, decoration: const InputDecoration(labelText: 'Follow-up / support note', border: OutlineInputBorder())),
                const SizedBox(height: 16),
                Text('Ratings (rate only what you observed)', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                ..._dimensions.map((raw) {
                  final d = Map<String, dynamic>.from(raw as Map);
                  final id = int.tryParse('${d['id']}');
                  if (id == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DropdownButtonFormField<int?>(
                      value: _ratings[id],
                      decoration: InputDecoration(labelText: d['name']?.toString() ?? 'Rating', border: const OutlineInputBorder()),
                      items: const [DropdownMenuItem<int?>(value: null, child: Text('Not rated')), DropdownMenuItem(value: 1, child: Text('1 - Needs significant support')), DropdownMenuItem(value: 2, child: Text('2 - Developing')), DropdownMenuItem(value: 3, child: Text('3 - Consistent / expected')), DropdownMenuItem(value: 4, child: Text('4 - Strong')), DropdownMenuItem(value: 5, child: Text('5 - Outstanding'))],
                      onChanged: (v) => setState(() => _ratings[id] = v),
                    ),
                  );
                }),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Share with student / parent'), value: _share, onChanged: (v) => setState(() => _share = v)),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Eligible for recognition score'), subtitle: const Text('Student of the Month/Year uses human-approved scoring.'), value: _recognitionEligible, onChanged: (v) => setState(() => _recognitionEligible = v)),
                SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined), label: Text(_saving ? 'Saving...' : 'Save Observation'))),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          Text('Recent Observations', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (_observations.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No observations yet.'))),
          ..._observations.map((raw) {
            final o = Map<String, dynamic>.from(raw as Map);
            return Card(child: ListTile(
              title: Text(o['category']?.toString() ?? 'Observation'),
              subtitle: Text('${o['observation_text'] ?? ''}\nBy ${o['observer']?['name'] ?? 'Teacher'}'),
              isThreeLine: true,
              trailing: Text(o['tone']?.toString() ?? ''),
            ));
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isStudent ? 'My Growth & Recognition' : 'Anecdotal Records')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton(onPressed: _load, child: const Text('Retry'))])))
              : (_isStudent ? _mineView() : _teacherView()),
    );
  }
}
