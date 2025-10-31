// File: lib/screens/teacher/digital_diary.dart
// Corrected Digital Diary widget (teacher area). Uses Dio + file_picker.

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int PAGE_SIZE = 20;
final Dio dio = Dio(BaseOptions(receiveDataWhenStatusError: true));

Future<Map<String, String>> getAuthHeaders() async {
  final sp = await SharedPreferences.getInstance();
  final token = sp.getString('token') ?? sp.getString('jwt') ?? sp.getString('accessToken') ?? sp.getString('authToken');
  if (token == null || token.isEmpty) return {};
  return {'Authorization': 'Bearer $token'};
}

class RoleFlags {
  final List<String> roles;
  final bool isAdmin;
  final bool isSuperadmin;
  final bool isHR;
  final bool isCoordinator;
  final bool isTeacher;
  final bool isStudent;

  RoleFlags({
    required this.roles,
    required this.isAdmin,
    required this.isSuperadmin,
    required this.isHR,
    required this.isCoordinator,
    required this.isTeacher,
    required this.isStudent,
  });

  factory RoleFlags.fromPrefs(Map<String, dynamic> map) {
    final raw = (map['roles'] as List?) ?? [];
    final roles = raw.map((e) => e.toString()).toList();
    final lc = roles.map((r) => r.toLowerCase()).toList();
    return RoleFlags(
      roles: roles,
      isAdmin: lc.contains('admin'),
      isSuperadmin: lc.contains('superadmin'),
      isHR: lc.contains('hr'),
      isCoordinator: lc.contains('academic_coordinator'),
      isTeacher: lc.contains('teacher'),
      isStudent: lc.contains('student'),
    );
  }
}

Future<RoleFlags> getRoleFlags() async {
  final sp = await SharedPreferences.getInstance();
  final single = sp.getString('userRole');
  final multiRaw = sp.getString('roles');
  List<String> multi = [];
  try {
    if (multiRaw != null) {
      final decoded = jsonDecode(multiRaw);
      if (decoded is List) multi = decoded.map((e) => e.toString()).toList();
    }
  } catch (_) {}
  final roles = multi.isNotEmpty ? multi : (single != null ? [single] : []);
  final lc = roles.map((r) => (r).toLowerCase()).toList();
  return RoleFlags(
    roles: roles,
    isAdmin: lc.contains('admin'),
    isSuperadmin: lc.contains('superadmin'),
    isHR: lc.contains('hr'),
    isCoordinator: lc.contains('academic_coordinator'),
    isTeacher: lc.contains('teacher'),
    isStudent: lc.contains('student'),
  );
}

/// Diary API helpers that try a few base paths. Modify as needed for your backend.
List<String> buildDiaryCandidates() {
  return ['/diaries', 'diaries'];
}

Future<Response> diaryRequest({
  String method = 'get',
  String suffix = '',
  Map<String, dynamic>? params,
  dynamic data,
  Map<String, String> headers = const {},
}) async {
  final sp = await SharedPreferences.getInstance();
  final cached = sp.getString('diary_base_selected');
  final candidates = buildDiaryCandidates();
  final tried = cached != null ? [cached, ...candidates.where((p) => p != cached)] : candidates;
  dynamic lastErr;
  String joinBase(String base, String suf) {
    if (suf.isEmpty) return base;
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final s = suf.startsWith('/') ? suf : '/$suf';
    return '$b$s';
  }

  for (final base in tried) {
    final url = joinBase(base, suffix);
    try {
      final auth = await getAuthHeaders();
      final opt = Options(headers: {...auth, ...headers});
      late Response res;
      final m = method.toLowerCase();
      if (m == 'get') res = await dio.get(url, queryParameters: params, options: opt);
      else if (m == 'post') res = await dio.post(url, data: data, queryParameters: params, options: opt);
      else if (m == 'put') res = await dio.put(url, data: data, queryParameters: params, options: opt);
      else if (m == 'delete') res = await dio.delete(url, data: data, queryParameters: params, options: opt);
      else throw Exception('Unsupported method $method');
      if (cached != base) await sp.setString('diary_base_selected', base);
      return res;
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) rethrow;
      lastErr = e;
    }
  }
  throw lastErr ?? Exception('Diary request failed');
}

Future<Response> diaryGet(String s, [Map<String, dynamic>? p]) => diaryRequest(method: 'get', suffix: s, params: p);
Future<Response> diaryPost(String s, [dynamic d, Map<String, String> h = const {}]) => diaryRequest(method: 'post', suffix: s, data: d, headers: h);
Future<Response> diaryPut(String s, [dynamic d, Map<String, String> h = const {}]) => diaryRequest(method: 'put', suffix: s, data: d, headers: h);
Future<Response> diaryDelete(String s, [Map<String, dynamic>? p]) => diaryRequest(method: 'delete', suffix: s, params: p);

