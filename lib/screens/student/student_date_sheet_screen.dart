import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../widgets/student_drawer_menu.dart';

class StudentDateSheetScreen extends StatefulWidget {
  const StudentDateSheetScreen({super.key});

  @override
  State<StudentDateSheetScreen> createState() => _StudentDateSheetScreenState();
}

class _StudentDateSheetScreenState extends State<StudentDateSheetScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _schedules = [];

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

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
      final response = await ApiService.rawGet(
          '/exam-schedules/my-date-sheet?upcoming=false');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded is Map
            ? decoded['message'] ?? 'Failed to load date sheet'
            : 'Failed to load date sheet');
      }
      final decoded = jsonDecode(response.body);
      final raw = decoded is Map ? decoded['schedules'] : null;
      if (!mounted) return;
      setState(() {
        _schedules = raw is List
            ? raw
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
            : [];
      });
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _date(dynamic value) {
    final parsed = DateTime.tryParse('${value ?? ''}');
    return parsed == null
        ? '${value ?? '-'}'
        : DateFormat('EEE, d MMM yyyy').format(parsed);
  }

  String _time(dynamic value) {
    final raw = '${value ?? ''}'.trim();
    if (raw.isEmpty) return '-';
    final parsed = DateFormat('HH:mm:ss').tryParse(raw) ??
        DateFormat('HH:mm').tryParse(raw);
    return parsed == null ? raw : DateFormat('h:mm a').format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Date Sheet')),
      drawer: const StudentDrawerMenu(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const SizedBox(height: 100),
                      const Icon(Icons.error_outline_rounded,
                          size: 48, color: Colors.redAccent),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                    ],
                  )
                : _schedules.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(24),
                        children: const [
                          SizedBox(height: 100),
                          Icon(Icons.event_note_rounded,
                              size: 56, color: Colors.blueGrey),
                          SizedBox(height: 12),
                          Text(
                            'No date sheet has been published yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(14),
                        itemCount: _schedules.length,
                        itemBuilder: (context, index) {
                          final row = _schedules[index];
                          final exam = _map(row['exam']);
                          final subject = _map(row['subject']);
                          final term = _map(row['term']);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(11),
                                    decoration: BoxDecoration(
                                      color: Colors.indigo.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                        Icons.event_available_rounded,
                                        color: Colors.indigo),
                                  ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('${subject['name'] ?? 'Subject'}',
                                            style: const TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 4),
                                        Text(
                                            '${exam['name'] ?? 'Exam'} · ${term['name'] ?? ''}',
                                            style: TextStyle(
                                                color: Colors.grey.shade700)),
                                        const Divider(height: 22),
                                        Text(_date(row['exam_date']),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 4),
                                        Text(
                                            '${_time(row['start_time'])} – ${_time(row['end_time'])}'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
