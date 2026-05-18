// lib/screens/teacher/teacher_messages_screen.dart
//
// Professional Teacher Messages screen.
// Features:
// - Teacher inbox using /api/messages/me
// - Search + filters
// - Compose message to class/section or single student
// - Load classes/sections/students
// - Open thread and reply
//
// Requires existing files:
// - lib/models/student_message.dart
// - lib/services/api_service.dart with:
//   fetchStudentMessages()
//   fetchStudentMessageThread()
//   replyToStudentMessageThread()
//   rawGet()
//   rawPost()

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:http_parser/http_parser.dart';
import 'package:http/http.dart' as http;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/student_message.dart';
import '../../services/api_service.dart';

class TeacherMessagesScreen extends StatefulWidget {
  final int? openThreadId;

  const TeacherMessagesScreen({
    super.key,
    this.openThreadId,
  });

  @override
  State<TeacherMessagesScreen> createState() => _TeacherMessagesScreenState();
}

class _TeacherMessagesScreenState extends State<TeacherMessagesScreen> {
  List<StudentMessageInboxItem> _inbox = [];

  bool _loading = true;
  bool _unreadOnly = false;
  bool _composeOpen = false;
  bool _sending = false;

  String _type = '';
  String _query = '';

  final _searchController = TextEditingController();
  Timer? _debounce;

  // Compose state
  String _targetMode = 'CLASS_SECTION'; // CLASS_SECTION | SINGLE
  String _classId = '';
  String _sectionId = '';
  String _studentId = '';
  String _subject = '';
  String _body = '';
  List<Map<String, dynamic>> _attachments = [];

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _sections = [];
  List<Map<String, dynamic>> _students = [];

  bool _listsLoading = false;
  bool _studentsLoading = false;