class Diary {
  int id;
  String date;
  String type;
  String title;
  String content;
  dynamic classObj;
  dynamic sectionObj;
  dynamic subject;
  List<dynamic> attachments;
  List<dynamic> targets;
  List<dynamic> acknowledgements;
  List<dynamic> views;
  List<int>? _sourceIds;

  Diary({
    required this.id,
    required this.date,
    required this.type,
    required this.title,
    required this.content,
    this.classObj,
    this.sectionObj,
    this.subject,
    this.attachments = const [],
    this.targets = const [],
    this.acknowledgements = const [],
    this.views = const [],
    List<int>? sourceIds,
  }) : _sourceIds = sourceIds;

  factory Diary.fromMap(Map m) {
    return Diary(
      id: (m['id'] is int) ? m['id'] : int.tryParse('${m['id']}') ?? 0,
      date: m['date'] ?? '',
      type: m['type'] ?? 'ANNOUNCEMENT',
      title: m['title'] ?? '',
      content: m['content'] ?? '',
      classObj: m['class'] ?? m['Class'],
      sectionObj: m['section'] ?? m['Section'],
      subject: m['subject'],
      attachments: (m['attachments'] is List) ? List.from(m['attachments']) : [],
      targets: (m['targets'] is List) ? List.from(m['targets']) : [],
      acknowledgements: (m['acknowledgements'] is List) ? List.from(m['acknowledgements']) : [],
      views: (m['views'] is List) ? List.from(m['views']) : [],
      sourceIds: (m['_sourceIds'] is List) ? List.from(m['_sourceIds']).map((e) => int.tryParse('$e') ?? 0).toList() : null,
    );
  }
}

// ---------- Widgets ----------
class DigitalDiaryPage extends StatefulWidget {
  const DigitalDiaryPage({Key? key}) : super(key: key);

  @override
  State<DigitalDiaryPage> createState() => _DigitalDiaryPageState();
}

class _DigitalDiaryPageState extends State<DigitalDiaryPage> {
  late Future<RoleFlags> _rolesFuture;

  @override
  void initState() {
    super.initState();
    _rolesFuture = getRoleFlags();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RoleFlags>(
      future: _rolesFuture,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final r = snap.data!;
        final showManage = r.isAdmin || r.isSuperadmin || r.isHR || r.isCoordinator || r.isTeacher;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (showManage) ...[
                ManageDiariesWidget(),
                const SizedBox(height: 24),
                const Divider(thickness: 2),
                const SizedBox(height: 24),
              ],
              DiaryFeedWidget(),
            ],
          ),
        );
      },
    );
  }
}

class DiaryCardWidget extends StatefulWidget {
  final Diary diary;
  final bool canAck;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const DiaryCardWidget({
    Key? key,
    required this.diary,
    this.canAck = false,
    this.onEdit,
    this.onDelete,
  }) : super(key: key);

  @override
  State<DiaryCardWidget> createState() => _DiaryCardWidgetState();
}

class _DiaryCardWidgetState extends State<DiaryCardWidget> {
  bool acked = false;
  bool loadingAck = false;
  String note = '';

  @override
  void initState() {
    super.initState();
    acked = (widget.diary.acknowledgements.isNotEmpty);
  }

