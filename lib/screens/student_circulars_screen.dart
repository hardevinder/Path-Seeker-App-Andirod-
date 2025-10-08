// lib/screens/student_circulars_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/circular.dart';
import '../services/api_service.dart';

// Optional: socket.io (uncomment in pubspec and below import & code if you have a socket server)
// import 'package:socket_io_client/socket_io_client.dart' as IO;

class StudentCircularsScreen extends StatefulWidget {
  const StudentCircularsScreen({super.key});

  @override
  State<StudentCircularsScreen> createState() => _StudentCircularsScreenState();
}

class _StudentCircularsScreenState extends State<StudentCircularsScreen> {
  List<Circular> _circulars = [];
  bool _loading = true;
  String _query = '';
  bool _onlyWithFiles = false;
  String _sinceDays = '30'; // 7,30,90,all
  final _searchController = TextEditingController();
  Timer? _debounce;

  // Optional socket (commented)
  // IO.Socket? socket;

  @override
  void initState() {
    super.initState();
    _load();
    // _initSocket();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // socket?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ApiService.fetchCirculars();
      // filter audience: student or both (like your original)
      _circulars = list.where((c) => c.audience == 'student' || c.audience == 'both').toList();
    } catch (e, st) {
      // gracefully show snack
      debugPrint('Error fetching circulars: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't load circulars — try again later.")),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
        : DateTime.now().subtract(Duration(days: int.tryParse(_sinceDays) ?? 30));

    return _circulars.where((c) {
      if (_onlyWithFiles && (c.fileUrl == null || c.fileUrl!.isEmpty)) return false;
      if (sinceDate != null && c.createdAt.isBefore(sinceDate)) return false;
      if (lowerQ.isEmpty) return true;
      final hay = '${c.title} ${c.description ?? ''} ${c.audience}'.toLowerCase();
      return hay.contains(lowerQ);
    }).toList();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _query = v;
      });
    });
  }

  String _formatDT(DateTime dt) {
    return DateFormat.yMMMd().add_jm().format(dt);
  }

  String _fileKind(String? url) {
    if (url == null) return 'other';
    final clean = url.split('?').first.split('#').first;
    final dot = clean.lastIndexOf('.');
    if (dot == -1) return 'other';
    final ext = clean.substring(dot + 1).toLowerCase();
    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'].contains(ext)) return 'image';
    if (ext == 'pdf') return 'pdf';
    return 'other';
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open attachment')));
      }
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
          onOpenAttachment: (url) => _openUrl(url),
          formatDT: _formatDT,
          fileKind: _fileKind,
        ),
      ),
    );
  }

  Widget _buildCard(Circular c, int index) {
    final hasFile = c.fileUrl != null && c.fileUrl!.isNotEmpty;
    return InkWell(
      onTap: () => _showFullView(c),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(color: Color(0x11000000), blurRadius: 8, offset: Offset(0, 4))
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFFE8F1FF),
              child: Text('${index + 1}', style: const TextStyle(color: Color(0xFF1F7AE0), fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    Expanded(child: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700))),
                    const SizedBox(width: 8),
                    if (hasFile)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE7F0FF),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text('Attachment', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF1F7AE0))),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  c.description ?? 'No description',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[700]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECF5FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(c.audience == 'both' ? 'All Students' : 'Students', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1B6ED6))),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.circle, size: 6, color: Color(0xFFC9D6EA)),
                  const SizedBox(width: 8),
                  Text(_formatDT(c.createdAt), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ])
              ]),
            )
          ],
        ),
      ),
    );
  }

  Widget _loadingList() {
    // simple shimmer-like placeholders
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemBuilder: (_, i) => Container(
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(colors: [Color(0xFFF2F6FF), Color(0xFFE9F1FF), Color(0xFFF2F6FF)], begin: Alignment.centerLeft, end: Alignment.centerRight),
        ),
      ),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemCount: 4,
    );
  }

  @override
  Widget build(BuildContext context) {
    final processed = _processed;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FF),
      appBar: AppBar(
        title: const Text('Student Circulars'),
        elevation: 0,
        backgroundColor: const Color(0xFF1F7AE0),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          )
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          // Hero
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF1F7AE0), Color(0xFF6AA7FF)]),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Student Circulars', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(height: 6),
                    Text('Latest notices & attachments', style: TextStyle(color: Colors.white.withOpacity(0.95))),
                  ]),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.notifications, color: Colors.white),
                )
              ],
            ),
          ),

          // Filters
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(children: [
              // search
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search title or description…',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.search),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    setState(() => _onlyWithFiles = !_onlyWithFiles);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(color: _onlyWithFiles ? const Color(0xFFE7F0FF) : Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.attach_file, color: _onlyWithFiles ? const Color(0xFF1F7AE0) : Colors.black54),
                  ),
                )
              ]),
              const SizedBox(height: 10),

              // quick filter chips
              Row(children: [
                _FilterChip(label: '7d', selected: _sinceDays == '7', onTap: () => setState(() => _sinceDays = '7')),
                const SizedBox(width: 8),
                _FilterChip(label: '30d', selected: _sinceDays == '30', onTap: () => setState(() => _sinceDays = '30')),
                const SizedBox(width: 8),
                _FilterChip(label: '90d', selected: _sinceDays == '90', onTap: () => setState(() => _sinceDays = '90')),
                const SizedBox(width: 8),
                _FilterChip(label: 'All', selected: _sinceDays == 'all', onTap: () => setState(() => _sinceDays = 'all')),
                const Spacer(),
                // count
                Text('${processed.length}', style: const TextStyle(color: Colors.black54)),
              ]),
            ]),
          ),

          // content
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? _loadingList()
                  : processed.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                          children: [
                            Center(child: Column(children: const [
                              Icon(Icons.inbox, size: 56, color: Colors.black26),
                              SizedBox(height: 12),
                              Text('No circulars found', style: TextStyle(fontWeight: FontWeight.bold)),
                              SizedBox(height: 6),
                              Text('Try changing filters or check back later.', style: TextStyle(color: Colors.black54)),
                            ])),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemBuilder: (ctx, i) {
                            final c = processed[i];
                            return _buildCard(c, i);
                          },
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemCount: processed.length,
                        ),
            ),
          )
        ]),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1F7AE0) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFE6EEF9)),
        ),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.black87, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// Full-screen bottom sheet detail view