  @override
  void initState() {
    super.initState();
    _loadInbox().then((_) {
      final id = widget.openThreadId;
      if (id != null && id > 0 && mounted) {
        _openThread(id);
      }
    });
    _loadLists();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInbox() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final rows = await ApiService.fetchStudentMessages(
        page: 1,
        limit: 50,
        type: _type.trim().isEmpty ? null : _type.trim(),
        search: _query.trim().isEmpty ? null : _query.trim(),
        unreadOnly: _unreadOnly,
      );

      if (!mounted) return;
      setState(() => _inbox = rows);
    } catch (e, st) {
      debugPrint('Teacher messages load error: $e\n$st');
      if (mounted) {
        _snack("Couldn't load messages. ${_shortError(e)}");
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadLists() async {
    if (!mounted) return;
    setState(() => _listsLoading = true);

    try {
      final classes = await _getListWithFallback(
        endpoints: ['/api/classes', '/classes'],
        keys: ['classes', 'data', 'rows', 'items'],
      );

      final sections = await _getListWithFallback(
        endpoints: ['/api/sections', '/sections'],
        keys: ['sections', 'data', 'rows', 'items'],
      );

      if (!mounted) return;
      setState(() {
        _classes = classes;
        _sections = sections;
      });
    } catch (e, st) {
      debugPrint('Teacher messages list load error: $e\n$st');
    } finally {
      if (mounted) setState(() => _listsLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _getListWithFallback({
    required List<String> endpoints,
    required List<String> keys,
  }) async {
    Object? lastError;

    for (final endpoint in endpoints) {
      try {
        final res = await ApiService.rawGet(endpoint);
        if (res.statusCode < 200 || res.statusCode >= 300) {
          lastError = 'HTTP ${res.statusCode}: ${res.body}';
          continue;
        }

        final decoded = jsonDecode(res.body);
        final rows = _pickRows(decoded, keys);
        return rows;
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception(lastError ?? 'Unable to load list');
  }

  Future<void> _loadStudents() async {
    if (_classId.isEmpty || _sectionId.isEmpty) {
      _snack('Please select class and section first.');
      return;
    }

    setState(() => _studentsLoading = true);

    try {
      final query = Uri(queryParameters: {
        'class_id': _classId,
        'section_id': _sectionId,
        'limit': '500',
      }).query;

      final rows = await _getListWithFallback(
        endpoints: [
          '/api/students/searchByClassAndSection?$query',
          '/students/searchByClassAndSection?$query',
        ],
        keys: ['students', 'data', 'rows', 'items'],
      );

      if (!mounted) return;
      setState(() {
        _students = rows;
        if (_students.every((s) => _idOf(s) != _studentId)) {
          _studentId = '';
        }
      });
    } catch (e, st) {
      debugPrint('Teacher messages students load error: $e\n$st');
      if (mounted) _snack('Unable to load students.');
    } finally {
      if (mounted) setState(() => _studentsLoading = false);
    }
  }

  List<Map<String, dynamic>> _pickRows(dynamic decoded, List<String> keys) {
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    if (decoded is Map) {
      for (final key in keys) {
        final value = decoded[key];
        if (value is List) {
          return value
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    }

    return <Map<String, dynamic>>[];
  }

  Future<void> _sendNewMessage() async {
    final subject = _subject.trim();
    final body = _body.trim();

    if (subject.isEmpty || body.isEmpty) {
      _snack('Please enter subject and message.');
      return;
    }

    if (_targetMode == 'CLASS_SECTION') {
      if (_classId.isEmpty || _sectionId.isEmpty) {
        _snack('Please select class and section.');
        return;
      }
    }

    if (_targetMode == 'SINGLE') {
      if (_classId.isEmpty || _sectionId.isEmpty || _studentId.isEmpty) {
        _snack('Please select class, section and student.');
        return;
      }
    }

    setState(() => _sending = true);

    try {
      final payload = <String, dynamic>{
        'type': 'TEACHER_MESSAGE',
        'targetMode': _targetMode,
        'subject': subject,
        'body': body,
        if (_classId.isNotEmpty) 'classId': int.tryParse(_classId) ?? _classId,
        if (_sectionId.isNotEmpty) 'sectionId': int.tryParse(_sectionId) ?? _sectionId,
        if (_studentId.isNotEmpty) 'studentId': int.tryParse(_studentId) ?? _studentId,
      };

      final hasAttachments = _attachments.isNotEmpty;
      final res = hasAttachments
          ? await _multipartMessageWithFallback(
              endpoints: ['/api/messages', '/messages'],
              fields: payload,
              attachments: _attachments,
            )
          : await _postWithFallback(
              endpoints: ['/api/messages', '/messages'],
              payload: payload,
            );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(_extractApiError(res.body, 'Failed to send message.'));
      }

      if (!mounted) return;
      _snack('Message sent successfully.');
      _resetCompose();
      await _loadInbox();
    } catch (e, st) {
      debugPrint('Teacher send message error: $e\n$st');
      if (mounted) _snack("Couldn't send message. ${_shortError(e)}");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<dynamic> _postWithFallback({
    required List<String> endpoints,
    required Map<String, dynamic> payload,
  }) async {
    Object? lastError;

    for (final endpoint in endpoints) {
      try {
        final res = await ApiService.rawPost(endpoint, payload);
        if (res.statusCode == 404) {
          lastError = 'HTTP 404: ${res.body}';
          continue;
        }
        return res;
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception(lastError ?? 'Request failed');
  }

  Future<http.Response> _multipartMessageWithFallback({
    required List<String> endpoints,
    required Map<String, dynamic> fields,
    required List<Map<String, dynamic>> attachments,
  }) async {
    Object? lastError;

    for (final endpoint in endpoints) {
      try {
        final res = await _multipartMessage(
          endpoint: endpoint,
          fields: fields,
          attachments: attachments,
        );

        if (res.statusCode == 404) {
          lastError = 'HTTP 404: ${res.body}';
          continue;
        }

        return res;
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception(lastError ?? 'Message upload failed');
  }

  Future<http.Response> _multipartMessage({
    required String endpoint,
    required Map<String, dynamic> fields,
    required List<Map<String, dynamic>> attachments,
  }) async {
    final token = await _getToken();
    final uri = Uri.parse(_absoluteApiUrl(endpoint));
    final req = http.MultipartRequest('POST', uri);

    if (token != null && token.trim().isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $token';
    }
    req.headers['Accept'] = 'application/json';

    fields.forEach((key, value) {
      if (value == null) return;
      req.fields[key] = '$value';
    });

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
      }
    }

    final streamed = await req.send().timeout(const Duration(seconds: 60));
    return http.Response.fromStream(streamed);
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

    setState(() => _attachments.addAll(picked));
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
              decoration: const InputDecoration(labelText: 'Display Name (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (ok == true && urlCtrl.text.trim().isNotEmpty) {
      setState(() {
        _attachments.add({
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


  void _resetCompose() {
    setState(() {
      _composeOpen = false;
      _targetMode = 'CLASS_SECTION';
      _classId = '';
      _sectionId = '';
      _studentId = '';
      _subject = '';
      _body = '';
      _students = [];
      _attachments = [];
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _query = value);
      _loadInbox();
    });
  }

  Future<void> _openThread(int threadId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeacherMessageThreadScreen(threadId: threadId),
      ),
    );
    if (mounted) _loadInbox();
  }

  void _setType(String value) {
    setState(() => _type = value);
    _loadInbox();
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'FEE_REMINDER':
        return const Color(0xFFDC2626);
      case 'TEACHER_MESSAGE':
        return const Color(0xFF2563EB);
      case 'STUDENT_QUERY':
        return const Color(0xFF16A34A);
      case 'ACCOUNT_MESSAGE':
        return const Color(0xFFD97706);
      case 'ADMIN_MESSAGE':
        return const Color(0xFF111827);
      default:
        return const Color(0xFF64748B);
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'FEE_REMINDER':
        return Icons.receipt_long_rounded;
      case 'TEACHER_MESSAGE':
        return Icons.school_rounded;
      case 'STUDENT_QUERY':
        return Icons.question_answer_rounded;
      case 'ACCOUNT_MESSAGE':
        return Icons.account_balance_wallet_rounded;
      case 'ADMIN_MESSAGE':
        return Icons.admin_panel_settings_rounded;
      default:
        return Icons.chat_bubble_rounded;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'FEE_REMINDER':
        return 'Fee Reminder';
      case 'TEACHER_MESSAGE':
        return 'Teacher';
      case 'STUDENT_QUERY':
        return 'Student Query';
      case 'ACCOUNT_MESSAGE':
        return 'Accounts';
      case 'ADMIN_MESSAGE':
        return 'Admin';
      default:
        return 'General';
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    return DateFormat('dd MMM, hh:mm a').format(dt.toLocal());
  }

  Widget _buildInboxCard(StudentMessageInboxItem row) {
    final thread = row.thread;
    final latest = thread.latestMessage;
    final color = _typeColor(thread.type);
    final preview = latest?.body.trim().isNotEmpty == true
        ? latest!.body.trim()
        : 'Tap to view message details';

    return InkWell(
      onTap: () => _openThread(thread.id),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: row.isUnread ? color.withOpacity(.28) : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: row.isUnread ? color.withOpacity(.12) : const Color(0x0F000000),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 49,
              height: 49,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withOpacity(.72)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(_typeIcon(thread.type), color: Colors.white),
            ),
            if (row.isUnread)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                    thread.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFF0F172A),
                      fontSize: 15.5,
                      fontWeight: row.isUnread ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDate(thread.lastMessageAt ?? thread.createdAt),
                  style: const TextStyle(fontSize: 11.3, color: Color(0xFF64748B)),
                ),
              ]),
              const SizedBox(height: 7),
              Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.35, color: Color(0xFF475569), fontSize: 13.2),
              ),
              const SizedBox(height: 10),
              Row(children: [
                _Pill(text: _typeLabel(thread.type), color: color, icon: _typeIcon(thread.type)),
                const SizedBox(width: 8),
                if (latest?.attachments.isNotEmpty == true)
                  const _SoftIconLabel(icon: Icons.attach_file_rounded, text: 'Attachment'),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _composePanel() {
    final filteredSections = _sections.where((s) {
      if (_classId.isEmpty) return true;
      final cid = _classIdOf(s);
      if (cid.isEmpty) return true;
      return cid == _classId;
    }).toList();

    final screenHeight = MediaQuery.of(context).size.height;
    final maxPanelHeight = screenHeight * 0.48;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: !_composeOpen
          ? const SizedBox.shrink()
          : Container(
              key: const ValueKey('compose-panel'),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              constraints: BoxConstraints(
                maxHeight: maxPanelHeight < 330 ? 330 : maxPanelHeight,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.edit_note_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            'New Message',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Send to class/section or a selected student',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          ),
                        ]),
                      ),
                      IconButton(
                        onPressed: _sending ? null : () => setState(() => _composeOpen = false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ]),
                    const SizedBox(height: 14),

                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _ModeChip(
                        label: 'Class / Section',
                        selected: _targetMode == 'CLASS_SECTION',
                        onTap: () => setState(() {
                          _targetMode = 'CLASS_SECTION';
                          _studentId = '';
                        }),
                      ),
                      _ModeChip(
                        label: 'Single Student',
                        selected: _targetMode == 'SINGLE',
                        onTap: () => setState(() => _targetMode = 'SINGLE'),
                      ),
                    ]),
                    const SizedBox(height: 12),

                    Row(children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _classId.isEmpty ? null : _classId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Class',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: _classes
                              .map((c) => DropdownMenuItem<String>(
                                    value: _idOf(c),
                                    child: Text(_classNameOf(c), overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: _sending || _listsLoading
                              ? null
                              : (v) {
                                  setState(() {
                                    _classId = v ?? '';
                                    _sectionId = '';
                                    _studentId = '';
                                    _students = [];
                                  });
                                },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _sectionId.isEmpty ? null : _sectionId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Section',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: filteredSections
                              .map((s) => DropdownMenuItem<String>(
                                    value: _idOf(s),
                                    child: Text(_sectionNameOf(s), overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: _sending
                              ? null
                              : (v) {
                                  setState(() {
                                    _sectionId = v ?? '';
                                    _studentId = '';
                                    _students = [];
                                  });
                                },
                        ),
                      ),
                    ]),

                    if (_targetMode == 'SINGLE') ...[
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _studentId.isEmpty ? null : _studentId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Student',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: _students
                                .map((s) => DropdownMenuItem<String>(
                                      value: _idOf(s),
                                      child: Text(_studentNameOf(s), overflow: TextOverflow.ellipsis),
                                    ))
                                .toList(),
                            onChanged: _sending ? null : (v) => setState(() => _studentId = v ?? ''),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 48,
                          child: FilledButton.icon(
                            onPressed: _studentsLoading || _sending ? null : _loadStudents,
                            icon: _studentsLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.group_rounded),
                            label: const Text('Load'),
                          ),
                        ),
                      ]),
                    ],

                    const SizedBox(height: 10),
                    TextField(
                      enabled: !_sending,
                      decoration: const InputDecoration(
                        labelText: 'Subject',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => _subject = v,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      enabled: !_sending,
                      minLines: 3,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Message',
                        hintText: 'Type message for students...',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      onChanged: (v) => _body = v,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Attach Files'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _sending ? null : _pickFiles,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.link),
                            label: const Text('Add Link'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF2563EB),
                              side: const BorderSide(color: Color(0xFF2563EB)),
                            ),
                            onPressed: _sending ? null : _addLinkAttachment,
                          ),
                        ),
                      ],
                    ),
                    if (_attachments.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text(
                            'Selected Attachments',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const Spacer(),
                          Text(
                            '${_attachments.length}',
                            style: const TextStyle(
                              color: Color(0xFF2563EB),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ..._attachments.map((a) => _buildAttachmentInputTile(a)).toList(),
                    ],
                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton.icon(
                        onPressed: _sending ? null : _resetCompose,
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Close'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _sending ? null : _sendNewMessage,
                        icon: _sending
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                        label: Text(_sending ? 'Sending...' : 'Send'),
                      ),
                    ]),
                  ]),
                ),
              ),
            ),
    );
  }


