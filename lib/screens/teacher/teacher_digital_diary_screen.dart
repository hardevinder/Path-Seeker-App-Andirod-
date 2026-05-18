// File: lib/screens/teacher/teacher_digital_diary_screen.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/constants.dart';

class TeacherDigitalDiaryScreen extends StatefulWidget {
  const TeacherDigitalDiaryScreen({super.key});

  @override
  State<TeacherDigitalDiaryScreen> createState() =>
      _TeacherDigitalDiaryScreenState();
}

class _TeacherDigitalDiaryScreenState extends State<TeacherDigitalDiaryScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          _DiaryFeedTab(),
          _DiaryCreateTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFF6C63FF),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _selectedIndex = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: 'Feed',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            label: 'Create Diary',
          ),
        ],
      ),
    );
  }
}

/*──────────────────────────────────────────────
  FEED TAB  (View / Filter / Edit / Delete)
──────────────────────────────────────────────*/
class _DiaryFeedTab extends StatefulWidget {
  const _DiaryFeedTab();

  @override
  State<_DiaryFeedTab> createState() => _DiaryFeedTabState();
}

class _DiaryFeedTabState extends State<_DiaryFeedTab> {
  bool loading = true;
  List<Map<String, dynamic>> diaries = [];
  DateTime? dateFrom;
  DateTime? dateTo;
  String? type;
  String? query;
  int page = 1;
  Map<String, dynamic>? pagination;

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchDiaries();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authToken') ?? prefs.getString('token');
  }

  Future<void> _fetchDiaries({bool reset = true}) async {
    if (reset) {
      setState(() {
        page = 1;
        diaries.clear();
      });
    }

    setState(() => loading = true);
    final token = await _getToken();
    if (token == null) {
      setState(() => loading = false);
      return;
    }

    try {
      final params = {
        'page': '$page',
        'pageSize': '20',
        if (type != null && type!.isNotEmpty) 'type': type!,
        if (dateFrom != null)
          'dateFrom': DateFormat('yyyy-MM-dd').format(dateFrom!),
        if (dateTo != null) 'dateTo': DateFormat('yyyy-MM-dd').format(dateTo!),
        if (query != null && query!.isNotEmpty) 'q': query!,
      };

      final uri =
          Uri.parse('$baseUrl/diaries').replace(queryParameters: params);

      final res = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (!mounted) return;

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        setState(() {
          diaries = List<Map<String, dynamic>>.from(body['data'] ?? []);
          pagination = body['pagination'];
        });
      } else {
        _snack('Failed to load diaries (${res.statusCode})', true);
      }
    } catch (e) {
      _snack('Failed to load diaries: $e', true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _deleteDiary(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Diary'),
        content:
            const Text('Are you sure you want to delete this diary entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final token = await _getToken();
    if (token == null) return;

    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/diaries/$id'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (!mounted) return;

      if (res.statusCode == 200) {
        _snack('Diary deleted');
        _fetchDiaries();
      } else {
        _snack('Delete failed: ${res.body}', true);
      }
    } catch (e) {
      _snack('Error: $e', true);
    }
  }

  IconData _icon(String type) {
    switch (type) {
      case 'HOMEWORK':
        return Icons.book;
      case 'REMARK':
        return Icons.note_alt;
      case 'ANNOUNCEMENT':
        return Icons.campaign;
      default:
        return Icons.description;
    }
  }

  void _snack(String msg, [bool err = false]) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: err ? Colors.red : const Color(0xFF6C63FF),
      ),
    );
  }

  Future<void> _showAttachmentsDialog(
    List<Map<String, dynamic>> attachments,
  ) async {
    if (attachments.isEmpty) return;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Attachments',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const Divider(),
              ...attachments.map(
                (a) => ListTile(
                  leading: const Icon(
                    Icons.attachment,
                    color: Color(0xFF6C63FF),
                  ),
                  title: Text((a['name'] ?? 'Attachment').toString()),
                  subtitle: Text((a['url'] ?? '').toString()),
                  trailing: IconButton(
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => _openLink((a['url'] ?? '').toString()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openLink(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }


  String _safe(dynamic v) => v?.toString() ?? '';

  Future<List<Map<String, dynamic>>> _fetchAcknowledgements(int diaryId) async {
    final token = await _getToken();
    if (token == null) throw Exception('No token found');

    final detailHeaders = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    try {
      final ackUri = Uri.parse('$baseUrl/diaries/$diaryId/acknowledgements');
      final ackRes = await http.get(ackUri, headers: detailHeaders);

      if (ackRes.statusCode == 200) {
        final body = jsonDecode(ackRes.body);
        if (body is Map && body['acknowledgements'] is List) {
          return List<Map<String, dynamic>>.from(body['acknowledgements']);
        }
        if (body is Map && body['data'] is List) {
          return List<Map<String, dynamic>>.from(body['data']);
        }
        if (body is List) {
          return List<Map<String, dynamic>>.from(body);
        }
      }
    } catch (_) {
      // fallback below
    }

    final detailUri = Uri.parse('$baseUrl/diaries/$diaryId');
    final detailRes = await http.get(detailUri, headers: detailHeaders);

    if (detailRes.statusCode != 200) {
      throw Exception('Failed to load acknowledgements (${detailRes.statusCode})');
    }

    final body = jsonDecode(detailRes.body);
    if (body is Map && body['diary'] is Map) {
      final diary = Map<String, dynamic>.from(body['diary']);
      return List<Map<String, dynamic>>.from(diary['acknowledgements'] ?? []);
    }
    if (body is Map) {
      return List<Map<String, dynamic>>.from(body['acknowledgements'] ?? []);
    }
    return [];
  }

  Widget _ackTile(Map<String, dynamic> ack) {
    final student = ack['student'] is Map
        ? Map<String, dynamic>.from(ack['student'])
        : <String, dynamic>{};

    final name = _safe(
      student['name'] ?? ack['studentName'] ?? 'Student',
    );
    final admission = _safe(
      student['admission_number'] ??
          ack['admissionNumber'] ??
          ack['admission_number'],
    );
    final roll = _safe(student['roll_number'] ?? ack['rollNumber']);
    final note = _safe(ack['note']);
    final when = _safe(ack['createdAt'] ?? ack['acknowledgedAt']);
    String whenText = when;
    final parsed = DateTime.tryParse(when);
    if (parsed != null) {
      whenText = DateFormat('dd MMM yyyy, hh:mm a').format(parsed.toLocal());
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF6C63FF).withOpacity(0.12),
            child: Text(
              name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'S',
              style: const TextStyle(
                color: Color(0xFF6C63FF),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Student' : name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                if (admission.isNotEmpty)
                  Text(
                    'Admission No: $admission',
                    style: const TextStyle(color: Colors.black54),
                  ),
                if (roll.isNotEmpty)
                  Text(
                    'Roll No: $roll',
                    style: const TextStyle(color: Colors.black54),
                  ),
                const SizedBox(height: 6),
                Text(
                  'Acknowledged: $whenText',
                  style: const TextStyle(fontSize: 12.5),
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Note: $note',
                    style: const TextStyle(color: Colors.black87),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAcknowledgementsSheet(Map<String, dynamic> diary) async {
    final diaryId = diary['id'] is int
        ? diary['id'] as int
        : int.tryParse('${diary['id']}') ?? 0;
    if (diaryId <= 0) {
      _snack('Invalid diary id', true);
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Container(
            height: MediaQuery.of(context).size.height * 0.82,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _fetchAcknowledgements(diaryId),
              builder: (context, snapshot) {
                final title = _safe(diary['title']).isEmpty
                    ? 'Diary #$diaryId'
                    : _safe(diary['title']);

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
                  );
                }

                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        Container(
                          width: 46,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Acknowledgements',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            title,
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.error_outline,
                          size: 42,
                          color: Colors.redAccent,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                        const Spacer(),
                      ],
                    ),
                  );
                }

                final acks = snapshot.data ?? [];

                return Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Acknowledgements',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C63FF).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '${acks.length}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF6C63FF),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'total',
                                  style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: acks.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'No acknowledgements yet.',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                              itemCount: acks.length,
                              itemBuilder: (_, i) => _ackTile(acks[i]),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Digital Diary Feed',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _fetchDiaries,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _filterBar(),
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF6C63FF),
                    ),
                  )
                : diaries.isEmpty
                    ? const Center(child: Text('No diary entries found'))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: diaries.length,
                        itemBuilder: (_, i) {
                          final d = diaries[i];
                          final dt = d['date'] != null
                              ? DateFormat('dd MMM yyyy')
                                  .format(DateTime.parse(d['date']))
                              : '';
                          final attachments =
                              List<Map<String, dynamic>>.from(
                            d['attachments'] ?? [],
                          );

                          return Card(
                            margin: const EdgeInsets.all(12),
                            elevation: 3,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    const Color(0xFF6C63FF).withOpacity(0.1),
                                child: Icon(
                                  _icon(d['type'] ?? ''),
                                  color: const Color(0xFF6C63FF),
                                ),
                              ),
                              title: Text(
                                d['title'] ?? 'Untitled',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    '${d['type']} • $dt',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    d['content'] ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      if (attachments.isNotEmpty)
                                        TextButton.icon(
                                          icon: const Icon(
                                            Icons.attach_file,
                                            size: 16,
                                          ),
                                          label: Text(
                                            '${attachments.length} attachment(s)',
                                          ),
                                          onPressed: () =>
                                              _showAttachmentsDialog(attachments),
                                        ),
                                      TextButton.icon(
                                        icon: const Icon(
                                          Icons.check_circle_outline,
                                          size: 16,
                                          color: Color(0xFF6C63FF),
                                        ),
                                        label: Text(
                                          '${(d['acknowledgements'] is List) ? (d['acknowledgements'] as List).length : 0} acknowledgement(s)',
                                        ),
                                        onPressed: () => _showAcknowledgementsSheet(d),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'acknowledgements') {
                                    _showAcknowledgementsSheet(d);
                                  } else if (v == 'edit') {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            _DiaryCreateTab(existing: d),
                                      ),
                                    );
                                    _fetchDiaries();
                                  } else if (v == 'delete') {
                                    _deleteDiary(d['id']);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'acknowledgements',
                                    child: Row(
                                      children: [
                                        Icon(Icons.check_circle_outline, color: Color(0xFF6C63FF)),
                                        SizedBox(width: 8),
                                        Text('Acknowledgements'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, color: Colors.blue),
                                        SizedBox(width: 8),
                                        Text('Edit'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Delete'),
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
        ],
      ),
    );
  }

  Widget _filterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Color(0xFF6C63FF),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (v) {
                    query = v.trim();
                    _fetchDiaries();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  setState(() {
                    dateFrom = null;
                    dateTo = null;
                    type = null;
                    query = null;
                    _searchCtrl.clear();
                  });
                  _fetchDiaries();
                },
                icon: const Icon(Icons.clear_all, color: Colors.red),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              FilterChip(
                label: Text(
                  dateFrom == null
                      ? 'From'
                      : DateFormat('dd MMM').format(dateFrom!),
                ),
                onSelected: (sel) async {
                  if (!sel) return;
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() => dateFrom = picked);
                    _fetchDiaries();
                  }
                },
              ),
              FilterChip(
                label: Text(
                  dateTo == null
                      ? 'To'
                      : DateFormat('dd MMM').format(dateTo!),
                ),
                onSelected: (sel) async {
                  if (!sel) return;
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() => dateTo = picked);
                    _fetchDiaries();
                  }
                },
              ),
              FilterChip(
                label: const Text('Homework'),
                selected: type == 'HOMEWORK',
                onSelected: (v) {
                  setState(() => type = v ? 'HOMEWORK' : null);
                  _fetchDiaries();
                },
              ),
              FilterChip(
                label: const Text('Remark'),
                selected: type == 'REMARK',
                onSelected: (v) {
                  setState(() => type = v ? 'REMARK' : null);
                  _fetchDiaries();
                },
              ),
              FilterChip(
                label: const Text('Announcement'),
                selected: type == 'ANNOUNCEMENT',
                onSelected: (v) {
                  setState(() => type = v ? 'ANNOUNCEMENT' : null);
                  _fetchDiaries();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/*──────────────────────────────────────────────
  CREATE TAB  (New Diary with file + links + preview)
──────────────────────────────────────────────*/
class _DiaryCreateTab extends StatefulWidget {
  final Map<String, dynamic>? existing;

  const _DiaryCreateTab({this.existing});

  @override
  State<_DiaryCreateTab> createState() => _DiaryCreateTabState();
}

class _DiaryCreateTabState extends State<_DiaryCreateTab> {
  final _formKey = GlobalKey<FormState>();

  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();

  DateTime date = DateTime.now();
  String type = 'HOMEWORK';
  bool submitting = false;

  List<Map<String, dynamic>> attachments = [];
  List<Map<String, dynamic>> classes = [];
  List<Map<String, dynamic>> sections = [];
  List<Map<String, dynamic>> students = [];

  String? classId;
  String? sectionId;
  List<String> selectedStudentIds = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadClasses(),
      _loadSections(),
    ]);

    if (widget.existing != null) {
      final d = widget.existing!;
      setState(() {
        classId = d['classId']?.toString();
        sectionId = d['sectionId']?.toString();
        _titleCtrl.text = d['title'] ?? '';
        _contentCtrl.text = d['content'] ?? '';
        type = d['type'] ?? 'HOMEWORK';
        date = DateTime.tryParse((d['date'] ?? '').toString()) ?? DateTime.now();
        attachments = List<Map<String, dynamic>>.from(d['attachments'] ?? []);
      });

      if (classId != null && sectionId != null) {
        await _loadStudents();
      }
    }

    if (mounted) setState(() {});
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authToken') ?? prefs.getString('token');
  }

  String _str(dynamic value) => value?.toString() ?? '';

  String _classNameById(String? id) {
    final match = classes.cast<Map<String, dynamic>?>().firstWhere(
          (c) => c?['id']?.toString() == id,
          orElse: () => null,
        );
    return match?['name']?.toString() ?? '-';
  }

  String _sectionNameById(String? id) {
    final match = sections.cast<Map<String, dynamic>?>().firstWhere(
          (s) => s?['id']?.toString() == id,
          orElse: () => null,
        );
    return match?['name']?.toString() ?? '-';
  }

  List<String> _selectedStudentNames() {
    if (selectedStudentIds.isEmpty) return [];
    return students
        .where((s) => selectedStudentIds.contains(s['id'].toString()))
        .map((s) => s['name'].toString())
        .toList();
  }

  bool _isImageFileName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp');
  }

  String? _mimeTypeForName(String name) {
    final lower = name.toLowerCase();

    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif';
    }
    if (lower.endsWith('.pdf')) {
      return 'application/pdf';
    }
    if (lower.endsWith('.doc')) {
      return 'application/msword';
    }
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xls')) {
      return 'application/vnd.ms-excel';
    }
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.odt')) {
      return 'application/vnd.oasis.opendocument.text';
    }
    return null;
  }

  IconData _attachmentIcon(String name, {bool isLink = false}) {
    if (isLink) return Icons.link;
    final lower = name.toLowerCase();

    if (_isImageFileName(lower)) return Icons.image;
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) return Icons.description;
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) return Icons.table_chart;
    return Icons.attach_file;
  }

  Future<void> _loadClasses() async {
    final token = await _getToken();
    if (token == null) return _snack('No token found', true);

    try {
      final uri = Uri.parse('$baseUrl/classes');
      final res = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        setState(() {
          if (decoded is List) {
            classes = decoded
                .map<Map<String, dynamic>>(
                  (x) => {
                    'id': x['id'].toString(),
                    'name': x['class_name'] ?? x['name'] ?? 'Unnamed Class',
                  },
                )
                .toList();
          } else if (decoded is Map && decoded['data'] is List) {
            classes = List<Map<String, dynamic>>.from(
              (decoded['data'] as List).map(
                (x) => {
                  'id': x['id'].toString(),
                  'name': x['class_name'] ?? x['name'] ?? 'Unnamed Class',
                },
              ),
            );
          }
        });
      }
    } catch (e) {
      _snack('Error loading classes: $e', true);
    }
  }

  Future<void> _loadSections() async {
    final token = await _getToken();
    if (token == null) return _snack('No token found', true);

    try {
      final uri = Uri.parse('$baseUrl/sections');
      final res = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        List list = [];

        if (decoded is List) {
          list = decoded;
        } else if (decoded is Map && decoded['data'] is List) {
          list = decoded['data'];
        } else if (decoded is Map && decoded['sections'] is List) {
          list = decoded['sections'];
        }

        setState(() {
          sections = List<Map<String, dynamic>>.from(
            list.map(
              (x) => {
                'id': x['id'].toString(),
                'name': x['section_name'] ?? x['name'] ?? 'Unnamed Section',
              },
            ),
          );
        });
      }
    } catch (e) {
      _snack('Error loading sections: $e', true);
    }
  }

  Future<void> _loadStudents() async {
    if (classId == null || sectionId == null) return;

    final token = await _getToken();
    if (token == null) return _snack('No token found', true);

    try {
      final uri =
          Uri.parse('$baseUrl/students/searchByClassAndSection').replace(
        queryParameters: {
          'class_id': classId!,
          'section_id': sectionId!,
        },
      );

      final res = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        List list = [];

        if (decoded is List) {
          list = decoded;
        } else if (decoded is Map && decoded['data'] is List) {
          list = decoded['data'];
        } else if (decoded is Map && decoded['students'] is List) {
          list = decoded['students'];
        }

        setState(() {
          students = List<Map<String, dynamic>>.from(
            list.map(
              (x) => {
                'id': x['id'].toString(),
                'name': x['name'] ??
                    x['student_name'] ??
                    x['full_name'] ??
                    'Unnamed Student',
              },
            ),
          );
        });
      }
    } catch (e) {
      _snack('Error loading students: $e', true);
    }
  }

  Future<void> _pickFiles() async {
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Documents',
          extensions: [
            'jpg',
            'jpeg',
            'png',
            'gif',
            'webp',
            'pdf',
            'doc',
            'docx',
            'xls',
            'xlsx',
            'odt',
          ],
        ),
      ],
    );

    if (files.isEmpty) return;

    final picked = <Map<String, dynamic>>[];

    for (final f in files) {
      Uint8List? bytes;
      try {
        bytes = await f.readAsBytes();
      } catch (_) {}

      picked.add({
        'path': f.path,
        'name': f.name,
        'local': true,
        if (bytes != null) 'bytes': bytes,
      });
    }

    setState(() {
      attachments.addAll(picked);
    });
  }

  Future<void> _addLinkAttachment() async {
    final urlCtrl = TextEditingController();
    final nameCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Link Attachment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(labelText: 'URL'),
            ),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Display Name (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (ok == true && urlCtrl.text.trim().isNotEmpty) {
      setState(() {
        attachments.add({
          'url': urlCtrl.text.trim(),
          'name': nameCtrl.text.trim().isNotEmpty
              ? nameCtrl.text.trim()
              : urlCtrl.text.trim(),
          'local': false,
        });
      });
    }
  }

  Future<void> _previewAttachment(Map<String, dynamic> a) async {
    final isLocal = a['local'] == true;
    final name = _str(a['name']);

    if (!isLocal) {
      final url = _str(a['url']);
      if (url.isEmpty) {
        _snack('Invalid link', true);
        return;
      }
      await _openLink(url);
      return;
    }

    if (_isImageFileName(name)) {
      await showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            color: Colors.black,
            padding: const EdgeInsets.all(12),
            child: Stack(
              children: [
                Center(child: _buildImagePreviewWidget(a)),
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    await _openLocalAttachment(a);
  }

  Widget _buildImagePreviewWidget(Map<String, dynamic> a) {
    final bytes = a['bytes'];
    final path = _str(a['path']);

    if (bytes is Uint8List) {
      return InteractiveViewer(
        child: Image.memory(bytes, fit: BoxFit.contain),
      );
    }

    if (path.isNotEmpty) {
      return InteractiveViewer(
        child: Image.file(File(path), fit: BoxFit.contain),
      );
    }

    return const Text(
      'Preview not available',
      style: TextStyle(color: Colors.white),
    );
  }

  Future<void> _openLocalAttachment(Map<String, dynamic> a) async {
    try {
      final path = _str(a['path']);
      final name = _str(a['name']).isEmpty ? 'Attachment' : _str(a['name']);
      final bytes = a['bytes'];

      if (path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          await OpenFilex.open(path);
          return;
        }
      }

      if (bytes is Uint8List) {
        final dir = await getTemporaryDirectory();
        final safeName = name.replaceAll(RegExp(r'[^\w\.\-\s]'), '_');
        final tempFile = File('${dir.path}/$safeName');
        await tempFile.writeAsBytes(bytes, flush: true);
        await OpenFilex.open(tempFile.path);
        return;
      }

      _snack('Preview not available for this file', true);
    } catch (e) {
      _snack('Unable to open file: $e', true);
    }
  }

  Future<void> _openLink(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _snack('Cannot open link', true);
    }
  }

  Future<void> _showDiaryPreview() async {
    if (!_formKey.currentState!.validate()) return;

    if (classId == null || sectionId == null) {
      _snack('Please select class & section', true);
      return;
    }

    final selectedNames = _selectedStudentNames();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 46,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Diary Preview',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _previewInfoCard(
                        title: _titleCtrl.text.trim().isEmpty
                            ? 'Untitled'
                            : _titleCtrl.text.trim(),
                        type: type,
                        dateText: DateFormat('dd MMM yyyy').format(date),
                      ),
                      const SizedBox(height: 14),
                      _previewSection(
                        'Class & Section',
                        '${_classNameById(classId)} • ${_sectionNameById(sectionId)}',
                      ),
                      const SizedBox(height: 12),
                      _previewSection(
                        'Target Students',
                        selectedNames.isEmpty
                            ? 'Whole class/section'
                            : selectedNames.join(', '),
                      ),
                      const SizedBox(height: 12),
                      _previewSection(
                        'Content',
                        _contentCtrl.text.trim(),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Attachments',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (attachments.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text('No attachments added'),
                        )
                      else
                        Column(
                          children: attachments
                              .map((a) => _buildAttachmentTile(a, inPreview: true))
                              .toList(),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          side: const BorderSide(color: Color(0xFF6C63FF)),
                          foregroundColor: const Color(0xFF6C63FF),
                        ),
                        child: const Text('Close'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: submitting
                            ? null
                            : () {
                                Navigator.pop(context);
                                _submit();
                              },
                        icon: const Icon(Icons.send),
                        label: Text(widget.existing == null ? 'Submit Now' : 'Update Now'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: const Color(0xFF6C63FF),
                          foregroundColor: Colors.white,
                        ),
                      ),
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

  Widget _previewInfoCard({
    required String title,
    required String type,
    required String dateText,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF6C63FF).withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                label: Text(type),
                backgroundColor: Colors.white,
              ),
              Chip(
                label: Text(dateText),
                backgroundColor: Colors.white,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewSection(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value.isEmpty ? '-' : value,
            style: const TextStyle(fontSize: 15),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (classId == null || sectionId == null) {
      _snack('Please select class & section', true);
      return;
    }

    setState(() => submitting = true);

    final token = await _getToken();
    if (token == null) {
      _snack('No token', true);
      setState(() => submitting = false);
      return;
    }

    final isEdit = widget.existing != null;
    final uri = isEdit
        ? Uri.parse('$baseUrl/diaries/${widget.existing!['id']}')
        : Uri.parse('$baseUrl/diaries');

    final req = http.MultipartRequest(isEdit ? 'PUT' : 'POST', uri);
    req.headers['Authorization'] = 'Bearer $token';

    req.fields['sessionId'] = '1';
    req.fields['date'] = DateFormat('yyyy-MM-dd').format(date);
    req.fields['title'] = _titleCtrl.text.trim();
    req.fields['content'] = _contentCtrl.text.trim();
    req.fields['type'] = type;
    req.fields['classId'] = classId!;
    req.fields['sectionId'] = sectionId!;
    req.fields['isActive'] = 'true';

    if (selectedStudentIds.isNotEmpty) {
      req.fields['studentIds'] = jsonEncode(selectedStudentIds);
    }

    final linkList = attachments
        .where((a) => a['local'] == false && a['url'] != null)
        .map(
          (a) => {
            'url': a['url'],
            'name': a['name'],
            'kind': '',
          },
        )
        .toList();

    if (linkList.isNotEmpty) {
      req.fields['attachments'] = jsonEncode(linkList);
    }

    for (final a in attachments.where((a) => a['local'] == true)) {
      final name = _str(a['name']);
      final mimeType = _mimeTypeForName(name);

      if (mimeType == null) {
        _snack('File type not allowed for $name', true);
        continue;
      }

      final parts = mimeType.split('/');
      final bytes = a['bytes'];
      final path = _str(a['path']);

      if (bytes is Uint8List) {
        req.files.add(
          http.MultipartFile.fromBytes(
            'files',
            bytes,
            filename: name,
            contentType: MediaType(parts[0], parts[1]),
          ),
        );
      } else if (path.isNotEmpty) {
        req.files.add(
          await http.MultipartFile.fromPath(
            'files',
            path,
            filename: name,
            contentType: MediaType(parts[0], parts[1]),
          ),
        );
      } else {
        _snack('Skipping invalid file: $name', true);
      }
    }

    debugPrint('------ DIARY SUBMIT DEBUG ------');
    req.fields.forEach((key, value) {
      debugPrint('$key: $value');
    });
    debugPrint('Attachments: ${attachments.length}');
    debugPrint('--------------------------------');

    try {
      final res = await req.send();
      final body = await res.stream.bytesToString();

      if (!mounted) return;

      if (res.statusCode == 200 || res.statusCode == 201) {
        _snack(isEdit ? 'Diary updated successfully' : 'Diary saved successfully');

        if (isEdit) {
          Navigator.pop(context, true);
        } else {
          setState(() {
            _titleCtrl.clear();
            _contentCtrl.clear();
            attachments.clear();
            selectedStudentIds.clear();
            type = 'HOMEWORK';
            date = DateTime.now();
          });
        }
      } else {
        _snack('Failed (${res.statusCode}): $body', true);
      }
    } catch (e) {
      _snack('Error: $e', true);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  void _snack(String msg, [bool err = false]) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: err ? Colors.red : const Color(0xFF6C63FF),
      ),
    );
  }

  Widget _buildAttachmentTile(
    Map<String, dynamic> a, {
    bool inPreview = false,
  }) {
    final isLocal = a['local'] == true;
    final name = _str(a['name']).isEmpty ? 'Attachment' : _str(a['name']);
    final subtitle = isLocal ? 'Local file' : _str(a['url']);
    final isImage = isLocal && _isImageFileName(name);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: isImage
            ? _attachmentImageThumb(a)
            : CircleAvatar(
                backgroundColor: const Color(0xFF6C63FF).withOpacity(0.1),
                child: Icon(
                  _attachmentIcon(name, isLink: !isLocal),
                  color: const Color(0xFF6C63FF),
                ),
              ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          subtitle.isEmpty ? '-' : subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        onTap: () => _previewAttachment(a),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: isLocal
                  ? (isImage ? 'Preview image' : 'Open file')
                  : 'Open link',
              icon: Icon(
                isImage ? Icons.visibility : Icons.open_in_new,
                color: const Color(0xFF6C63FF),
              ),
              onPressed: () => _previewAttachment(a),
            ),
            if (!inPreview)
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close, color: Colors.red),
                onPressed: () => setState(() => attachments.remove(a)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _attachmentImageThumb(Map<String, dynamic> a) {
    final bytes = a['bytes'];
    final path = _str(a['path']);

    if (bytes is Uint8List) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          bytes,
          width: 42,
          height: 42,
          fit: BoxFit.cover,
        ),
      );
    }

    if (path.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(path),
          width: 42,
          height: 42,
          fit: BoxFit.cover,
        ),
      );
    }

    return CircleAvatar(
      backgroundColor: const Color(0xFF6C63FF).withOpacity(0.1),
      child: const Icon(Icons.image, color: Color(0xFF6C63FF)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Diary' : 'Create Diary'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Select Class'),
                value: classId,
                items: classes
                    .map(
                      (c) => DropdownMenuItem(
                        value: c['id'].toString(),
                        child: Text(c['name']),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    classId = v;
                    sectionId = null;
                    students.clear();
                    selectedStudentIds.clear();
                  });
                  _loadSections();
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Select Section'),
                value: sectionId,
                items: sections
                    .map(
                      (s) => DropdownMenuItem(
                        value: s['id'].toString(),
                        child: Text(s['name']),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    sectionId = v;
                    students.clear();
                    selectedStudentIds.clear();
                  });
                  _loadStudents();
                },
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () async {
                  if (students.isEmpty) {
                    _snack('No students loaded for this class/section', true);
                    return;
                  }

                  final result = await showDialog<List<String>>(
                    context: context,
                    builder: (context) {
                      bool selectAll =
                          selectedStudentIds.length == students.length;
                      List<String> tempSelected = List.from(selectedStudentIds);

                      return StatefulBuilder(
                        builder: (context, setStateDialog) {
                          return AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Select Students'),
                                TextButton.icon(
                                  icon: Icon(
                                    selectAll
                                        ? Icons.check_box
                                        : Icons.check_box_outline_blank,
                                    color: const Color(0xFF6C63FF),
                                  ),
                                  label: const Text('Select All'),
                                  onPressed: () {
                                    setStateDialog(() {
                                      selectAll = !selectAll;
                                      tempSelected = selectAll
                                          ? students
                                              .map((s) => s['id'].toString())
                                              .toList()
                                          : [];
                                    });
                                  },
                                ),
                              ],
                            ),
                            content: SizedBox(
                              width: double.maxFinite,
                              height: 400,
                              child: ListView(
                                children: students
                                    .map(
                                      (s) => CheckboxListTile(
                                        title: Text(s['name']),
                                        value: tempSelected
                                            .contains(s['id'].toString()),
                                        onChanged: (v) {
                                          setStateDialog(() {
                                            if (v == true) {
                                              tempSelected
                                                  .add(s['id'].toString());
                                            } else {
                                              tempSelected
                                                  .remove(s['id'].toString());
                                            }
                                          });
                                        },
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, null),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6C63FF),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () =>
                                    Navigator.pop(context, tempSelected),
                                child: const Text('Done'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );

                  if (result != null) {
                    setState(() => selectedStudentIds = result);
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          selectedStudentIds.isEmpty
                              ? 'Select Students (optional)'
                              : selectedStudentIds.length == students.length
                                  ? 'All Students Selected'
                                  : '${selectedStudentIds.length} Students Selected',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_drop_down,
                        color: Color(0xFF6C63FF),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Title *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Title required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contentCtrl,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Content *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Content required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Type'),
                value: type,
                items: const [
                  DropdownMenuItem(
                    value: 'HOMEWORK',
                    child: Text('Homework'),
                  ),
                  DropdownMenuItem(
                    value: 'REMARK',
                    child: Text('Remark'),
                  ),
                  DropdownMenuItem(
                    value: 'ANNOUNCEMENT',
                    child: Text('Announcement'),
                  ),
                ],
                onChanged: (v) => setState(() => type = v ?? 'HOMEWORK'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Date: ${DateFormat('dd MMM yyyy').format(date)}',
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.date_range,
                      color: Color(0xFF6C63FF),
                    ),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => date = picked);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Attach Files'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _pickFiles,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.link),
                      label: const Text('Add Link'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6C63FF),
                        side: const BorderSide(color: Color(0xFF6C63FF)),
                      ),
                      onPressed: _addLinkAttachment,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (attachments.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Selected Attachments',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${attachments.length}',
                          style: const TextStyle(
                            color: Color(0xFF6C63FF),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...attachments.map((a) => _buildAttachmentTile(a)).toList(),
                  ],
                ),
              const SizedBox(height: 20),
              submitting
                  ? const CircularProgressIndicator(color: Color(0xFF6C63FF))
                  : Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.visibility),
                            label: const Text('Preview'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              foregroundColor: const Color(0xFF6C63FF),
                              side: const BorderSide(
                                color: Color(0xFF6C63FF),
                              ),
                            ),
                            onPressed: _showDiaryPreview,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.save),
                            label: Text(isEdit ? 'Update' : 'Submit'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6C63FF),
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48),
                            ),
                            onPressed: _submit,
                          ),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}