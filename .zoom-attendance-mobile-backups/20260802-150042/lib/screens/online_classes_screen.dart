import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/role_manager.dart';
import '../models/online_class_models.dart';
import '../services/online_class_api.dart';
import '../widgets/student_drawer_menu.dart';
import '../widgets/teacher_drawer_menu.dart';

class OnlineClassesScreen extends StatefulWidget {
  const OnlineClassesScreen({super.key});

  @override
  State<OnlineClassesScreen> createState() => _OnlineClassesScreenState();
}

class _OnlineClassesScreenState extends State<OnlineClassesScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _teacherView = false;
  ZoomConnection _zoom = const ZoomConnection(connected: false);
  List<OnlineClass> _classes = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(showLoader: false);
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final role = AppRoles.normalize(prefs.getString('activeRole'));
      final teacher = role == AppRoles.teacher ||
          role == AppRoles.coordinator ||
          role == AppRoles.superadmin;
      final results = await Future.wait<dynamic>([
        OnlineClassApi.classes(),
        if (teacher) OnlineClassApi.zoomStatus(),
      ]);
      if (!mounted) return;
      setState(() {
        _teacherView = teacher;
        _classes = results[0] as List<OnlineClass>;
        _zoom = teacher
            ? results[1] as ZoomConnection
            : const ZoomConnection(connected: false);
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _connect() async {
    try {
      final url = await OnlineClassApi.zoomAuthorizationUrl();
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw const OnlineClassApiException(
            'Could not open Zoom authorization.');
      }
    } catch (error) {
      _message(error.toString(), error: true);
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Disconnect Zoom?'),
            content: const Text(
                'Scheduled class history will remain, but you cannot create or modify meetings until Zoom is reconnected.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep connected')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Disconnect')),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await OnlineClassApi.disconnectZoom();
      _message('Zoom account disconnected.');
      await _load(showLoader: false);
    } catch (error) {
      _message(error.toString(), error: true);
    }
  }

  Future<void> _openZoom(OnlineClass item, {required bool start}) async {
    try {
      final url = await OnlineClassApi.actionUrl(item.id, start: start);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw const OnlineClassApiException('Could not open Zoom.');
      }
    } catch (error) {
      _message(error.toString(), error: true);
    }
  }

  Future<void> _cancel(OnlineClass item) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Cancel online class?'),
            content: Text('“${item.title}” will also be deleted from Zoom.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep class')),
              FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Cancel class')),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await OnlineClassApi.cancel(item.id);
      _message('Online class cancelled.');
      await _load(showLoader: false);
    } catch (error) {
      _message(error.toString(), error: true);
    }
  }

  Future<void> _showForm([OnlineClass? item]) async {
    if (!_zoom.connected) {
      _message('Connect your Zoom account before scheduling a class.',
          error: true);
      return;
    }
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _OnlineClassForm(item: item),
    );
    if (saved == true) {
      _message(item == null ? 'Online class scheduled.' : 'Class updated.');
      await _load(showLoader: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer:
          _teacherView ? const TeacherDrawerMenu() : const StudentDrawerMenu(),
      appBar: AppBar(
        title: const Text('Online Classes'),
        actions: [
          IconButton(
              tooltip: 'Refresh',
              onPressed: () => _load(showLoader: false),
              icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: _teacherView && _zoom.connected
          ? FloatingActionButton.extended(
              onPressed: () => _showForm(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Schedule'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => _load(showLoader: false),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  if (_error != null) _ErrorCard(text: _error!, retry: _load),
                  if (_teacherView) _zoomCard(),
                  const SizedBox(height: 18),
                  Text(
                    _teacherView ? 'My scheduled classes' : 'Upcoming classes',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (_classes.isEmpty)
                    const _EmptyState()
                  else
                    ..._classes.map(_classCard),
                ],
              ),
      ),
    );
  }

  Widget _zoomCard() {
    return Card(
      elevation: 0,
      color: const Color(0xFFEFF6FF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFBFDBFE)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  color: const Color(0xFF2D8CFF),
                  borderRadius: BorderRadius.circular(15)),
              child: const Icon(Icons.videocam_rounded,
                  color: Colors.white, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _zoom.connected ? 'Zoom connected' : 'Connect Zoom',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _zoom.connected
                        ? (_zoom.email ?? 'Connected account')
                        : 'Connect your Zoom account to schedule classes.',
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _zoom.connected
                ? IconButton(
                    tooltip: 'Disconnect Zoom',
                    onPressed: _disconnect,
                    icon: const Icon(Icons.link_off_rounded, color: Colors.red))
                : FilledButton(
                    onPressed: _connect, child: const Text('Connect')),
          ],
        ),
      ),
    );
  }

  Widget _classCard(OnlineClass item) {
    final cancelled = item.status == 'cancelled';
    final date = DateFormat('EEE, d MMM · h:mm a').format(item.startTime);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(item.title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800))),
              _StatusBadge(status: item.status),
            ]),
            const SizedBox(height: 8),
            Text(
              '${item.className}${item.sectionName.isEmpty ? '' : ' – ${item.sectionName}'} · ${item.subjectName}',
              style: const TextStyle(
                  color: Color(0xFF475569), fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.schedule_rounded,
                  size: 18, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              Expanded(child: Text('$date · ${item.durationMinutes} minutes')),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.person_outline_rounded,
                  size: 18, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              Text(item.teacherName),
            ]),
            if (item.agenda?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(item.agenda!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF64748B))),
            ],
            if (!cancelled) ...[
              const Divider(height: 24),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                    onPressed: () => _openZoom(item, start: false),
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Join')),
                if (item.canStart)
                  FilledButton.icon(
                      onPressed: () => _openZoom(item, start: true),
                      icon: const Icon(Icons.videocam_rounded),
                      label: const Text('Start')),
                if (item.canManage)
                  OutlinedButton(
                      onPressed: () => _showForm(item),
                      child: const Text('Edit')),
                if (item.canManage)
                  TextButton(
                      onPressed: () => _cancel(item),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Cancel')),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _OnlineClassForm extends StatefulWidget {
  final OnlineClass? item;
  const _OnlineClassForm({this.item});
  @override
  State<_OnlineClassForm> createState() => _OnlineClassFormState();
}

class _OnlineClassFormState extends State<_OnlineClassForm> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _agenda;
  late final TextEditingController _duration;
  List<OnlineClassAssignment> _assignments = const [];
  int? _classId;
  int? _sectionId;
  int? _subjectId;
  late DateTime _dateTime;
  bool _waitingRoom = true;
  bool _muteUponEntry = true;
  String _recording = 'none';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _title = TextEditingController(text: item?.title ?? '');
    _agenda = TextEditingController(text: item?.agenda ?? '');
    _duration =
        TextEditingController(text: (item?.durationMinutes ?? 40).toString());
    _classId = item?.classId;
    _sectionId = item?.sectionId;
    _subjectId = item?.subjectId;
    _dateTime = item?.startTime ?? DateTime.now().add(const Duration(hours: 1));
    _waitingRoom = item?.settings['waiting_room'] != false;
    _muteUponEntry = item?.settings['mute_upon_entry'] != false;
    _recording = item?.settings['auto_recording']?.toString() ?? 'none';
    _loadOptions();
  }

  @override
  void dispose() {
    _title.dispose();
    _agenda.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final assignments = await OnlineClassApi.assignments();
      if (mounted) {
        setState(() {
          _assignments = assignments;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted)
        setState(() {
          _error = error.toString();
          _loading = false;
        });
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate:
          _dateTime.isBefore(DateTime.now()) ? DateTime.now() : _dateTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_dateTime));
    if (time == null) return;
    setState(() => _dateTime =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    if (_classId == null || _subjectId == null) {
      setState(() => _error = 'Select a class and subject.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await OnlineClassApi.save({
        'class_id': _classId,
        'section_id': _sectionId,
        'subject_id': _subjectId,
        'title': _title.text.trim(),
        'agenda': _agenda.text.trim(),
        'start_time': _dateTime.toUtc().toIso8601String(),
        'timezone': 'Asia/Kolkata',
        'duration_minutes': int.parse(_duration.text),
        'waiting_room': _waitingRoom,
        'mute_upon_entry': _muteUponEntry,
        'join_before_host': false,
        'recording_setting': _recording,
      }, id: widget.item?.id);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final classes = <int, String>{
      for (final row in _assignments) row.classId: row.className
    };
    final classRows =
        _assignments.where((row) => row.classId == _classId).toList();
    final sections = <int, String>{
      for (final row in classRows) row.sectionId: row.sectionName
    };
    final sectionRows =
        classRows.where((row) => row.sectionId == _sectionId).toList();
    final subjects = <int, String>{
      for (final row in sectionRows) row.subjectId: row.subjectName
    };
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: _loading
          ? const SizedBox(
              height: 240, child: Center(child: CircularProgressIndicator()))
          : Form(
              key: _key,
              child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(
                                widget.item == null
                                    ? 'Schedule class'
                                    : 'Edit class',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800))),
                        IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close)),
                      ]),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(_error!,
                              style: const TextStyle(color: Colors.red)),
                        ),
                      DropdownButtonFormField<int>(
                        value: classes.containsKey(_classId) ? _classId : null,
                        decoration: const InputDecoration(labelText: 'Class'),
                        items: classes.entries
                            .map((o) => DropdownMenuItem(
                                value: o.key, child: Text(o.value)))
                            .toList(),
                        onChanged: (v) => setState(() {
                          _classId = v;
                          _sectionId = null;
                          _subjectId = null;
                        }),
                        validator: (v) =>
                            v == null ? 'Class is required' : null,
                      ),
                      DropdownButtonFormField<int>(
                        value: sections.containsKey(_sectionId)
                            ? _sectionId
                            : null,
                        decoration: const InputDecoration(labelText: 'Section'),
                        items: sections.entries
                            .map((o) => DropdownMenuItem(
                                value: o.key, child: Text(o.value)))
                            .toList(),
                        onChanged: (v) => setState(() {
                          _sectionId = v;
                          _subjectId = null;
                        }),
                        validator: (v) =>
                            v == null ? 'Section is required' : null,
                      ),
                      DropdownButtonFormField<int>(
                        value: subjects.containsKey(_subjectId)
                            ? _subjectId
                            : null,
                        decoration: const InputDecoration(labelText: 'Subject'),
                        items: subjects.entries
                            .map((o) => DropdownMenuItem(
                                value: o.key, child: Text(o.value)))
                            .toList(),
                        onChanged: (v) => setState(() => _subjectId = v),
                        validator: (v) =>
                            v == null ? 'Subject is required' : null,
                      ),
                      TextFormField(
                          controller: _title,
                          decoration: const InputDecoration(labelText: 'Title'),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Title is required'
                              : null),
                      TextFormField(
                          controller: _agenda,
                          maxLines: 2,
                          decoration: const InputDecoration(
                              labelText: 'Agenda (optional)')),
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Date and time'),
                          subtitle: Text(DateFormat('EEE, d MMM yyyy · h:mm a')
                              .format(_dateTime)),
                          trailing: const Icon(Icons.edit_calendar_rounded),
                          onTap: _pickDate),
                      TextFormField(
                          controller: _duration,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Duration (minutes)'),
                          validator: (v) {
                            final n = int.tryParse(v ?? '');
                            return n == null || n < 10 || n > 1440
                                ? 'Enter 10–1440 minutes'
                                : null;
                          }),
                      DropdownButtonFormField<String>(
                          value: _recording,
                          decoration:
                              const InputDecoration(labelText: 'Recording'),
                          items: const [
                            DropdownMenuItem(
                                value: 'none', child: Text('Disabled')),
                            DropdownMenuItem(
                                value: 'local', child: Text('Local')),
                            DropdownMenuItem(
                                value: 'cloud', child: Text('Cloud'))
                          ],
                          onChanged: (v) =>
                              setState(() => _recording = v ?? 'none')),
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Waiting room'),
                          value: _waitingRoom,
                          onChanged: (v) => setState(() => _waitingRoom = v)),
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Mute participants on entry'),
                          value: _muteUponEntry,
                          onChanged: (v) => setState(() => _muteUponEntry = v)),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.save_rounded),
                          label: Text(_saving ? 'Saving…' : 'Save class')),
                    ]),
              ),
            ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'started' => Colors.green,
      'cancelled' => Colors.red,
      'completed' => Colors.blueGrey,
      _ => Colors.blue,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: color.withOpacity(.12),
          borderRadius: BorderRadius.circular(20)),
      child: Text(status,
          style: TextStyle(color: color.shade700, fontWeight: FontWeight.w700)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 70),
        child: Column(children: [
          Icon(Icons.video_call_outlined, size: 64, color: Color(0xFF94A3B8)),
          SizedBox(height: 12),
          Text('No online classes found.',
              style: TextStyle(fontSize: 16, color: Color(0xFF64748B))),
        ]),
      );
}

class _ErrorCard extends StatelessWidget {
  final String text;
  final Future<void> Function({bool showLoader}) retry;
  const _ErrorCard({required this.text, required this.retry});
  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xFFFEF2F2),
        child: ListTile(
          leading: const Icon(Icons.error_outline, color: Colors.red),
          title: Text(text),
          trailing:
              TextButton(onPressed: () => retry(), child: const Text('Retry')),
        ),
      );
}
