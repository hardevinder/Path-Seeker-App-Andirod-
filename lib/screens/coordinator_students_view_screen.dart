import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/api_service.dart';

class CoordinatorStudentsViewScreen extends StatefulWidget {
  const CoordinatorStudentsViewScreen({super.key});

  @override
  State<CoordinatorStudentsViewScreen> createState() =>
      _CoordinatorStudentsViewScreenState();
}

class _CoordinatorStudentsViewScreenState
    extends State<CoordinatorStudentsViewScreen> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _admissionTypes = [];

  String _search = '';
  String? _classFilter;
  String? _sessionFilter;
  String _statusFilter = 'all';
  String _siblingFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  List<Map<String, dynamic>> get _filteredStudents {
    final query = _normalizeSearch(_search);
    return _students.where((student) {
      final searchable = [
        student['admission_number'],
        student['name'],
        student['father_name'],
        student['mother_name'],
        student['father_phone'],
        student['mother_phone'],
        student['class_name'],
        student['section_name'],
        student['roll_number'],
        student['aadhaar_number'],
        _admissionTypeLabel(student),
      ].map(_normalizeSearch).join(' ');

      final textOk = query.isEmpty || searchable.contains(query);
      final classOk =
          _classFilter == null || '${student['class_id']}' == _classFilter;
      final sessionOk =
          _sessionFilter == null || '${student['session_id']}' == _sessionFilter;
      final status = _safe(student['status'], 'enabled').toLowerCase();
      final statusOk = _statusFilter == 'all' || status == _statusFilter;
      final siblingOk = _siblingFilter == 'all' ||
          (_siblingFilter == 'yes' && _hasSibling(student)) ||
          (_siblingFilter == 'no' && !_hasSibling(student));
      return textOk && classOk && sessionOk && statusOk && siblingOk;
    }).toList();
  }

  int get _enabledCount => _filteredStudents
      .where((student) =>
          _safe(student['status'], 'enabled').toLowerCase() == 'enabled')
      .length;

  int get _disabledCount => _filteredStudents
      .where((student) =>
          _safe(student['status'], 'enabled').toLowerCase() == 'disabled')
      .length;

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _loadStudents(),
        _loadList('/classes', const ['classes']),
        _loadList('/sessions', const ['sessions']),
        _loadList('/admission-types/active', const ['admissionTypes']),
      ]);
      if (!mounted) return;
      setState(() {
        _students = results[0];
        _classes = results[1];
        _sessions = results[2];
        _admissionTypes = results[3];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadStudents() async {
    final response = await ApiService.rawGet('/students');
    if (!_ok(response.statusCode)) {
      throw Exception(_extractError(response.body, 'Failed to load students'));
    }
    return _extractRows(jsonDecode(response.body), const ['students']);
  }

  Future<List<Map<String, dynamic>>> _loadList(
    String endpoint,
    List<String> preferredKeys,
  ) async {
    try {
      final response = await ApiService.rawGet(endpoint);
      if (!_ok(response.statusCode)) return [];
      return _extractRows(jsonDecode(response.body), preferredKeys);
    } catch (_) {
      return [];
    }
  }

  void _resetFilters() {
    setState(() {
      _search = '';
      _classFilter = null;
      _sessionFilter = null;
      _statusFilter = 'all';
      _siblingFilter = 'all';
    });
  }

  void _showDetails(Map<String, dynamic> student) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.94,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  _detailHeader(student),
                  const SizedBox(height: 14),
                  _detailSection('Academic', [
                    _field('Admission Number', student['admission_number']),
                    _field('Class', student['class_name']),
                    _field('Section', student['section_name']),
                    _field('Roll Number', student['roll_number']),
                    _field('Session', student['session_name']),
                    _field('House', student['house_name']),
                    _field('Admission Type', _admissionTypeLabel(student)),
                    _field('Date of Admission', student['date_of_admission']),
                  ]),
                  _detailSection('Personal', [
                    _field('Gender', student['gender'] ?? student['Gender']),
                    _field('Date of Birth', student['Date_Of_Birth']),
                    _field('Blood Group', _bloodGroup(student)),
                    _field('State', student['state'] ?? student['State']),
                    _field('Category', student['category']),
                    _field('Religion', student['religion']),
                    _field('PEN Number', student['pen_number']),
                    _field('Aadhaar', _aadhaar(student['aadhaar_number'])),
                  ]),
                  _detailSection('Parents & Contact', [
                    _field('Father Name', student['father_name']),
                    _field('Father Phone', student['father_phone']),
                    _field('Mother Name', student['mother_name']),
                    _field('Mother Phone', student['mother_phone']),
                    _field('Address', student['address'], full: true),
                  ]),
                  _detailSection('Transport & Previous School', [
                    _field(
                      'Bus Service Fee',
                      'Rs ${_safe(student['bus_service'], '0')}',
                    ),
                    _field(
                      'Transport Route',
                      student['route_name'] ?? student['route_id'],
                    ),
                    _field('Bus Gender', student['bus_gender']),
                    _field('Previous School', student['prev_school_name']),
                    _field('Previous Class', student['prev_class']),
                    _field(
                      'Previous Admission No.',
                      student['prev_admission_no'],
                    ),
                    _field(
                      'Previous School Address',
                      student['prev_school_address'],
                      full: true,
                    ),
                  ]),
                  _detailSection('Siblings', _siblingFields(student)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailHeader(Map<String, dynamic> student) {
    final status = _safe(student['status'], 'enabled');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          _studentAvatar(student, radius: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _safe(student['name'], 'Student'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Adm # ${_safe(student['admission_number'], '-')}',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill(
                      '${_safe(student['class_name'], '-')} - '
                      '${_safe(student['section_name'], '-')}',
                    ),
                    _pill(status.toUpperCase()),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailSection(String title, List<Widget> children) {
    final visible = children.where((child) => child is! SizedBox).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 10),
          if (visible.isEmpty)
            const Text('-', style: TextStyle(color: Colors.black54))
          else
            ...visible,
        ],
      ),
    );
  }

  Widget _field(String label, dynamic value, {bool full = false}) {
    final text = _safe(value);
    if (text.isEmpty || text == '-') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: full ? 122 : 116,
            child: Text(
              label,
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _siblingFields(Map<String, dynamic> student) {
    final fields = <Widget>[];
    for (var i = 1; i <= 4; i++) {
      final token = _safe(student['sibling_id_$i']);
      final name = _safe(student['sibling_name_$i']);
      if (token.isEmpty && name.isEmpty) continue;
      fields.add(_field('Sibling $i', name.isEmpty ? token : '$name ($token)'));
    }
    if (fields.isEmpty) {
      fields.add(
        const Text(
          'None recorded',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }
    return fields;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredStudents;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Students'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _state(
                  Icons.warning_rounded,
                  'Could not load students',
                  _error!,
                  actionLabel: 'Retry',
                  onAction: _loadAll,
                )
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                    children: [
                      _hero(rows.length),
                      const SizedBox(height: 12),
                      _filters(),
                      const SizedBox(height: 12),
                      if (rows.isEmpty)
                        _state(
                          Icons.school_rounded,
                          'No students found',
                          'Try changing filters or pull down to refresh.',
                        )
                      else
                        ...rows.map(_studentCard),
                    ],
                  ),
                ),
    );
  }

  Widget _hero(int filteredCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.school_rounded, color: Colors.white, size: 36),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Students View',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _heroStat('Shown', '$filteredCount'),
              _heroStat('Active', '$_enabledCount'),
              _heroStat('Inactive', '$_disabledCount'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(label, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _filters() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search admission, name, parent, phone',
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _search = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            value: _classFilter,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Class',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All Classes'),
              ),
              ..._classes.map(
                (cls) => DropdownMenuItem<String?>(
                  value: '${cls['id']}',
                  child: Text(_safe(cls['class_name'] ?? cls['name'], 'Class')),
                ),
              ),
            ],
            onChanged: (value) => setState(() => _classFilter = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            value: _sessionFilter,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Session',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All Sessions'),
              ),
              ..._sessions.map(
                (session) => DropdownMenuItem<String?>(
                  value: '${session['id']}',
                  child: Text(
                    _safe(
                      session['session_name'] ?? session['name'] ?? session['year'],
                      'Session',
                    ),
                  ),
                ),
              ),
            ],
            onChanged: (value) => setState(() => _sessionFilter = value),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _statusFilter,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'enabled', child: Text('Enabled')),
                    DropdownMenuItem(value: 'disabled', child: Text('Disabled')),
                  ],
                  onChanged: (value) =>
                      setState(() => _statusFilter = value ?? 'all'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _siblingFilter,
                  decoration: const InputDecoration(
                    labelText: 'Siblings',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'yes', child: Text('Has')),
                    DropdownMenuItem(value: 'no', child: Text('None')),
                  ],
                  onChanged: (value) =>
                      setState(() => _siblingFilter = value ?? 'all'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reset Filters'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _studentCard(Map<String, dynamic> student) {
    final status = _safe(student['status'], 'enabled');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showDetails(student),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _studentAvatar(student),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _safe(student['name'], 'Student'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Adm # ${_safe(student['admission_number'], '-')}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _pill(
                          '${_safe(student['class_name'], '-')} - '
                          '${_safe(student['section_name'], '-')}',
                        ),
                        _pill('Roll ${_safe(student['roll_number'], '-')}'),
                        _pill(status.toUpperCase()),
                        if (_hasSibling(student)) _pill('Sibling'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      [
                        if (_safe(student['father_name']).isNotEmpty)
                          'F: ${student['father_name']}',
                        if (_safe(student['father_phone']).isNotEmpty)
                          '${student['father_phone']}',
                      ].join(' | '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _studentAvatar(Map<String, dynamic> student, {double radius = 24}) {
    final url = _photoUrl(student);
    if (url.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFFEFF6FF),
        child: Text(
          _initials(_safe(student['name'], 'S')),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundImage: NetworkImage(url),
      backgroundColor: const Color(0xFFEFF6FF),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _state(
    IconData icon,
    String title,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: const Color(0xFF64748B)),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _extractRows(
    dynamic decoded,
    List<String> preferredKeys,
  ) {
    final keys = [
      ...preferredKeys,
      'data',
      'rows',
      'items',
      'results',
      'students',
      'classes',
      'sessions',
      'admissionTypes',
    ].toSet().toList();
    final raw = decoded is List
        ? decoded
        : decoded is Map
            ? keys.map((key) => decoded[key]).firstWhere(
                  (value) => value is List,
                  orElse: () => [],
                )
            : [];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _admissionTypeLabel(Map<String, dynamic> student) {
    final direct = _safe(
      _mapOf(student['AdmissionType'])['name'] ??
          student['admissionTypeName'] ??
          student['admission_type_name'] ??
          student['admission_type_label'] ??
          _mapOf(student['admissionType'])['name'],
    );
    if (direct.isNotEmpty) return direct;
    final id = _safe(student['admission_type_id']);
    if (id.isNotEmpty) {
      for (final type in _admissionTypes) {
        if ('${type['id']}' == id) return _safe(type['name'], '-');
      }
    }
    return _safe(student['admission_type'], '-');
  }

  String _photoUrl(Map<String, dynamic> student) {
    final photo = _safe(student['photo']);
    if (photo.isEmpty) return '';
    final uri = Uri.tryParse(photo);
    if (uri != null && uri.hasScheme) return photo;
    return '${ApiService.baseUrl}/uploads/photoes/students/${Uri.encodeComponent(photo)}';
  }

  bool _hasSibling(Map<String, dynamic> student) {
    for (var i = 1; i <= 4; i++) {
      if (_safe(student['sibling_id_$i']).isNotEmpty ||
          _safe(student['sibling_name_$i']).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  String _bloodGroup(Map<String, dynamic> student) {
    return _safe(
      student['b_group'] ??
          student['B_group'] ??
          student['B_GROUP'] ??
          student['blood_group'] ??
          student['Blood_Group'],
      '-',
    );
  }

  String _aadhaar(dynamic value) {
    final text = _safe(value);
    if (text.length == 12) {
      return '${text.substring(0, 4)}-${text.substring(4, 8)}-${text.substring(8)}';
    }
    return text;
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final first = parts.isNotEmpty ? parts.first[0] : 'S';
    final second = parts.length > 1 ? parts.elementAt(1)[0] : '';
    return '$first$second'.toUpperCase();
  }

  String _normalizeSearch(dynamic value) {
    return _safe(value).toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _ok(int statusCode) => statusCode >= 200 && statusCode < 300;

  Map<String, dynamic> _mapOf(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  String _safe(dynamic value, [String fallback = '']) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  String _extractError(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final message =
            decoded['message'] ?? decoded['error'] ?? decoded['sqlMessage'];
        if (message != null && message.toString().trim().isNotEmpty) {
          return message.toString();
        }
      }
    } catch (_) {}
    return fallback;
  }
}
