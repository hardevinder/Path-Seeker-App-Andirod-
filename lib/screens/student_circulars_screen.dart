// lib/screens/student_circulars_screen.dart
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/circular.dart';
import '../services/api_service.dart';

// Optional: socket.io (uncomment in pubspec and below import & code if you have a socket server)
// import 'package:socket_io_client/socket_io_client.dart' as IO;

class StudentCircularsScreen extends StatefulWidget {
  /// Used when dashboard opens circulars after sibling switch.
  /// Backend should verify that this admission number belongs to the logged-in
  /// student or one of the logged-in student's siblings.
  final String? selectedAdmissionNumber;
  final String? selectedStudentName;
  final String? initialCircularId;

  const StudentCircularsScreen({
    super.key,
    this.selectedAdmissionNumber,
    this.selectedStudentName,
    this.initialCircularId,
  });

  @override
  State<StudentCircularsScreen> createState() => _StudentCircularsScreenState();
}

class _StudentCircularsScreenState extends State<StudentCircularsScreen> {
  List<Circular> _circulars = [];
  bool _loading = true;
  String _query = '';
  bool _onlyWithFiles = false;
  String _sinceDays = '30'; // 7,30,90,all

  String? _activeAdmissionNumber;
  String? _activeStudentName;

  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _initialCircularOpened = false;

  // Optional socket (commented)
  // IO.Socket? socket;

  String? get _admissionForApi {
    final text =
        (_activeAdmissionNumber ?? widget.selectedAdmissionNumber ?? '').trim();
    return text.isEmpty ? null : text;
  }

  String get _studentTitleText {
    final name =
        (_activeStudentName ?? widget.selectedStudentName ?? '').trim();
    final adm = (_admissionForApi ?? '').trim();

    if (name.isNotEmpty && adm.isNotEmpty) return '$name • Adm $adm';
    if (name.isNotEmpty) return name;
    if (adm.isNotEmpty) return 'Adm $adm';
    return 'Latest notices & attachments';
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
    // _initSocket();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // socket?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final prefs = await SharedPreferences.getInstance();

      final selectedFromWidget = (widget.selectedAdmissionNumber ?? '').trim();
      final selectedFromPrefs =
          (prefs.getString('selectedStudentAdmissionNumber') ??
                  prefs.getString('activeStudentAdmission') ??
                  '')
              .trim();

      final selectedNameFromWidget = (widget.selectedStudentName ?? '').trim();
      final selectedNameFromPrefs = (prefs.getString('selectedStudentName') ??
              prefs.getString('activeStudentName') ??
              '')
          .trim();

      if (!mounted) return;
      setState(() {
        _activeAdmissionNumber = selectedFromWidget.isNotEmpty
            ? selectedFromWidget
            : selectedFromPrefs;
        _activeStudentName = selectedNameFromWidget.isNotEmpty
            ? selectedNameFromWidget
            : selectedNameFromPrefs;
      });
    } catch (e, st) {
      debugPrint('Student circular bootstrap error: $e\n$st');
    }

    await _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final list = await ApiService.fetchCirculars(
        admissionNumber: _admissionForApi,
      );

      // Backend should already filter selected-class circulars.
      // Keep audience filter here for safety on student app.
      final allowed = list
          .where((c) => c.audience == 'student' || c.audience == 'both')
          .toList();

