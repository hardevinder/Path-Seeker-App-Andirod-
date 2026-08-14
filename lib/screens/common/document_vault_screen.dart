import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/role_manager.dart';
import '../../services/document_vault_api.dart';

class DocumentVaultScreen extends StatefulWidget {
  const DocumentVaultScreen({super.key});

  @override
  State<DocumentVaultScreen> createState() => _DocumentVaultScreenState();
}

class _DocumentVaultScreenState extends State<DocumentVaultScreen> {
  bool _loading = true;
  String? _error;
  String _scope = '';
  Map<String, dynamic> _owner = const {};
  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _requirements = const [];
  int? _busyTypeId;
  int? _openingDocumentId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _scopeForRole(String role) {
    switch (AppRoles.normalize(role)) {
      case AppRoles.student:
        return 'student';
      case AppRoles.driver:
        return 'driver';
      case AppRoles.teacher:
      case AppRoles.departmentHod:
      case AppRoles.coordinator:
      case AppRoles.hr:
      case AppRoles.accounts:
      case AppRoles.examination:
      case AppRoles.frontoffice:
        return 'employee';
      default:
        return '';
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('activeRole') ?? prefs.getString('role') ?? '';
      final scope = _scopeForRole(role);
      if (scope.isEmpty) {
        throw const DocumentVaultApiException(
            'Document Vault is not enabled for this mobile role.');
      }
      final data = await DocumentVaultApi.myVault(scope);
      if (!mounted) return;
      setState(() {
        _scope = scope;
        _owner = data['owner'] is Map
            ? Map<String, dynamic>.from(data['owner'] as Map)
            : <String, dynamic>{};
        _summary = data['summary'] is Map
            ? Map<String, dynamic>.from(data['summary'] as Map)
            : <String, dynamic>{};
        final raw = data['requirements'];
        _requirements = raw is List
            ? raw
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
            : <Map<String, dynamic>>[];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('DocumentVaultApiException: ', '');
        _loading = false;
      });
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  String _localPath(String raw) {
    if (raw.isEmpty) return '';
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.scheme == 'file') {
      try {
        return uri.toFilePath();
      } catch (_) {}
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
      if (!e.message.toString().toLowerCase().contains('cancel')) {
        _snack(e.message ?? e.code, error: true);
      }
    } finally {
      await scanner.close();
    }
    return null;
  }

  Future<String?> _pickFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Document',
          extensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
        ),
      ],
    );
    return file?.path;
  }

  Future<void> _chooseUpload(Map<String, dynamic> requirement) async {
    String? path;
    if (!kIsWeb && Platform.isAndroid) {
      final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.document_scanner)),
                title: const Text('Scan with camera'),
                subtitle: const Text('Auto crop pages and create one PDF'),
                onTap: () => Navigator.pop(context, 'scan'),
              ),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.attach_file)),
                title: const Text('Choose existing file'),
                subtitle: const Text('PDF or image from device'),
                onTap: () => Navigator.pop(context, 'file'),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      );
      if (action == 'scan') path = await _scanPdf();
      if (action == 'file') path = await _pickFile();
    } else {
      path = await _pickFile();
    }
    if (path == null || path.isEmpty) return;
    if (!mounted) return;
    await _showMetadataAndUpload(requirement, path);
  }

  Future<void> _showMetadataAndUpload(
      Map<String, dynamic> requirement, String filePath) async {
    final number = TextEditingController();
    final notes = TextEditingController();
    DateTime? issuedOn;
    DateTime? expiresOn;
    String? localError;
    final requiresExpiry = requirement['requires_expiry'] == true ||
        requirement['requires_expiry']?.toString() == '1';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> pickDate(bool expiry) async {
            final initial = expiry
                ? (expiresOn ?? DateTime.now().add(const Duration(days: 365)))
                : (issuedOn ?? DateTime.now());
            final selected = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: DateTime(1950),
              lastDate: DateTime(DateTime.now().year + 20),
            );
            if (selected == null) return;
            setDialogState(() {
              if (expiry) {
                expiresOn = selected;
              } else {
                issuedOn = selected;
              }
            });
          }

          Future<void> submit() async {
            if (requiresExpiry && expiresOn == null) {
              setDialogState(() => localError = 'Expiry date is required.');
              return;
            }
            Navigator.pop(dialogContext);
            await _upload(
              requirement: requirement,
              filePath: filePath,
              documentNumber: number.text,
              issuedOn: issuedOn,
              expiresOn: expiresOn,
              notes: notes.text,
            );
          }

          return AlertDialog(
            title: Text('Upload ${requirement['name'] ?? 'Document'}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.picture_as_pdf_outlined),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            filePath.split(Platform.pathSeparator).last,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: number,
                    decoration: const InputDecoration(
                      labelText: 'Document / Certificate No. (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pickDate(false),
                          icon: const Icon(Icons.event),
                          label: Text(issuedOn == null
                              ? 'Issue date'
                              : DateFormat('dd MMM yyyy').format(issuedOn!)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pickDate(true),
                          icon: const Icon(Icons.event_busy),
                          label: Text(expiresOn == null
                              ? (requiresExpiry ? 'Expiry *' : 'Expiry')
                              : DateFormat('dd MMM yyyy').format(expiresOn!)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (localError != null) ...[
                    const SizedBox(height: 10),
                    Text(localError!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: submit,
                icon: const Icon(Icons.cloud_upload),
                label: const Text('Upload'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _upload({
    required Map<String, dynamic> requirement,
    required String filePath,
    required String documentNumber,
    required DateTime? issuedOn,
    required DateTime? expiresOn,
    required String notes,
  }) async {
    final id = int.tryParse(requirement['id']?.toString() ?? '');
    if (id == null) return;
    setState(() => _busyTypeId = id);
    try {
      await DocumentVaultApi.uploadMine(
        scope: _scope,
        documentTypeId: id,
        filePath: filePath,
        documentNumber: documentNumber,
        issuedOn: issuedOn == null ? null : DateFormat('yyyy-MM-dd').format(issuedOn),
        expiresOn: expiresOn == null ? null : DateFormat('yyyy-MM-dd').format(expiresOn),
        notes: notes,
      );
      _snack('Document uploaded for verification.');
      await _load();
    } catch (e) {
      _snack(e.toString().replaceFirst('DocumentVaultApiException: ', ''),
          error: true);
    } finally {
      if (mounted) setState(() => _busyTypeId = null);
    }
  }

  Future<void> _openDocument(Map<String, dynamic> doc) async {
    final id = int.tryParse(doc['id']?.toString() ?? '');
    if (id == null) return;
    setState(() => _openingDocumentId = id);
    try {
      final path = await DocumentVaultApi.downloadToTemp(
        documentId: id,
        scope: _scope,
        suggestedName: doc['original_name']?.toString() ?? 'document-$id',
      );
      await OpenFilex.open(path);
    } catch (e) {
      _snack(e.toString().replaceFirst('DocumentVaultApiException: ', ''),
          error: true);
    } finally {
      if (mounted) setState(() => _openingDocumentId = null);
    }
  }

  String _status(Map<String, dynamic>? doc) {
    if (doc == null) return 'missing';
    return (doc['effective_status'] ?? doc['status'] ?? 'missing')
        .toString()
        .toLowerCase();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'verified':
        return Colors.green;
      case 'submitted':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      case 'expired':
        return Colors.black87;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'verified':
        return 'VERIFIED';
      case 'submitted':
        return 'PENDING';
      case 'rejected':
        return 'REJECTED';
      case 'expired':
        return 'EXPIRED';
      default:
        return 'MISSING';
    }
  }

  Widget _summaryCard(String label, dynamic value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text('$value',
                style:
                    const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            Text(label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }

  Widget _requirementCard(Map<String, dynamic> requirement) {
    final rawDocs = requirement['documents'];
    final docs = rawDocs is List
        ? rawDocs
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    final latest = docs.isNotEmpty ? docs.first : null;
    final status = _status(latest);
    final required = requirement['is_required'] == true ||
        requirement['is_required']?.toString() == '1';
    final busy = _busyTypeId?.toString() == requirement['id']?.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: required && status == 'missing'
              ? Colors.red.shade200
              : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: _statusColor(status).withOpacity(.12),
                  child: Icon(Icons.description_outlined,
                      color: _statusColor(status)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(requirement['name']?.toString() ?? 'Document',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 3),
                      Text(
                        [
                          requirement['category']?.toString(),
                          required ? 'Required' : 'Optional',
                          requirement['requires_expiry'] == true
                              ? 'Expiry tracked'
                              : null,
                        ].where((e) => e != null && e!.isNotEmpty).join(' • '),
                        style: TextStyle(
                            color: Colors.grey.shade700, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withOpacity(.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(_statusLabel(status),
                      style: TextStyle(
                          color: _statusColor(status),
                          fontSize: 10,
                          fontWeight: FontWeight.w900)),
                ),
              ],
            ),
            if (latest != null) ...[
              const Divider(height: 24),
              Text(latest['original_name']?.toString() ?? 'Uploaded document',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if ((latest['document_number'] ?? '').toString().isNotEmpty)
                Text('No. ${latest['document_number']}',
                    style: TextStyle(color: Colors.grey.shade700)),
              if ((latest['expires_on'] ?? '').toString().isNotEmpty)
                Text('Expires: ${latest['expires_on']}',
                    style: TextStyle(
                        color: latest['is_expired'] == true
                            ? Colors.red
                            : Colors.grey.shade700)),
              if ((latest['rejection_reason'] ?? '').toString().isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(9),
                  width: double.infinity,
                  decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('Reason: ${latest['rejection_reason']}',
                      style: TextStyle(color: Colors.red.shade800)),
                ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _openingDocumentId == latest['id']
                    ? null
                    : () => _openDocument(latest),
                icon: _openingDocumentId == latest['id']
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.visibility_outlined),
                label: const Text('View document'),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : () => _chooseUpload(requirement),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.document_scanner_outlined),
                label: Text(
                    latest == null ? 'SCAN / UPLOAD' : 'REPLACE / RE-UPLOAD'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Document Vault'),
        actions: [
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/official-documents'),
            tooltip: 'Issued to Me',
            icon: const Icon(Icons.mark_email_unread_outlined),
          ),
          IconButton(
              onPressed: _loading ? null : _load,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      const SizedBox(height: 60),
                      Icon(Icons.error_outline,
                          size: 56, color: Colors.red.shade300),
                      const SizedBox(height: 14),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1D4ED8), Color(0xFF6D28D9)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              radius: 26,
                              backgroundColor: Colors.white24,
                              child: Icon(Icons.shield_outlined,
                                  color: Colors.white, size: 30),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_owner['name']?.toString() ?? 'My Documents',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 19)),
                                  const SizedBox(height: 3),
                                  Text(
                                    _owner['reference']?.toString() ?? '',
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                  const SizedBox(height: 5),
                                  const Text(
                                    'Private • Secure • School verified',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.indigo.shade100),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: Colors.indigo.shade50,
                            child: Icon(Icons.mark_email_unread_outlined,
                                color: Colors.indigo.shade700),
                          ),
                          title: const Text(
                            'Documents Issued to Me',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: const Text(
                            'Official letters, notices, certificates & acknowledgements',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              Navigator.pushNamed(context, '/official-documents'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _summaryCard(
                              'Complete',
                              '${_summary['completion_percent'] ?? 0}%',
                              Icons.pie_chart_outline,
                              Colors.blue),
                          const SizedBox(width: 8),
                          _summaryCard(
                              'Missing',
                              _summary['missing_required'] ?? 0,
                              Icons.warning_amber_rounded,
                              Colors.red),
                          const SizedBox(width: 8),
                          _summaryCard(
                              'Verified',
                              _summary['verified'] ?? 0,
                              Icons.verified_outlined,
                              Colors.green),
                        ],
                      ),
                      if ((_summary['expiring'] ?? 0) > 0 ||
                          (_summary['expired'] ?? 0) > 0) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.notification_important_outlined,
                                  color: Colors.orange),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${_summary['expiring'] ?? 0} expiring soon • ${_summary['expired'] ?? 0} expired',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Text('Required & Other Documents',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 17)),
                          const Spacer(),
                          Text('${_requirements.length} types',
                              style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_requirements.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No document types are configured yet.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else
                        ..._requirements.map(_requirementCard),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }
}
