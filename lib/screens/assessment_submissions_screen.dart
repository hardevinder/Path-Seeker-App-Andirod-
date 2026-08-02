import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
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

class _AssessmentSubmissionsScreenState
    extends State<AssessmentSubmissionsScreen> {
  List<AssessmentSubmission> _rows = [];
  bool _loading = true;

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

  Future<void> _evaluate(AssessmentSubmission row) async {
    final marks = TextEditingController(text: '${row.obtainedMarks ?? 0}');
    final feedback = TextEditingController(text: row.feedback ?? '');
    final corrected = <String>[];
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Evaluate ${row.studentName}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (row.latestAttempt != null)
                    Wrap(
                      spacing: 8,
                      children: row.latestAttempt!.files
                          .map((file) => ActionChip(
                                avatar: const Icon(Icons.visibility, size: 18),
                                label: Text(file.name),
                                onPressed: () => AssessmentApi.downloadAndOpen(
                                    '/api/assessments/${widget.assessment.id}/files/${file.id}',
                                    file.name),
                              ))
                          .toList(),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: marks,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText:
                          'Marks out of ${widget.assessment.totalMarks.g}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: feedback,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Teacher feedback',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final files = await openFiles(
                        acceptedTypeGroups: const [
                          XTypeGroup(
                            label: 'Corrected sheets',
                            extensions: ['pdf', 'jpg', 'jpeg', 'png'],
                          )
                        ],
                      );
                      setDialogState(() {
                        corrected
                          ..clear()
                          ..addAll(files.map((f) => f.path));
                      });
                    },
                    icon: const Icon(Icons.attach_file),
                    label: Text(corrected.isEmpty
                        ? 'Attach Corrected Sheet'
                        : '${corrected.length} file(s) attached'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () async {
                  try {
                    await AssessmentApi.grade(
                      assessmentId: widget.assessment.id,
                      studentId: row.studentId,
                      obtainedMarks: double.tryParse(marks.text) ?? 0,
                      feedback: feedback.text.trim(),
                      correctedPaths: corrected,
                    );
                    if (context.mounted) Navigator.pop(context, true);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(e.toString())));
                    }
                  }
                },
                child: const Text('Save Marks')),
          ],
        ),
      ),
    );
    marks.dispose();
    feedback.dispose();
    if (saved == true) {
      _snack('Evaluation saved.');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Submissions'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: _rows.length,
              itemBuilder: (context, index) {
                final row = _rows[index];
                final submitted = row.latestAttempt != null;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(row.studentName.isEmpty
                          ? '?'
                          : row.studentName[0].toUpperCase()),
                    ),
                    title: Text(row.studentName,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([
                      if (row.admissionNumber.isNotEmpty)
                        'Adm. ${row.admissionNumber}',
                      row.status.replaceAll('_', ' '),
                      if (row.submittedAt != null)
                        DateFormat('dd MMM, hh:mm a')
                            .format(row.submittedAt!),
                    ].join(' · ')),
                    trailing: submitted
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(row.obtainedMarks == null
                                  ? 'Pending'
                                  : '${row.obtainedMarks}/${widget.assessment.totalMarks.g}'),
                              const SizedBox(height: 4),
                              const Text('Tap to evaluate',
                                  style: TextStyle(
                                      color: Colors.blue, fontSize: 11)),
                            ],
                          )
                        : const Chip(label: Text('Not submitted')),
                    onTap: submitted ? () => _evaluate(row) : null,
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          try {
            await AssessmentApi.action(
                widget.assessment.id, 'results/publish');
            _snack('Evaluated results published to students and parents.');
          } catch (e) {
            _snack(e.toString());
          }
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