  Future<void> doAck() async {
    if (!widget.canAck) return;
    setState(() => loadingAck = true);
    try {
      await diaryPost('/${widget.diary.id}/ack', note.isNotEmpty ? {'note': note} : null);
      setState(() {
        acked = true;
        note = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Acknowledged')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to acknowledge: $e')));
    } finally {
      setState(() => loadingAck = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seenCount = widget.diary.views.length;
    final ackCount = widget.diary.acknowledgements.length;
    final dateDisplay = widget.diary.date.isNotEmpty ? DateFormat.yMMMEd().format(DateTime.tryParse(widget.diary.date) ?? DateTime.now()) : '';

    final attachments = (widget.diary.attachments ?? []).map<Map<String, String?>>((a) {
      if (a is String) return {'href': a, 'label': a.split('/').last};
      if (a is Map) {
        final href = a['fileUrl']?.toString() ?? a['url']?.toString();
        final label = a['originalName']?.toString() ?? a['name']?.toString() ?? (href != null ? href.split('/').last : 'Attachment');
        return {'href': href, 'label': label};
      }
      return {'href': null, 'label': 'Attachment'};
    }).where((a) => a['href'] != null).toList();

    final hasMultipleTargets = (widget.diary.targets ?? []).isNotEmpty;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.blue.shade400, Colors.blue.shade700]),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_month, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(dateDisplay, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 4),
                    Chip(label: Text(widget.diary.type, style: const TextStyle(fontWeight: FontWeight.bold))),
                  ]),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('👁 $seenCount', style: const TextStyle(color: Colors.white70)),
                    Text('✓ $ackCount', style: const TextStyle(color: Colors.white70)),
                  ],
                )
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.diary.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Text(widget.diary.content, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 12),
              if (hasMultipleTargets)
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: (widget.diary.targets ?? []).map<Widget>((t) {
                    final className = (t is Map ? (t['class']?['class_name'] ?? t['class']?['name']) : null) ?? 'Class ${t is Map ? (t['classId'] ?? '') : ''}';
                    final sectionName = (t is Map ? (t['section']?['section_name'] ?? t['section']?['name']) : null) ?? 'Sec ${t is Map ? (t['sectionId'] ?? '') : ''}';
                    return Chip(label: Text('$className - $sectionName'));
                  }).toList(),
                ),
              if (attachments.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: attachments.map((a) {
                    return OutlinedButton.icon(
                      onPressed: () {
                        // open url — integrate url_launcher if you want
                      },
                      icon: const Icon(Icons.attach_file),
                      label: Text(a['label'] ?? 'Attachment'),
                    );
                  }).toList(),
                )
              ],
              const SizedBox(height: 12),
              if (widget.canAck)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    if (acked)
                      const Chip(
                        avatar: Icon(Icons.check_circle, color: Colors.white),
                        backgroundColor: Colors.green,
                        label: Text('Acknowledged', style: TextStyle(color: Colors.white)),
                      )
                    else ...[
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(hintText: 'Optional note...', isDense: true),
                          onChanged: (v) => setState(() => note = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: loadingAck ? null : doAck,
                        child: loadingAck ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Acknowledge'),
                      )
                    ]
                  ]),
                )
            ]),
          ),
          if (widget.onEdit != null || widget.onDelete != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  if (widget.onEdit != null)
                    OutlinedButton.icon(onPressed: widget.onEdit, icon: const Icon(Icons.edit), label: const Text('Edit')),
                  const SizedBox(width: 8),
                  if (widget.onDelete != null)
                    OutlinedButton.icon(
                      onPressed: widget.onDelete,
                      icon: const Icon(Icons.delete),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    ),
                ],
              ),
            )
        ],
      ),
    );
  }
}

/// ---------- Manage Diaries Widget ----------
class ManageDiariesWidget extends StatefulWidget {
  const ManageDiariesWidget({Key? key}) : super(key: key);

  @override
  State<ManageDiariesWidget> createState() => _ManageDiariesWidgetState();
}

class _ManageDiariesWidgetState extends State<ManageDiariesWidget> {
  List<Diary> diaries = [];
  bool applyLoading = false;
  bool pageLoading = false;
  int page = 1;
  int total = 0;
  Map<String, dynamic> filters = {
    'from': '',
    'to': '',
    'classId': '',
    'sectionId': '',
    'subjectId': '',
    'type': '',
    'q': '',
  };

  List<dynamic> classes = [];
  List<dynamic> sections = [];
  List<dynamic> subjects = [];
  List<dynamic> sessions = [];

  Map<String, dynamic> form = {};
  bool multiMode = false;
  List<Map<String, dynamic>> targets = [];
  Map<String, dynamic> draftTarget = {'classId': '', 'sectionId': ''};
  bool saving = false;
  List<dynamic> studentsForPicker = [];
  bool studentsLoading = false;
  String studentSearch = '';
  List<int> selectedStudentIds = [];

  bool showModal = false;

  @override
  void initState() {
    super.initState();
    _initLists();
  }

  Future<void> _initLists() async {
    setState(() => applyLoading = true);
    try {
      final cl = await dio.get('/classes', options: Options(headers: await getAuthHeaders()));
      final sec = await dio.get('/sections', options: Options(headers: await getAuthHeaders()));
      setState(() {
        classes = (cl.data is List) ? cl.data : (cl.data['classes'] ?? []);
        sections = (sec.data is List) ? sec.data : (sec.data['sections'] ?? []);
      });
    } catch (_) {}
    try {
      final resp = await dio.get('/class-subject-teachers/teacher/class-subjects', options: Options(headers: await getAuthHeaders()));
      final arr = (resp.data?['assignments'] ?? []).map((a) => a['subject']).where((s) => s != null).toList();
      final map = <dynamic, dynamic>{};
      for (var s in arr) map[s['id']] = s;
      setState(() => subjects = map.values.toList());
    } catch (_) {
      setState(() => subjects = []);
    }
    try {
      final r = await dio.get('/sessions', options: Options(headers: await getAuthHeaders()));
      final list = (r.data is List) ? r.data : (r.data['items'] ?? []);
      setState(() => sessions = list);
      if (list.isNotEmpty) {
        form['sessionId'] = (list.firstWhere((s) => s['is_active'] == true, orElse: () => list.first))['id'];
      }
    } catch (_) {
      setState(() => sessions = []);
    }
    await loadDiaries(1);
    setState(() => applyLoading = false);
  }

