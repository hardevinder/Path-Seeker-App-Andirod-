import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:intl/intl.dart';

import '../models/assessment_models.dart';
import '../services/assessment_api.dart';

class AssessmentOfflineSubmissionScreen extends StatefulWidget {
  final Assessment assessment;
  const AssessmentOfflineSubmissionScreen({
    super.key,
    required this.assessment,
  });

  @override
  State<AssessmentOfflineSubmissionScreen> createState() =>
      _AssessmentOfflineSubmissionScreenState();
}

class _AssessmentOfflineSubmissionScreenState
    extends State<AssessmentOfflineSubmissionScreen> {
  final List<String> _paths = [];
  bool _scanning = false;
  bool _submitting = false;

  Future<void> _pickFiles() async {
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Answer sheets',
          extensions: ['pdf', 'jpg', 'jpeg', 'png'],
        )
      ],
    );
    if (files.isEmpty) return;
    setState(() {
      for (final file in files) {
        if (file.path.isNotEmpty && !_paths.contains(file.path)) {
          _paths.add(file.path);
        }
      }
    });
  }

  Future<void> _scan() async {
    if (kIsWeb || !Platform.isAndroid || _scanning) return;
    setState(() => _scanning = true);
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.pdf},
        mode: ScannerMode.full,
        pageLimit: 40,
        isGalleryImport: true,
      ),
    );
    try {
      final result = await scanner.scanDocument();
      final path = result.pdf?.uri.trim() ?? '';
      if (path.isNotEmpty && await File(path).exists()) {
        setState(() => _paths.add(path));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${result.pdf?.pageCount ?? 0} page(s) scanned.')));
        }
      }
    } on PlatformException catch (e) {
      if (!e.message.toString().toLowerCase().contains('cancel') && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${e.message ?? e.code}')));
      }
    } finally {
      await scanner.close();
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _submit() async {
    if (_paths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Scan or select at least one answer sheet.')));
      return;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Submit answer sheets?'),
            content: Text(
                '${_paths.length} file(s) will be submitted to your teacher.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Submit')),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    setState(() => _submitting = true);
    try {
      await AssessmentApi.submitOffline(widget.assessment.id, _paths);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Answer sheets submitted successfully.')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Submit Written Test')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            color: const Color(0xFFEFF4FF),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.assessment.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 4),
                Text(
                    '${widget.assessment.subjectName} · ${widget.assessment.totalMarks.g} marks'),
                if (widget.assessment.endsAt != null)
                  Text(
                      'Due ${DateFormat('dd MMM, hh:mm a').format(widget.assessment.endsAt!)}'),
              ],
            ),
          ),
          Expanded(
            child: _paths.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(30),
                      child: Text(
                        'Use the document scanner for a clean multi-page PDF, or select existing PDF/images.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _paths.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final value = _paths.removeAt(oldIndex);
                        _paths.insert(newIndex, value);
                      });
                    },
                    itemBuilder: (context, index) {
                      final path = _paths[index];
                      return Card(
                        key: ValueKey('$path-$index'),
                        child: ListTile(
                          leading: CircleAvatar(child: Text('${index + 1}')),
                          title: Text(path.split(Platform.pathSeparator).last,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: const Text('Drag to change order'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: () => setState(() => _paths.removeAt(index)),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (!kIsWeb && Platform.isAndroid) ...[
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _scanning ? null : _scan,
                            icon: const Icon(Icons.document_scanner_outlined),
                            label: Text(_scanning ? 'Scanning…' : 'Scan'),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickFiles,
                          icon: const Icon(Icons.attach_file),
                          label: const Text('Select Files'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.cloud_upload_outlined),
                      label: Text(_submitting
                          ? 'Submitting…'
                          : 'Submit ${_paths.length} File(s)'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