  Widget _buildAttachmentInputTile(Map<String, dynamic> a) {
    final isLocal = a['local'] == true;
    final name = _str(a['name']).isEmpty ? 'Attachment' : _str(a['name']);
    final subtitle = isLocal ? 'Local file' : _str(a['url']);
    final isImage = isLocal && _isImageFileName(name);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: ListTile(
        dense: true,
        leading: isImage
            ? _attachmentImageThumb(a)
            : CircleAvatar(
                backgroundColor: const Color(0xFF2563EB).withOpacity(0.10),
                child: Icon(
                  _attachmentIcon(name, isLink: !isLocal),
                  color: const Color(0xFF2563EB),
                ),
              ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          subtitle.isEmpty ? '-' : subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        onTap: () => _previewAttachment(a),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: isLocal ? (isImage ? 'Preview image' : 'Open file') : 'Open link',
              icon: Icon(
                isImage ? Icons.visibility : Icons.open_in_new,
                color: const Color(0xFF2563EB),
              ),
              onPressed: () => _previewAttachment(a),
            ),
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close, color: Colors.red),
              onPressed: () => setState(() => _attachments.remove(a)),
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
      backgroundColor: const Color(0xFF2563EB).withOpacity(0.10),
      child: const Icon(Icons.image, color: Color(0xFF2563EB)),
    );
  }

  Widget _loadingList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemBuilder: (_, __) => Container(
        height: 112,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [Color(0xFFF1F5F9), Color(0xFFEAF1FF), Color(0xFFF8FAFC)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
      ),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemCount: 5,
    );
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _inbox.where((x) => x.isUnread).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FF),
      appBar: AppBar(
        elevation: 0,
        title: const Text('Teacher Messages'),
        backgroundColor: const Color(0xFF2563EB),
        actions: [
          IconButton(
            onPressed: _loadInbox,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _composeOpen
          ? null
          : FloatingActionButton.extended(
              onPressed: () => setState(() => _composeOpen = true),
              backgroundColor: const Color(0xFF2563EB),
              icon: const Icon(Icons.add_comment_rounded),
              label: const Text('Compose'),
            ),
      body: SafeArea(
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(26),
                bottomRight: Radius.circular(26),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text(
                      'Teacher Messages',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Send class messages and reply to students',
                      style: TextStyle(color: Colors.white.withOpacity(.92)),
                    ),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.18),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(.18)),
                  ),
                  child: const Icon(Icons.forum_rounded, color: Colors.white),
                ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                _HeroStat(label: 'Total', value: '${_inbox.length}', icon: Icons.inbox_rounded),
                const SizedBox(width: 10),
                _HeroStat(label: 'Unread', value: '$unreadCount', icon: Icons.mark_email_unread_rounded),
              ]),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search messages...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () {
                    setState(() => _unreadOnly = !_unreadOnly);
                    _loadInbox();
                  },
                  child: Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: _unreadOnly ? const Color(0xFFE7F0FF) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _unreadOnly ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Icon(
                      Icons.mark_email_unread_rounded,
                      color: _unreadOnly ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _FilterChip2(label: 'All', selected: _type.isEmpty, onTap: () => _setType('')),
                  const SizedBox(width: 8),
                  _FilterChip2(label: 'Teacher', selected: _type == 'TEACHER_MESSAGE', onTap: () => _setType('TEACHER_MESSAGE')),
                  const SizedBox(width: 8),
                  _FilterChip2(label: 'Student Query', selected: _type == 'STUDENT_QUERY', onTap: () => _setType('STUDENT_QUERY')),
                  const SizedBox(width: 8),
                  _FilterChip2(label: 'Fee', selected: _type == 'FEE_REMINDER', onTap: () => _setType('FEE_REMINDER')),
                  const SizedBox(width: 8),
                  _FilterChip2(label: 'Admin', selected: _type == 'ADMIN_MESSAGE', onTap: () => _setType('ADMIN_MESSAGE')),
                ]),
              ),
            ]),
          ),

          _composePanel(),

          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadInbox,
              child: _loading
                  ? _loadingList()
                  : _inbox.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.fromLTRB(16, 45, 16, 20),
                          children: const [
                            Icon(Icons.forum_outlined, size: 62, color: Colors.black26),
                            SizedBox(height: 14),
                            Center(
                              child: Text(
                                'No messages found',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                            ),
                            SizedBox(height: 6),
                            Center(
                              child: Text(
                                'Compose a message or try changing filters.',
                                style: TextStyle(color: Colors.black54),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, _composeOpen ? 18 : 88),
                          itemCount: _inbox.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) => _buildInboxCard(_inbox[i]),
                        ),
            ),
          ),
        ]),
      ),
    );
  }

  void _snack(String message, [bool err = false]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: err ? Colors.red : const Color(0xFF2563EB),
      ),
    );
  }
}