  Future<void> loadDiaries(int p) async {
    setState(() => applyLoading = true);
    try {
      final params = {
        'page': p,
        'pageSize': PAGE_SIZE,
        if ((filters['from'] ?? '').toString().isNotEmpty) 'dateFrom': filters['from'],
        if ((filters['to'] ?? '').toString().isNotEmpty) 'dateTo': filters['to'],
        if ((filters['classId'] ?? '').toString().isNotEmpty) 'classId': filters['classId'],
        if ((filters['sectionId'] ?? '').toString().isNotEmpty) 'sectionId': filters['sectionId'],
        if ((filters['subjectId'] ?? '').toString().isNotEmpty) 'subjectId': filters['subjectId'],
        if ((filters['type'] ?? '').toString().isNotEmpty) 'type': filters['type'],
        if ((filters['q'] ?? '').toString().isNotEmpty) 'q': filters['q'],
      };
      final res = await diaryGet('', params);
      final list = (res.data?['data'] is List) ? res.data['data'] : [];
      setState(() {
        diaries = List.from(list.map((m) => Diary.fromMap(m)));
        total = res.data?['pagination']?['total'] ?? 0;
        page = p;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load diaries: $e')));
    } finally {
      setState(() => applyLoading = false);
    }
  }

  void openCreate() {
    setState(() {
      form = {
        'id': null,
        'sessionId': sessions.isNotEmpty ? (sessions.firstWhere((s) => s['is_active'] == true, orElse: () => sessions[0])['id']) : null,
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'type': 'ANNOUNCEMENT',
        'title': '',
        'content': '',
        'classId': '',
        'sectionId': '',
        'subjectId': '',
        'attachments': [],
        'selectedFiles': [],
        'replaceAttachments': false,
        'keepAttachmentIds': [],
      };
      multiMode = false;
      targets = [];
      draftTarget = {'classId': '', 'sectionId': ''};
      studentsForPicker = [];
      selectedStudentIds = [];
      showModal = true;
    });
  }

  void openEdit(Diary d) {
    final existing = (d.attachments ?? []).map((a) {
      return {
        'id': a is Map ? a['id'] : null,
        'name': a is Map ? (a['originalName'] ?? a['name'] ?? (a['fileUrl']?.toString().split('/')?.last ?? 'Attachment')) : (a is String ? a.split('/').last : 'Attachment'),
        'url': a is Map ? (a['fileUrl'] ?? a['url']) : (a is String ? a : null),
        'kind': a is Map ? (a['kind'] ?? '') : '',
        'mimeType': a is Map ? a['mimeType'] : null,
        'size': a is Map ? a['size'] : null,
      };
    }).toList();
    setState(() {
      form = {
        'id': d.id,
        'sessionId': d.subject?['sessionId'] ?? null,
        'date': d.date.split('T').first,
        'type': d.type,
        'title': d.title,
        'content': d.content,
        'classId': d.classObj?['id']?.toString() ?? '',
        'sectionId': d.sectionObj?['id']?.toString() ?? '',
        'subjectId': d.subject?['id']?.toString() ?? '',
        'attachments': existing,
        'selectedFiles': [],
        'replaceAttachments': false,
        'keepAttachmentIds': existing.where((a) => a['id'] != null).map((a) => a['id']).toList(),
      };
      multiMode = false;
      targets = [];
      draftTarget = {'classId': '', 'sectionId': ''};
      showModal = true;
    });
  }

  Future<void> save() async {
    if (form['sessionId'] == null || (form['date'] ?? '').toString().isEmpty || (form['type'] ?? '').toString().isEmpty || (form['title'] ?? '').toString().isEmpty || (form['content'] ?? '').toString().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill session, date, type, title and content.')));
      return;
    }
    if (!multiMode && (form['classId'] == null || (form['classId'] ?? '').toString().isEmpty) && form['id'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select Class & Section.')));
      return;
    }
    if (multiMode && (targets.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add at least one Class & Section in Targets.')));
      return;
    }

    setState(() => saving = true);
    try {
      final hasFiles = ((form['selectedFiles'] ?? []) as List).isNotEmpty;
      final isUpdate = form['id'] != null;
      if (!hasFiles && !(isUpdate && form['replaceAttachments'] == true)) {
        final payload = {
          'sessionId': int.tryParse('${form['sessionId']}') ?? form['sessionId'],
          'date': form['date'],
          'type': form['type'],
          'title': form['title'],
          'content': form['content'],
          'subjectId': form['subjectId'] != null && form['subjectId'] != '' ? int.tryParse('${form['subjectId']}') : null,
          'attachments': ((form['attachments'] ?? []) as List).map((a) {
            final m = a is Map ? a : {};
            return {
              'fileUrl': m['url'] ?? m['fileUrl'] ?? '',
              'originalName': m['name'] ?? m['originalName'] ?? (m['url']?.toString().split('/')?.last ?? ''),
              'mimeType': m['mimeType'] ?? 'application/octet-stream',
              'size': m['size'] ?? 0
            };
          }).toList(),
          if (isUpdate) 'replaceAttachments': form['replaceAttachments'] == true,
          if (multiMode && !isUpdate) 'targets': targets,
          if (!multiMode && !isUpdate) 'classId': int.tryParse('${form['classId']}') ?? form['classId'],
          if (!multiMode && !isUpdate) 'sectionId': int.tryParse('${form['sectionId']}') ?? form['sectionId'],
          if (!isUpdate && !multiMode && selectedStudentIds.isNotEmpty) 'studentIds': selectedStudentIds,
        };
        if (isUpdate) await diaryPut('/${form['id']}', payload);
        else await diaryPost('', payload);
      } else {
        final fd = FormData();
        fd.fields.addAll([
          MapEntry('sessionId', '${form['sessionId']}'),
          MapEntry('date', form['date']),
          MapEntry('type', form['type']),
          MapEntry('title', form['title']),
          MapEntry('content', form['content']),
        ]);
        fd.fields.add(MapEntry('attachments', jsonEncode(((form['attachments'] ?? []) as List).map((a) {
          final m = a is Map ? a : {};
          return {'fileUrl': m['url'] ?? m['fileUrl'] ?? '', 'originalName': m['name'] ?? m['originalName'] ?? '', 'mimeType': m['mimeType'] ?? 'application/octet-stream', 'size': m['size'] ?? 0};
        }).toList())));
        if (multiMode && form['id'] == null) {
          fd.fields.add(MapEntry('targets', jsonEncode(targets)));
          for (var i = 0; i < targets.length; i++) {
            fd.fields.add(MapEntry('targets[$i][classId]', '${targets[i]['classId']}'));
            fd.fields.add(MapEntry('targets[$i][sectionId]', '${targets[i]['sectionId']}'));
          }
        } else {
          fd.fields.add(MapEntry('classId', '${form['classId']}'));
          fd.fields.add(MapEntry('sectionId', '${form['sectionId']}'));
        }
        if (!isUpdate && !multiMode && selectedStudentIds.isNotEmpty) {
          fd.fields.add(MapEntry('studentIds', selectedStudentIds.join(',')));
        }
        if (isUpdate) {
          if (form['replaceAttachments']) fd.fields.add(MapEntry('replaceAttachments', 'true'));
          else fd.fields.add(MapEntry('existingFiles', jsonEncode(form['keepAttachmentIds'] ?? [])));
        }
        final selFiles = (form['selectedFiles'] ?? []) as List;
        for (var f in selFiles) {
          try {
            if (f is PlatformFile && f.path != null) {
              fd.files.add(MapEntry('files', MultipartFile.fromFileSync(f.path!, filename: f.name)));
            } else if (f is File) {
              fd.files.add(MapEntry('files', MultipartFile.fromFileSync(f.path, filename: f.path.split('/').last)));
            }
          } catch (e) {
            // skip problematic files but continue
          }
        }
        if (form['id'] != null) await diaryPut('/${form['id']}', fd);
        else await diaryPost('', fd);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(form['id'] != null ? 'Diary updated' : 'Diary created')));
      setState(() => showModal = false);
      await loadDiaries(1);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    } finally {
      setState(() => saving = false);
    }
  }

  Future<void> del(dynamic idOrIds) async {
    final ids = idOrIds is List ? idOrIds : [idOrIds];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(ids.length > 1 ? 'Delete this message from all classes?' : 'Delete this diary?'),
        content: Text(ids.length > 1
            ? 'This will remove all copies of this message across selected classes/sections.'
            : 'This will archive (hide) the note. You can hard-delete later if needed.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => applyLoading = true);
    try {
      for (var id in ids) {
        await diaryDelete('/$id');
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
      await loadDiaries(1);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    } finally {
      setState(() => applyLoading = false);
    }
  }

  void addTarget() {
    final c = int.tryParse('${draftTarget['classId']}') ?? 0;
    final s = int.tryParse('${draftTarget['sectionId']}') ?? 0;
    if (c == 0 || s == 0) return;
    final exists = targets.any((t) => t['classId'] == c && t['sectionId'] == s);
    if (exists) return;
    setState(() {
      targets.add({'classId': c, 'sectionId': s});
      draftTarget = {'classId': '', 'sectionId': ''};
    });
  }

  void removeTargetAt(int idx) {
    setState(() => targets.removeAt(idx));
  }

  Future<void> pickFilesForForm() async {
    try {
      final res = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (res != null) {
        setState(() {
          form['selectedFiles'] = res.files;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('File pick failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Digital Diary Management', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      const Text('Create, attach files, and manage notes across classes.', style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        ElevatedButton.icon(onPressed: openCreate, icon: const Icon(Icons.add_circle), label: const Text('Add Diary')),
      ]),
      const SizedBox(height: 12),
      Card(
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Search', isDense: true),
                  onChanged: (v) => setState(() => filters['q'] = v),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: applyLoading ? null : () => loadDiaries(1),
                icon: applyLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search),
                label: const Text('Apply'),
              )
            ])
          ]),
        ),
      ),
      const SizedBox(height: 12),
      if (applyLoading) const Center(child: CircularProgressIndicator()) else Column(children: [
        GridView.builder(
          itemCount: diaries.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 1, mainAxisExtent: 300, childAspectRatio: 3),
          itemBuilder: (context, idx) {
            final d = diaries[idx];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: DiaryCardWidget(
                diary: d,
                canAck: false,
                onEdit: () => openEdit(d),
                onDelete: () => del(d._sourceIds ?? [d.id]),
              ),
            );
          },
        ),
        if (total > PAGE_SIZE)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                  onPressed: page <= 1 || pageLoading ? null : () => loadDiaries(page - 1),
                  child: pageLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Prev')),
              const SizedBox(width: 12),
              Text('Page $page of ${((total / PAGE_SIZE).ceil())}'),
              const SizedBox(width: 12),
              ElevatedButton(
                  onPressed: (page * PAGE_SIZE) >= total || pageLoading ? null : () => loadDiaries(page + 1),
                  child: pageLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Next')),
            ],
          )
      ]),
      const SizedBox(height: 12),
      if (showModal)
        Dialog(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(form['id'] != null ? 'Edit Diary Entry' : 'Create New Diary Entry', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(onPressed: () => setState(() => showModal = false), icon: const Icon(Icons.close)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField(
                      value: form['sessionId'],
                      items: sessions.map<DropdownMenuItem>((s) => DropdownMenuItem(value: s['id'], child: Text(s['name'] ?? '${s['start_date']}'))).toList(),
                      onChanged: (v) => setState(() => form['sessionId'] = v),
                      decoration: const InputDecoration(labelText: 'Session'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: form['date']?.toString() ?? '',
                      decoration: const InputDecoration(labelText: 'Date'),
                      onChanged: (v) => setState(() => form['date'] = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField(
                      value: form['type'],
                      items: const [
                        DropdownMenuItem(value: 'ANNOUNCEMENT', child: Text('Announcement')),
                        DropdownMenuItem(value: 'HOMEWORK', child: Text('Homework')),
                        DropdownMenuItem(value: 'REMARK', child: Text('Remark')),
                      ],
                      onChanged: (v) => setState(() => form['type'] = v),
                      decoration: const InputDecoration(labelText: 'Type'),
                    ),
                  )
                ]),
                const SizedBox(height: 8),
                if (!multiMode && form['id'] == null)
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: (form['classId'] ?? '').toString(),
                        items: classes.map<DropdownMenuItem<String>>((c) => DropdownMenuItem(value: (c['id'] ?? '').toString(), child: Text(c['class_name'] ?? c['name'] ?? '${c['id']}'))).toList(),
                        onChanged: (v) => setState(() => form['classId'] = v),
                        decoration: const InputDecoration(labelText: 'Class'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: (form['sectionId'] ?? '').toString(),
                        items: sections.map<DropdownMenuItem<String>>((s) => DropdownMenuItem(value: (s['id'] ?? '').toString(), child: Text(s['section_name'] ?? s['name'] ?? '${s['id']}'))).toList(),
                        onChanged: (v) => setState(() => form['sectionId'] = v),
                        decoration: const InputDecoration(labelText: 'Section'),
                      ),
                    )
                  ]),
                const SizedBox(height: 8),
                if (form['id'] == null && !multiMode)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Students (optional)'),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(child: TextFormField(decoration: const InputDecoration(hintText: 'Search (min 2 chars)'), onChanged: (v) => setState(() => studentSearch = v))),
                        const SizedBox(width: 8),
                        ElevatedButton(onPressed: () async {
                          setState(() => studentsLoading = true);
                          try {
                            final res = await dio.get('/students/searchByClassAndSection', queryParameters: {
                              'class_id': form['classId'],
                              'section_id': form['sectionId'],
                              'q': studentSearch.length >= 2 ? studentSearch : null,
                              'limit': 500
                            }, options: Options(headers: await getAuthHeaders()));
                            final data = res.data;
                            final list = data is List ? data : (data['data'] ?? data['items'] ?? []);
                            setState(() {
                              studentsForPicker = List.from(list);
                              selectedStudentIds = selectedStudentIds.where((id) => studentsForPicker.any((s) => s['id'] == id)).toList();
                            });
                          } catch (e) {
                            // ignore
                          } finally {
                            setState(() => studentsLoading = false);
                          }
                        }, child: const Text('Load')) }),
                      const SizedBox(height: 8),
                      if (studentsLoading) const CircularProgressIndicator() else if (studentsForPicker.isEmpty) const Text('No students loaded.'),
                      if (studentsForPicker.isNotEmpty)
                        SizedBox(
                          height: 160,
                          child: ListView.builder(
                            itemCount: studentsForPicker.length,
                            itemBuilder: (c, i) {
                              final s = studentsForPicker[i];
                              return CheckboxListTile(
                                title: Text('${s['roll_number'] != null ? '${s['roll_number']}. ' : ''}${s['name'] ?? ''}${s['admission_number'] != null ? ' (${s['admission_number']})' : ''}'),
                                value: selectedStudentIds.contains(s['id']),
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) selectedStudentIds.add(s['id']);
                                    else selectedStudentIds.remove(s['id']);
                                  });
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: (form['subjectId'] ?? '').toString(),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('General')),
                        ...subjects.map<DropdownMenuItem<String>>((s) => DropdownMenuItem(value: (s['id'] ?? '').toString(), child: Text(s['name'] ?? ''))).toList()
                      ],
                      onChanged: (v) => setState(() => form['subjectId'] = v),
                      decoration: const InputDecoration(labelText: 'Subject (Optional)'),
                    ),
                  )
                ]),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: form['title']?.toString() ?? '',
                  decoration: const InputDecoration(labelText: 'Title'),
                  onChanged: (v) => setState(() => form['title'] = v),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: form['content']?.toString() ?? '',
                  decoration: const InputDecoration(labelText: 'Content'),
                  maxLines: 5,
                  onChanged: (v) => setState(() => form['content'] = v),
                ),
                const SizedBox(height: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Attachments (Links)'),
                  const SizedBox(height: 6),
                  // --- Attachments (links) UI — safe version ---
final attachmentsList = List.from((form['attachments'] ?? []) as List);

Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    for (var i = 0; i < attachmentsList.length; i++)
      ListTile(
        title: Text(attachmentsList[i]['name'] ?? ''),
        subtitle: Text(attachmentsList[i]['url'] ?? ''),
        trailing: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            // remove safely inside setState
            setState(() {
              attachmentsList.removeAt(i);
              form['attachments'] = attachmentsList;
            });
          },
        ),
      ),

    TextButton.icon(
      onPressed: () {
        final nameCtrl = TextEditingController();
        final urlCtrl = TextEditingController();
        showDialog(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: const Text('Add Attachment Link'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'File name')),
                  TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'URL')),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
                TextButton(
                  onPressed: () {
                    final list = List.from((form['attachments'] ?? []) as List);
                    list.add({'name': nameCtrl.text, 'url': urlCtrl.text});
                    setState(() => form['attachments'] = list);
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
      icon: const Icon(Icons.add),
      label: const Text('Add Link'),
    )
  ],
)

                ]),
                const SizedBox(height: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Upload Files from Computer'),
                  const SizedBox(height: 6),
                  ElevatedButton.icon(onPressed: pickFilesForForm, icon: const Icon(Icons.upload_file), label: const Text('Pick files')),
                  Builder(builder: (ctx) {
                    final selFiles = (form['selectedFiles'] ?? []) as List;
                    if (selFiles.isEmpty) return const SizedBox.shrink();
                    return Wrap(spacing: 8, children: selFiles.map<Widget>((f) {
                      final name = (f is PlatformFile) ? (f.name ?? f.path?.split('/')?.last ?? 'file') : (f is File ? f.path.split('/')?.last : 'file');
                      return Chip(label: Text(name));
                    }).toList());
                  })
                ]),
                if (form['id'] != null)
                  Column(children: [
                    SwitchListTile(
                      value: form['replaceAttachments'] == true,
                      onChanged: (v) => setState(() => form['replaceAttachments'] = v),
                      title: const Text('Replace all existing attachments with the ones above'),
                    ),
                    if (!(form['replaceAttachments'] == true) && ((form['attachments'] ?? []) as List).any((a) => a['id'] != null))
                      Column(children: [
                        const Text('Keep / remove existing attachments:'),
                        Wrap(spacing: 8, children: ((form['attachments'] ?? []) as List).where((a) => a['id'] != null).map<Widget>((a) {
                          final id = a['id'];
                          return FilterChip(
                            label: Text(a['name']),
                            selected: (form['keepAttachmentIds'] ?? []).contains(id),
                            onSelected: (sel) {
                              setState(() {
                                final s = (form['keepAttachmentIds'] ?? []) as List;
                                if (sel) s.add(id); else s.remove(id);
                                form['keepAttachmentIds'] = s;
                              });
                            },
                          );
                        }).toList()),
                        const Text('Unchecked items will be removed on save.', style: TextStyle(color: Colors.grey)),
                      ])
                  ]),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(onPressed: () => setState(() => showModal = false), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: saving ? null : save, child: saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(form['id'] != null ? 'Update' : 'Save')),
                ]),
              ]),
            ),
          ),
        )
    ]);
  }
}

