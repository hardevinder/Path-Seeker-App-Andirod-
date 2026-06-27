import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';

const List<String> _dayKeys = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
];

const Map<String, String> _dayLabels = {
  'monday': 'Mon',
  'tuesday': 'Tue',
  'wednesday': 'Wed',
  'thursday': 'Thu',
  'friday': 'Fri',
  'saturday': 'Sat',
};

class CoordinatorSubstitutionAssignmentScreen extends StatefulWidget {
  const CoordinatorSubstitutionAssignmentScreen({super.key});

  @override
  State<CoordinatorSubstitutionAssignmentScreen> createState() =>
      _CoordinatorSubstitutionAssignmentScreenState();
}

class _CoordinatorSubstitutionAssignmentScreenState
    extends State<CoordinatorSubstitutionAssignmentScreen> {
  final DateFormat _apiDate = DateFormat('yyyy-MM-dd');
  final DateFormat _displayDate = DateFormat('dd MMM yyyy');

  bool _bootLoading = true;
  bool _timetableLoading = false;
  bool _availabilityLoading = false;
  bool _saving = false;
  String? _error;

  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _periods = [];
  List<Map<String, dynamic>> _timetable = [];
  List<Map<String, dynamic>> _holidays = [];
  List<Map<String, dynamic>> _availableTeachers = [];
  Map<String, Map<String, dynamic>> _substitutions = {};

  int? _selectedTeacherId;
  String? _selectedDay;
  int? _selectedPeriodId;
  String _teacherSearch = '';

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  String get _selectedDateString => _apiDate.format(_selectedDate);

  String? get _cellKey => _selectedDay != null && _selectedPeriodId != null
      ? '${_selectedDay}_$_selectedPeriodId'
      : null;

  Map<String, dynamic>? get _selectedTeacher {
    for (final teacher in _teachers) {
      if (_toInt(teacher['userId']) == _selectedTeacherId) return teacher;
    }
    return null;
  }

  Map<String, dynamic>? get _selectedSubstitution {
    final key = _cellKey;
    return key == null ? null : _substitutions[key];
  }

  Map<String, String> get _weekDates {
    final base =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final monday = base.subtract(Duration(days: base.weekday - 1));
    return {
      for (var i = 0; i < _dayKeys.length; i++)
        _dayKeys[i]: _apiDate.format(monday.add(Duration(days: i))),
    };
  }

  List<Map<String, dynamic>> get _filteredTeachers {
    final query = _teacherSearch.trim().toLowerCase();
    if (query.isEmpty) return _teachers;
    return _teachers.where((teacher) {
      final text =
          '${teacher['name']} ${teacher['userId']} ${teacher['employeeId']}'
              .toLowerCase();
      return text.contains(query);
    }).toList();
  }

  Future<void> _loadInitial() async {
    if (!mounted) return;
    setState(() {
      _bootLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _loadTeachers(),
        _loadPeriods(),
        _loadHolidays(),
      ]);

      final teachers = results[0];
      final periods = results[1];
      final holidays = results[2];

      if (!mounted) return;
      setState(() {
        _teachers = teachers;
        _periods = periods;
        _holidays = holidays;
        _selectedTeacherId =
            teachers.isEmpty ? null : _toInt(teachers.first['userId']);
      });

      await _loadTeacherData();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _bootLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadTeachers() async {
    final response = await ApiService.rawGet('/teachers');
    if (!_ok(response.statusCode)) {
      throw Exception(_extractError(response.body, 'Failed to load teachers'));
    }

    final rows = _extractRows(jsonDecode(response.body), keys: ['teachers']);
    return rows
        .map<Map<String, dynamic>>((row) => {
              'userId': _toInt(
                row['user_id'] ?? _mapOf(row['User'])['id'] ?? row['id'],
              ),
              'employeeId': _toInt(
                row['employee_id'] ?? _mapOf(row['Employee'])['id'],
              ),
              'name': _safe(
                row['name'] ??
                    _mapOf(row['Employee'])['name'] ??
                    _mapOf(row['User'])['name'],
                'Unnamed',
              ),
            })
        .where((row) => row['userId'] != null)
        .toList()
      ..sort(
        (a, b) => _safe(a['name']).toLowerCase().compareTo(
              _safe(b['name']).toLowerCase(),
            ),
      );
  }

  Future<List<Map<String, dynamic>>> _loadPeriods() async {
    final response = await ApiService.rawGet('/periods');
    if (!_ok(response.statusCode)) {
      throw Exception(_extractError(response.body, 'Failed to load periods'));
    }

    final rows = _extractRows(jsonDecode(response.body), keys: ['periods']);
    return rows
        .map<Map<String, dynamic>>((row) => {
              'id': _toInt(row['id'] ?? row['periodId'] ?? row['period_id']),
              'name': _safe(
                row['period_name'] ?? row['name'],
                'P${row['id'] ?? ''}',
              ),
            })
        .where((row) => row['id'] != null)
        .toList()
      ..sort((a, b) => (_toInt(a['id']) ?? 0).compareTo(_toInt(b['id']) ?? 0));
  }

  Future<List<Map<String, dynamic>>> _loadHolidays() async {
    final response = await ApiService.rawGet('/holidays');
    if (!_ok(response.statusCode)) return [];
    return _extractRows(jsonDecode(response.body), keys: ['holidays']);
  }

  Future<void> _loadTeacherData() async {
    if (_selectedTeacherId == null) {
      setState(() {
        _timetable = [];
        _substitutions = {};
        _availableTeachers = [];
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _timetableLoading = true;
      _selectedDay = null;
      _selectedPeriodId = null;
      _availableTeachers = [];
    });

    try {
      final timetableResponse = await ApiService.rawGet(
        '/period-class-teacher-subject/timetable-teacher/$_selectedTeacherId',
      );
      final timetable = _ok(timetableResponse.statusCode)
          ? _extractRows(jsonDecode(timetableResponse.body), keys: ['timetable'])
          : <Map<String, dynamic>>[];
      final substitutions = await _fetchSubstitutionsForSelectedDate();

      if (!mounted) return;
      setState(() {
        _timetable = timetable;
        _substitutions = substitutions;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _timetable = [];
        _substitutions = {};
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _timetableLoading = false);
    }
  }

  Future<void> _loadAvailableTeachers() async {
    if (_selectedDay == null || _selectedPeriodId == null) {
      setState(() => _availableTeachers = []);
      return;
    }

    setState(() => _availabilityLoading = true);
    try {
      final response = await ApiService.rawGet(
        '/period-class-teacher-subject/teacher-availability-by-date'
        '?date=$_selectedDateString&periodId=$_selectedPeriodId',
      );
      if (!_ok(response.statusCode)) {
        setState(() => _availableTeachers = []);
        return;
      }

      final rows = _extractRows(
        jsonDecode(response.body),
        keys: ['availableTeachers'],
      );

      final available = rows
          .map<Map<String, dynamic>>((row) => {
                'id': _toInt(
                  row['user_id'] ?? _mapOf(row['User'])['id'] ?? row['id'],
                ),
                'name': _safe(
                  row['name'] ?? _mapOf(row['User'])['name'],
                  'Unnamed',
                ),
                'weeklyWorkload': 0,
                'dayWorkload': 0,
              })
          .where((row) => row['id'] != null)
          .toList();

      final withWorkload = await Future.wait(
        available.map((teacher) async {
          try {
            final workloadResponse = await ApiService.rawGet(
              '/period-class-teacher-subject/teacher-workload/${teacher['id']}',
            );
            if (!_ok(workloadResponse.statusCode)) return teacher;
            final data = jsonDecode(workloadResponse.body);
            if (data is! Map) return teacher;
            final daily = _mapOf(data['dailyWorkload']);
            return {
              ...teacher,
              'weeklyWorkload': _toInt(data['weeklyWorkload']) ?? 0,
              'dayWorkload': _toInt(daily[_selectedDay]) ?? 0,
            };
          } catch (_) {
            return teacher;
          }
        }),
      );

      withWorkload.sort((a, b) {
        final weekly = (_toInt(a['weeklyWorkload']) ?? 0)
            .compareTo(_toInt(b['weeklyWorkload']) ?? 0);
        if (weekly != 0) return weekly;
        final daily =
            (_toInt(a['dayWorkload']) ?? 0).compareTo(_toInt(b['dayWorkload']) ?? 0);
        if (daily != 0) return daily;
        return _safe(a['name']).compareTo(_safe(b['name']));
      });

      if (!mounted) return;
      setState(() => _availableTeachers = withWorkload);
    } catch (_) {
      if (mounted) setState(() => _availableTeachers = []);
    } finally {
      if (mounted) setState(() => _availabilityLoading = false);
    }
  }

  Future<Map<String, Map<String, dynamic>>>
      _fetchSubstitutionsForSelectedDate() async {
    final response = await ApiService.rawGet(
      '/substitutions/by-date?date=$_selectedDateString',
    );
    final substitutions = <String, Map<String, dynamic>>{};
    if (!_ok(response.statusCode)) return substitutions;

    final rows = _extractRows(jsonDecode(response.body));
    for (final row in rows) {
      final originalTeacherId = _toInt(
        row['original_teacherId'] ??
            row['original_teacherID'] ??
            row['originalTeacherId'],
      );
      final day = _normalizeDay(row['day']);
      final periodId = _toInt(row['periodId'] ?? row['period_id']);
      if (originalTeacherId == _selectedTeacherId &&
          day != null &&
          periodId != null) {
        substitutions['${day}_$periodId'] = row;
      }
    }
    return substitutions;
  }

  Future<void> _refreshSubstitutionsForSelectedDate() async {
    final substitutions = await _fetchSubstitutionsForSelectedDate();
    if (mounted) setState(() => _substitutions = substitutions);
  }

  Map<String, Map<int, List<Map<String, dynamic>>>> _buildGrid() {
    final grid = <String, Map<int, List<Map<String, dynamic>>>>{};
    for (final day in _dayKeys) {
      grid[day] = {
        for (final period in _periods) _toInt(period['id']) ?? -1: [],
      };
    }

    for (final row in _timetable) {
      final day = _normalizeDay(row['day'] ?? row['Day'] ?? row['weekday']);
      final periodId = _periodId(row);
      if (day == null || periodId == null || grid[day]?[periodId] == null) {
        continue;
      }
      grid[day]![periodId]!.add(row);
    }
    return grid;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    await _loadTeacherData();
  }

  Future<void> _changeWeek(int days) async {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: days)));
    await _loadTeacherData();
  }

  Future<void> _selectCell(
    String day,
    int periodId,
    List<Map<String, dynamic>> records,
  ) async {
    if (records.isEmpty) {
      _showMessage('Free period', 'Substitution can be assigned only where a class is scheduled.');
      return;
    }

    final dateForDay = _weekDates[day];
    setState(() {
      _selectedDay = day;
      _selectedPeriodId = periodId;
      if (dateForDay != null) {
        _selectedDate = DateTime.parse(dateForDay);
      }
    });
    await _refreshSubstitutionsForSelectedDate();
    await _loadAvailableTeachers();
  }

  Future<void> _assignSubstitute(Map<String, dynamic> teacher) async {
    final key = _cellKey;
    if (key == null) {
      _showMessage('No cell selected', 'Please select a scheduled class first.');
      return;
    }
    setState(() {
      _substitutions[key] = {
        ...teacher,
        'teacherId': teacher['id'],
        'teacherName': teacher['name'],
      };
    });
  }

  Future<void> _saveCurrent() async {
    final key = _cellKey;
    final day = _selectedDay;
    final periodId = _selectedPeriodId;
    final selectedSub = _selectedSubstitution;
    if (key == null || day == null || periodId == null) {
      _showMessage('No cell selected', 'Please select a scheduled class first.');
      return;
    }
    if (selectedSub == null) {
      _showMessage('No substitute selected', 'Please select an available teacher.');
      return;
    }

    final result = _buildPayload(day, periodId, selectedSub);
    final error = result['error'];
    if (error != null) {
      _showMessage('Missing information', _safe(error));
      return;
    }

    setState(() => _saving = true);
    try {
      final response = await ApiService.rawPost(
        '/substitutions',
        Map<String, dynamic>.from(result['payload'] as Map),
      );
      if (!_ok(response.statusCode)) {
        _showMessage('Save failed', _extractError(response.body, 'Failed to save substitution.'));
        return;
      }

      final returned = jsonDecode(response.body);
      final saved = returned is Map
          ? Map<String, dynamic>.from(returned)
          : Map<String, dynamic>.from(selectedSub);
      saved['Teacher'] = {
        'id': result['selectedTeacherId'],
        'name': _safe(selectedSub['teacherName'] ?? selectedSub['name']),
      };

      setState(() => _substitutions[key] = saved);
      _showMessage('Saved', 'Substitution saved successfully.');
    } catch (e) {
      _showMessage('Save failed', e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeCurrent() async {
    final key = _cellKey;
    final selectedSub = _selectedSubstitution;
    if (key == null || selectedSub == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove substitution?'),
        content: const Text('This will clear the substitute teacher for this period.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final id = _toInt(selectedSub['id']);
    setState(() => _saving = true);
    try {
      if (id != null) {
        final response = await ApiService.rawDelete('/substitutions/$id');
        if (!_ok(response.statusCode) && response.statusCode != 404) {
          _showMessage('Remove failed', 'Could not remove substitution.');
          return;
        }
      }
      setState(() => _substitutions.remove(key));
      _showMessage('Removed', 'Substitution removed.');
    } catch (e) {
      _showMessage('Remove failed', e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _buildPayload(
    String day,
    int periodId,
    Map<String, dynamic> teacherSub,
  ) {
    final grid = _buildGrid();
    final records = grid[day]?[periodId] ?? [];
    if (records.isEmpty) return {'error': 'No class record found in this cell.'};

    final first = records.first;
    final originalTeacherId = _toInt(
      first['teacherId'] ?? first['teacher_id'] ?? _mapOf(first['Teacher'])['id'],
    );
    final selectedTeacherId = _toInt(teacherSub['teacherId'] ?? teacherSub['id']);

    int? classId;
    int? subjectId;
    for (final row in records) {
      classId ??= _toInt(row['classId'] ?? row['class_id'] ?? _mapOf(row['Class'])['id']);
      subjectId ??= _toInt(
        row['subjectId'] ?? row['subject_id'] ?? _mapOf(row['Subject'])['id'],
      );
    }

    if (classId == null) return {'error': 'Class record lacks a valid class ID.'};
    if (subjectId == null) return {'error': 'Class record lacks a valid subject ID.'};
    if (originalTeacherId == null) {
      return {'error': 'Original teacher ID is missing for this class.'};
    }
    if (selectedTeacherId == null) {
      return {'error': 'Selected substitute teacher is invalid.'};
    }

    return {
      'payload': {
        'date': _selectedDateString,
        'periodId': periodId,
        'classId': classId,
        'teacherId': selectedTeacherId,
        'original_teacherId': originalTeacherId,
        'subjectId': subjectId,
        'day': _prettyDay(day),
        'published': true,
      },
      'selectedTeacherId': selectedTeacherId,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Substitution Assignment'),
        actions: [
          IconButton(
            tooltip: 'Listing',
            onPressed: () => Navigator.pushNamed(context, '/coordinator/substitutions'),
            icon: const Icon(Icons.list_alt_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _bootLoading || _timetableLoading ? null : _loadInitial,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _bootLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _state(
                  Icons.warning_rounded,
                  'Could not load substitutions',
                  _error!,
                  actionLabel: 'Retry',
                  onAction: _loadInitial,
                )
              : RefreshIndicator(
                  onRefresh: _loadTeacherData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                    children: [
                      _hero(),
                      const SizedBox(height: 12),
                      _controls(),
                      const SizedBox(height: 12),
                      _weekBar(),
                      const SizedBox(height: 12),
                      _timetableGrid(),
                      const SizedBox(height: 12),
                      _availablePanel(),
                      const SizedBox(height: 12),
                      _actionsPanel(),
                    ],
                  ),
                ),
    );
  }

  Widget _hero() {
    final selected = _selectedTeacher;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF0F766E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Assign Substitutions',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  selected == null
                      ? 'Select teacher and period to assign substitute.'
                      : '${selected['name']} - $_selectedDateString',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    return _panel(
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search Teacher',
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _teacherSearch = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: _filteredTeachers.any((t) => t['userId'] == _selectedTeacherId)
                ? _selectedTeacherId
                : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Select Teacher',
              border: OutlineInputBorder(),
            ),
            items: _filteredTeachers
                .map(
                  (teacher) => DropdownMenuItem<int>(
                    value: _toInt(teacher['userId']),
                    child: Text(
                      _safe(teacher['name'], 'Unnamed'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) async {
              setState(() => _selectedTeacherId = value);
              await _loadTeacherData();
            },
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month_rounded),
              label: Text(_displayDate.format(_selectedDate)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weekBar() {
    final dates = _weekDates;
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: () => _changeWeek(-7),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Column(
            children: [
              const Text(
                'Week',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
              Text(
                '${_niceDate(dates['monday'])} - ${_niceDate(dates['saturday'])}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: () => _changeWeek(7),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  Widget _timetableGrid() {
    final grid = _buildGrid();
    final dates = _weekDates;
    final holidayByDate = {
      for (final holiday in _holidays) _dateOnly(holiday['date']): holiday,
    };

    if (_timetableLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return _panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Text(
              'Teacher Timetable',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 42,
              dataRowMinHeight: 64,
              dataRowMaxHeight: 86,
              columns: [
                const DataColumn(label: Text('Day')),
                ..._periods.map(
                  (period) => DataColumn(
                    label: Text(_safe(period['name'], 'P${period['id']}')),
                  ),
                ),
              ],
              rows: _dayKeys.map((day) {
                final date = dates[day] ?? '';
                final holiday = holidayByDate[date];
                return DataRow(
                  color: holiday != null
                      ? MaterialStateProperty.all(const Color(0xFFFFF1F2))
                      : null,
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 76,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _dayLabels[day] ?? day,
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              _niceDate(date),
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ..._periods.map((period) {
                      final periodId = _toInt(period['id']) ?? -1;
                      final records = grid[day]?[periodId] ?? [];
                      final key = '${day}_$periodId';
                      final sub = _substitutions[key];
                      final selected = key == _cellKey;
                      return DataCell(
                        _gridCell(
                          day: day,
                          periodId: periodId,
                          records: records,
                          substitution: sub,
                          selected: selected,
                          disabled: holiday != null,
                        ),
                        onTap: holiday != null
                            ? null
                            : () => _selectCell(day, periodId, records),
                      );
                    }),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridCell({
    required String day,
    required int periodId,
    required List<Map<String, dynamic>> records,
    required Map<String, dynamic>? substitution,
    required bool selected,
    required bool disabled,
  }) {
    final hasClass = records.isNotEmpty;
    final first = hasClass ? records.first : <String, dynamic>{};
    final color = selected
        ? const Color(0xFFEDE9FE)
        : substitution != null
            ? const Color(0xFFECFDF5)
            : disabled
                ? const Color(0xFFFFF1F2)
                : Colors.white;

    return Container(
      width: 150,
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? const Color(0xFF7C3AED) : Colors.black12,
        ),
      ),
      child: disabled
          ? const Text('Holiday', style: TextStyle(fontWeight: FontWeight.w800))
          : !hasClass
              ? const Text('Free', style: TextStyle(color: Colors.black45))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _classLabel(first),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      _subjectName(first),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    if (substitution != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Sub: ${_subTeacherName(substitution)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF047857),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }

  Widget _availablePanel() {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Available Teachers',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
              _pill('${_availableTeachers.length}'),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _cellKey == null
                ? 'Select a scheduled period to load available teachers.'
                : '${_prettyDay(_selectedDay!)} - ${_periodName(_selectedPeriodId)}',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 10),
          if (_availabilityLoading)
            const Center(child: CircularProgressIndicator())
          else if (_cellKey == null)
            _miniState('No period selected')
          else if (_availableTeachers.isEmpty)
            _miniState('No available teacher found')
          else
            ..._availableTeachers.map(_availableTeacherTile),
        ],
      ),
    );
  }

  Widget _availableTeacherTile(Map<String, dynamic> teacher) {
    final selected = _subTeacherId(_selectedSubstitution) == _toInt(teacher['id']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEFFDF7) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? const Color(0xFF10B981) : Colors.black12,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: selected ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
          child: Icon(
            selected ? Icons.check_rounded : Icons.person_rounded,
            color: selected ? Colors.white : const Color(0xFF334155),
          ),
        ),
        title: Text(
          _safe(teacher['name'], 'Unnamed'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          'Week: ${teacher['weeklyWorkload']} | Day: ${teacher['dayWorkload']}',
        ),
        onTap: () => _assignSubstitute(teacher),
      ),
    );
  }

  Widget _actionsPanel() {
    final sub = _selectedSubstitution;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Selected Substitution',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            sub == null
                ? 'No substitute selected.'
                : '${_subTeacherName(sub)} for ${_prettyDay(_selectedDay ?? '')} ${_periodName(_selectedPeriodId)}',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving || sub == null ? null : _saveCurrent,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: const Text('Save'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving || sub == null ? null : _removeCurrent,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Remove'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panel({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: child,
    );
  }

  Widget _state(
    IconData icon,
    String title,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: const Color(0xFF64748B)),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, textAlign: TextAlign.center),
    );
  }

  Widget _pill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFDF7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }

  void _showMessage(String title, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title: $message'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<Map<String, dynamic>> _extractRows(
    dynamic decoded, {
    List<String> keys = const ['data', 'rows', 'items', 'substitutions'],
  }) {
    final searchKeys = [
      ...keys,
      'data',
      'rows',
      'items',
      'substitutions',
    ].toSet().toList();
    final raw = decoded is List
        ? decoded
        : decoded is Map
            ? searchKeys.map((key) => decoded[key]).firstWhere(
                  (value) => value is List,
                  orElse: () => [],
                )
            : [];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String? _normalizeDay(dynamic value) {
    final text = _safe(value).toLowerCase();
    if (text.isEmpty) return null;
    if (_dayKeys.contains(text)) return text;
    final short = text.length >= 3 ? text.substring(0, 3) : text;
    const map = {
      'mon': 'monday',
      'tue': 'tuesday',
      'wed': 'wednesday',
      'thu': 'thursday',
      'fri': 'friday',
      'sat': 'saturday',
    };
    return map[short];
  }

  String _prettyDay(String day) {
    if (day.isEmpty) return '-';
    final normalized = _normalizeDay(day) ?? day;
    return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
  }

  int? _periodId(Map<String, dynamic> row) {
    return _toInt(
      row['periodId'] ?? row['period_id'] ?? _mapOf(row['Period'])['id'],
    );
  }

  String _periodName(int? periodId) {
    for (final period in _periods) {
      if (_toInt(period['id']) == periodId) {
        return _safe(period['name'], 'P$periodId');
      }
    }
    return periodId == null ? '-' : 'P$periodId';
  }

  String _classLabel(Map<String, dynamic> row) {
    final classObj = _mapOf(row['Class'] ?? row['class']);
    final sectionObj = _mapOf(row['Section'] ?? row['section']);
    final className = _safe(
      classObj['class_name'] ??
          classObj['name'] ??
          row['className'] ??
          row['class_name'] ??
          row['classId'] ??
          row['class_id'],
      '-',
    );
    final sectionName = _safe(
      sectionObj['section_name'] ??
          sectionObj['name'] ??
          row['sectionName'] ??
          row['section_name'],
    );
    return sectionName.isEmpty ? className : '$className - $sectionName';
  }

  String _subjectName(Map<String, dynamic> row) {
    final subject = _mapOf(row['Subject'] ?? row['subject']);
    return _safe(
      subject['name'] ??
          row['subjectName'] ??
          row['subject_name'] ??
          row['subject'],
      'No Subject',
    );
  }

  String _subTeacherName(Map<String, dynamic> sub) {
    final teacher = _mapOf(sub['Teacher']);
    return _safe(
      teacher['name'] ??
          sub['teacherName'] ??
          sub['name'] ??
          sub['teacher_name'],
      'Substitute',
    );
  }

  int? _subTeacherId(Map<String, dynamic>? sub) {
    if (sub == null) return null;
    final teacher = _mapOf(sub['Teacher']);
    return _toInt(
      sub['teacherId'] ??
          sub['teacher_id'] ??
          teacher['id'] ??
          sub['id'],
    );
  }

  String _dateOnly(dynamic value) {
    final raw = _safe(value);
    if (raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw.length >= 10 ? raw.substring(0, 10) : raw;
    return _apiDate.format(parsed);
  }

  String _niceDate(dynamic value) {
    final raw = _safe(value);
    if (raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    return parsed == null ? raw : DateFormat('dd MMM').format(parsed);
  }

  bool _ok(int statusCode) => statusCode >= 200 && statusCode < 300;

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  Map<String, dynamic> _mapOf(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  String _safe(dynamic value, [String fallback = '']) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  String _extractError(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final message =
            decoded['message'] ?? decoded['error'] ?? decoded['sqlMessage'];
        if (message != null && message.toString().trim().isNotEmpty) {
          return message.toString();
        }
      }
    } catch (_) {}
    return fallback;
  }
}