class TeacherMessageThreadScreen extends StatefulWidget {
  final int threadId;

  const TeacherMessageThreadScreen({
    super.key,
    required this.threadId,
  });

  @override
  State<TeacherMessageThreadScreen> createState() => _TeacherMessageThreadScreenState();
}

class _TeacherMessageThreadScreenState extends State<TeacherMessageThreadScreen> {
  StudentMessageThread? _thread;
  bool _loading = true;
  bool _sending = false;
  bool _hasReplyText = false;

  final _replyController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _replyController.addListener(() {
      final has = _replyController.text.trim().isNotEmpty;
      if (has != _hasReplyText && mounted) {
        setState(() => _hasReplyText = has);
      }
    });
    _load();
  }

  @override
  void dispose() {
    _replyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final thread = await ApiService.fetchStudentMessageThread(widget.threadId);
      if (!mounted) return;

      setState(() => _thread = thread);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } catch (e, st) {
      debugPrint('Teacher thread load error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't load thread. ${_shortError(e)}")),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendReply() async {
    final body = _replyController.text.trim();
    if (body.isEmpty || _sending) return;

    setState(() => _sending = true);

    try {
      await ApiService.replyToStudentMessageThread(
        threadId: widget.threadId,
        body: body,
      );
      _replyController.clear();
      await _load();
    } catch (e, st) {
      debugPrint('Teacher reply error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't send reply. ${_shortError(e)}")),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'FEE_REMINDER':
        return const Color(0xFFDC2626);
      case 'TEACHER_MESSAGE':
        return const Color(0xFF2563EB);
      case 'ACCOUNT_MESSAGE':
        return const Color(0xFFD97706);
      case 'ADMIN_MESSAGE':
        return const Color(0xFF111827);
      case 'STUDENT_QUERY':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFF64748B);
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'FEE_REMINDER':
        return 'Fee Reminder';
      case 'TEACHER_MESSAGE':
        return 'Teacher Message';
      case 'ACCOUNT_MESSAGE':
        return 'Accounts';
      case 'ADMIN_MESSAGE':
        return 'Admin';
      case 'STUDENT_QUERY':
        return 'Student Query';
      default:
        return 'General';
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('dd MMM, hh:mm a').format(dt.toLocal());
  }

  Future<void> _openAttachment(StudentMessageAttachment a) async {
    final fileUrl = _absoluteFileUrl(a.url);
    if (fileUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attachment URL is missing')),
        );
      }
      return;
    }

    final uri = Uri.tryParse(fileUrl);
    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid attachment URL')),
        );
      }
      return;
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open attachment')),
      );
    }
  }

  Widget _messageBubble(StudentThreadMessage m) {
    // For teacher screen, staff/admin/account messages are shown on right.
    // Student messages are shown on left.
    final role = m.senderRole.toLowerCase();
    final isMe = role != 'student';

    final color = isMe ? const Color(0xFF2563EB) : const Color(0xFFFFFFFF);
    final textColor = isMe ? Colors.white : const Color(0xFF0F172A);
    final borderColor = isMe ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: EdgeInsets.only(
          left: isMe ? 42 : 0,
          right: isMe ? 0 : 42,
          bottom: 12,
        ),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
          border: Border.all(color: borderColor),
          boxShadow: const [
            BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                m.displaySender,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: Color(0xFF2563EB),
                ),
              ),
            ),
          Text(
            m.body,
            style: TextStyle(color: textColor, fontSize: 14.5, height: 1.38),
          ),
          if (m.attachments.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...m.attachments.map((a) => _AttachmentTile(
                  attachment: a,
                  isMe: isMe,
                  onTap: () => _openAttachment(a),
                )),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              _formatDate(m.createdAt),
              style: TextStyle(
                color: isMe ? Colors.white.withOpacity(.78) : const Color(0xFF64748B),
                fontSize: 10.5,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thread = _thread;
    final color = thread == null ? const Color(0xFF2563EB) : _typeColor(thread.type);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FF),
      appBar: AppBar(
        backgroundColor: color,
        elevation: 0,
        title: Text(thread?.subject ?? 'Message'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : thread == null
                ? const Center(child: Text('Message not found'))
                : Column(children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(24),
                          bottomRight: Radius.circular(24),
                        ),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          thread.subject,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          _WhitePill(text: _typeLabel(thread.type)),
                          _WhitePill(text: thread.status),
                          if (thread.admissionNumber != null)
                            _WhitePill(text: 'Adm ${thread.admissionNumber}'),
                        ]),
                      ]),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                          children: thread.messages.isEmpty
                              ? const [
                                  SizedBox(height: 80),
                                  Center(child: Text('No messages yet')),
                                ]
                              : thread.messages.map(_messageBubble).toList(),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -4)),
                        ],
                      ),
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _replyController,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.newline,
                            decoration: InputDecoration(
                              hintText: 'Type your reply...',
                              filled: true,
                              fillColor: const Color(0xFFF1F5F9),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 48,
                          width: 48,
                          child: ElevatedButton(
                            onPressed: (_sending || !_hasReplyText) ? null : _sendReply,
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              backgroundColor: color,
                            ),
                            child: _sending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.send_rounded),
                          ),
                        ),
                      ]),
                    ),
                  ]),
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  final StudentMessageAttachment attachment;
  final bool isMe;
  final VoidCallback onTap;

  const _AttachmentTile({
    required this.attachment,
    required this.isMe,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = attachment.isPdf
        ? Icons.picture_as_pdf_rounded
        : attachment.isImage
            ? Icons.image_rounded
            : Icons.insert_drive_file_rounded;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: isMe ? Colors.white.withOpacity(.14) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isMe ? Colors.white.withOpacity(.18) : const Color(0xFFE2E8F0)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: isMe ? Colors.white : const Color(0xFF2563EB)),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              attachment.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isMe ? Colors.white : const Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _HeroStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.16),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(.14)),
        ),
        child: Row(children: [
          Icon(icon, color: Colors.white, size: 19),
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: Colors.white.withOpacity(.86), fontSize: 12)),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;

  const _Pill({
    required this.text,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }
}

