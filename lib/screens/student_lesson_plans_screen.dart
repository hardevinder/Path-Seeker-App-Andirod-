// lib/screens/student_lesson_plans_screen.dart
import 'package:flutter/material.dart';

import '../models/student_lesson_plan_model.dart';
import '../services/student_lesson_plan_api.dart';
import '../widgets/student_drawer_menu.dart';

class StudentLessonPlansScreen extends StatefulWidget {
  const StudentLessonPlansScreen({super.key});

  @override
  State<StudentLessonPlansScreen> createState() =>
      _StudentLessonPlansScreenState();
}

class _StudentLessonPlansScreenState extends State<StudentLessonPlansScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  StudentLessonPlanStudent? _student;
  List<StudentLessonPlan> _plans = [];

  String _term = 'ALL';

  static const Color _primary = Color(0xFF4F46E5);
  static const Color _primary2 = Color(0xFF06B6D4);
  static const Color _bg = Color(0xFFF6F8FF);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final res = await StudentLessonPlanApi.fetchMyLessonPlans(
        term: _term == 'ALL' ? null : _term,
      );

      if (!mounted) return;
      setState(() {
        _student = res.student;
        _plans = res.lessonPlans;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  List<StudentLessonPlan> get _filteredPlans {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _plans;

    return _plans.where((p) {
      final blob = [
        p.subjectName,
        p.teacherName,
        p.topic,
        p.subtopic,
        p.specificObjectives,
        p.homework,
        p.activities,
        p.resources,
        p.assessmentPlan,
        p.weekStart,
        p.weekEnd,
        p.term,
      ].join(' ').toLowerCase();
      return blob.contains(q);
    }).toList();
  }

  void _showDetails(StudentLessonPlan plan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LessonPlanDetailSheet(plan: plan),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plans = _filteredPlans;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _bg,
      drawer: const StudentDrawerMenu(),
      appBar: AppBar(
        title: const Text('Weekly Learning Plan'),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            _heroCard(),
            const SizedBox(height: 14),
            _filtersCard(),
            const SizedBox(height: 14),
            if (_loading)
              const _LoadingCard()
            else if (_error != null)
              _ErrorCard(message: _error!, onRetry: _load)
            else if (plans.isEmpty)
              _EmptyCard(
                hasSearch: _searchCtrl.text.trim().isNotEmpty || _term != 'ALL',
                onClear: () {
                  _searchCtrl.clear();
                  setState(() => _term = 'ALL');
                  _load();
                },
              )
            else ...[
              _countRow(plans.length),
              const SizedBox(height: 10),
              ...plans.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _lessonPlanCard(p),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _heroCard() {
    final classLine = [
      _student?.className,
      _student?.sectionName,
    ].where((e) => (e ?? '').trim().isNotEmpty).join(' • ');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_primary, _primary2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.22),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -34,
            top: -42,
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.11),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.17),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.22)),
                ),
                child: const Icon(Icons.auto_stories_rounded,
                    color: Colors.white, size: 30),
              ),
              const SizedBox(height: 14),
              const Text(
                'Weekly Learning Plan',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                classLine.isEmpty
                    ? 'See what your teachers have planned for learning this week.'
                    : '$classLine • see what you will learn this week',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.88),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _heroChip(Icons.fact_check_rounded, '${_plans.length} Plans'),
                  if ((_student?.admissionNumber ?? '').isNotEmpty)
                    _heroChip(Icons.confirmation_number_outlined,
                        _student!.admissionNumber),
                  _heroChip(Icons.visibility_rounded, 'Published by teacher'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _filtersCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.tune_rounded, color: _primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Search & Filter',
                style: TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 16, color: _text),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search subject, topic, homework...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchCtrl.text.trim().isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _searchCtrl.clear,
                    ),
              filled: true,
              fillColor: const Color(0xFFF8FAFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _termChip('ALL', 'All'),
                _termChip('FULL_YEAR', 'Full Year'),
                _termChip('TERM1', 'Term 1'),
                _termChip('TERM2', 'Term 2'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _termChip(String value, String label) {
    final selected = _term == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _term = value);
          _load();
        },
        selectedColor: _primary.withOpacity(0.14),
        labelStyle: TextStyle(
          color: selected ? _primary : _muted,
          fontWeight: FontWeight.w800,
        ),
        side: BorderSide(
            color: selected
                ? _primary.withOpacity(0.35)
                : const Color(0xFFE5E7EB)),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }

  Widget _countRow(int count) {
    return Row(
      children: [
        const Text(
          'Available Plans',
          style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w900, color: _text),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count found',
            style: const TextStyle(
                color: _primary, fontWeight: FontWeight.w900, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _lessonPlanCard(StudentLessonPlan plan) {
    final objectivePreview = plan.specificObjectives.trim();
    final activityPreview = plan.activities.trim();

    return InkWell(
      onTap: () => _showDetails(plan),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _boxDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _primary.withOpacity(0.95),
                        _primary2.withOpacity(0.86)
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child:
                      const Icon(Icons.menu_book_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.subjectName.isEmpty ? 'Subject' : plan.subjectName,
                        style: const TextStyle(
                            color: _primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        plan.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _text,
                            fontSize: 16,
                            fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        plan.weekLabel,
                        style: const TextStyle(
                            color: _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: _muted),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _miniBadge(Icons.school_rounded,
                    plan.className.isEmpty ? 'Class' : plan.className),
                _miniBadge(Icons.groups_rounded, plan.sectionsLabel),
                if (plan.teacherName.isNotEmpty)
                  _miniBadge(Icons.person_rounded, plan.teacherName),
                _miniBadge(
                    Icons.calendar_month_rounded, _friendlyTerm(plan.term)),
              ],
            ),
            if (objectivePreview.isNotEmpty) ...[
              const SizedBox(height: 12),
              _previewBox(
                icon: Icons.flag_rounded,
                title: 'What you will learn',
                text: objectivePreview,
                color: const Color(0xFF2563EB),
                bg: const Color(0xFFEFF6FF),
                border: const Color(0xFFBFDBFE),
              ),
            ] else if (activityPreview.isNotEmpty) ...[
              const SizedBox(height: 12),
              _previewBox(
                icon: Icons.extension_rounded,
                title: 'Class activity',
                text: activityPreview,
                color: const Color(0xFF7C3AED),
                bg: const Color(0xFFF5F3FF),
                border: const Color(0xFFDDD6FE),
              ),
            ],
            if (plan.homework.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              _previewBox(
                icon: Icons.home_work_outlined,
                title: 'Homework',
                text: plan.homework,
                color: const Color(0xFFD97706),
                bg: const Color(0xFFFFFBEB),
                border: const Color(0xFFFDE68A),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _previewBox({
    required IconData icon,
    required String title,
    required String text,
    required Color color,
    required Color bg,
    required Color border,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: TextStyle(
                    color: color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.35),
                children: [
                  TextSpan(
                    text: '$title: ',
                    style: TextStyle(color: color, fontWeight: FontWeight.w900),
                  ),
                  TextSpan(text: text.trim()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _muted),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11.5, color: _muted, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _boxDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE8ECF5)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.045),
          blurRadius: 18,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }
}

class _LessonPlanDetailSheet extends StatelessWidget {
  final StudentLessonPlan plan;

  const _LessonPlanDetailSheet({
    required this.plan,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5).withOpacity(0.10),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.auto_stories_rounded,
                          color: Color(0xFF4F46E5)),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.subjectName.isEmpty
                                ? 'Learning Plan'
                                : plan.subjectName,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            plan.weekLabel,
                            style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
                  children: [
                    _infoCard(),
                    const SizedBox(height: 12),
                    _section('Topic', plan.title, Icons.topic_rounded),
                    _section('What you will learn', plan.specificObjectives,
                        Icons.flag_rounded),
                    _section('Class activities', plan.activities,
                        Icons.extension_rounded),
                    _section('Study resources', plan.resources,
                        Icons.library_books_rounded),
                    _section(
                        'Homework', plan.homework, Icons.home_work_rounded),
                    _section(
                      'Assessment / Test hint',
                      _assessmentText(plan),
                      Icons.assignment_turned_in_rounded,
                    ),
                    _StudentEvaluationsPanel(plan: plan),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _assessmentText(StudentLessonPlan plan) {
    final assessment = plan.assessmentPlan.trim();
    if (assessment.isNotEmpty) return assessment;

    final evaluation = plan.evaluationMethod.trim();
    if (evaluation.isNotEmpty) return evaluation;

    return '';
  }

  Widget _infoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _tag(Icons.school_rounded,
              plan.className.isEmpty ? 'Class' : plan.className),
          _tag(Icons.groups_rounded, plan.sectionsLabel),
          if (plan.teacherName.isNotEmpty)
            _tag(Icons.person_rounded, plan.teacherName),
          _tag(Icons.calendar_month_rounded, _friendlyTerm(plan.term)),
          if (plan.academicSession.isNotEmpty)
            _tag(Icons.history_edu_rounded, plan.academicSession),
        ],
      ),
    );
  }

  Widget _tag(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF4F46E5)),
          const SizedBox(width: 5),
          Text(text,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _section(String title, String value, IconData icon) {
    final text = value.trim();
    if (text.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8ECF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF4F46E5), size: 18),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: const TextStyle(
                height: 1.45, color: Color(0xFF374151), fontSize: 13.2),
          ),
        ],
      ),
    );
  }
}

