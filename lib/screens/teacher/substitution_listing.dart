// lib/screens/teacher/substitution_listing.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import '../../services/api_service.dart';

class TeacherSubstitutionListing extends StatefulWidget {
  final int? teacherId;
  const TeacherSubstitutionListing({Key? key, this.teacherId}) : super(key: key);

  @override
  State<TeacherSubstitutionListing> createState() => _TeacherSubstitutionListingState();
}

class _TeacherSubstitutionListingState extends State<TeacherSubstitutionListing> {
  bool _loading = true;
  List<dynamic> _all = [];
  List<String> _errors = [];

  // filters
  DateTime? _filterDate;
  String? _filterCoveredTo; // teacher name
  String? _filterClass;
  String? _filterPeriod;
  String? _filterSubject;

  // dropdown options
  List<String> _coveredToOptions = [];
  List<String> _classOptions = [];
  List<String> _periodOptions = [];
  List<String> _subjectOptions = [];

  IO.Socket? _socket;

  final PageController _todayPageController = PageController(viewportFraction: 0.88);

  @override
  void initState() {
    super.initState();
    _initSocket();
    _loadAll();
  }

  @override
  void dispose() {
    _socket?.dispose();
    _todayPageController.dispose();
    super.dispose();
  }

  int get _teacherId => widget.teacherId ?? 0;