class _CircularDetailSheet extends StatelessWidget {
  final Circular circular;
  final void Function(String url) onOpenAttachment;
  final String Function(DateTime) formatDT;
  final String Function(String?) fileKind;

  const _CircularDetailSheet({
    required this.circular,
    required this.onOpenAttachment,
    required this.formatDT,
    required this.fileKind,
  });

  @override
  Widget build(BuildContext context) {
    final hasFile = circular.fileUrl != null && circular.fileUrl!.isNotEmpty;
    final kind = fileKind(circular.fileUrl);
    return Material(
      color: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Row(
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(4))),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close))
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(circular.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Row(children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: const Color(0xFFECF5FF), borderRadius: BorderRadius.circular(999)), child: Text(circular.audience == 'both' ? 'All Students' : 'Students', style: const TextStyle(color: Color(0xFF1B6ED6), fontWeight: FontWeight.w700))),
                  const SizedBox(width: 10),
                  const Icon(Icons.circle, size: 6, color: Color(0xFFC9D6EA)),
                  const SizedBox(width: 8),
                  Text(formatDT(circular.createdAt), style: const TextStyle(color: Colors.black54)),
                ]),
                const SizedBox(height: 12),
                if (circular.description != null && circular.description!.isNotEmpty)
                  Text(circular.description!, style: const TextStyle(fontSize: 15, height: 1.45))
                else
                  const Text('No description provided.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.black54)),
                const SizedBox(height: 14),
                if (hasFile) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Attachment', style: TextStyle(fontWeight: FontWeight.w700)),
                      Row(children: [
                        TextButton(onPressed: () => onOpenAttachment(circular.fileUrl!), child: const Text('Open')),
                        const SizedBox(width: 6),
                        TextButton(onPressed: () => onOpenAttachment(circular.fileUrl!), child: const Text('Download')),
                      ]),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (kind == 'image')
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: circular.fileUrl!,
                        placeholder: (_, __) => Container(height: 180, color: Colors.grey[100]),
                        errorWidget: (_, __, ___) => Container(height: 180, color: Colors.grey[100], child: const Icon(Icons.broken_image)),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: 220,
                      ),
                    )
                  else if (kind == 'pdf')
                    Container(
                      height: 220,
                      width: double.infinity,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0xFFF8FAFC)),
                      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [
                        Icon(Icons.picture_as_pdf, size: 44, color: Colors.black26),
                        SizedBox(height: 6),
                        Text('PDF preview not embedded\nOpen to view', textAlign: TextAlign.center, style: TextStyle(color: Colors.black45)),
                      ])),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0xFFF8FAFC)),
                      child: const Text('Preview not available. Use Open / Download.'),
                    ),
                ],

                const SizedBox(height: 20),
                // action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        label: const Text('Close'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[200], foregroundColor: Colors.black),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (hasFile)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => onOpenAttachment(circular.fileUrl!),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open Attachment'),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