/// ---------- Diary Feed ----------
class DiaryFeedWidget extends StatefulWidget {
  const DiaryFeedWidget({Key? key}) : super(key: key);

  @override
  State<DiaryFeedWidget> createState() => _DiaryFeedWidgetState();
}

class _DiaryFeedWidgetState extends State<DiaryFeedWidget> {
  bool loading = true;
  List<Diary> diaries = [];
  List<dynamic> classes = [];
  List<dynamic> sections = [];
  Map<String, dynamic> sel = {'classId': '', 'sectionId': ''};
  late Future<RoleFlags> _rolesFuture;

  @override
  void initState() {
    super.initState();
    _rolesFuture = getRoleFlags();
    _initLists();
  }

  Future<void> _initLists() async {
    setState(() => loading = true);
    try {
      final cl = await dio.get('/classes', options: Options(headers: await getAuthHeaders()));
      final sec = await dio.get('/sections', options: Options(headers: await getAuthHeaders()));
      setState(() {
        classes = (cl.data is List) ? cl.data : (cl.data['classes'] ?? []);
        sections = (sec.data is List) ? sec.data : (sec.data['sections'] ?? []);
      });
    } catch (_) {}
    await load();
    setState(() => loading = false);
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final r = await diaryGet('/student/feed/list', {
        if (sel['classId'] != null && (sel['classId']?.toString().isNotEmpty ?? false)) 'classId': int.tryParse(sel['classId'].toString()),
        if (sel['sectionId'] != null && (sel['sectionId']?.toString().isNotEmpty ?? false)) 'sectionId': int.tryParse(sel['sectionId'].toString()),
        'page': 1,
        'pageSize': PAGE_SIZE,
      });
      final raw = r.data?['data'] ?? [];
      setState(() => diaries = List.from(raw.map((m) => Diary.fromMap(m))));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load diary feed: $e')));
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RoleFlags>(
      future: _rolesFuture,
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final roles = snap.data!;
        final isNonStudent = !roles.isStudent;

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (isNonStudent)
            Card(
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: (sel['classId'] ?? '').toString(),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('Select Class')),
                          ...classes.map<DropdownMenuItem<String>>((c) => DropdownMenuItem(value: (c['id'] ?? '').toString(), child: Text(c['class_name'] ?? c['name'] ?? ''))).toList()
                        ],
                        onChanged: (v) => setState(() => sel['classId'] = v),
                        decoration: const InputDecoration(labelText: 'Class'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: (sel['sectionId'] ?? '').toString(),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('Select Section')),
                          ...sections.map<DropdownMenuItem<String>>((s) => DropdownMenuItem(value: (s['id'] ?? '').toString(), child: Text(s['section_name'] ?? s['name'] ?? ''))).toList()
                        ],
                        onChanged: (v) => setState(() => sel['sectionId'] = v),
                        decoration: const InputDecoration(labelText: 'Section'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: loading ? null : load, child: loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Load Feed'))
                  ]),
                  const SizedBox(height: 8),
                  const Text('Choose a class and section to view their personalized diary feed.', style: TextStyle(color: Colors.grey)),
                ]),
              ),
            ),
          const SizedBox(height: 12),
          if (loading) const Center(child: CircularProgressIndicator())
          else Column(children: [
            Row(children: const [
              Icon(Icons.menu_book, color: Colors.blue),
              SizedBox(width: 8),
              Text('Recent Diary Notes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 12),
            if (diaries.isEmpty)
              Center(child: Column(children: const [Icon(Icons.info_outline, size: 64, color: Colors.blue), SizedBox(height: 8), Text('No Diary Notes Yet')])),
            if (diaries.isNotEmpty)
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: diaries.length,
                itemBuilder: (context, idx) {
                  final d = diaries[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: DiaryCardWidget(diary: d, canAck: true),
                  );
                },
              )
          ])
        ]);
      },
    );
  }
}