  Future<void> _initSocket() async {
    try {
      // Use ApiService.baseUrl host for socket connect (http -> ws)
      final raw = ApiService.baseUrl;
      // only attempt if socket_io_client package available and baseUrl starts with http
      if (raw != null && raw.startsWith('http')) {
        final uri = Uri.parse(raw);
        final scheme = (uri.scheme == 'https') ? 'wss' : 'ws';
        final host = uri.host;
        final portPart = uri.hasPort ? ':${uri.port}' : '';
        final wsUrl = '$scheme://$host$portPart';

        _socket = IO.io(raw, <String, dynamic>{
          'transports': ['websocket'],
          'autoConnect': true,
        });
        _socket?.onConnect((_) {
          if (kDebugMode) debugPrint('[socket] connected');
        });
        _socket?.on('newSubstitution', (_) => _loadAll());
        _socket?.on('substitutionUpdated', (_) => _loadAll());
        _socket?.on('substitutionDeleted', (_) => _loadAll());
        _socket?.onDisconnect((_) {
          if (kDebugMode) debugPrint('[socket] disconnected');
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('socket init error: $e');
    }
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _errors = [];
    });

    try {
      final resp = await ApiService.rawGet('/substitutions/teacher');
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        dynamic decoded;
        try {
          decoded = json.decode(resp.body);
        } catch (_) {
          decoded = resp.body;
        }

        List<dynamic> list = [];
        if (decoded is List) list = decoded;
        else if (decoded is Map && decoded['rows'] is List) list = decoded['rows'];
        else if (decoded is Map && decoded['data'] is List) list = decoded['data'];
        else if (decoded is Map && decoded['substitutions'] is List) list = decoded['substitutions'];
        else {
          // try to find any list inside
          final anyList = (decoded is Map)
              ? decoded.values.firstWhere((v) => v is List, orElse: () => <dynamic>[])
              : <dynamic>[];
          if (anyList is List) list = anyList;
        }

        // normalize date string to ISO YYYY-MM-DD if possible
        list = list.map((e) {
          if (e is Map) {
            final m = Map<String, dynamic>.from(e);
            if (m.containsKey('date') && m['date'] is String) {
              // convert to yyyy-MM-dd (strip time)
              try {
                final dt = DateTime.parse(m['date'].toString());
                m['date'] = DateFormat('yyyy-MM-dd').format(dt);
              } catch (_) {
                // leave as is
              }
            }
            return m;
          }
          return e;
        }).toList();

        // update state and dropdowns
        if (mounted) {
          setState(() {
            _all = list;
            _extractOptions();
          });
        }
      } else {
        setState(() {
          _errors.add('Failed to fetch (${resp.statusCode})');
        });
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('fetch substitutions error: $e\n$st');
      setState(() {
        _errors.add('Failed to fetch substitutions: $e');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _extractOptions() {
    final coveredSet = <String>{};
    final clsSet = <String>{};
    final perSet = <String>{};
    final subSet = <String>{};

    for (final s in _all) {
      try {
        final m = s as Map;
        final covered = m['OriginalTeacher'] is Map ? (m['OriginalTeacher']['name']?.toString() ?? '') : (m['originalTeacherName']?.toString() ?? '');
        if (covered != null && covered.isNotEmpty) coveredSet.add(covered);

        final cls = m['Class'] is Map ? (m['Class']['class_name']?.toString() ?? '') : (m['class']?.toString() ?? m['classId']?.toString() ?? '');
        if (cls != null && cls.isNotEmpty) clsSet.add(cls);

        final p = m['Period'] is Map ? (m['Period']['period_name']?.toString() ?? '') : (m['periodName']?.toString() ?? m['periodId']?.toString() ?? '');
        if (p != null && p.isNotEmpty) perSet.add(p);

        final subj = m['Subject'] is Map ? (m['Subject']['name']?.toString() ?? '') : (m['subject']?.toString() ?? '');
        if (subj != null && subj.isNotEmpty) subSet.add(subj);
      } catch (_) {}
    }

    _coveredToOptions = coveredSet.toList()..sort();
    _classOptions = clsSet.toList()..sort();
    _periodOptions = perSet.toList()..sort();
    _subjectOptions = subSet.toList()..sort();
  }

  // Filtering logic
  List<dynamic> get _filtered {
    return _all.where((raw) {
      final s = raw as Map;
      final dateStr = s['date']?.toString() ?? '';
      final covered = s['OriginalTeacher'] is Map ? (s['OriginalTeacher']['name']?.toString() ?? '') : (s['originalTeacherName']?.toString() ?? '');
      final cls = s['Class'] is Map ? (s['Class']['class_name']?.toString() ?? '') : (s['class']?.toString() ?? s['classId']?.toString() ?? '');
      final per = s['Period'] is Map ? (s['Period']['period_name']?.toString() ?? '') : (s['periodName']?.toString() ?? s['periodId']?.toString() ?? '');
      final subj = s['Subject'] is Map ? (s['Subject']['name']?.toString() ?? '') : (s['subject']?.toString() ?? '');

      final matchDate = (_filterDate != null) ? dateStr == DateFormat('yyyy-MM-dd').format(_filterDate!) : true;
      final matchCovered = (_filterCoveredTo != null) ? covered == _filterCoveredTo : true;
      final matchClass = (_filterClass != null) ? cls == _filterClass : true;
      final matchPeriod = (_filterPeriod != null) ? per == _filterPeriod : true;
      final matchSubject = (_filterSubject != null) ? subj == _filterSubject : true;
      return matchDate && matchCovered && matchClass && matchPeriod && matchSubject;
    }).toList();
  }

  // Stats helpers
  String _todayIso() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  int _countToday() {
    final t = _todayIso();
    return _all.where((s) {
      try {
        final m = s as Map;
        return (m['date']?.toString() ?? '') == t;
      } catch (_) {
        return false;
      }
    }).length;
  }

  int _countThisWeek() {
    final now = DateTime.now();
    final dow = (now.weekday + 6) % 7;
    final monday = DateTime(now.year, now.month, now.day - dow);
    final saturday = monday.add(const Duration(days: 5));
    return _all.where((s) {
      try {
        final m = s as Map;
        final dStr = m['date']?.toString();
        if (dStr == null || dStr.isEmpty) return false;
        final dt = DateTime.parse(dStr);
        return !dt.isBefore(monday) && !dt.isAfter(saturday);
      } catch (_) {
        return false;
      }
    }).length;
  }

  // Today's list for slider (based on filterDate if set otherwise today)
  List<Map> _todaysForSlider() {
    final dateToUse = _filterDate != null ? DateFormat('yyyy-MM-dd').format(_filterDate!) : _todayIso();
    return _all.where((s) => (s['date']?.toString() ?? '') == dateToUse).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _exportCsvOfFiltered() async {
    final rows = _filtered;
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No rows to export')));
      return;
    }

    final header = ['id', 'date', 'coveredTo', 'class', 'period', 'subject'];
    final csvLines = <String>[];
    csvLines.add(header.join(','));

    for (final r in rows) {
      try {
        final m = r as Map;
        final id = (m['id'] ?? '').toString();
        final date = (m['date'] ?? '').toString();
        final covered = m['OriginalTeacher'] is Map ? (m['OriginalTeacher']['name']?.toString() ?? '') : (m['originalTeacherName']?.toString() ?? '');
        final cls = m['Class'] is Map ? (m['Class']['class_name']?.toString() ?? '') : (m['class']?.toString() ?? m['classId']?.toString() ?? '');
        final per = m['Period'] is Map ? (m['Period']['period_name']?.toString() ?? '') : (m['periodName']?.toString() ?? m['periodId']?.toString() ?? '');
        final subj = m['Subject'] is Map ? (m['Subject']['name']?.toString() ?? '') : (m['subject']?.toString() ?? '');
        final cells = [id, date, covered, cls, per, subj].map((c) => '"${(c ?? '').toString().replaceAll('"', '""')}"').join(',');
        csvLines.add(cells);
      } catch (_) {}
    }

    final csv = csvLines.join('\n');
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/substitutions_${DateTime.now().toIso8601String().split('T').first}.csv');
      await file.writeAsString(csv, encoding: utf8);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('CSV saved to ${file.path}')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save CSV')));
    }
  }

  void _clearFilters() {
    setState(() {
      _filterDate = null;
      _filterCoveredTo = null;
      _filterClass = null;
      _filterPeriod = null;
      _filterSubject = null;
    });
  }

  // pick date
  Future<void> _pickDate() async {
    final initial = _filterDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      setState(() {
        _filterDate = picked;
      });
    }
  }

  Widget _buildSummary() {
    return Row(
      children: [
        _statChip('Total', _all.length.toString(), Icons.list_alt, Colors.blue),
        const SizedBox(width: 8),
        _statChip('Today', _countToday().toString(), Icons.today, Colors.orange),
        const SizedBox(width: 8),
        _statChip('This week', _countThisWeek().toString(), Icons.calendar_view_week, Colors.green),
        const Spacer(),
        ElevatedButton.icon(
          icon: const Icon(Icons.download),
          label: const Text('Export CSV'),
          onPressed: _exportCsvOfFiltered,
        ),
      ],
    );
  }

  Widget _statChip(String label, String value, IconData icon, Color color) {
    return Chip(
      backgroundColor: color.withOpacity(0.12),
      label: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ],
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
    );
  }

  // row widget
  Widget _buildRow(Map s, int index) {
    final date = s['date']?.toString() ?? '';
    final covered = s['OriginalTeacher'] is Map ? (s['OriginalTeacher']['name']?.toString() ?? '') : (s['originalTeacherName']?.toString() ?? '');
    final cls = s['Class'] is Map ? (s['Class']['class_name']?.toString() ?? '') : (s['class']?.toString() ?? s['classId']?.toString() ?? '');
    final per = s['Period'] is Map ? (s['Period']['period_name']?.toString() ?? '') : (s['periodName']?.toString() ?? s['periodId']?.toString() ?? '');
    final subj = s['Subject'] is Map ? (s['Subject']['name']?.toString() ?? '') : (s['subject']?.toString() ?? '');

    final isToday = date == _todayIso();

    return Card(
      color: isToday ? Colors.blue.shade50 : null,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(child: Text('${index + 1}')),
        title: Text('$date — ${covered ?? ''}'),
        subtitle: Text('${cls ?? ''} • ${per ?? ''}'),
        trailing: Text(subj ?? ''),
        onTap: () {
          // optional - show detail dialog
          showDialog(
            context: context,
            builder: (_) {
              return AlertDialog(
                title: Text('Substitution'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Date: $date'),
                    const SizedBox(height: 6),
                    Text('Covered To: ${covered ?? ''}'),
                    const SizedBox(height: 6),
                    Text('Class: ${cls ?? ''}'),
                    const SizedBox(height: 6),
                    Text('Period: ${per ?? ''}'),
                    const SizedBox(height: 6),
                    Text('Subject: ${subj ?? ''}'),
                  ],
                ),
                actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final todaySlider = _todaysForSlider();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Covered Substitutions'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    // errors
                    if (_errors.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _errors.map((e) => Text('• $e', style: const TextStyle(color: Colors.black87))).toList(),
                        ),
                      ),

                    // summary + export
                    _buildSummary(),
                    const SizedBox(height: 12),

                    // filters card
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: InkWell(
                                    onTap: _pickDate,
                                    child: InputDecorator(
                                      decoration: const InputDecoration(labelText: 'Date', border: OutlineInputBorder()),
                                      child: Text(_filterDate == null ? 'Any' : DateFormat.yMd().format(_filterDate!)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: DropdownButtonFormField<String>(
                                    value: _filterCoveredTo,
                                    items: [null, ..._coveredToOptions]
                                        .map((e) => DropdownMenuItem<String>(
                                              value: e,
                                              child: Text(e ?? 'Any'),
                                            ))
                                        .toList(),
                                    onChanged: (v) => setState(() => _filterCoveredTo = v),
                                    decoration: const InputDecoration(labelText: 'Covered To', border: OutlineInputBorder()),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _filterClass,
                                    items: [null, ..._classOptions]
                                        .map((e) => DropdownMenuItem<String>(value: e, child: Text(e ?? 'Any')))
                                        .toList(),
                                    onChanged: (v) => setState(() => _filterClass = v),
                                    decoration: const InputDecoration(labelText: 'Class', border: OutlineInputBorder()),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _filterPeriod,
                                    items: [null, ..._periodOptions]
                                        .map((e) => DropdownMenuItem<String>(value: e, child: Text(e ?? 'Any')))
                                        .toList(),
                                    onChanged: (v) => setState(() => _filterPeriod = v),
                                    decoration: const InputDecoration(labelText: 'Period', border: OutlineInputBorder()),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _filterSubject,
                                    items: [null, ..._subjectOptions]
                                        .map((e) => DropdownMenuItem<String>(value: e, child: Text(e ?? 'Any')))
                                        .toList(),
                                    onChanged: (v) => setState(() => _filterSubject = v),
                                    decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder()),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _clearFilters,
                                  icon: const Icon(Icons.clear),
                                  label: const Text('Clear filters'),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade200, foregroundColor: Colors.black),
                                ),
                                const SizedBox(width: 8),
                                Text('${filtered.length} result(s)', style: const TextStyle(color: Colors.black54)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // today's slider header
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          const Icon(Icons.today, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text('Today\'s Substitutions (${DateFormat.yMMMd().format(_filterDate ?? DateTime.now())})', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // slider
                    if (todaySlider.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: const [
                              Icon(Icons.hourglass_empty),
                              SizedBox(width: 8),
                              Expanded(child: Text('No substitutions for this date')),
                            ],
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: 140,
                        child: PageView.builder(
                          controller: _todayPageController,
                          itemCount: todaySlider.length,
                          itemBuilder: (context, index) {
                            final m = todaySlider[index];
                            final covered = m['OriginalTeacher'] is Map ? (m['OriginalTeacher']['name'] ?? '') : (m['originalTeacherName'] ?? '');
                            final cls = m['Class'] is Map ? (m['Class']['class_name'] ?? '') : (m['class'] ?? m['classId'] ?? '');
                            final per = m['Period'] is Map ? (m['Period']['period_name'] ?? '') : (m['periodName'] ?? m['periodId'] ?? '');
                            final subj = m['Subject'] is Map ? (m['Subject']['name'] ?? '') : (m['subject'] ?? '');
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Material(
                                elevation: 3,
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.white),
                                  child: Row(
                                    children: [
                                      CircleAvatar(child: Text(per.toString().split(' ').map((p) => p.isNotEmpty ? p[0] : '').take(2).join())),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(covered ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                            const SizedBox(height: 4),
                                            Text('$cls • $subj', style: const TextStyle(color: Colors.black54)),
                                          ],
                                        ),
                                      ),
                                      Chip(label: Text(per ?? '')),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                    const SizedBox(height: 12),

                    // list header
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('All substitutions (${filtered.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 8),

                    // list
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(child: Text(_all.isEmpty ? 'No substitutions available' : 'No substitutions match filters'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, idx) {
                                final m = filtered[idx] as Map;
                                return _buildRow(m, idx);
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
