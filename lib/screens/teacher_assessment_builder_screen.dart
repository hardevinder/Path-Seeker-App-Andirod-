import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models/assessment_models.dart';
import '../services/assessment_api.dart';

class TeacherAssessmentBuilderScreen extends StatefulWidget {
  final Assessment? existing;
  final int? onlineClassId;
  final String? initialAssessmentType;
  const TeacherAssessmentBuilderScreen({
    super.key,
    this.existing,
    this.onlineClassId,
    this.initialAssessmentType,
  });

  @override
  State<TeacherAssessmentBuilderScreen> createState() =>
      _TeacherAssessmentBuilderScreenState();
}

class _TeacherAssessmentBuilderScreenState
    extends State<TeacherAssessmentBuilderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _topic = TextEditingController();
  final _instructions = TextEditingController(text: 'Attempt all questions.');
  final _marks = TextEditingController(text: '20');
  final _duration = TextEditingController(text: '30');
  final _attempts = TextEditingController(text: '1');
  final _questionCount = TextEditingController(text: '10');
  final _onlineClass = TextEditingController();
  List<Map<String, dynamic>> _options = [];
  List<Map<String, dynamic>> _questions = [];
  int? _classId;
  int? _sectionId;
  int? _subjectId;
  String _mode = 'online';
  String _assessmentType = 'test';
  String _publishTrigger = 'manual';
  String _resultRelease = 'manual';
  String? _questionPaperPath;
  bool _randomizeQuestions = false;
  bool _randomizeOptions = false;
  bool _loading = true;
  bool _saving = false;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing == null &&
        const ['quiz', 'test', 'assignment', 'practice']
            .contains(widget.initialAssessmentType)) {
      _assessmentType = widget.initialAssessmentType!;
      if (_assessmentType == 'assignment') {
        _mode = 'offline';
        _instructions.text =
            'Complete the assignment and upload clear scanned pages or a PDF.';
      }
    }
    _onlineClass.text = '${widget.onlineClassId ?? existing?.onlineClassId ?? ''}';
    if (existing != null) {
      _title.text = existing.title;
      _topic.text = existing.description;
      _instructions.text = existing.instructions;
      _marks.text = '${existing.totalMarks}';
      _duration.text = '${existing.durationMinutes ?? 30}';
      _attempts.text = '${existing.maxAttempts}';
      _classId = existing.classId;
      _sectionId = existing.sectionId;
      _subjectId = existing.subjectId;
      _mode = existing.mode;
      _assessmentType = existing.assessmentType;
      _publishTrigger = existing.publishTrigger;
      _resultRelease = existing.resultRelease;
      _questions = existing.questions.map((q) => q.toDraftJson()).toList();
      _questionCount.text = '${_questions.isEmpty ? 10 : _questions.length}';
    }
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      _options = await AssessmentApi.options();
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  List<Map<String, dynamic>> _unique(String idKey, String nameKey,
      {int? classId, int? sectionId}) {
    final seen = <int>{};
    final rows = <Map<String, dynamic>>[];
    for (final row in _options) {
      if (classId != null && _asInt(row['class_id']) != classId) continue;
      if (sectionId != null && _asInt(row['section_id']) != sectionId) continue;
      final id = _asInt(row[idKey]);
      if (id <= 0 || !seen.add(id)) continue;
      rows.add({'id': id, 'name': row[nameKey]?.toString() ?? '#$id'});
    }
    return rows;
  }

  Future<void> _generateAi() async {
    if (_classId == null || _subjectId == null || _title.text.trim().isEmpty) {
      _snack('Select class and subject, then enter a title.');
      return;
    }
    setState(() => _generating = true);
    try {
      final result = await AssessmentApi.generateAi({
        'class_id': _classId,
        if (_sectionId != null) 'section_id': _sectionId,
        'subject_id': _subjectId,
        'title': _title.text.trim(),
        'topic': _topic.text.trim(),
        'total_marks': double.tryParse(_marks.text) ?? 20,
        'duration_minutes': int.tryParse(_duration.text) ?? 30,
        'question_count': int.tryParse(_questionCount.text) ?? 10,
        'question_types': ['mcq', 'true_false', 'fill_blank', 'short', 'long'],
        'language': 'English',
      });
      setState(() {
        _title.text = result['title']?.toString() ?? _title.text;
        _topic.text = result['description']?.toString() ?? _topic.text;
        _instructions.text =
            result['instructions']?.toString() ?? _instructions.text;
        final raw = result['questions'];
        _questions = raw is List
            ? raw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : [];
      });
      _snack('AI draft generated. Review every question before publishing.');
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _pickQuestionPaper() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Question paper',
          extensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'],
        )
      ],
    );
    if (file != null && file.path.isNotEmpty) {
      setState(() => _questionPaperPath = file.path);
    }
  }

  void _addQuestion() {
    setState(() => _questions.add({
          'question_type': 'mcq',
          'question_text': '',
          'options': ['', '', '', ''],
          'correct_answer': 0,
          'marks': 1,
          'difficulty': 'medium',
        }));
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_classId == null || _subjectId == null) {
      _snack('Select class and subject.');
      return;
    }
    if (_mode == 'online' && _questions.isEmpty) {
      _snack('Online tests require at least one question.');
      return;
    }
    if (_mode == 'offline' &&
        _questions.isEmpty &&
        (_questionPaperPath?.isEmpty ?? true) &&
        widget.existing == null) {
      _snack('Upload a question paper or add questions.');
      return;
    }
    setState(() => _saving = true);
    try {
      await AssessmentApi.save(
        id: widget.existing?.id,
        questionPaperPath: _questionPaperPath,
        fields: {
          'online_class_id': _onlineClass.text.trim(),
          'class_id': _classId,
          'section_id': _sectionId ?? '',
          'subject_id': _subjectId,
          'title': _title.text.trim(),
          'description': _topic.text.trim(),
          'instructions': _instructions.text.trim(),
          'assessment_type': _assessmentType,
          'mode': _mode,
          'total_marks': double.tryParse(_marks.text) ?? 0,
          'duration_minutes': int.tryParse(_duration.text) ?? 30,
          'publish_trigger': _publishTrigger,
          'max_attempts': int.tryParse(_attempts.text) ?? 1,
          'result_release': _resultRelease,
          'randomize_questions': _randomizeQuestions,
          'randomize_options': _randomizeOptions,
          'questions': _questions,
          'settings': <String, dynamic>{'created_from': 'mobile'},
        },
      );
      if (!mounted) return;
      _snack(widget.existing == null
          ? 'Assessment created.'
          : 'Assessment updated.');
      Navigator.pop(context, true);
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _topic.dispose();
    _instructions.dispose();
    _marks.dispose();
    _duration.dispose();
    _attempts.dispose();
    _questionCount.dispose();
    _onlineClass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final classes = _unique('class_id', 'class_name');
    final sections = _unique('section_id', 'section_name', classId: _classId);
    final subjects = _unique('subject_id', 'subject_name',
        classId: _classId, sectionId: _sectionId);
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.existing == null
              ? (_assessmentType == 'assignment'
                  ? 'Create Assignment'
                  : 'Create Assessment')
              : 'Edit Assessment')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _sectionTitle('Basic details'),
                  DropdownButtonFormField<int>(
                    value: _classId,
                    decoration: const InputDecoration(
                        labelText: 'Class', border: OutlineInputBorder()),
                    items: classes
                        .map((e) => DropdownMenuItem<int>(
                            value: e['id'] as int,
                            child: Text(e['name'].toString())))
                        .toList(),
                    onChanged: (value) => setState(() {
                      _classId = value;
                      _sectionId = null;
                      _subjectId = null;
                    }),
                    validator: (value) => value == null ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: sections.any((e) => e['id'] == _sectionId)
                        ? _sectionId
                        : null,
                    decoration: const InputDecoration(
                        labelText: 'Section (optional)',
                        border: OutlineInputBorder()),
                    items: sections
                        .map((e) => DropdownMenuItem<int>(
                            value: e['id'] as int,
                            child: Text(e['name'].toString())))
                        .toList(),
                    onChanged: (value) => setState(() {
                      _sectionId = value;
                      _subjectId = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: subjects.any((e) => e['id'] == _subjectId)
                        ? _subjectId
                        : null,
                    decoration: const InputDecoration(
                        labelText: 'Subject', border: OutlineInputBorder()),
                    items: subjects
                        .map((e) => DropdownMenuItem<int>(
                            value: e['id'] as int,
                            child: Text(e['name'].toString())))
                        .toList(),
                    onChanged: (value) => setState(() => _subjectId = value),
                    validator: (value) => value == null ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _title,
                    decoration: const InputDecoration(
                        labelText: 'Test title', border: OutlineInputBorder()),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _topic,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Topic / chapters',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _instructions,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Instructions',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _mode,
                        decoration: const InputDecoration(
                            labelText: 'Mode', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(
                              value: 'online', child: Text('Online test')),
                          DropdownMenuItem(
                              value: 'offline',
                              child: Text('Written / scanned')),
                        ],
                        onChanged: (v) => setState(() => _mode = v ?? 'online'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _assessmentType,
                        decoration: const InputDecoration(
                            labelText: 'Type', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'test', child: Text('Test')),
                          DropdownMenuItem(value: 'quiz', child: Text('Quiz')),
                          DropdownMenuItem(
                              value: 'assignment', child: Text('Assignment')),
                          DropdownMenuItem(
                              value: 'practice', child: Text('Practice')),
                        ],
                        onChanged: (v) => setState(
                            () => _assessmentType = v ?? 'test'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: _numberField(_marks, 'Total marks', decimal: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _numberField(_duration, 'Minutes')),
                    const SizedBox(width: 10),
                    Expanded(child: _numberField(_attempts, 'Attempts')),
                  ]),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _onlineClass,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Linked online class ID (optional)',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _publishTrigger,
                    decoration: const InputDecoration(
                        labelText: 'Publishing', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(
                          value: 'manual', child: Text('Save as draft')),
                      DropdownMenuItem(
                          value: 'immediate', child: Text('Publish immediately')),
                      DropdownMenuItem(
                          value: 'after_class',
                          child: Text('Publish when Zoom class ends')),
                    ],
                    onChanged: (v) => setState(
                        () => _publishTrigger = v ?? 'manual'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _resultRelease,
                    decoration: const InputDecoration(
                        labelText: 'Result release',
                        border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(
                          value: 'manual', child: Text('Teacher publishes')),
                      DropdownMenuItem(
                          value: 'immediate',
                          child: Text('Immediate if fully objective')),
                    ],
                    onChanged: (v) => setState(
                        () => _resultRelease = v ?? 'manual'),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Randomize questions'),
                    value: _randomizeQuestions,
                    onChanged: (v) => setState(() => _randomizeQuestions = v),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Randomize answer options'),
                    value: _randomizeOptions,
                    onChanged: (v) => setState(() => _randomizeOptions = v),
                  ),
                  if (_mode == 'offline') ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _pickQuestionPaper,
                      icon: const Icon(Icons.upload_file),
                      label: Text(_questionPaperPath == null
                          ? 'Upload Question Paper'
                          : _questionPaperPath!.split('/').last),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(child: _sectionTitle('Questions')),
                      SizedBox(
                        width: 72,
                        child: TextFormField(
                          controller: _questionCount,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Count', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: _generating ? null : _generateAi,
                        icon: const Icon(Icons.auto_awesome),
                        label: Text(_generating ? 'AI…' : 'AI Generate'),
                      ),
                    ],
                  ),
                  const Text(
                    'AI output is a draft. The teacher must review it before publishing.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  ..._questions.asMap().entries.map((entry) =>
                      _questionEditor(entry.key, entry.value)),
                  OutlinedButton.icon(
                    onPressed: _addQuestion,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Question'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text(_saving
                        ? 'Saving…'
                        : _assessmentType == 'assignment'
                            ? 'Save Assignment'
                            : 'Save Assessment'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _questionEditor(int index, Map<String, dynamic> question) {
    final type = question['question_type']?.toString() ?? 'mcq';
    final options = question['options'] is List
        ? List<String>.from((question['options'] as List).map((e) => '$e'))
        : <String>['', '', '', ''];
    while (type == 'mcq' && options.length < 4) options.add('');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(children: [
              Text('Question ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => setState(() => _questions.removeAt(index)),
              ),
            ]),
            DropdownButtonFormField<String>(
              value: type,
              decoration: const InputDecoration(
                  labelText: 'Question type', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'mcq', child: Text('MCQ')),
                DropdownMenuItem(
                    value: 'true_false', child: Text('True / False')),
                DropdownMenuItem(
                    value: 'fill_blank', child: Text('Fill in blank')),
                DropdownMenuItem(value: 'short', child: Text('Short answer')),
                DropdownMenuItem(value: 'long', child: Text('Long answer')),
              ],
              onChanged: (value) => setState(() {
                question['question_type'] = value;
                if (value == 'true_false') {
                  question['options'] = ['True', 'False'];
                  question['correct_answer'] = 0;
                }
              }),
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: question['question_text']?.toString() ?? '',
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Question', border: OutlineInputBorder()),
              onChanged: (v) => question['question_text'] = v,
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: '${question['marks'] ?? 1}',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Marks', border: OutlineInputBorder()),
              onChanged: (v) => question['marks'] = double.tryParse(v) ?? 1,
            ),
            if (const ['mcq', 'true_false'].contains(type)) ...[
              const SizedBox(height: 8),
              ...options.asMap().entries.map((entry) => Row(
                    children: [
                      Radio<int>(
                        value: entry.key,
                        groupValue: _asInt(question['correct_answer']),
                        onChanged: (v) =>
                            setState(() => question['correct_answer'] = v),
                      ),
                      Expanded(
                        child: TextFormField(
                          initialValue: entry.value,
                          readOnly: type == 'true_false',
                          decoration: InputDecoration(
                              labelText: 'Option ${entry.key + 1}'),
                          onChanged: (v) {
                            options[entry.key] = v;
                            question['options'] = options;
                          },
                        ),
                      ),
                    ],
                  )),
            ] else if (type == 'fill_blank') ...[
              const SizedBox(height: 8),
              TextFormField(
                initialValue: question['correct_answer'] is List
                    ? (question['correct_answer'] as List).join(', ')
                    : question['correct_answer']?.toString() ?? '',
                decoration: const InputDecoration(
                    labelText: 'Accepted answers, comma separated'),
                onChanged: (v) => question['correct_answer'] =
                    v.split(',').map((e) => e.trim()).toList(),
              ),
            ] else ...[
              const SizedBox(height: 8),
              TextFormField(
                initialValue: question['explanation']?.toString() ?? '',
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Answer key / marking guidance'),
                onChanged: (v) => question['explanation'] = v,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _numberField(TextEditingController controller, String label,
          {bool decimal = false}) =>
      TextFormField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration:
            InputDecoration(labelText: label, border: const OutlineInputBorder()),
      );

  Widget _sectionTitle(String title) => Text(title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800));
}

int _asInt(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;
