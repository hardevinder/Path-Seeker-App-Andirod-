import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';

class CoordinatorDigitalDiaryMonitorScreen extends StatefulWidget {
  const CoordinatorDigitalDiaryMonitorScreen({super.key});

  @override
  State<CoordinatorDigitalDiaryMonitorScreen> createState() =>
      _CoordinatorDigitalDiaryMonitorScreenState();
}

class _CoordinatorDigitalDiaryMonitorScreenState
    extends State<CoordinatorDigitalDiaryMonitorScreen> {
  static const int _pageSize = 25;

  final DateFormat _apiDate = DateFormat('yyyy-MM-dd');
  final DateFormat _displayDate = DateFormat('dd MMM yyyy');
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _diaries = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _sections = [];
  List<Map<String, dynamic>> _sessions = [];

  bool _loading = true;
  bool _loadingMasters = true;
  String? _error;
  int _page = 1;
  int _total = 0;
  int _totalPages = 0;

  DateTime? _from;
  DateTime? _to;
  String? _classId;
  String? _sectionId;
  String? _sessionId;
  String? _type;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadMasterData();
    await _loadDiaries();
  }

  Future<void> _loadMasterData() async {
    if (!mounted) return;
    setState(() => _loadingMasters = true);
    try {
      final results = await Future.wait([
        _getList('/classes'),
        _getList('/sections'),
        _getList('/sessions'),
      ]);
      final activeSession = results[2].cast<Map<String, dynamic>>().firstWhere(
            (item) =>
                item['is_active'] == true ||
                item['isActive'] == true ||
                '${item['status'] ?? ''}'.toLowerCase() == 'active',
            orElse: () => results[2].isNotEmpty
                ? results[2].first
                : <String, dynamic>{},
          );
      if (!mounted) return;
      setState(() {
        _classes = results[0];
        _sections = results[1];
        _sessions = results[2];
        _sessionId = _idOf(activeSession);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _loadingMasters = false);
    }
  }

  Future<List<Map<String, dynamic>>> _getList(String endpoint) async {
    final response = await ApiService.rawGet(endpoint);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractError(response.body, 'Failed to load $endpoint'));
    }
    final decoded = jsonDecode(response.body);
    final raw = decoded is List
        ? decoded
        : decoded is Map
            ? (decoded['data'] ??
                decoded['items'] ??
                decoded['rows'] ??
                decoded['classes'] ??
                decoded['sections'] ??
                decoded['sessions'] ??
                [])
            : [];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> _loadDiaries({int page = 1}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final params = <String, String>{
        'page': '$page',
        'pageSize': '$_pageSize',
        'order': 'date:DESC',
        if (_from != null) 'dateFrom': _apiDate.format(_from!),
        if (_to != null) 'dateTo': _apiDate.format(_to!),
        if (_notBlank(_classId)) 'classId': _classId!,
        if (_notBlank(_sectionId)) 'sectionId': _sectionId!,
        if (_notBlank(_sessionId)) 'sessionId': _sessionId!,
        if (_notBlank(_type)) 'type': _type!,
        if (_searchCtrl.text.trim().length >= 2) 'q': _searchCtrl.text.trim(),
      };
      final query = Uri(queryParameters: params).query;
      final response = await ApiService.rawGet('/diaries?$query');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          _extractError(response.body, 'Failed to load digital diaries'),
        );
      }

      final decoded = jsonDecode(response.body);
      final raw = decoded is Map
          ? (decoded['data'] ?? decoded['items'] ?? decoded['rows'] ?? [])
          : decoded;
      final pagination = decoded is Map && decoded['pagination'] is Map
          ? Map<String, dynamic>.from(decoded['pagination'])
          : <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        _diaries = raw is List
            ? raw
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
            : [];
        _page = _asInt(pagination['page'], page);
        _total = _asInt(pagination['total'], _diaries.length);
        _totalPages = _asInt(pagination['totalPages'], 0);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAcknowledgements(int diaryId) async {
    final response =
        await ApiService.rawGet('/diaries/$diaryId/acknowledgements');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _extractError(response.body, 'Failed to load acknowledgements'),
      );
    }
    final decoded = jsonDecode(response.body);
    final raw = decoded is Map
        ? (decoded['acknowledgements'] ?? decoded['data'] ?? decoded['rows'])
        : decoded;
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> _showAcknowledgements(Map<String, dynamic> diary) async {
    final id = int.tryParse('${diary['id'] ?? ''}') ?? 0;
    if (id <= 0) {
      _snack('Invalid diary id', isError: true);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.76,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _fetchAcknowledgements(id),
              builder: (context, snapshot) {
                final rows = snapshot.data ?? [];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Diary Acknowledgements',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _safe(diary['title']).isEmpty
                                ? 'Diary #$id'
                                : _safe(diary['title']),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Expanded(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (snapshot.hasError)
                      Expanded(
                        child: _state(
                          Icons.warning_rounded,
                          _cleanError(snapshot.error),
                          'Try again from the diary list.',
                        ),
                      )
                    else if (rows.isEmpty)
                      Expanded(
                        child: _state(
                          Icons.mark_email_unread_rounded,
                          'No acknowledgements yet',
                          'Students will appear here after they acknowledge this diary.',
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.all(14),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final ack = rows[index];
                            final student = _mapOf(ack['student']);
                            return _ackCard(ack, student);
                          },
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

  Future<void> _pickDate({required bool isFrom}) async {
    final current = isFrom ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  void _resetFilters() {
    setState(() {
      _from = null;
      _to = null;
      _classId = null;
      _sectionId = null;
      _type = null;
      _searchCtrl.clear();
    });
    _loadDiaries();
  }

  int get _privateCount => _diaries
      .where((item) =>
          (item['recipients'] is List) && item['recipients'].isNotEmpty)
      .length;

  int get _teacherCount => _diaries.map(_teacherName).toSet().length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Digital Diary Monitor'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _loadDiaries(page: _page),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadDiaries(page: _page),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            _hero(),
            const SizedBox(height: 12),
            _stats(),
            const SizedBox(height: 12),
            _filters(),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _state(Icons.warning_rounded, 'Could not load diaries', _error!)
            else if (_diaries.isEmpty)
              _state(
                Icons.inbox_rounded,
                'No digital diary found',
                'Try changing filters or pull down to refresh.',
              )
            else ...[
              ..._diaries.map(_diaryCard),
              const SizedBox(height: 10),
              _pager(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        children: [
          Icon(Icons.menu_book_rounded, color: Colors.white, size: 34),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Digital Diary Monitor',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Check which teacher sent diary notes to each class and section.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stats() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = constraints.maxWidth > 640 ? 4 : 2;
        return GridView.count(
          crossAxisCount: count,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.72,
          children: [
            _statCard('Total Diaries', '$_total', Icons.library_books_rounded),
            _statCard('Shown', '${_diaries.length}', Icons.visibility_rounded),
            _statCard('Teachers', '$_teacherCount', Icons.co_present_rounded),
            _statCard('Private', '$_privateCount', Icons.lock_rounded),
          ],
        );
      },
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF1D4ED8)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
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
          Row(
            children: [
              Expanded(
                child: _dateButton(
                  'From',
                  _from,
                  () => _pickDate(isFrom: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dateButton(
                  'To',
                  _to,
                  () => _pickDate(isFrom: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _dropdown(
            label: _loadingMasters ? 'Loading classes...' : 'Class',
            value: _classId,
            items: _classes,
            nameKeys: const ['class_name', 'name'],
            emptyLabel: 'All Classes',
            onChanged: (value) => setState(() => _classId = value),
          ),
          const SizedBox(height: 10),
          _dropdown(
            label: _loadingMasters ? 'Loading sections...' : 'Section',
            value: _sectionId,
            items: _sections,
            nameKeys: const ['section_name', 'name'],
            emptyLabel: 'All Sections',
            onChanged: (value) => setState(() => _sectionId = value),
          ),
          const SizedBox(height: 10),
          _dropdown(
            label: _loadingMasters ? 'Loading sessions...' : 'Session',
            value: _sessionId,
            items: _sessions,
            nameKeys: const ['name', 'session_name', 'title'],
            emptyLabel: 'All Sessions',
            onChanged: (value) => setState(() => _sessionId = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _type,
            decoration: const InputDecoration(
              labelText: 'Type',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem<String>(value: null, child: Text('All Types')),
              DropdownMenuItem<String>(
                value: 'HOMEWORK',
                child: Text('Homework'),
              ),
              DropdownMenuItem<String>(
                value: 'REMARK',
                child: Text('Remark'),
              ),
              DropdownMenuItem<String>(
                value: 'ANNOUNCEMENT',
                child: Text('Announcement'),
              ),
            ],
            onChanged: (value) => setState(() => _type = value),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _loadDiaries(),
            decoration: const InputDecoration(
              labelText: 'Search title or content',
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : () => _loadDiaries(),
                  icon: const Icon(Icons.filter_alt_rounded),
                  label: const Text('Apply'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _resetFilters,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reset'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dateButton(String label, DateTime? date, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.date_range_rounded, size: 18),
      label: Text(
        date == null ? label : _displayDate.format(date),
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required List<Map<String, dynamic>> items,
    required List<String> nameKeys,
    required String emptyLabel,
    required ValueChanged<String?> onChanged,
  }) {
    final options = items
        .map((item) => MapEntry(_idOf(item), _nameOf(item, nameKeys)))
        .where((entry) => _notBlank(entry.key))
        .toList();

    return DropdownButtonFormField<String>(
      value: options.any((entry) => entry.key == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem<String>(value: null, child: Text(emptyLabel)),
        ...options.map(
          (entry) => DropdownMenuItem<String>(
            value: entry.key,
            child: Text(entry.value, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _diaryCard(Map<String, dynamic> diary) {
    final type = _safe(diary['type'], '-');
    final attachments =
        diary['attachments'] is List ? diary['attachments'] as List : [];
    final attachmentItems = attachments
        .map(_attachmentInfo)
        .where((item) => _notBlank(item['label']))
        .toList();
    final recipients =
        diary['recipients'] is List ? diary['recipients'] as List : [];
    final privateDiary = recipients.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: _typeColor(type).withOpacity(0.12),
                  child: Icon(_typeIcon(type), color: _typeColor(type)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _safe(diary['title'], 'Untitled Diary'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_formatDate(diary['date'])} • ${_teacherName(diary)}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _pill('${_className(diary)} - ${_sectionName(diary)}'),
                _pill(_subjectName(diary)),
                _pill(type),
                _pill(privateDiary ? 'Private' : 'Class visible'),
                _pill('${attachments.length} files'),
              ],
            ),
            if (_safe(diary['content']).isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _safe(diary['content']),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.32),
              ),
            ],
            if (attachmentItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Attachments',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: attachmentItems.map(_attachmentChip).toList(),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Created by ID: ${_safe(diary['createdById'], '-')}',
                    style: const TextStyle(color: Colors.black45, fontSize: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showAcknowledgements(diary),
                  icon: const Icon(Icons.fact_check_rounded, size: 18),
                  label: const Text('Acks'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Map<String, String> _attachmentInfo(dynamic value) {
    if (value is String) {
      final url = value.trim();
      return {
        'url': url,
        'label': _fileNameFromUrl(url),
      };
    }

    if (value is Map) {
      final item = Map<String, dynamic>.from(value);
      final url = _safe(
        item['url'] ??
            item['fileUrl'] ??
            item['filePath'] ??
            item['file'] ??
            item['path'] ??
            item['href'],
      );
      final label = _safe(
        item['name'] ??
            item['originalName'] ??
            item['fileName'] ??
            item['filename'] ??
            item['label'],
        _fileNameFromUrl(url),
      );
      return {'url': url, 'label': label};
    }

    return {'url': '', 'label': 'Attachment'};
  }

  Widget _attachmentChip(Map<String, String> item) {
    final url = item['url'] ?? '';
    return ActionChip(
      avatar: const Icon(Icons.attach_file_rounded, size: 18),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 230),
        child: Text(
          item['label'] ?? 'Attachment',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      onPressed: url.isEmpty ? null : () => _openAttachment(url),
    );
  }

  Future<void> _openAttachment(String rawUrl) async {
    final normalized = _absoluteUrl(rawUrl);
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      _snack('Attachment link is invalid', isError: true);
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _snack('Could not open attachment', isError: true);
    }
  }

  String _absoluteUrl(String rawUrl) {
    final url = rawUrl.trim();
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '${ApiService.baseUrl}$url';
    return '${ApiService.baseUrl}/$url';
  }

  String _fileNameFromUrl(String url) {
    final parts = url.split('/').where((part) => part.trim().isNotEmpty);
    if (parts.isEmpty) return 'Attachment';
    return parts.last.split('?').first;
  }

  Widget _pill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _ackCard(Map<String, dynamic> ack, Map<String, dynamic> student) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _safe(student['name'], 'Student'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Admission: ${_safe(student['admission_number'], '-')} • Roll: ${_safe(student['roll_number'], '-')}',
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          if (_safe(ack['note']).isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(_safe(ack['note'])),
          ],
          const SizedBox(height: 5),
          Text(
            'Acknowledged: ${_formatDateTime(ack['createdAt'])}',
            style: const TextStyle(color: Colors.black45, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _pager() {
    final label =
        _totalPages > 0 ? 'Page $_page of $_totalPages' : 'Page $_page';
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _page <= 1 ? null : () => _loadDiaries(page: _page - 1),
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('Prev'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _totalPages > 0 && _page >= _totalPages
                ? null
                : () => _loadDiaries(page: _page + 1),
            icon: const Icon(Icons.chevron_right_rounded),
            label: const Text('Next'),
          ),
        ),
      ],
    );
  }

  Widget _state(IconData icon, String title, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 38, color: const Color(0xFF64748B)),
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
        ],
      ),
    );
  }

  String _idOf(Map<String, dynamic> item) => _safe(
        item['id'] ?? item['classId'] ?? item['sectionId'] ?? item['sessionId'],
      );

  String _nameOf(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = _safe(item[key]);
      if (value.isNotEmpty) return value;
    }
    final id = _idOf(item);
    return id.isEmpty ? '-' : id;
  }

  String _className(Map<String, dynamic> d) {
    final classObj = _mapOf(d['class'] ?? d['Class']);
    return _safe(
      classObj['class_name'] ??
          classObj['name'] ??
          d['className'] ??
          d['classId'],
      '-',
    );
  }

  String _sectionName(Map<String, dynamic> d) {
    final sectionObj = _mapOf(d['section'] ?? d['Section']);
    return _safe(
      sectionObj['section_name'] ??
          sectionObj['name'] ??
          d['sectionName'] ??
          d['sectionId'],
      '-',
    );
  }

  String _subjectName(Map<String, dynamic> d) {
    final subject = _mapOf(d['subject'] ?? d['Subject']);
    return _safe(
      subject['name'] ?? d['subjectName'] ?? d['subjectId'],
      'General',
    );
  }

  String _teacherName(Map<String, dynamic> d) {
    final createdBy = _mapOf(d['createdBy'] ?? d['CreatedBy']);
    final teacher = _mapOf(d['teacher']);
    return _safe(
      createdBy['name'] ?? teacher['name'] ?? d['createdByName'],
      'User ${_safe(d['createdById'], '-')}',
    );
  }

  Map<String, dynamic> _mapOf(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  String _formatDate(dynamic value) {
    final raw = _safe(value);
    if (raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    return parsed == null ? raw : _displayDate.format(parsed);
  }

  String _formatDateTime(dynamic value) {
    final raw = _safe(value);
    if (raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('dd MMM yyyy, hh:mm a').format(parsed.toLocal());
  }

  Color _typeColor(String type) {
    switch (type.toUpperCase()) {
      case 'HOMEWORK':
        return const Color(0xFF2563EB);
      case 'REMARK':
        return const Color(0xFFD97706);
      case 'ANNOUNCEMENT':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFF7C3AED);
    }
  }

  IconData _typeIcon(String type) {
    switch (type.toUpperCase()) {
      case 'HOMEWORK':
        return Icons.assignment_rounded;
      case 'REMARK':
        return Icons.rate_review_rounded;
      case 'ANNOUNCEMENT':
        return Icons.campaign_rounded;
      default:
        return Icons.menu_book_rounded;
    }
  }

  int _asInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('${value ?? ''}') ?? fallback;
  }

  String _safe(dynamic value, [String fallback = '']) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  bool _notBlank(String? value) => value != null && value.trim().isNotEmpty;

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

  String _cleanError(Object? error) =>
      error.toString().replaceFirst('Exception: ', '');

  void _snack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Colors.red.shade700 : null,
      ),
    );
  }
}
