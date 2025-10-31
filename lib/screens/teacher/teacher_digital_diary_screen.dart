// File: lib/screens/teacher/teacher_digital_diary_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/constants.dart';
import 'package:http_parser/http_parser.dart';


class TeacherDigitalDiaryScreen extends StatefulWidget {
  const TeacherDigitalDiaryScreen({super.key});

  @override
  State<TeacherDigitalDiaryScreen> createState() =>
      _TeacherDigitalDiaryScreenState();
}

class _TeacherDigitalDiaryScreenState extends State<TeacherDigitalDiaryScreen> {
  int _selectedIndex = 0; // bottom navigation index

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
  bool deleting = false;
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
    if (token == null) return;
    try {
      final params = {
        'page': '$page',
        'pageSize': '20',
        if (type != null && type!.isNotEmpty) 'type': type!,
        if (dateFrom != null)
          'dateFrom': DateFormat('yyyy-MM-dd').format(dateFrom!),
        if (dateTo != null)
          'dateTo': DateFormat('yyyy-MM-dd').format(dateTo!),
        if (query != null && query!.isNotEmpty) 'q': query!,
      };
      final uri = Uri.parse('$baseUrl/diaries').replace(queryParameters: params);
      final res = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      });
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        setState(() {
          diaries = List<Map<String, dynamic>>.from(body['data'] ?? []);
          pagination = body['pagination'];
        });
      }
    } catch (e) {
      _snack('Failed to load diaries: $e', true);
    } finally {
      setState(() => loading = false);
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
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
      final res = await http.delete(Uri.parse('$baseUrl/diaries/$id'),
          headers: {'Authorization': 'Bearer $token'});
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: err ? Colors.red : const Color(0xFF6C63FF),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Digital Diary Feed',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _fetchDiaries, icon: const Icon(Icons.refresh))
        ],
      ),
      body: Column(
        children: [
          _filterBar(),
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
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
                                  d['attachments'] ?? []);
                          return Card(
                            margin: const EdgeInsets.all(12),
                            elevation: 3,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    const Color(0xFF6C63FF).withOpacity(0.1),
                                child: Icon(_icon(d['type'] ?? ''),
                                    color: const Color(0xFF6C63FF)),
                              ),
                              title: Text(
                                d['title'] ?? 'Untitled',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text('${d['type']} • $dt',
                                      style: const TextStyle(fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Text(
                                    d['content'] ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (attachments.isNotEmpty)
                                    TextButton.icon(
                                      icon: const Icon(Icons.attach_file,
                                          size: 16),
                                      label: Text(
                                          '${attachments.length} attachment(s)'),
                                      onPressed: () =>
                                          _showAttachmentsDialog(attachments),
                                    ),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'edit') {
                                    showDialog(
                                      context: context,
                                      builder: (_) => _DiaryCreateTab(existing: d),
                                    ).then((_) => _fetchDiaries());
                                  } else if (v == 'delete') {
                                    _deleteDiary(d['id']);
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(children: [
                                        Icon(Icons.edit, color: Colors.blue),
                                        SizedBox(width: 8),
                                        Text('Edit')
                                      ])),
                                  const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(children: [
                                        Icon(Icons.delete, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Delete')
                                      ])),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          )
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
                    prefixIcon:
                        const Icon(Icons.search, color: Color(0xFF6C63FF)),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none),
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
                      dateFrom = dateTo = null;
                      type = query = null;
                      _searchCtrl.clear();
                    });
                    _fetchDiaries();
                  },
                  icon: const Icon(Icons.clear_all, color: Colors.red))
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              FilterChip(
                label: Text(dateFrom == null
                    ? 'From'
                    : DateFormat('dd MMM').format(dateFrom!)),
                onSelected: (sel) async {
                  if (sel) {
                    final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365)));
                    if (picked != null) setState(() => dateFrom = picked);
                    _fetchDiaries();
                  }
                },
              ),
              FilterChip(
                label: Text(dateTo == null
                    ? 'To'
                    : DateFormat('dd MMM').format(dateTo!)),
                onSelected: (sel) async {
                  if (sel) {
                    final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365)));
                    if (picked != null) setState(() => dateTo = picked);
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
                  }),
              FilterChip(
                  label: const Text('Remark'),
                  selected: type == 'REMARK',
                  onSelected: (v) {
                    setState(() => type = v ? 'REMARK' : null);
                    _fetchDiaries();
                  }),
              FilterChip(
                  label: const Text('Announcement'),
                  selected: type == 'ANNOUNCEMENT',
                  onSelected: (v) {
                    setState(() => type = v ? 'ANNOUNCEMENT' : null);
                    _fetchDiaries();
                  }),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showAttachmentsDialog(
      List<Map<String, dynamic>> attachments) async {
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
              const Text('Attachments',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const Divider(),
              ...attachments.map((a) => ListTile(
                    leading:
                        const Icon(Icons.attachment, color: Color(0xFF6C63FF)),
                    title: Text(a['name'] ?? 'Attachment'),
                    subtitle: Text(a['url'] ?? ''),
                    trailing: IconButton(
                      icon: const Icon(Icons.open_in_new),
                      onPressed: () => _openLink(a['url']),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openLink(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
/*──────────────────────────────────────────────
  CREATE TAB  (New Diary with file + links)
──────────────────────────────────────────────*/
class _DiaryCreateTab extends StatefulWidget {
  final Map<String, dynamic>? existing; // for edit mode
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
  List<String> selectedStudentIds = []; // for multi-select students

  @override
  void initState() {
    super.initState();
    _loadInitialData();
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
        date = DateTime.tryParse(d['date'] ?? '') ?? DateTime.now();
        attachments =
            List<Map<String, dynamic>>.from(d['attachments'] ?? []);
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

  Future<void> _loadClasses() async {
    final token = await _getToken();
    if (token == null) return _snack('No token found', true);
    try {
      final uri = Uri.parse('$baseUrl/classes');
      final res = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        setState(() {
          if (decoded is List) {
            classes = decoded
                .map<Map<String, dynamic>>((x) => {
                      'id': x['id'].toString(),
                      'name': x['class_name'] ?? x['name'] ?? 'Unnamed Class',
                    })
                .toList();
          } else if (decoded is Map && decoded['data'] is List) {
            classes = List<Map<String, dynamic>>.from(
              (decoded['data'] as List).map((x) => {
                    'id': x['id'].toString(),
                    'name': x['class_name'] ?? x['name'] ?? 'Unnamed Class',
                  }),
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
      final res = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        List list = [];
        if (decoded is List) list = decoded;
        else if (decoded is Map && decoded['data'] is List) list = decoded['data'];
        else if (decoded is Map && decoded['sections'] is List) list = decoded['sections'];
        setState(() {
          sections = List<Map<String, dynamic>>.from(
            list.map((x) => {
                  'id': x['id'].toString(),
                  'name': x['section_name'] ?? x['name'] ?? 'Unnamed Section',
                }),
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
      final uri = Uri.parse('$baseUrl/students/searchByClassAndSection')
          .replace(queryParameters: {
        'class_id': classId!,
        'section_id': sectionId!,
      });
      final res = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        List list = [];
        if (decoded is List) list = decoded;
        else if (decoded is Map && decoded['data'] is List) list = decoded['data'];
        else if (decoded is Map && decoded['students'] is List)
          list = decoded['students'];
        setState(() {
          students = List<Map<String, dynamic>>.from(list.map((x) => {
                'id': x['id'].toString(),
                'name': x['name'] ??
                    x['student_name'] ??
                    x['full_name'] ??
                    'Unnamed Student',
              }));
        });
      }
    } catch (e) {
      _snack('Error loading students: $e', true);
    }
  }

  Future<void> _pickFiles() async {
    final files = await openFiles(acceptedTypeGroups: [
      const XTypeGroup(label: 'Documents', extensions: ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx'])
    ]);
    if (files.isNotEmpty) {
      setState(() {
        attachments.addAll(
          files.map((f) => {'path': f.path, 'name': f.name, 'local': true}),
        );
      });
    }
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
            TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'URL')),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Display Name (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF)),
              child: const Text('Add')),
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
          'local': false
        });
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (classId == null || sectionId == null) {
      _snack('Please select class & section', true);
      return;
    }
    setState(() => submitting = true);
    final token = await _getToken();
    if (token == null) return _snack('No token', true);

    final isEdit = widget.existing != null;
    final uri = isEdit
        ? Uri.parse('$baseUrl/diaries/${widget.existing!['id']}')
        : Uri.parse('$baseUrl/diaries');
    final req = http.MultipartRequest(isEdit ? 'PUT' : 'POST', uri);
    req.headers['Authorization'] = 'Bearer $token';
    req.fields['sessionId'] = '1'; // ✅ required field from backend

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
        .where((a) => a['local'] == false && (a['url'] != null))
        .map((a) => {'url': a['url'], 'name': a['name'], 'kind': ''})
        .toList();
    if (linkList.isNotEmpty) req.fields['attachments'] = jsonEncode(linkList);

   for (final a in attachments.where((a) => a['local'] == true)) {
  final file = File(a['path']);
  final ext = a['name'].split('.').last.toLowerCase();

  // Map extensions to proper MIME types expected by backend
  String? mimeType;
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      mimeType = 'image/jpeg';
      break;
    case 'png':
      mimeType = 'image/png';
      break;
    case 'pdf':
      mimeType = 'application/pdf';
      break;
    case 'doc':
      mimeType = 'application/msword';
      break;
    case 'docx':
      mimeType =
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      break;
    case 'xls':
      mimeType = 'application/vnd.ms-excel';
      break;
    case 'xlsx':
      mimeType =
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      break;
    case 'odt':
      mimeType = 'application/vnd.oasis.opendocument.text';
      break;
    default:
      _snack('File type .$ext not allowed', true);
      continue;
  }

  final parts = mimeType.split('/');
  req.files.add(await http.MultipartFile.fromPath(
    'files', // change this to the field name your backend expects if different
    file.path,
    filename: a['name'],
    contentType: MediaType(parts[0], parts[1]),
  ));
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
      if (res.statusCode == 200 || res.statusCode == 201) {
        _snack('Diary saved successfully');
        if (mounted) Navigator.pop(context);
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: err ? Colors.red : const Color(0xFF6C63FF),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Create Diary' : 'Edit Diary'),
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
                    .map((c) => DropdownMenuItem(
                        value: c['id'].toString(), child: Text(c['name'])))
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
                    .map((s) => DropdownMenuItem(
                        value: s['id'].toString(), child: Text(s['name'])))
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
              // Multi-select Students
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
                      List<String> tempSelected =
                          List.from(selectedStudentIds);
                      return StatefulBuilder(
                        builder: (context, setStateDialog) {
                          return AlertDialog(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
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
                                    .map((s) => CheckboxListTile(
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
                                        ))
                                    .toList(),
                              ),
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, null),
                                  child: const Text('Cancel')),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF6C63FF),
                                    foregroundColor: Colors.white),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
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
                      const Icon(Icons.arrow_drop_down,
                          color: Color(0xFF6C63FF))
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Title *'),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Title required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contentCtrl,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Content *'),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Content required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Type'),
                value: type,
                items: const [
                  DropdownMenuItem(value: 'HOMEWORK', child: Text('Homework')),
                  DropdownMenuItem(value: 'REMARK', child: Text('Remark')),
                  DropdownMenuItem(
                      value: 'ANNOUNCEMENT', child: Text('Announcement')),
                ],
                onChanged: (v) => setState(() => type = v ?? 'HOMEWORK'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                        'Date: ${DateFormat('dd MMM yyyy').format(date)}'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.date_range,
                        color: Color(0xFF6C63FF)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => date = picked);
                    },
                  )
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
                          foregroundColor: Colors.white),
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
                          side:
                              const BorderSide(color: Color(0xFF6C63FF))),
                      onPressed: _addLinkAttachment,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (attachments.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: attachments.map((a) {
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          a['local'] == true
                              ? Icons.file_present
                              : Icons.link,
                          color: const Color(0xFF6C63FF),
                        ),
                        title: Text(a['name'] ?? 'File'),
                        subtitle: Text(
                            a['local'] == true
                                ? 'Local file'
                                : (a['url'] ?? ''),
                            style: const TextStyle(fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () =>
                              setState(() => attachments.remove(a)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 20),
              submitting
                  ? const CircularProgressIndicator(color: Color(0xFF6C63FF))
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      label: Text(widget.existing == null
                          ? 'Submit'
                          : 'Update'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _submit,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