      if (!mounted) return;
      setState(() => _circulars = allowed);
      _openInitialCircularIfAvailable();
    } catch (e, st) {
      debugPrint('Error fetching circulars: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't load circulars. ${_shortError(e)}")),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openInitialCircularIfAvailable() {
    if (_initialCircularOpened) return;
    final targetId = (widget.initialCircularId ?? '').trim();
    if (targetId.isEmpty) return;
    final matches = _circulars.where((item) => item.id == targetId);
    if (matches.isEmpty) return;
    _initialCircularOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showFullView(matches.first);
    });
  }

  // Optional socket initializer if you have a socket server
  // void _initSocket() {
  //   socket = IO.io('https://your-socket-server', IO.OptionBuilder()
  //       .setTransports(['websocket'])
  //       .disableAutoConnect()
  //       .build());
  //   socket?.connect();
  //   socket?.onConnect((_) => debugPrint('socket connected'));
  //   socket?.on('newCircular', (data) {
  //     final c = Circular.fromJson(data['circular']);
  //     if (c.audience == 'student' || c.audience == 'both') {
  //       setState(() => _circulars.insert(0, c));
  //       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('New: ${c.title}')));
  //     }
  //   });
  //   socket?.on('circularUpdated', (data) { ... });
  //   socket?.on('circularDeleted', (data) { ... });
  // }

  List<Circular> get _processed {
    final lowerQ = _query.trim().toLowerCase();
    final sinceDate = _sinceDays == 'all'
        ? null
        : DateTime.now()
            .subtract(Duration(days: int.tryParse(_sinceDays) ?? 30));

    return _circulars.where((c) {
      if (_onlyWithFiles && (c.fileUrl == null || c.fileUrl!.isEmpty))
        return false;
      if (sinceDate != null && c.createdAt.isBefore(sinceDate)) return false;
      if (lowerQ.isEmpty) return true;

      final hay =
          '${c.title} ${c.description ?? ''} ${c.audience}'.toLowerCase();
      return hay.contains(lowerQ);
    }).toList();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _query = v);
    });
  }

  String _formatDT(DateTime dt) {
    return DateFormat.yMMMd().add_jm().format(dt.toLocal());
  }

  String _fileKind(String? url) {
    if (url == null) return 'other';

    final clean = url.split('?').first.split('#').first;
    final dot = clean.lastIndexOf('.');
    if (dot == -1) return 'other';

    final ext = clean.substring(dot + 1).toLowerCase();
    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'].contains(ext)) {
      return 'image';
    }
    if (ext == 'pdf') return 'pdf';
    return 'other';
  }

  Future<void> _openUrl(String url) async {
    final clean = url.trim();
    if (clean.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attachment URL is missing')),
        );
      }
      return;
    }

    final uri = Uri.tryParse(clean);
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

  void _showFullView(Circular c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.95,
        child: _CircularDetailSheet(
          circular: c,
          studentTitle: _studentTitleText,
          onOpenAttachment: (url) => _openUrl(url),
          formatDT: _formatDT,
          fileKind: _fileKind,
        ),
      ),
    );
  }

  Widget _buildCard(Circular c, int index) {
    final hasFile = c.fileUrl != null && c.fileUrl!.trim().isNotEmpty;

    return InkWell(
      onTap: () => _showFullView(c),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1F7AE0), Color(0xFF7C3AED)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15.5,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (hasFile)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE7F0FF),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.attach_file_rounded,
                                    size: 13, color: Color(0xFF1F7AE0)),
                                SizedBox(width: 3),
                                Text(
                                  'File',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11.5,
                                    color: Color(0xFF1F7AE0),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      c.description?.trim().isNotEmpty == true
                          ? c.description!.trim()
                          : 'No description',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        height: 1.35,
                        fontSize: 13.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECF5FF),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          c.audience == 'both'
                              ? 'Students & Staff'
                              : 'Students',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1B6ED6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.circle,
                          size: 6, color: Color(0xFFC9D6EA)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _formatDT(c.createdAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: Color(0xFF94A3B8)),
                    ]),
                  ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadingList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemBuilder: (_, i) => Container(
        height: 104,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [Color(0xFFF2F6FF), Color(0xFFE9F1FF), Color(0xFFF2F6FF)],
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
    final processed = _processed;
    final totalWithFiles =
        _circulars.where((c) => c.fileUrl?.trim().isNotEmpty == true).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FF),
      appBar: AppBar(
        title: const Text('Student Circulars'),
        elevation: 0,
        backgroundColor: const Color(0xFF1F7AE0),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1F7AE0), Color(0xFF7C3AED)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(26),
                bottomRight: Radius.circular(26),
              ),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Student Circulars',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _studentTitleText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(color: Colors.white.withOpacity(.92)),
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
                    child:
                        const Icon(Icons.campaign_rounded, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _HeroStat(
                      label: 'Total',
                      value: '${_circulars.length}',
                      icon: Icons.inbox_rounded),
                  const SizedBox(width: 10),
                  _HeroStat(
                      label: 'Files',
                      value: '$totalWithFiles',
                      icon: Icons.attach_file_rounded),
                ],
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search title or description…',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.search_rounded),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _onlyWithFiles = !_onlyWithFiles),
                  child: Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: _onlyWithFiles
                          ? const Color(0xFFE7F0FF)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _onlyWithFiles
                            ? const Color(0xFF1F7AE0)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Icon(
                      Icons.attach_file_rounded,
                      color: _onlyWithFiles
                          ? const Color(0xFF1F7AE0)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _FilterChip(
                    label: '7d',
                    selected: _sinceDays == '7',
                    onTap: () => setState(() => _sinceDays = '7')),
                const SizedBox(width: 8),
                _FilterChip(
                    label: '30d',
                    selected: _sinceDays == '30',
                    onTap: () => setState(() => _sinceDays = '30')),
                const SizedBox(width: 8),
                _FilterChip(
                    label: '90d',
                    selected: _sinceDays == '90',
                    onTap: () => setState(() => _sinceDays = '90')),
                const SizedBox(width: 8),
                _FilterChip(
                    label: 'All',
                    selected: _sinceDays == 'all',
                    onTap: () => setState(() => _sinceDays = 'all')),
                const Spacer(),
                Text(
                  '${processed.length}',
                  style: const TextStyle(
                      color: Colors.black54, fontWeight: FontWeight.w800),
                ),
              ]),
            ]),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? _loadingList()
                  : processed.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 34),
                          children: const [
                            Icon(Icons.inbox_rounded,
                                size: 62, color: Colors.black26),
                            SizedBox(height: 14),
                            Center(
                              child: Text(
                                'No circulars found',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                            ),
                            SizedBox(height: 6),
                            Center(
                              child: Text(
                                'Try changing filters or check back later.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.black54),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          itemBuilder: (ctx, i) => _buildCard(processed[i], i),
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemCount: processed.length,
                        ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1F7AE0) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF1F7AE0) : const Color(0xFFE6EEF9),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF1F7AE0).withOpacity(.16),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w800,
          ),
        ),
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
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 19),
            const SizedBox(width: 8),
            Text(value,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w900)),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: Colors.white.withOpacity(.86), fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// Full-screen bottom sheet detail view
