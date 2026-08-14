import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/student_health_api.dart';

class StudentHealthGrowthScreen extends StatefulWidget {
  const StudentHealthGrowthScreen({super.key});

  @override
  State<StudentHealthGrowthScreen> createState() =>
      _StudentHealthGrowthScreenState();
}

class _StudentHealthGrowthScreenState
    extends State<StudentHealthGrowthScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};

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
      final data = await StudentHealthApi.mine();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('StudentHealthApiException: ', '');
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _measurements {
    final raw = _data['measurements'];
    return raw is List
        ? raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> get _screenings {
    final raw = _data['screenings'];
    return raw is List
        ? raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
  }

  Map<String, dynamic> get _profile => _data['profile'] is Map
      ? Map<String, dynamic>.from(_data['profile'] as Map)
      : <String, dynamic>{};

  Map<String, dynamic> get _settings => _data['settings'] is Map
      ? Map<String, dynamic>.from(_data['settings'] as Map)
      : <String, dynamic>{};

  double? _num(dynamic v) {
    if (v == null) return null;
    return double.tryParse(v.toString());
  }

  Widget _metric(String title, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 6),
            Text(value,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _trendChart({
    required String title,
    required String keyName,
    required String unit,
  }) {
    final rows = _measurements
        .where((m) => _num(m[keyName]) != null)
        .toList(growable: false);
    if (rows.length < 2) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Two or more measurements are needed for a trend.'),
            ],
          ),
        ),
      );
    }

    final spots = <FlSpot>[];
    for (var i = 0; i < rows.length; i++) {
      spots.add(FlSpot(i.toDouble(), _num(rows[i][keyName])!));
    }
    final values = spots.map((e) => e.y).toList();
    var minY = values.reduce((a, b) => a < b ? a : b);
    var maxY = values.reduce((a, b) => a > b ? a : b);
    if (maxY == minY) {
      minY -= 1;
      maxY += 1;
    } else {
      minY -= 2;
      maxY += 2;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            SizedBox(
              height: 210,
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        getTitlesWidget: (value, meta) => Text(
                          value.toStringAsFixed(0),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 34,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= rows.length) {
                            return const SizedBox.shrink();
                          }
                          final raw = rows[i]['measurement_date']?.toString();
                          DateTime? d = raw == null ? null : DateTime.tryParse(raw);
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              d == null ? '' : DateFormat('MMM').format(d),
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (items) => items
                          .map((item) => LineTooltipItem(
                                '${item.y.toStringAsFixed(1)} $unit',
                                const TextStyle(fontWeight: FontWeight.w700),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _familyUpdate() async {
    final allergy = TextEditingController(
        text: _profile['food_allergies']?.toString() ?? '');
    final medication = TextEditingController(
        text: _profile['emergency_medication_instructions']?.toString() ?? '');
    final phone = TextEditingController(
        text: _profile['emergency_contact_phone']?.toString() ?? '');
    final notes = TextEditingController(
        text: _profile['family_notes']?.toString() ?? '');

    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Family health update'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                  controller: allergy,
                  decoration:
                      const InputDecoration(labelText: 'Food allergies')),
              TextField(
                  controller: medication,
                  decoration: const InputDecoration(
                      labelText: 'Emergency medication / instructions')),
              TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration:
                      const InputDecoration(labelText: 'Emergency phone')),
              TextField(
                  controller: notes,
                  maxLines: 3,
                  decoration:
                      const InputDecoration(labelText: 'Family notes')),
              const SizedBox(height: 10),
              const Text(
                'Family updates remain marked as family-reported until the school verifies them.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Submit')),
        ],
      ),
    );
    if (save != true) return;
    try {
      await StudentHealthApi.updateMyProfile({
        'food_allergies': allergy.text,
        'emergency_medication_instructions': medication.text,
        'emergency_contact_phone': phone.text,
        'family_notes': notes.text,
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Health information submitted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }


  Future<void> _familyMeasurement() async {
    final height = TextEditingController();
    final weight = TextEditingController();
    final notes = TextEditingController();
    var selectedDate = DateTime.now();

    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add family measurement'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Measurement date'),
                  subtitle: Text(DateFormat('dd MMM yyyy').format(selectedDate)),
                  trailing: const Icon(Icons.calendar_month_rounded),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setLocal(() => selectedDate = picked);
                  },
                ),
                TextField(
                  controller: height,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Height (cm)'),
                ),
                TextField(
                  controller: weight,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Weight (kg)'),
                ),
                TextField(
                  controller: notes,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Note (optional)'),
                ),
                const SizedBox(height: 10),
                const Text(
                  'This stays marked as family-reported until school/health staff verifies it.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (save != true) return;
    try {
      await StudentHealthApi.addFamilyMeasurement(
        measurementDate: DateFormat('yyyy-MM-dd').format(selectedDate),
        heightCm: height.text,
        weightKg: weight.text,
        notes: notes.text,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Family-reported measurement saved.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Health & Growth')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    final student = _data['student'] is Map
        ? Map<String, dynamic>.from(_data['student'] as Map)
        : <String, dynamic>{};
    final latest = _measurements.isEmpty ? <String, dynamic>{} : _measurements.last;
    final showBmi = _settings['show_bmi_to_student'] != false;
    final showWeight = _settings['show_weight_chart_to_student'] != false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Health & Growth'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Text(student['name']?.toString() ?? 'Student',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            Text(
              '${student['class_name'] ?? ''} ${student['section_name'] ?? ''} • ${student['admission_number'] ?? ''}',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _metric('Height',
                    latest['height_cm'] == null ? '-' : '${latest['height_cm']} cm',
                    Icons.height_rounded),
                const SizedBox(width: 8),
                _metric('Weight',
                    latest['weight_kg'] == null ? '-' : '${latest['weight_kg']} kg',
                    Icons.monitor_weight_outlined),
                if (showBmi) ...[
                  const SizedBox(width: 8),
                  _metric('BMI', latest['bmi']?.toString() ?? '-',
                      Icons.insights_rounded),
                ],
              ],
            ),
            const SizedBox(height: 10),
            if (_settings['allow_family_updates'] != false)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _familyMeasurement,
                  icon: const Icon(Icons.add_chart_rounded),
                  label: const Text('Add family-reported measurement'),
                ),
              ),
            const SizedBox(height: 12),
            _trendChart(title: 'Height Growth', keyName: 'height_cm', unit: 'cm'),
            if (showWeight)
              _trendChart(title: 'Weight Trend', keyName: 'weight_kg', unit: 'kg'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Health profile',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text('Blood group: ${_profile['blood_group'] ?? '-'}'),
                    Text(
                        'Allergies: ${_profile['food_allergies'] ?? _profile['other_allergies'] ?? 'None reported'}'),
                    Text(
                        'Emergency instructions: ${_profile['emergency_medication_instructions'] ?? '-'}'),
                    Text(
                        'Emergency phone: ${_profile['emergency_contact_phone'] ?? '-'}'),
                    const SizedBox(height: 10),
                    if (_settings['allow_family_updates'] != false)
                      OutlinedButton.icon(
                        onPressed: _familyUpdate,
                        icon: const Icon(Icons.edit_note_rounded),
                        label: const Text('Update family health information'),
                      ),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Health screenings',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (_screenings.isEmpty)
                      const Text('No screening has been recorded yet.')
                    else
                      ..._screenings.take(6).map((s) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.health_and_safety_outlined),
                            title: Text(
                                '${s['screening_date'] ?? ''} • ${s['screening_type'] ?? 'Health Screening'}'),
                            subtitle: Text(
                              'Dental: ${s['dental_status'] ?? '-'} • Vision: ${s['vision_status'] ?? '-'}\n'
                              '${s['followup_recommended'] == true ? 'Follow-up recommended: ${s['followup_notes'] ?? 'Please review the health record.'}' : ''}',
                            ),
                          )),
                  ],
                ),
              ),
            ),
            if ((_data['bmi_note'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  _data['bmi_note'].toString(),
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
