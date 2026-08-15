import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

import '../../services/parent_consent_api.dart';

class ParentConsentScreen extends StatefulWidget {
  const ParentConsentScreen({super.key});

  @override
  State<ParentConsentScreen> createState() => _ParentConsentScreenState();
}

class _ParentConsentScreenState extends State<ParentConsentScreen> {
  bool _loading = true;
  String? _error;
  bool _canRespond = false;
  List<Map<String, dynamic>> _items = const [];
  int? _busyId;
  bool _pendingOnly = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ParentConsentApi.myRequests();
      final raw = data['items'];
      final items = raw is List
          ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _items = items;
        _canRespond = data['can_respond'] == true || data['can_respond']?.toString() == '1';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  String _status(Map<String, dynamic> item) => (item['overall_status'] ?? 'pending').toString();

  Color _statusColor(String status) {
    switch (status) {
      case 'complete': return Colors.green.shade700;
      case 'declined':
      case 'scan_rejected': return Colors.red.shade700;
      case 'scan_review':
      case 'awaiting_scan':
      case 'digital_pending': return Colors.orange.shade800;
      case 'viewed': return Colors.blue.shade700;
      default: return Colors.grey.shade700;
    }
  }

  String _statusLabel(String status) {
    const map = {
      'complete': 'Complete',
      'declined': 'Declined',
      'scan_rejected': 'Signed scan rejected',
      'scan_review': 'Signed scan under review',
      'awaiting_scan': 'Signed scan required',
      'digital_pending': 'Digital response required',
      'viewed': 'Viewed',
      'pending': 'Pending',
    };
    return map[status] ?? status.replaceAll('_', ' ');
  }

  String _date(dynamic raw) {
    final s = (raw ?? '').toString();
    if (s.isEmpty) return '';
    final parsed = DateTime.tryParse(s);
    return parsed == null ? s : DateFormat('dd MMM yyyy').format(parsed);
  }

