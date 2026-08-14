import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/role_manager.dart';
import '../../services/document_vault_api.dart';

class OfficialIssuedDocumentsScreen extends StatefulWidget {
  const OfficialIssuedDocumentsScreen({super.key});

  @override
  State<OfficialIssuedDocumentsScreen> createState() =>
      _OfficialIssuedDocumentsScreenState();
}

class _OfficialIssuedDocumentsScreenState
    extends State<OfficialIssuedDocumentsScreen> {
  bool _loading = true;
  String? _error;
  String _scope = '';
  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _documents = const [];
  int? _busyId;

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
      final role =
          prefs.getString('activeRole') ?? prefs.getString('role') ?? '';
      final scope = _scopeForRole(role);
      if (scope.isEmpty) {
        throw const DocumentVaultApiException(
            'Official documents are not available for this mobile role.');
      }
      final data = await DocumentVaultApi.officialMine(scope);
      if (!mounted) return;
      final rawDocs = data['documents'];
      setState(() {
        _scope = scope;
        _summary = data['summary'] is Map
            ? Map<String, dynamic>.from(data['summary'] as Map)
            : <String, dynamic>{};
        _documents = rawDocs is List
            ? rawDocs
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

  Future<void> _openDocument(Map<String, dynamic> doc) async {
    final id = int.tryParse(doc['id']?.toString() ?? '');
    if (id == null) return;
    setState(() => _busyId = id);
    try {
      final path = await DocumentVaultApi.downloadOfficialToTemp(
        documentId: id,
        scope: _scope,
        suggestedName: doc['original_name']?.toString() ??
            '${doc['letter_number'] ?? 'official-document'}.pdf',
      );
      await OpenFilex.open(path);
      await _load();
    } catch (e) {
      _snack(
        e.toString().replaceFirst('DocumentVaultApiException: ', ''),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _acknowledge(Map<String, dynamic> doc) async {
    final id = int.tryParse(doc['id']?.toString() ?? '');
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Acknowledge document?'),
        content: const Text(
          'This confirms that you have received and read this official document.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Acknowledge'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busyId = id);
    try {
      await DocumentVaultApi.acknowledgeOfficial(id);
      _snack('Document acknowledged.');
      await _load();
    } catch (e) {
      _snack(
        e.toString().replaceFirst('DocumentVaultApiException: ', ''),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'issued':
        return Colors.blue;
      case 'viewed':
        return Colors.teal;
      case 'acknowledged':
        return Colors.green;
      case 'revoked':
        return Colors.red;
      case 'superseded':
        return Colors.black87;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'issued':
        return 'NEW';
      case 'viewed':
        return 'VIEWED';
      case 'acknowledged':
        return 'ACKNOWLEDGED';
      case 'revoked':
        return 'REVOKED';
      case 'superseded':
        return 'SUPERSEDED';
      default:
        return status.toUpperCase();
    }
  }

  String _prettyDate(dynamic raw) {
    final value = raw?.toString() ?? '';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value.isEmpty ? '—' : value;
    return DateFormat('dd MMM yyyy').format(parsed);
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
            const SizedBox(height: 7),
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

  Widget _documentCard(Map<String, dynamic> doc) {
    final status = (doc['status'] ?? '').toString().toLowerCase();
    final confidential =
        doc['confidential'] == true || doc['confidential']?.toString() == '1';
    final ackRequired = doc['acknowledgement_required'] == true ||
        doc['acknowledgement_required']?.toString() == '1';
    final canAck = doc['can_acknowledge'] == true ||
        doc['can_acknowledge']?.toString() == '1';
    final id = int.tryParse(doc['id']?.toString() ?? '');
    final typeRaw = doc['documentType'];
    final type = typeRaw is Map
        ? Map<String, dynamic>.from(typeRaw)
        : <String, dynamic>{};
    final issuerRaw = doc['issuer'];
    final issuer = issuerRaw is Map
        ? Map<String, dynamic>.from(issuerRaw)
        : <String, dynamic>{};

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: confidential ? Colors.red.shade200 : Colors.grey.shade200,
          width: confidential ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: _statusColor(status).withOpacity(.12),
                  child: Icon(Icons.mark_email_read_outlined,
                      color: _statusColor(status)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc['title']?.toString() ??
                            type['name']?.toString() ??
                            'Official Document',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          type['category']?.toString(),
                          doc['letter_number']?.toString(),
                          _prettyDate(doc['issue_date']),
                        ]
                            .where((e) => e != null && e!.trim().isNotEmpty)
                            .join(' • '),
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
                  child: Text(
                    _statusLabel(status),
                    style: TextStyle(
                      color: _statusColor(status),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            if ((doc['subject'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Subject: ${doc['subject']}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                if (confidential)
                  Chip(
                    avatar: const Icon(Icons.lock, size: 16),
                    label: const Text('Confidential'),
                    backgroundColor: Colors.red.shade50,
                  ),
                if (ackRequired)
                  Chip(
                    avatar: const Icon(Icons.check_box_outlined, size: 16),
                    label: const Text('Acknowledgement required'),
                    backgroundColor: Colors.orange.shade50,
                  ),
                if ((issuer['name'] ?? '').toString().isNotEmpty)
                  Chip(
                    avatar:
                        const Icon(Icons.account_balance_outlined, size: 16),
                    label: Text('Issued by ${issuer['name']}'),
                    backgroundColor: Colors.grey.shade100,
                  ),
              ],
            ),
            if ((doc['revoked_reason'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Revoked: ${doc['revoked_reason']}',
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        id == null || _busyId == id || status == 'revoked'
                            ? null
                            : () => _openDocument(doc),
                    icon: _busyId == id
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.visibility_outlined),
                    label: const Text('VIEW DOCUMENT'),
                  ),
                ),
                if (canAck) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: id == null || _busyId == id
                          ? null
                          : () => _acknowledge(doc),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('ACKNOWLEDGE'),
                    ),
                  ),
                ],
              ],
            ),
            if ((doc['acknowledged_at'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Acknowledged: ${_prettyDate(doc['acknowledged_at'])}',
                style: TextStyle(
                    color: Colors.green.shade700, fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Issued to Me'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
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
                            colors: [Color(0xFF0F766E), Color(0xFF1D4ED8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: Colors.white24,
                              child: Icon(Icons.mail_outline,
                                  color: Colors.white, size: 30),
                            ),
                            SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Official Documents Issued to Me',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 18),
                                  ),
                                  SizedBox(height: 5),
                                  Text(
                                    'Secure school letters • View history • Acknowledge receipt',
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
                      Row(
                        children: [
                          _summaryCard('Total', _summary['total'] ?? 0,
                              Icons.description_outlined, Colors.blue),
                          const SizedBox(width: 8),
                          _summaryCard('New', _summary['new'] ?? 0,
                              Icons.mark_email_unread_outlined, Colors.orange),
                          const SizedBox(width: 8),
                          _summaryCard(
                              'Ack Pending',
                              _summary['acknowledgement_pending'] ?? 0,
                              Icons.pending_actions_outlined,
                              Colors.red),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Text(
                            'Official Letters & Documents',
                            style: TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 17),
                          ),
                          const Spacer(),
                          Text('${_documents.length}',
                              style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_documents.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(28),
                            child: Column(
                              children: [
                                Icon(Icons.inbox_outlined, size: 44),
                                SizedBox(height: 10),
                                Text(
                                  'No official documents have been issued to you yet.',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ..._documents.map(_documentCard),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }
}