class _StudentEvaluationsPanel extends StatefulWidget {
  final StudentLessonPlan plan;

  const _StudentEvaluationsPanel({required this.plan});

  @override
  State<_StudentEvaluationsPanel> createState() =>
      _StudentEvaluationsPanelState();
}

class _StudentEvaluationsPanelState extends State<_StudentEvaluationsPanel> {
  bool _loading = true;
  String? _error;
  List<StudentLessonPlanEvaluation> _evaluations = [];

  @override
  void initState() {
    super.initState();
    _evaluations = widget.plan.evaluations;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await StudentLessonPlanApi.fetchEvaluations(widget.plan.id);
      if (!mounted) return;
      setState(() {
        _evaluations = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _openEvaluation(StudentLessonPlanEvaluation evaluation) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StudentEvaluationSheet(seed: evaluation),
    );
  }

  Future<void> _openPdf(StudentLessonPlanEvaluation evaluation) async {
    try {
      await StudentLessonPlanApi.openEvaluationPdf(evaluation);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8ECF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.quiz_rounded,
                  color: Color(0xFF4F46E5),
                  size: 18,
                ),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Tests / Evaluations',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Reload',
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _softMessage(_error!, Icons.error_outline_rounded, Colors.red)
          else if (_evaluations.isEmpty)
            _softMessage(
              'No test published for this lesson yet.',
              Icons.assignment_outlined,
              const Color(0xFF64748B),
            )
          else
            ..._evaluations.map(_evaluationCard),
        ],
      ),
    );
  }

  Widget _evaluationCard(StudentLessonPlanEvaluation evaluation) {
    final result = evaluation.result;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  evaluation.displayTitle,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              _evalPill(evaluation.type.toUpperCase(), const Color(0xFF4F46E5)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _evalPill(
                'Marks: ${_formatNum(evaluation.effectiveTotalMarks)}',
                const Color(0xFFD97706),
              ),
              if (evaluation.timeMinutes != null)
                _evalPill(
                    '${evaluation.timeMinutes} min', const Color(0xFF64748B)),
              if (result?.marksObtained != null)
                _evalPill(
                  'Your Marks: ${_formatNum(result!.marksObtained)} / ${_formatNum(evaluation.effectiveTotalMarks)}${evaluation.percentage == null ? '' : ' (${_formatNum(evaluation.percentage)}%)'}',
                  const Color(0xFF16A34A),
                ),
              _evalPill(
                evaluation.answersVisibleToStudents
                    ? 'Answers Available'
                    : 'Answers Hidden',
                evaluation.answersVisibleToStudents
                    ? const Color(0xFFD97706)
                    : const Color(0xFF64748B),
              ),
            ],
          ),
          if ((result?.remark ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Text(
                'Remark: ${result!.remark}',
                style: const TextStyle(
                  color: Color(0xFF166534),
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _openEvaluation(evaluation),
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text('View Questions'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _openPdf(evaluation),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: const Text('PDF'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _softMessage(String text, IconData icon, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentEvaluationSheet extends StatefulWidget {
  final StudentLessonPlanEvaluation seed;

  const _StudentEvaluationSheet({required this.seed});

  @override
  State<_StudentEvaluationSheet> createState() =>
      _StudentEvaluationSheetState();
}

class _StudentEvaluationSheetState extends State<_StudentEvaluationSheet> {
  bool _loading = true;
  StudentLessonPlanEvaluation? _evaluation;

  @override
  void initState() {
    super.initState();
    _evaluation = widget.seed;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ev = await StudentLessonPlanApi.fetchEvaluation(widget.seed.id);
      if (mounted) setState(() => _evaluation = ev);
    } catch (_) {
      if (mounted) setState(() => _evaluation = widget.seed);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPdf() async {
    final ev = _evaluation;
    if (ev == null) return;
    try {
      await StudentLessonPlanApi.openEvaluationPdf(ev);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ev = _evaluation;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                child: Row(
                  children: [
                    const Icon(Icons.quiz_rounded, color: Color(0xFF4F46E5)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        ev?.displayTitle ?? 'Question Paper',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ev == null
                        ? const Center(
                            child: Text('Question paper not available.'))
                        : ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            children: [
                              Wrap(
                                spacing: 7,
                                runSpacing: 7,
                                children: [
                                  _evalPill(ev.type.toUpperCase(),
                                      const Color(0xFF4F46E5)),
                                  _evalPill(
                                    'Marks: ${_formatNum(ev.effectiveTotalMarks)}',
                                    const Color(0xFFD97706),
                                  ),
                                  if (ev.timeMinutes != null)
                                    _evalPill('${ev.timeMinutes} min',
                                        const Color(0xFF64748B)),
                                  if (ev.result?.marksObtained != null)
                                    _evalPill(
                                      'Your Marks: ${_formatNum(ev.result!.marksObtained)} / ${_formatNum(ev.effectiveTotalMarks)}',
                                      const Color(0xFF16A34A),
                                    ),
                                  _evalPill(
                                    ev.answersVisibleToStudents
                                        ? 'Answers Available'
                                        : 'Answers Hidden',
                                    ev.answersVisibleToStudents
                                        ? const Color(0xFFD97706)
                                        : const Color(0xFF64748B),
                                  ),
                                ],
                              ),
                              if (ev.instructions.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _infoMessage('Instructions', ev.instructions),
                              ],
                              if ((ev.result?.remark ?? '')
                                  .trim()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _infoMessage(
                                  'Teacher Remark',
                                  ev.result!.remark,
                                  color: const Color(0xFF16A34A),
                                  bg: const Color(0xFFF0FDF4),
                                  border: const Color(0xFFBBF7D0),
                                ),
                              ],
                              const SizedBox(height: 12),
                              if (ev.items.isEmpty)
                                _infoMessage('Questions', 'No questions found.')
                              else
                                ...ev.items.asMap().entries.map(
                                      (entry) => _QuestionCard(
                                        item: entry.value,
                                        index: entry.key,
                                        showAnswers:
                                            ev.answersVisibleToStudents,
                                      ),
                                    ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: _openPdf,
                                icon: const Icon(Icons.picture_as_pdf_rounded),
                                label: const Text('Open PDF'),
                              ),
                            ],
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoMessage(
    String title,
    String text, {
    Color color = const Color(0xFF2563EB),
    Color bg = const Color(0xFFEFF6FF),
    Color border = const Color(0xFFBFDBFE),
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(color: color, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(text,
              style: const TextStyle(height: 1.4, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final StudentLessonPlanEvaluationItem item;
  final int index;
  final bool showAnswers;

  const _QuestionCard({
    required this.item,
    required this.index,
    required this.showAnswers,
  });

  @override
  Widget build(BuildContext context) {
    final type = item.type.toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8ECF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Q${index + 1}. ${item.question.isEmpty ? 'Question' : item.question}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, height: 1.35),
                ),
              ),
              const SizedBox(width: 8),
              _evalPill(type, const Color(0xFF4F46E5)),
            ],
          ),
          const SizedBox(height: 8),
          _evalPill('${_formatNum(item.marks)} marks', const Color(0xFFD97706)),
          if (type == 'MCQ' && item.options.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...item.options.asMap().entries.map((entry) {
              final correct = showAnswers && item.correctIndex == entry.key;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: correct
                      ? const Color(0xFFF0FDF4)
                      : const Color(0xFFF8FAFF),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: correct
                        ? const Color(0xFF86EFAC)
                        : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: const Color(0xFFE0E7FF),
                      child: Text(
                        String.fromCharCode(65 + entry.key),
                        style: const TextStyle(
                          color: Color(0xFF4F46E5),
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                        child: Text(entry.value.isEmpty ? '-' : entry.value)),
                    if (correct)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.check_circle_rounded,
                            color: Color(0xFF16A34A), size: 18),
                      ),
                  ],
                ),
              );
            }),
          ],
          if (type != 'MCQ' && showAnswers && item.answerKey.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Text(
                'Answer Key\n${item.answerKey}',
                style: const TextStyle(
                  color: Color(0xFF166534),
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
          ],
          if (!showAnswers) ...[
            const SizedBox(height: 8),
            const Text(
              'Answer key will appear only when teacher allows it.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Widget _evalPill(String label, Color color) {
  final text = label.trim().isEmpty ? '-' : label.trim();
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withOpacity(0.12)),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

String _formatNum(num? value) {
  if (value == null) return '-';
  if (value == value.roundToDouble()) return '${value.toInt()}';
  return value.toStringAsFixed(1);
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _commonBox(),
      child: const Column(
        children: [
          CircularProgressIndicator(color: Color(0xFF4F46E5)),
          SizedBox(height: 14),
          Text('Loading learning plans...',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _commonBox(),
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded,
              color: Colors.red.shade600, size: 42),
          const SizedBox(height: 10),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final bool hasSearch;
  final VoidCallback onClear;

  const _EmptyCard({required this.hasSearch, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _commonBox(),
      child: Column(
        children: [
          Icon(Icons.auto_stories_outlined,
              size: 48, color: Colors.grey.shade500),
          const SizedBox(height: 12),
          Text(
            hasSearch
                ? 'No learning plan found for current filter.'
                : 'No learning plans shared yet.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            hasSearch
                ? 'Try clearing search/filter.'
                : 'When teachers share plans for your class, they will appear here.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
          ),
          if (hasSearch) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_rounded),
              label: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    );
  }
}

String _friendlyTerm(String term) {
  final t = term.trim().toUpperCase();

  if (t == 'TERM1') return 'Term 1';
  if (t == 'TERM2') return 'Term 2';
  if (t == 'FULL_YEAR') return 'Full Year';

  return term.trim().isEmpty ? 'Term' : term;
}

BoxDecoration _commonBox() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: const Color(0xFFE8ECF5)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.045),
        blurRadius: 18,
        offset: const Offset(0, 10),
      ),
    ],
  );
}