  Future<void> _openForm(Map<String, dynamic> item, {bool signed = false}) async {
    final id = int.tryParse(item['id'].toString());
    if (id == null) return;
    setState(() => _busyId = id);
    try {
      await ParentConsentApi.markViewed(id).catchError((_) {});
      final request = item['request'] is Map ? Map<String, dynamic>.from(item['request']) : <String, dynamic>{};
      final path = await ParentConsentApi.downloadToTemp(
        recipientId: id,
        signedScan: signed,
        suggestedName: signed ? 'signed-parent-consent-$id.pdf' : '${request['title'] ?? 'parent-consent'}-$id.pdf',
      );
      await OpenFilex.open(path);
      if (!signed) await _load();
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _respond(Map<String, dynamic> item, String response) async {
    final id = int.tryParse(item['id'].toString());
    if (id == null) return;
    final request = item['request'] is Map ? Map<String, dynamic>.from(item['request']) : <String, dynamic>{};
    final title = request['title']?.toString() ?? 'this request';
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(response == 'accepted' ? 'Give consent / acknowledge?' : 'Decline consent?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title),
          const SizedBox(height: 14),
          TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Optional note', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(response == 'accepted' ? 'Confirm' : 'Decline')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busyId = id);
    try {
      await ParentConsentApi.respond(recipientId: id, responseValue: response, note: note.text);
      _snack(response == 'accepted' ? 'Consent / acknowledgement recorded.' : 'Decline response recorded.');
      await _load();
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      note.dispose();
      if (mounted) setState(() => _busyId = null);
    }
  }

  String _localPath(String raw) {
    if (raw.isEmpty) return '';
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.scheme == 'file') {
      try { return uri.toFilePath(); } catch (_) {}
    }
    return raw.replaceFirst(RegExp(r'^file://'), '');
  }

  Future<String?> _scanPdf() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.pdf},
        mode: ScannerMode.base,
        pageLimit: 12,
        isGalleryImport: false,
      ),
    );
    try {
      final result = await scanner.scanDocument();
      final path = _localPath(result.pdf?.uri.trim() ?? '');
      if (path.isNotEmpty && await File(path).exists()) return path;
    } on PlatformException catch (e) {
      if (!e.message.toString().toLowerCase().contains('cancel')) _snack(e.message ?? e.code, error: true);
    } finally {
      await scanner.close();
    }
    return null;
  }

  Future<String?> _pickExisting() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Signed consent', extensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif']),
    ]);
    return file?.path;
  }

  Future<void> _scanAndUpload(Map<String, dynamic> item) async {
    final id = int.tryParse(item['id'].toString());
    if (id == null) return;
    String? path;
    if (!kIsWeb && Platform.isAndroid) {
      final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.document_scanner)),
            title: const Text('Scan signed paper'),
            subtitle: const Text('Camera scan, auto-crop pages and create one PDF'),
            onTap: () => Navigator.pop(ctx, 'scan'),
          ),
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.attach_file)),
            title: const Text('Choose existing signed file'),
            subtitle: const Text('PDF or image already on this device'),
            onTap: () => Navigator.pop(ctx, 'file'),
          ),
          const SizedBox(height: 8),
        ])),
      );
      if (action == 'scan') path = await _scanPdf();
      if (action == 'file') path = await _pickExisting();
    } else {
      path = await _pickExisting();
    }
    if (path == null || path!.isEmpty) return;

    setState(() => _busyId = id);
    try {
      await ParentConsentApi.uploadSignedScan(recipientId: id, filePath: path!);
      _snack('Signed form submitted to school for verification.');
      await _load();
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _items.where((item) {
      if (!_pendingOnly) return true;
      return !['complete', 'declined'].contains(_status(item));
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent Consent'),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(children: const [SizedBox(height: 220), Center(child: CircularProgressIndicator())])
            : ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Colors.indigo.shade700, Colors.deepPurple.shade500]),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [Icon(Icons.draw_rounded, color: Colors.white), SizedBox(width: 10), Text('Consent & Acknowledgement', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))]),
                      const SizedBox(height: 8),
                      Text(_canRespond
                          ? 'Review school requests, respond digitally, or scan and upload a parent-signed paper when required.'
                          : 'You can view requests here. A linked parent/guardian login is required to submit consent.',
                        style: const TextStyle(color: Colors.white70, height: 1.35)),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [ButtonSegment(value: true, label: Text('Pending')), ButtonSegment(value: false, label: Text('All'))],
                    selected: {_pendingOnly},
                    onSelectionChanged: (s) => setState(() => _pendingOnly = s.first),
                  ),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Card(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: Colors.red.shade800))))),
                  const SizedBox(height: 8),
                  if (visible.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No consent requests in this view.')))),
                  ...visible.map((item) {
                    final request = item['request'] is Map ? Map<String, dynamic>.from(item['request']) : <String, dynamic>{};
                    final student = item['student'] is Map ? Map<String, dynamic>.from(item['student']) : <String, dynamic>{};
                    final id = int.tryParse(item['id'].toString()) ?? 0;
                    final busy = _busyId == id;
                    final status = _status(item);
                    final allowsScan = item['allows_scan'] == true || item['allows_scan']?.toString() == '1';
                    final hasScan = (item['signed_scan_file_path'] ?? '').toString().isNotEmpty;
                    final allowDecline = request['allow_decline'] != false && request['allow_decline']?.toString() != '0';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 1.5,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(request['title']?.toString() ?? 'Parent Consent', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 4),
                              Text('${student['name'] ?? 'Student'} • ${request['category'] ?? 'General'}', style: TextStyle(color: Colors.grey.shade700)),
                            ])),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: _statusColor(status).withOpacity(.1), borderRadius: BorderRadius.circular(30)), child: Text(_statusLabel(status), style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.w700, fontSize: 11))),
                          ]),
                          if ((request['description'] ?? '').toString().isNotEmpty) ...[const SizedBox(height: 10), Text(request['description'].toString(), maxLines: 4, overflow: TextOverflow.ellipsis)],
                          const SizedBox(height: 10),
                          Wrap(spacing: 8, runSpacing: 6, children: [
                            Chip(label: Text('Issued ${_date(request['issue_date'])}'), visualDensity: VisualDensity.compact),
                            if ((request['due_date'] ?? '').toString().isNotEmpty) Chip(label: Text('Due ${_date(request['due_date'])}'), visualDensity: VisualDensity.compact),
                            if ((item['scan_status'] ?? '').toString() == 'rejected') Chip(label: Text(item['scan_rejection_reason']?.toString() ?? 'Signed scan rejected'), backgroundColor: Colors.red.shade50, visualDensity: VisualDensity.compact),
                          ]),
                          const Divider(height: 22),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            OutlinedButton.icon(onPressed: busy ? null : () => _openForm(item), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('View / Download Form')),
                            if (hasScan) OutlinedButton.icon(onPressed: busy ? null : () => _openForm(item, signed: true), icon: const Icon(Icons.file_present_outlined), label: const Text('View My Signed Copy')),
                            if (_canRespond && allowsScan && !['complete', 'declined'].contains(status)) FilledButton.tonalIcon(onPressed: busy ? null : () => _scanAndUpload(item), icon: const Icon(Icons.document_scanner_outlined), label: Text(hasScan ? 'Rescan / Replace' : 'Scan Signed Form')),
                          ]),
                          if (_canRespond && !['complete', 'declined'].contains(status)) ...[
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(child: FilledButton.icon(onPressed: busy ? null : () => _respond(item, 'accepted'), icon: const Icon(Icons.check_circle_outline), label: const Text('Give Consent / Acknowledge'))),
                              if (allowDecline) ...[const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: busy ? null : () => _respond(item, 'declined'), icon: const Icon(Icons.cancel_outlined), label: const Text('Decline')))],
                            ]),
                          ],
                          if (busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
                        ]),
                      ),
                    );
                  }),
                  const SizedBox(height: 40),
                ],
              ),
      ),
    );
  }
}