class _WhitePill extends StatelessWidget {
  final String text;

  const _WhitePill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.16)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _SoftIconLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SoftIconLabel({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: const Color(0xFF64748B)),
      const SizedBox(width: 3),
      Text(text, style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
    ]);
  }
}

class _FilterChip2 extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip2({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2563EB) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0)),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withOpacity(.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF334155),
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => onTap(),
      selectedColor: const Color(0xFFE7F0FF),
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF2563EB) : const Color(0xFF334155),
        fontWeight: FontWeight.w800,
      ),
      side: BorderSide(
        color: selected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
      ),
    );
  }
}

Future<String?> _getToken() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('authToken') ??
      prefs.getString('token') ??
      prefs.getString('jwt') ??
      prefs.getString('accessToken');
}

String _str(dynamic value) => value?.toString() ?? '';

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
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.doc')) return 'application/msword';
  if (lower.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
  if (lower.endsWith('.xlsx')) {
    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  }
  if (lower.endsWith('.odt')) return 'application/vnd.oasis.opendocument.text';

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

String _absoluteApiUrl(String endpoint) {
  final cleanBase = ApiService.baseUrl.replaceAll(RegExp(r'/+$'), '');
  var cleanEndpoint = endpoint.trim();

  if (cleanEndpoint.startsWith('http://') || cleanEndpoint.startsWith('https://')) {
    return cleanEndpoint;
  }

  if (!cleanEndpoint.startsWith('/')) cleanEndpoint = '/$cleanEndpoint';

  if (cleanBase.endsWith('/api') && cleanEndpoint.startsWith('/api/')) {
    cleanEndpoint = cleanEndpoint.substring(4);
  }

  return '$cleanBase$cleanEndpoint';
}

String _shortError(Object e) {
  final s = e.toString();
  if (s.length <= 90) return s;
  return '${s.substring(0, 90)}...';
}

String _extractApiError(String body, String fallback) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final message = decoded['message'] ?? decoded['error'] ?? decoded['sqlMessage'];
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString();
      }
    }
  } catch (_) {}
  return fallback;
}

