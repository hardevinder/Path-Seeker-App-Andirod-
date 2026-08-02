import 'dart:async';

import 'package:flutter/material.dart';

import '../models/assessment_models.dart';
import '../services/assessment_api.dart';

class AssessmentAttemptScreen extends StatefulWidget {
  final Assessment assessment;
  const AssessmentAttemptScreen({super.key, required this.assessment});

  @override
  State<AssessmentAttemptScreen> createState() =>
      _AssessmentAttemptScreenState();
}

class _AssessmentAttemptScreenState extends State<AssessmentAttemptScreen> {
  Assessment? _assessment;
  AssessmentAttempt? _attempt;
  final Map<int, dynamic> _values = {};
  final Map<int, TextEditingController> _textControllers = {};
  Timer? _timer;
  Timer? _autosave;
  int? _remainingSeconds;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final result = await AssessmentApi.startAttempt(widget.assessment.id);
      _assessment = result.assessment;
      _attempt = result.attempt;
      for (final question in result.assessment.questions) {
        _textControllers[question.id] = TextEditingController();
      }
      for (final answer in result.assessment.enrollment?.latestAttempt?.answers ??
          const <AssessmentAnswer>[]) {
        _values[answer.questionId] =
            answer.answerText.isNotEmpty ? answer.answerText : answer.answerValue;
        _textControllers[answer.questionId]?.text = answer.answerText;
      }
      _startTimers();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startTimers() {
    final assessment = _assessment;
    final attempt = _attempt;
    if (assessment == null || attempt == null) return;
    if (assessment.durationMinutes != null) {
      void tick() {
        final deadline = attempt.startedAt
            .add(Duration(minutes: assessment.durationMinutes!));
        final seconds = deadline.difference(DateTime.now()).inSeconds;
        if (!mounted) return;
        setState(() => _remainingSeconds = seconds.clamp(0, 999999).toInt());
        if (seconds <= 0 && !_submitting) _submit(auto: true);
      }

      tick();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    }
    _autosave = Timer.periodic(const Duration(seconds: 20), (_) => _save());
  }

  List<Map<String, dynamic>> _answers() => (_assessment?.questions ?? [])
      .map((q) {
        final value = _values[q.id];
        if (const ['mcq', 'true_false'].contains(q.type)) {
          return {'question_id': q.id, 'answer_value': value};
        }
        return {
          'question_id': q.id,
          'answer_text': value?.toString() ?? '',
          if (q.type == 'fill_blank') 'answer_value': value?.toString() ?? '',
        };
      })
      .toList();

  Future<void> _save() async {
    if (_attempt == null || _assessment == null || _submitting) return;
    try {
      await AssessmentApi.saveAnswers(
          _assessment!.id, _attempt!.id, _answers());
    } catch (_) {}
  }

  Future<void> _submit({bool auto = false}) async {
    if (_attempt == null || _assessment == null || _submitting) return;
    if (!auto) {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Submit assessment?'),
              content: const Text(
                  'Your answers will be submitted for evaluation.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Continue Test')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Submit')),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }
    setState(() => _submitting = true);
    try {
      await AssessmentApi.submitOnline(
          _assessment!.id, _attempt!.id, _answers());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Assessment submitted successfully.')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _autosave?.cancel();
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _timeLabel() {
    final seconds = _remainingSeconds;
    if (seconds == null) return '';
    final minutes = seconds ~/ 60;
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final assessment = _assessment;
    return Scaffold(
      appBar: AppBar(
        title: Text(assessment?.title ?? widget.assessment.title),
        actions: [
          if (_remainingSeconds != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Chip(
                  avatar: const Icon(Icons.timer_outlined, size: 18),
                  label: Text(_timeLabel(),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: (_remainingSeconds ?? 999) < 60
                              ? Colors.red
                              : null)),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      color: const Color(0xFFEFF4FF),
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        assessment?.instructions.isNotEmpty == true
                            ? assessment!.instructions
                            : 'Attempt all questions. Answers save automatically.',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: assessment?.questions.length ?? 0,
                        itemBuilder: (context, index) {
                          final question = assessment!.questions[index];
                          return _questionCard(question, index);
                        },
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _submitting ? null : _save,
                                icon: const Icon(Icons.save_outlined),
                                label: const Text('Save Progress'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed:
                                    _submitting ? null : () => _submit(),
                                icon: _submitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Icon(Icons.send_rounded),
                                label: Text(
                                    _submitting ? 'Submitting…' : 'Submit'),
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

  Widget _questionCard(AssessmentQuestion question, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text('Q${index + 1}. ${question.text}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                Text('${question.marks.g} marks',
                    style: const TextStyle(color: Colors.black54)),
              ],
            ),
            const SizedBox(height: 12),
            if (const ['mcq', 'true_false'].contains(question.type))
              ...question.options.asMap().entries.map((entry) => RadioListTile<int>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.value),
                    value: entry.key,
                    groupValue: _values[question.id] is int
                        ? _values[question.id] as int
                        : int.tryParse('${_values[question.id]}'),
                    onChanged: (value) {
                      setState(() => _values[question.id] = value);
                    },
                  ))
            else
              TextField(
                controller: _textControllers[question.id],
                minLines: question.type == 'long' ? 5 : 2,
                maxLines: question.type == 'long' ? 10 : 5,
                decoration: InputDecoration(
                  hintText: question.type == 'fill_blank'
                      ? 'Enter the missing word or phrase'
                      : 'Write your answer',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => _values[question.id] = value,
              ),
          ],
        ),
      ),
    );
  }
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
