import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:intl/intl.dart';

import '../models/assessment_models.dart';
import '../services/assessment_api.dart';

class AssessmentSubmissionsScreen extends StatefulWidget {
  final Assessment assessment;
  const AssessmentSubmissionsScreen({super.key, required this.assessment});

  @override
  State<AssessmentSubmissionsScreen> createState() =>
      _AssessmentSubmissionsScreenState();
}

class _AssessmentSubmissionsScreenState extends State<AssessmentSubmissionsScreen> {
  List<AssessmentSubmission> _rows = [];
  bool _loading = true;
  int? _busyStudentId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rows = await AssessmentApi.submissions(widget.assessment.id);
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

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
        pageLimit: 10,
        isGalleryImport: false,
      ),
    );
    try {
      final result = await scanner.scanDocument();
      final path = _localPath(result.pdf?.uri.trim() ?? '');
      if (path.isNotEmpty && await File(path).exists()) return path;
    } on PlatformException catch (e) {
      if (!e.message.toString().toLowerCase().contains('cancel')) {
        _snack(e.message ?? e.code);
      }
    } finally {
      await scanner.close();
    }
    return null;
  }

  Future<void> _teacherScan(AssessmentSubmission row) async {
    String? path;
    if (!kIsWeb && Platform.isAndroid) {
      path = await _scanPdf();
    } else {
      final file = await openFile(
        acceptedTypeGroups: const [XTypeGroup(label: 'Answer sheet', extensions: ['pdf', 'jpg', 'jpeg', 'png'])],
      );
      path = file?.path;
    }
    if (path == null || path.isEmpty) return;

    setState(() => _busyStudentId = row.studentId);
    try {
      await AssessmentApi.teacherScan(
        assessmentId: widget.assessment.id,
        studentId: row.studentId,
        paths: [path],
        runAi: true,
      );
      _snack('Scan saved. AI suggestions prepared for teacher review.');
      await _load();
    } catch (e) {
      _snack(e.toString());
      await _load();
    } finally {
      if (mounted) setState(() => _busyStudentId = null);
    }
  }

  Future<void> _rerunAi(AssessmentSubmission row) async {
    setState(() => _busyStudentId = row.studentId);
    try {
      await AssessmentApi.rerunScanAi(widget.assessment.id, row.studentId);
      _snack('AI evaluation regenerated. Please review before saving.');
      await _load();
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busyStudentId = null);
    }
  }

  Future<void> _evaluate(AssessmentSubmission row) async {
    final attempt = row.latestAttempt;
    if (attempt == null) return;

    final marksByAnswer = <int, TextEditingController>{};
    final remarksByAnswer = <int, TextEditingController>{};
    for (final answer in attempt.answers) {
      marksByAnswer[answer.id] = TextEditingController(
        text: '${answer.awardedMarks ?? answer.aiAwardedMarks ?? 0}',
      );
      remarksByAnswer[answer.id] = TextEditingController(
        text: answer.teacherRemark.isNotEmpty ? answer.teacherRemark : answer.aiRemark,
      );
    }
    final initialTotal = attempt.answers.isNotEmpty
        ? attempt.answers.fold<double>(0, (sum, a) => sum + (a.awardedMarks ?? a.aiAwardedMarks ?? 0))
        : (row.obtainedMarks ?? 0);
    final marks = TextEditingController(text: '$initialTotal');
    final feedback = TextEditingController(
      text: row.feedback ?? attempt.aiSummary?['summary']?.toString() ?? '',
    );
    final corrected = <String>[];

    double calculatedTotal() => marksByAnswer.values.fold<double>(
        0, (sum, c) => sum + (double.tryParse(c.text) ?? 0));

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
          title: Text('Review ${row.studentName}'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _aiHeader(attempt),
                  if (attempt.files.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: attempt.files.map((file) => ActionChip(
                        avatar: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: Text(file.name),
                        onPressed: () => AssessmentApi.downloadAndOpen(
                          '/api/assessments/${widget.assessment.id}/files/${file.id}', file.name),
                      )).toList(),
                    ),
                  ],
                  if (attempt.aiSummary != null) _summaryCard(attempt),
                  if (attempt.answers.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Question-wise review', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 8),
                    ...attempt.answers.asMap().entries.map((entry) {
                      final index = entry.key;
                      final answer = entry.value;
                      final q = answer.question;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(child: Text('Q${index + 1}. ${q?.text ?? 'Question'}', style: const TextStyle(fontWeight: FontWeight.w700))),
                                if (answer.aiReviewRequired) const Chip(avatar: Icon(Icons.warning_amber, size: 16), label: Text('Review')),
                              ]),
                              if (answer.aiDetectedText.isNotEmpty) Padding(
                                padding: const EdgeInsets.only(top: 7),
                                child: Text('AI read: ${answer.aiDetectedText}', style: const TextStyle(color: Colors.black87)),
                              ),
                              if (answer.aiRemark.isNotEmpty) Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text('AI reason: ${answer.aiRemark}', style: const TextStyle(color: Colors.black54)),
                              ),
                              if (answer.aiConfidence != null) Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text('Confidence: ${answer.aiConfidence!.toStringAsFixed(0)}%'),
                              ),
                              const SizedBox(height: 10),
                              Row(children: [
                                SizedBox(
                                  width: 120,
                                  child: TextField(
                                    controller: marksByAnswer[answer.id],
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(labelText: 'Marks / ${q?.marks.g ?? '-'}', border: const OutlineInputBorder()),
                                    onChanged: (_) => setDialogState(() => marks.text = '${calculatedTotal()}'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: TextField(
                                  controller: remarksByAnswer[answer.id],
                                  decoration: const InputDecoration(labelText: 'Why marks cut / remark', border: OutlineInputBorder()),
                                )),
                              ]),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                  if (attempt.remedials.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('Small remedials', style: TextStyle(fontWeight: FontWeight.w800)),
                    ...attempt.remedials.map((r) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.auto_awesome_outlined),
                      title: Text(r['topic']?.toString().isNotEmpty == true ? r['topic'].toString() : 'Practice'),
                      subtitle: Text(r['action']?.toString() ?? ''),
                    )),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: marks,
                    readOnly: attempt.answers.isNotEmpty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Final marks / ${widget.assessment.totalMarks.g}', border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: feedback,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Overall feedback', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final files = await openFiles(acceptedTypeGroups: const [
                        XTypeGroup(label: 'Corrected sheets', extensions: ['pdf', 'jpg', 'jpeg', 'png'])
                      ]);
                      setDialogState(() { corrected..clear()..addAll(files.map((f) => f.path)); });
                    },
                    icon: const Icon(Icons.attach_file),
                    label: Text(corrected.isEmpty ? 'Attach corrected sheet' : '${corrected.length} file(s) attached'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (attempt.submissionSource != 'online')
              TextButton.icon(
                onPressed: () { Navigator.pop(context, false); _rerunAi(row); },
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Re-run AI'),
              ),
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: () async {
                try {
                  final answerGrades = attempt.answers.map((a) => {
                    'answer_id': a.id,
                    'awarded_marks': double.tryParse(marksByAnswer[a.id]?.text ?? '') ?? 0,
                    'teacher_remark': remarksByAnswer[a.id]?.text.trim() ?? '',
                  }).toList();
                  final total = attempt.answers.isNotEmpty ? calculatedTotal() : (double.tryParse(marks.text) ?? 0);
                  await AssessmentApi.grade(
                    assessmentId: widget.assessment.id,
                    studentId: row.studentId,
                    obtainedMarks: total,
                    feedback: feedback.text.trim(),
                    answerGrades: answerGrades,
                    correctedPaths: corrected,
                  );
                  if (context.mounted) Navigator.pop(context, true);
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                }
              },
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Approve & Save'),
            ),
          ],
        ),
      ),
    );

    for (final c in marksByAnswer.values) c.dispose();
    for (final c in remarksByAnswer.values) c.dispose();
    marks.dispose();
    feedback.dispose();
    if (saved == true) {
      _snack('Teacher evaluation approved and saved.');
      await _load();
    }
  }

  Widget _aiHeader(AssessmentAttempt attempt) {
    final status = attempt.aiEvaluationStatus.replaceAll('_', ' ');
    final confidence = attempt.aiConfidence;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF3F6FF), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome, color: Colors.indigo),
          const SizedBox(width: 8),
          Expanded(child: Text('AI evaluation: $status', style: const TextStyle(fontWeight: FontWeight.w800))),
          if (confidence != null) Text('${confidence.toStringAsFixed(0)}% confidence'),
        ]),
        if (attempt.teacherReviewRequired) const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Teacher approval required before result publishing.', style: TextStyle(color: Colors.deepOrange)),
        ),
      ]),
    );
  }

  Widget _summaryCard(AssessmentAttempt attempt) {
    final summary = attempt.aiSummary!;
    final strengths = summary['strengths'] is List ? List.from(summary['strengths']) : const [];
    final improve = summary['improvement_areas'] is List ? List.from(summary['improvement_areas']) : const [];
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if ((summary['summary']?.toString() ?? '').isNotEmpty) Text(summary['summary'].toString()),
          if (strengths.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Strengths: ${strengths.join(', ')}', style: const TextStyle(color: Colors.green))),
          if (improve.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text('Improve: ${improve.join(', ')}', style: const TextStyle(color: Colors.deepOrange))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student Test Papers'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: _rows.length,
              itemBuilder: (context, index) {
                final row = _rows[index];
                final attempt = row.latestAttempt;
                final busy = _busyStudentId == row.studentId;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      CircleAvatar(child: Text(row.studentName.isEmpty ? '?' : row.studentName[0].toUpperCase())),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(row.studentName, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text([
                          if (row.admissionNumber.isNotEmpty) 'Adm. ${row.admissionNumber}',
                          row.status.replaceAll('_', ' '),
                          if (row.submittedAt != null) DateFormat('dd MMM, hh:mm a').format(row.submittedAt!),
                        ].join(' · '), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                        if (attempt?.aiEvaluationStatus != null && attempt!.aiEvaluationStatus != 'not_started')
                          Text('AI: ${attempt.aiEvaluationStatus.replaceAll('_', ' ')}', style: const TextStyle(fontSize: 12, color: Colors.indigo)),
                      ])),
                      if (busy) const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) else ...[
                        IconButton(tooltip: 'Scan paper', onPressed: () => _teacherScan(row), icon: const Icon(Icons.document_scanner_outlined)),
                        if (attempt != null) IconButton(tooltip: 'Review result', onPressed: () => _evaluate(row), icon: const Icon(Icons.fact_check_outlined)),
                      ],
                    ]),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          try {
            await AssessmentApi.action(widget.assessment.id, 'results/publish');
            _snack('Approved results published to students and parents.');
          } catch (e) { _snack(e.toString()); }
        },
        icon: const Icon(Icons.publish),
        label: const Text('Publish Results'),
      ),
    );
  }
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