class _CircularDetailSheet extends StatelessWidget {
  final Circular circular;
  final String studentTitle;
  final void Function(String url) onOpenAttachment;
  final String Function(DateTime) formatDT;
  final String Function(String?) fileKind;

  const _CircularDetailSheet({
    required this.circular,
    required this.studentTitle,
    required this.onOpenAttachment,
    required this.formatDT,
    required this.fileKind,
  });

  @override
  Widget build(BuildContext context) {
    final hasFile =
        circular.fileUrl != null && circular.fileUrl!.trim().isNotEmpty;
    final kind = fileKind(circular.fileUrl);

    return Material(
      color: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        circular.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECF5FF),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              circular.audience == 'both'
                                  ? 'Students & Staff'
                                  : 'Students',
                              style: const TextStyle(
                                color: Color(0xFF1B6ED6),
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (studentTitle.trim().isNotEmpty &&
                              studentTitle.trim() !=
                                  'Latest notices & attachments')
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                studentTitle,
                                style: const TextStyle(
                                  color: Color(0xFF334155),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          Text(
                            formatDT(circular.createdAt),
                            style: const TextStyle(
                                color: Colors.black54, fontSize: 12.5),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (circular.description != null &&
                          circular.description!.trim().isNotEmpty)
                        Text(
                          circular.description!.trim(),
                          style: const TextStyle(
                              fontSize: 15,
                              height: 1.48,
                              color: Color(0xFF334155)),
                        )
                      else
                        const Text(
                          'No description provided.',
                          style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.black54),
                        ),
                      const SizedBox(height: 16),
                      if (hasFile) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Attachment',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 15),
                            ),
                            TextButton.icon(
                              onPressed: () =>
                                  onOpenAttachment(circular.fileUrl!),
                              icon: const Icon(Icons.open_in_new_rounded,
                                  size: 18),
                              label: const Text('Open'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (kind == 'image')
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: CachedNetworkImage(
                              imageUrl: circular.fileUrl!,
                              placeholder: (_, __) => Container(
                                  height: 190, color: Colors.grey[100]),
                              errorWidget: (_, __, ___) => Container(
                                height: 190,
                                color: Colors.grey[100],
                                child: const Icon(Icons.broken_image_rounded),
                              ),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: 230,
                            ),
                          )
                        else if (kind == 'pdf')
                          Container(
                            height: 220,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: const Color(0xFFF8FAFC),
                              border:
                                  Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: const Center(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.picture_as_pdf_rounded,
                                        size: 46, color: Color(0xFFDC2626)),
                                    SizedBox(height: 8),
                                    Text(
                                      'PDF preview not embedded\nOpen to view',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.black45),
                                    ),
                                  ]),
                            ),
                          )
                        else
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: const Color(0xFFF8FAFC),
                              border:
                                  Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: const Text(
                                'Preview not available. Use Open Attachment.'),
                          ),
                      ],
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                              label: const Text('Close'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey[200],
                                foregroundColor: Colors.black87,
                                elevation: 0,
                              ),
                            ),
                          ),
                          if (hasFile) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    onOpenAttachment(circular.fileUrl!),
                                icon: const Icon(Icons.open_in_new_rounded),
                                label: const Text('Open Attachment'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1F7AE0),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _shortError(Object e) {
  final s = e.toString();
  if (s.length <= 100) return s;
  return '${s.substring(0, 100)}...';
}