String _absoluteFileUrl(String url) {
  final clean = url.trim();
  if (clean.isEmpty) return clean;

  final lower = clean.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return clean;
  }

  final base = ApiService.baseUrl.replaceAll(RegExp(r'/+$'), '');
  if (clean.startsWith('/')) return '$base$clean';
  return '$base/$clean';
}

String _idOf(Map<String, dynamic> m) {
  final value = m['id'] ?? m['student_id'] ?? m['studentId'];
  return value == null ? '' : '$value';
}

String _classIdOf(Map<String, dynamic> m) {
  final value = m['class_id'] ?? m['classId'] ?? m['Class_ID'] ?? m['class']?['id'] ?? m['Class']?['id'];
  return value == null ? '' : '$value';
}

String _classNameOf(Map<String, dynamic> m) {
  return (m['class_name'] ?? m['className'] ?? m['name'] ?? m['ClassName'] ?? 'Class ${_idOf(m)}').toString();
}

String _sectionNameOf(Map<String, dynamic> m) {
  return (m['section_name'] ?? m['sectionName'] ?? m['name'] ?? m['SectionName'] ?? 'Section ${_idOf(m)}').toString();
}

String _studentNameOf(Map<String, dynamic> m) {
  final name = (m['name'] ?? m['student_name'] ?? m['studentName'] ?? '').toString();
  final adm = (m['admission_number'] ?? m['admissionNumber'] ?? m['AdmissionNumber'] ?? '').toString();
  final roll = (m['roll_number'] ?? m['rollNumber'] ?? '').toString();

  final prefix = roll.trim().isNotEmpty ? '$roll. ' : '';
  if (name.trim().isNotEmpty && adm.trim().isNotEmpty) return '$prefix$name ($adm)';
  if (name.trim().isNotEmpty) return '$prefix$name';
  if (adm.trim().isNotEmpty) return '$prefix$adm';
  return 'Student ${_idOf(m)}';
}