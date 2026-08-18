import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/teacher_performance_api.dart';

class TeacherPerformanceScreen extends StatefulWidget {
  const TeacherPerformanceScreen({super.key});
  @override
  State<TeacherPerformanceScreen> createState() =>
      _TeacherPerformanceScreenState();
}

class _TeacherPerformanceScreenState extends State<TeacherPerformanceScreen> {
  bool _loading = true;
  bool _aiBusy = false;
  String? _error;
  Map<String, dynamic> _data = {};
  List<dynamic> _trend = [];
  String _insight = '';
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  String get _monthText =>
      '${_month.year.toString().padLeft(4, '0')}-${_month.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _data = await TeacherPerformanceApi.myDashboard(month: _monthText);
      _trend = await TeacherPerformanceApi.trend(month: _monthText);
      _insight = '';
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(DateTime.now().year - 3, 1),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      helpText: 'Select any date in the month',
    );
    if (picked == null) return;
    _month = DateTime(picked.year, picked.month);
    await _load();
  }

  Future<void> _generateInsight() async {
    setState(() {
      _aiBusy = true;
      _error = null;
    });
    try {
      final r = await TeacherPerformanceApi.aiInsight(month: _monthText);
      final insight = r['insight'];
      _insight = insight is Map ? (insight['text']?.toString() ?? '') : '';
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Color _scoreColor(double score) {
    if (score >= 85) return Colors.green.shade700;
    if (score >= 70) return Colors.blue.shade700;
    if (score >= 55) return Colors.orange.shade800;
    return Colors.red.shade700;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Professional Growth'),
        actions: [
          IconButton(
              onPressed: _pickMonth,
              icon: const Icon(Icons.calendar_month_rounded),
              tooltip: _monthText),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12)),
                      child: Text(_error!,
                          style: TextStyle(color: Colors.red.shade800)),
                    ),
                  _scoreCard(),
                  const SizedBox(height: 16),
                  _teachingResultCard(),
                  const SizedBox(height: 16),
                  Text('Component Breakdown',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ...((_data['components'] is List
                          ? List<dynamic>.from(_data['components'])
                          : <dynamic>[])
                      .map((raw) => _componentCard(
                          Map<String, dynamic>.from(raw as Map)))),
                  const SizedBox(height: 16),
                  _trendCard(),
                  const SizedBox(height: 16),
                  _aiCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _scoreCard() {
    final score = double.tryParse('${_data['overall_score'] ?? 0}') ?? 0;
    final delta =
        double.tryParse('${_data['delta_from_previous_snapshot'] ?? 0}') ?? 0;
    final coverage = double.tryParse('${_data['coverage_percent'] ?? 0}') ?? 0;
    final teacher = _data['teacher'] is Map
        ? Map<String, dynamic>.from(_data['teacher'] as Map)
        : <String, dynamic>{};
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Text(teacher['name']?.toString() ?? 'Teacher',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text('${teacher['designation'] ?? 'Teacher'} • $_monthText',
                style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 18),
            Text(score.toStringAsFixed(1),
                style: TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w800,
                    color: _scoreColor(score))),
            const Text('/ 100', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
                '${delta > 0 ? '▲' : delta < 0 ? '▼' : '•'} ${delta.abs().toStringAsFixed(1)} from previous snapshot',
                style: TextStyle(
                    color: delta > 0
                        ? Colors.green
                        : delta < 0
                            ? Colors.red
                            : Colors.grey.shade700)),
            const SizedBox(height: 12),
            LinearProgressIndicator(
                value: (coverage / 100).clamp(0, 1),
                minHeight: 8,
                borderRadius: BorderRadius.circular(6)),
            const SizedBox(height: 6),
            Text(
                'Evidence coverage ${coverage.toStringAsFixed(1)}%${_data['provisional'] == true ? ' • Provisional' : ''}',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _componentCard(Map<String, dynamic> c) {
    final applicable = c['applicable'] == true && c['score'] != null;
    final score = applicable ? (double.tryParse('${c['score']}') ?? 0.0) : 0.0;
    final reasons =
        c['reasons'] is List ? List<dynamic>.from(c['reasons']) : <dynamic>[];
    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(
                    c['label']?.toString() ?? c['code']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            Text(applicable ? score.toStringAsFixed(1) : 'N/A',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: applicable ? _scoreColor(score) : Colors.grey)),
          ]),
          Text('Weight ${c['weight'] ?? 0}%',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 8),
          LinearProgressIndicator(
              value: applicable ? (score / 100).clamp(0, 1) : 0,
              minHeight: 6,
              borderRadius: BorderRadius.circular(5)),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(reasons.first.toString(),
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12))
          ],
        ]),
      ),
    );
  }


  Widget _metricBox(String label, String value, {String? note}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          if ((note ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(note!, style: TextStyle(fontSize: 10, color: Colors.grey.shade600), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ]),
      ),
    );
  }

  Widget _teachingResultCard() {
    final raw = _data['teaching_result'];
    final analytics = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final applicable = analytics['applicable'] == true;
    final summary = analytics['summary'] is Map ? Map<String, dynamic>.from(analytics['summary'] as Map) : <String, dynamic>{};
    final groups = analytics['groups'] is List ? List<dynamic>.from(analytics['groups']) : <dynamic>[];
    if (!applicable || groups.isEmpty) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.insights_rounded, color: Colors.blue.shade700),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Teaching Result & Student Growth', style: TextStyle(fontWeight: FontWeight.w800)),
              SizedBox(height: 4),
              Text('Graphs will appear after at least two comparable results exist for the same class, section and subject.'),
            ])),
          ]),
        ),
      );
    }

    final group = Map<String, dynamic>.from(groups.first as Map);
    final timeline = group['timeline'] is List ? List<dynamic>.from(group['timeline']) : <dynamic>[];
    final spots = <FlSpot>[];
    for (var i = 0; i < timeline.length; i++) {
      final row = Map<String, dynamic>.from(timeline[i] as Map);
      final avg = double.tryParse('${row['average'] ?? 0}') ?? 0;
      spots.add(FlSpot(i.toDouble(), avg.clamp(0, 100).toDouble()));
    }
    final score = double.tryParse('${analytics['teaching_score'] ?? 0}') ?? 0;
    final growth = double.tryParse('${summary['growth_points'] ?? 0}') ?? 0;
    final pass = double.tryParse('${summary['latest_pass_percent'] ?? 0}') ?? 0;
    final passBenchmark = double.tryParse('${analytics['pass_benchmark'] ?? 40}') ?? 40;
    final improved = int.tryParse('${summary['improved_students'] ?? 0}') ?? 0;
    final recovered = int.tryParse('${summary['recovered_students'] ?? 0}') ?? 0;
    final improvedCount = int.tryParse('${group['improved_students'] ?? 0}') ?? 0;
    final stableCount = int.tryParse('${group['stable_students'] ?? 0}') ?? 0;
    final declinedCount = int.tryParse('${group['declined_students'] ?? 0}') ?? 0;
    final totalMix = [improvedCount, stableCount, declinedCount].fold<int>(0, (a, b) => a + b);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Teaching Result & Student Growth', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text('Formal exams + Smart Assessments', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: _scoreColor(score).withOpacity(0.10), borderRadius: BorderRadius.circular(20)),
              child: Text('${score.toStringAsFixed(1)}/100', style: TextStyle(fontWeight: FontWeight.w800, color: _scoreColor(score))),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            _metricBox('Growth', '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(1)} pts', note: 'same-student'),
            const SizedBox(width: 8),
            _metricBox('Pass Rate', '${pass.toStringAsFixed(1)}%', note: 'latest'),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _metricBox('Improved', '$improved', note: 'student records'),
            const SizedBox(width: 8),
            _metricBox('Recovered', '$recovered', note: 'below ${passBenchmark.toStringAsFixed(0)}% → benchmark'),
          ]),
          const SizedBox(height: 18),
          Text('${group['class_name'] ?? 'Class'}${(group['section_name'] ?? '').toString().isNotEmpty ? '-${group['section_name']}' : ''} • ${group['subject_name'] ?? 'Subject'}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Learning Growth Trend', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 10),
          if (spots.length >= 2)
            SizedBox(
              height: 190,
              child: LineChart(LineChartData(
                minY: 0,
                maxY: 100,
                gridData: FlGridData(show: true, horizontalInterval: 20),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 34, interval: 20, getTitlesWidget: (v, meta) => Text('${v.toInt()}%', style: const TextStyle(fontSize: 9)))),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 38, interval: 1, getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (i < 0 || i >= timeline.length) return const SizedBox.shrink();
                    final row = Map<String, dynamic>.from(timeline[i] as Map);
                    final label = (row['label'] ?? '').toString();
                    return Padding(padding: const EdgeInsets.only(top: 6), child: Text(label.length > 8 ? '${label.substring(0, 8)}…' : label, style: const TextStyle(fontSize: 9)));
                  })),
                ),
                lineTouchData: LineTouchData(touchTooltipData: LineTouchTooltipData(getTooltipItems: (items) => items.map((item) {
                  final i = item.x.toInt();
                  final row = i >= 0 && i < timeline.length ? Map<String, dynamic>.from(timeline[i] as Map) : <String, dynamic>{};
                  return LineTooltipItem('${row['label'] ?? ''}\n${item.y.toStringAsFixed(1)}% • ${row['date'] ?? ''}', const TextStyle(color: Colors.white, fontWeight: FontWeight.w600));
                }).toList())),
                lineBarsData: [LineChartBarData(spots: spots, isCurved: true, barWidth: 3, dotData: const FlDotData(show: true))],
              )),
            ),
          if (totalMix > 0) ...[
            const SizedBox(height: 16),
            const Text('Student Progress Mix', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Row(children: [
                if (improvedCount > 0) Expanded(flex: improvedCount, child: Container(height: 12, color: Colors.green.shade600)),
                if (stableCount > 0) Expanded(flex: stableCount, child: Container(height: 12, color: Colors.blue.shade500)),
                if (declinedCount > 0) Expanded(flex: declinedCount, child: Container(height: 12, color: Colors.orange.shade600)),
              ]),
            ),
            const SizedBox(height: 6),
            Text('Improved $improvedCount  •  Stable $stableCount  •  Needs support $declinedCount', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          ],
        ]),
      ),
    );
  }

  Widget _trendCard() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Score Movement',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (_trend.isEmpty)
            const Text('Trend will build automatically as snapshots are saved.')
          else
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _trend.take(20).map((raw) {
                  final r = Map<String, dynamic>.from(raw as Map);
                  final s = double.tryParse('${r['overall_score'] ?? 0}') ?? 0;
                  return Expanded(
                      child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Tooltip(
                      message: '${r['snapshot_date']}: ${s.toStringAsFixed(1)}',
                      child: Container(
                          height: 15 + (s.clamp(0, 100) / 100) * 90,
                          decoration: BoxDecoration(
                              color: _scoreColor(s),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4)))),
                    ),
                  ));
                }).toList(),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _aiCard() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
                child: Text('AI Growth Insight',
                    style: TextStyle(fontWeight: FontWeight.w700))),
            TextButton.icon(
                onPressed: _aiBusy ? null : _generateInsight,
                icon: _aiBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome_rounded),
                label: const Text('Generate')),
          ]),
          Text(_insight.isEmpty
              ? 'AI explains strengths and next actions from your ERP evidence. It never changes your score.'
              : _insight),
        ]),
      ),
    );
  }
}
