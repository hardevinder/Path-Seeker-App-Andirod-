import 'package:flutter/material.dart';

import '../models/assessment_models.dart';
import '../services/assessment_api.dart';

class AssessmentResultScreen extends StatefulWidget {
  final Assessment assessment;
  const AssessmentResultScreen({super.key, required this.assessment});

  @override
  State<AssessmentResultScreen> createState() => _AssessmentResultScreenState();
}

class _AssessmentResultScreenState extends State<AssessmentResultScreen> {
  Assessment? _assessment;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _assessment = await AssessmentApi.detail(widget.assessment.id);
    } catch (_) {
      _assessment = widget.assessment;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final a = _assessment ?? widget.assessment;
    final e = a.enrollment;
    final attempt = e?.latestAttempt;
    final obtained = e?.obtainedMarks ?? attempt?.obtainedMarks ?? 0;
    final percentage = a.totalMarks > 0 ? (obtained / a.totalMarks * 100).clamp(0, 100).toDouble() : 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('Test Result')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(children: [
                Text(a.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text(a.subjectName, style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 18),
                SizedBox(
                  width: 150,
                  height: 150,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox.expand(child: CircularProgressIndicator(value: percentage / 100, strokeWidth: 14, backgroundColor: Colors.black12)),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('${percentage.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                      Text('${obtained.g}/${a.totalMarks.g}', style: const TextStyle(color: Colors.black54)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 10, children: [
                  Chip(label: Text('Grade ${e?.grade ?? '—'}')),
                  Chip(label: Text(a.mode == 'online' ? 'Online Test' : 'Scanned Test')),
                ]),
              ]),
            ),
          ),
          if ((e?.feedback ?? '').isNotEmpty) _section('Overall Feedback', Text(e!.feedback!)),
          if (attempt?.aiSummary != null) ...[
            if ((attempt!.aiSummary!['strengths'] as List?)?.isNotEmpty == true)
              _section('Strengths', _bulletList(List<String>.from(attempt.aiSummary!['strengths'] as List))),
            if ((attempt.aiSummary!['improvement_areas'] as List?)?.isNotEmpty == true)
              _section('Needs Improvement', _bulletList(List<String>.from(attempt.aiSummary!['improvement_areas'] as List))),
          ],
          if (attempt?.answers.isNotEmpty == true) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 12, 4, 8),
              child: Text('Question-wise Performance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            ...attempt!.answers.asMap().entries.map((entry) {
              final i = entry.key;
              final ans = entry.value;
              final max = ans.question?.marks ?? 0;
              final got = ans.awardedMarks ?? ans.aiAwardedMarks ?? 0;
              final ratio = max > 0 ? (got / max).clamp(0, 1).toDouble() : 0.0;
              final remark = ans.teacherRemark.isNotEmpty ? ans.teacherRemark : ans.aiRemark;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('Q${i + 1}. ${ans.question?.questionText ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700))),
                      Text('${got.g}/${max.g}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: ratio, minHeight: 8, borderRadius: BorderRadius.circular(8)),
                    if (remark.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(remark)),
                  ]),
                ),
              );
            }),
          ],
          if (attempt?.remedials.isNotEmpty == true)
            _section('Small Remedials', Column(children: attempt!.remedials.map((r) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.auto_awesome_outlined, size: 18)),
              title: Text(r['topic']?.toString().isNotEmpty == true ? r['topic'].toString() : 'Practice'),
              subtitle: Text(r['action']?.toString() ?? ''),
            )).toList())),
          if (attempt?.files.isNotEmpty == true) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 12, 4, 8),
              child: Text('Answer Sheet & Files', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            ...attempt!.files.where((f) => const ['student_submission', 'corrected_submission'].contains(f.kind)).map((file) => Card(
              child: ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: Text(file.name),
                subtitle: Text(file.kind == 'student_submission' ? 'Original scanned answer sheet' : 'Teacher feedback / corrected sheet'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => AssessmentApi.downloadAndOpen('/api/assessments/${a.id}/files/${file.id}', file.name),
              ),
            )),
          ],
        ],
      ),
    );
  }

  Widget _section(String title, Widget child) => Card(
    margin: const EdgeInsets.only(top: 10),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        child,
      ]),
    ),
  );

  Widget _bulletList(List<String> values) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: values.map((v) => Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  '), Expanded(child: Text(v))]),
    )).toList(),
  );
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toStringAsFixed(1);
}
