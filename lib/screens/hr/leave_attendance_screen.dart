import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../auth/role_manager.dart';
import '../../models/employee_attendance_model.dart';
import '../../services/employee_attendance_api.dart';
import '../../widgets/role_dashboard_drawer.dart';

class HrLeaveAttendanceScreen extends StatefulWidget {
  const HrLeaveAttendanceScreen({super.key});

  @override
  State<HrLeaveAttendanceScreen> createState() => _HrLeaveAttendanceScreenState();
}

class _HrLeaveAttendanceScreenState extends State<HrLeaveAttendanceScreen> {
  final DateFormat _apiDate = DateFormat('yyyy-MM-dd');
  final TextEditingController _searchController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<EmployeeLite> _employees = [];
  List<EmployeeAttendanceOption> _options = defaultEmployeeAttendanceOptions;
  Map<int, EmployeeAttendanceDraft> _attendance = {};

  String _department = 'all';
  String _bulkInTime = '';
  String _bulkOutTime = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _loadInitial();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _departments {
    final values = _employees.map((e) => e.departmentName).toSet().toList();
    values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  List<EmployeeLite> get _visibleEmployees {
    final query = _searchController.text.trim().toLowerCase();
    return _employees.where((employee) {
      if (_department != 'all' && employee.departmentName != _department) {
        return false;
      }
      if (query.isEmpty) return true;
      return employee.name.toLowerCase().contains(query) ||
          employee.employeeCode.toLowerCase().contains(query) ||
          employee.designation.toLowerCase().contains(query) ||
          employee.departmentName.toLowerCase().contains(query) ||
          employee.phone.toLowerCase().contains(query);
    }).toList();
  }

  Map<String, int> get _visibleCounts {
    final visibleIds = _visibleEmployees.map((e) => e.id).toSet();
    final counts = <String, int>{};
    for (final entry in _attendance.entries) {
      if (!visibleIds.contains(entry.key)) continue;
      final status = normalizeAttendanceStatus(entry.value.status);
      if (status.isEmpty) continue;
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return counts;
  }

  int get _markedVisibleCount {
    final visibleIds = _visibleEmployees.map((e) => e.id).toSet();
    return _attendance.entries
        .where((entry) => visibleIds.contains(entry.key))
        .where((entry) => normalizeAttendanceStatus(entry.value.status).isNotEmpty)
        .length;
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        EmployeeAttendanceApi.fetchEmployees(),
        EmployeeAttendanceApi.fetchAttendanceOptions(),
        EmployeeAttendanceApi.fetchMarkedAttendance(_selectedDate),
      ]);
      if (!mounted) return;
      setState(() {
        _employees = results[0] as List<EmployeeLite>;
        _options = results[1] as List<EmployeeAttendanceOption>;
        _attendance = results[2] as Map<int, EmployeeAttendanceDraft>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reloadAttendanceOnly() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final marked = await EmployeeAttendanceApi.fetchMarkedAttendance(_selectedDate);
      if (!mounted) return;
      setState(() => _attendance = marked);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(today) ? today : _selectedDate,
      firstDate: DateTime(today.year - 3),
      lastDate: today,
      helpText: 'Select attendance date',
    );
    if (picked == null) return;
    setState(() => _selectedDate = DateTime(picked.year, picked.month, picked.day));
    if (_selectedDate.weekday == DateTime.sunday && mounted) {
      _showSnack('Selected date is Sunday. You can still mark attendance if required.');
    }
    await _reloadAttendanceOnly();
  }

  void _setEmployeeStatus(int employeeId, String status) {
    setState(() {
      final old = _attendance[employeeId] ?? const EmployeeAttendanceDraft();
      _attendance[employeeId] = old.copyWith(status: status);
    });
  }

  void _setEmployeeTime(int employeeId, {String? inTime, String? outTime}) {
    setState(() {
      final old = _attendance[employeeId] ?? const EmployeeAttendanceDraft();
      _attendance[employeeId] = old.copyWith(
        inTime: inTime ?? old.inTime,
        outTime: outTime ?? old.outTime,
      );
    });
  }

  void _setEmployeeRemarks(int employeeId, String remarks) {
    setState(() {
      final old = _attendance[employeeId] ?? const EmployeeAttendanceDraft();
      _attendance[employeeId] = old.copyWith(remarks: remarks);
    });
  }

  void _markVisible(String status) {
    final normalized = normalizeAttendanceStatus(status);
    setState(() {
      for (final employee in _visibleEmployees) {
        final old = _attendance[employee.id] ?? const EmployeeAttendanceDraft();
        _attendance[employee.id] = old.copyWith(status: normalized);
      }
    });
  }

  void _applyBulkTimes() {
    if (_bulkInTime.isEmpty && _bulkOutTime.isEmpty) {
      _showSnack('Set at least one Bulk In or Bulk Out time.');
      return;
    }

    setState(() {
      for (final employee in _visibleEmployees) {
        final old = _attendance[employee.id] ?? const EmployeeAttendanceDraft();
        if (isNoTimeAttendanceStatus(old.status)) {
          _attendance[employee.id] = old.copyWith(inTime: '', outTime: '');
          continue;
        }
        _attendance[employee.id] = old.copyWith(
          inTime: _bulkInTime.isNotEmpty ? _bulkInTime : old.inTime,
          outTime: _bulkOutTime.isNotEmpty ? _bulkOutTime : old.outTime,
        );
      }
    });
    _showSnack('Bulk time applied to visible employees.');
  }

  void _clearVisibleTimes() {
    setState(() {
      for (final employee in _visibleEmployees) {
        final old = _attendance[employee.id];
        if (old == null) continue;
        _attendance[employee.id] = old.copyWith(inTime: '', outTime: '');
      }
      _bulkInTime = '';
      _bulkOutTime = '';
    });
  }

  Future<void> _saveAttendance() async {
    final visibleIds = _visibleEmployees.map((e) => e.id).toSet();
    final missingPresentTime = _attendance.entries.any((entry) {
      if (!visibleIds.contains(entry.key)) return false;
      return entry.value.status == 'present' &&
          (entry.value.inTime.isEmpty || entry.value.outTime.isEmpty);
    });

    if (missingPresentTime) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Submit without complete time?'),
          content: const Text(
            'Some Present entries are missing In/Out time. Do you want to continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Submit'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _saving = true);
    try {
      final message = await EmployeeAttendanceApi.markAttendance(
        date: _selectedDate,
        drafts: _attendance.entries,
      );
      if (!mounted) return;
      _showSnack(message);
      await _reloadAttendanceOnly();
    } catch (e) {
      if (!mounted) return;
      _showSnack(_cleanError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickBulkTime({required bool isInTime}) async {
    final current = isInTime ? _bulkInTime : _bulkOutTime;
    final picked = await _showTimePicker(current);
    if (picked == null) return;
    setState(() {
      if (isInTime) {
        _bulkInTime = picked;
      } else {
        _bulkOutTime = picked;
      }
    });
  }

  Future<void> _pickEmployeeTime(int employeeId, {required bool isInTime}) async {
    final rec = _attendance[employeeId] ?? const EmployeeAttendanceDraft();
    final current = isInTime ? rec.inTime : rec.outTime;
    final picked = await _showTimePicker(current);
    if (picked == null) return;
    _setEmployeeTime(
      employeeId,
      inTime: isInTime ? picked : null,
      outTime: isInTime ? null : picked,
    );
  }

  Future<String?> _showTimePicker(String current) async {
    TimeOfDay initial = TimeOfDay.now();
    if (current.isNotEmpty && current.contains(':')) {
      final pieces = current.split(':');
      final hour = int.tryParse(pieces[0]);
      final minute = int.tryParse(pieces[1]);
      if (hour != null && minute != null) {
        initial = TimeOfDay(hour: hour, minute: minute);
      }
    }

    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return null;
    return '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openCalendar(EmployeeLite employee) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EmployeeCalendarSheet(
        employee: employee,
        initialMonth: DateTime(_selectedDate.year, _selectedDate.month),
        options: _options,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleEmployees = _visibleEmployees;
    final counts = _visibleCounts;
    final departmentLabel = _department == 'all' ? 'All Departments' : _department;

    return Scaffold(
      drawer: const RoleDashboardDrawer(activeRole: AppRoles.hr),
      appBar: AppBar(
        title: const Text('Employee Attendance'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _saving ? null : _loadInitial,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 16,
                offset: Offset(0, -6),
              ),
            ],
          ),
          child: FilledButton.icon(
            onPressed: _saving || _loading ? null : _saveAttendance,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_done_rounded),
            label: Text(_saving ? 'Saving Attendance...' : 'Save Attendance'),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadInitial,
        child: _loading
            ? const _LoadingBody()
            : _error != null
                ? _ErrorBody(message: _error!, onRetry: _loadInitial)
                : CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _HeroHeader(
                                dateText: _apiDate.format(_selectedDate),
                                departmentText: departmentLabel,
                                total: visibleEmployees.length,
                                marked: _markedVisibleCount,
                                onDateTap: _pickDate,
                              ),
                              const SizedBox(height: 14),
                              _FilterPanel(
                                searchController: _searchController,
                                department: _department,
                                departments: _departments,
                                onDepartmentChanged: (value) {
                                  setState(() => _department = value ?? 'all');
                                },
                                bulkInTime: _bulkInTime,
                                bulkOutTime: _bulkOutTime,
                                onPickBulkIn: () => _pickBulkTime(isInTime: true),
                                onPickBulkOut: () => _pickBulkTime(isInTime: false),
                                onApplyBulk: _applyBulkTimes,
                                onClearTimes: _clearVisibleTimes,
                              ),
                              const SizedBox(height: 14),
                              _QuickActions(
                                onPresent: () => _markVisible('present'),
                                onAbsent: () => _markVisible('absent'),
                                onFirstHalf: () => _markVisible('first_half_day_leave'),
                                onSecondHalf: () => _markVisible('second_half_day_leave'),
                                onShortLeave: () => _markVisible('short_leave'),
                                onHoliday: () => _markVisible('holiday'),
                              ),
                              const SizedBox(height: 14),
                              _StatusSummaryGrid(options: _options, counts: counts),
                              const SizedBox(height: 10),
                              Text(
                                '${visibleEmployees.length} active employees',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                      if (visibleEmployees.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: _EmptyEmployees(),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, childIndex) {
                                if (childIndex.isOdd) {
                                  return const SizedBox(height: 12);
                                }
                                final index = childIndex ~/ 2;
                                final employee = visibleEmployees[index];
                                final record = _attendance[employee.id] ??
                                    const EmployeeAttendanceDraft();
                                return _EmployeeAttendanceCard(
                                  serial: index + 1,
                                  employee: employee,
                                  record: record,
                                  options: _options,
                                  onStatusChanged: (value) => _setEmployeeStatus(
                                    employee.id,
                                    value,
                                  ),
                                  onPickInTime: () => _pickEmployeeTime(
                                    employee.id,
                                    isInTime: true,
                                  ),
                                  onPickOutTime: () => _pickEmployeeTime(
                                    employee.id,
                                    isInTime: false,
                                  ),
                                  onClearTimes: () => _setEmployeeTime(
                                    employee.id,
                                    inTime: '',
                                    outTime: '',
                                  ),
                                  onRemarksChanged: (value) => _setEmployeeRemarks(
                                    employee.id,
                                    value,
                                  ),
                                  onCalendarTap: () => _openCalendar(employee),
                                );
                              },
                              childCount: visibleEmployees.length * 2 - 1,
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _cleanError(Object error) =>
      error.toString().replaceFirst('Exception: ', '').trim();
}

class _HeroHeader extends StatelessWidget {
  final String dateText;
  final String departmentText;
  final int total;
  final int marked;
  final VoidCallback onDateTap;

  const _HeroHeader({
    required this.dateText,
    required this.departmentText,
    required this.total,
    required this.marked,
    required this.onDateTap,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : math.min(1.0, marked / total);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF16A34A), Color(0xFF86EFAC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3316A34A),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.20),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.how_to_reg_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HR Attendance Desk',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Mark staff attendance with times, leave status and remarks.',
                      style: TextStyle(color: Colors.white70, height: 1.25),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroPill(
                icon: Icons.calendar_today_rounded,
                label: dateText,
                onTap: onDateTap,
              ),
              _HeroPill(
                icon: Icons.apartment_rounded,
                label: departmentText,
              ),
              _HeroPill(
                icon: Icons.people_alt_rounded,
                label: '$marked / $total marked',
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor: Colors.white.withOpacity(.22),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _HeroPill({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.18),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.white.withOpacity(.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return InkWell(borderRadius: BorderRadius.circular(100), onTap: onTap, child: child);
  }
}

class _FilterPanel extends StatelessWidget {
  final TextEditingController searchController;
  final String department;
  final List<String> departments;
  final ValueChanged<String?> onDepartmentChanged;
  final String bulkInTime;
  final String bulkOutTime;
  final VoidCallback onPickBulkIn;
  final VoidCallback onPickBulkOut;
  final VoidCallback onApplyBulk;
  final VoidCallback onClearTimes;

  const _FilterPanel({
    required this.searchController,
    required this.department,
    required this.departments,
    required this.onDepartmentChanged,
    required this.bulkInTime,
    required this.bulkOutTime,
    required this.onPickBulkIn,
    required this.onPickBulkOut,
    required this.onApplyBulk,
    required this.onClearTimes,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Search employee, code, phone or department',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: department == 'all' || departments.contains(department)
                  ? department
                  : 'all',
              decoration: InputDecoration(
                labelText: 'Department',
                prefixIcon: const Icon(Icons.apartment_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
              items: [
                const DropdownMenuItem(value: 'all', child: Text('All Departments')),
                ...departments.map(
                  (dept) => DropdownMenuItem(value: dept, child: Text(dept)),
                ),
              ],
              onChanged: onDepartmentChanged,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TimeButton(
                    label: 'Bulk In',
                    value: bulkInTime,
                    icon: Icons.login_rounded,
                    onTap: onPickBulkIn,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TimeButton(
                    label: 'Bulk Out',
                    value: bulkOutTime,
                    icon: Icons.logout_rounded,
                    onTap: onPickBulkOut,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onApplyBulk,
                    icon: const Icon(Icons.schedule_send_rounded),
                    label: const Text('Apply Times'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onClearTimes,
                    icon: const Icon(Icons.cleaning_services_rounded),
                    label: const Text('Clear Times'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final VoidCallback onPresent;
  final VoidCallback onAbsent;
  final VoidCallback onFirstHalf;
  final VoidCallback onSecondHalf;
  final VoidCallback onShortLeave;
  final VoidCallback onHoliday;

  const _QuickActions({
    required this.onPresent,
    required this.onAbsent,
    required this.onFirstHalf,
    required this.onSecondHalf,
    required this.onShortLeave,
    required this.onHoliday,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ActionChipButton(label: 'All Present', icon: Icons.done_all_rounded, onTap: onPresent),
        _ActionChipButton(label: 'All Absent', icon: Icons.person_off_rounded, onTap: onAbsent),
        _ActionChipButton(label: 'All H1', icon: Icons.looks_one_rounded, onTap: onFirstHalf),
        _ActionChipButton(label: 'All H2', icon: Icons.looks_two_rounded, onTap: onSecondHalf),
        _ActionChipButton(label: 'Short Leave', icon: Icons.timer_rounded, onTap: onShortLeave),
        _ActionChipButton(label: 'Holiday', icon: Icons.celebration_rounded, onTap: onHoliday),
      ],
    );
  }
}

class _ActionChipButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionChipButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFFE2E8F0)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
    );
  }
}

class _StatusSummaryGrid extends StatelessWidget {
  final List<EmployeeAttendanceOption> options;
  final Map<String, int> counts;

  const _StatusSummaryGrid({required this.options, required this.counts});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: options.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.85,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final option = options[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: option.color.withOpacity(.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: option.color.withOpacity(.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: option.color,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  option.abbreviation,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
              Text(
                '${counts[option.value] ?? 0}',
                style: TextStyle(
                  color: option.color,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmployeeAttendanceCard extends StatelessWidget {
  final int serial;
  final EmployeeLite employee;
  final EmployeeAttendanceDraft record;
  final List<EmployeeAttendanceOption> options;
  final ValueChanged<String> onStatusChanged;
  final VoidCallback onPickInTime;
  final VoidCallback onPickOutTime;
  final VoidCallback onClearTimes;
  final ValueChanged<String> onRemarksChanged;
  final VoidCallback onCalendarTap;

  const _EmployeeAttendanceCard({
    required this.serial,
    required this.employee,
    required this.record,
    required this.options,
    required this.onStatusChanged,
    required this.onPickInTime,
    required this.onPickOutTime,
    required this.onClearTimes,
    required this.onRemarksChanged,
    required this.onCalendarTap,
  });

  @override
  Widget build(BuildContext context) {
    final noTime = isNoTimeAttendanceStatus(record.status);
    final selectedOption = options.where((o) => o.value == record.status).firstOrNull;
    final accent = selectedOption?.color ?? const Color(0xFF64748B);

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: accent.withOpacity(.12),
                  child: Text(
                    serial.toString(),
                    style: TextStyle(color: accent, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _MiniBadge(icon: Icons.apartment_rounded, text: employee.departmentName),
                          if (employee.designation.isNotEmpty)
                            _MiniBadge(icon: Icons.badge_rounded, text: employee.designation),
                          if (employee.employeeCode.isNotEmpty)
                            _MiniBadge(icon: Icons.numbers_rounded, text: employee.employeeCode),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Monthly calendar',
                  onPressed: onCalendarTap,
                  icon: const Icon(Icons.calendar_month_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: options.map((option) {
                final selected = option.value == record.status;
                return ChoiceChip(
                  label: Text(option.abbreviation),
                  tooltip: option.label,
                  selected: selected,
                  showCheckmark: false,
                  selectedColor: option.color,
                  backgroundColor: option.color.withOpacity(.08),
                  side: BorderSide(
                    color: selected ? option.color : option.color.withOpacity(.18),
                  ),
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : option.color,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                  onSelected: (_) => onStatusChanged(option.value),
                );
              }).toList(),
            ),
            if (record.status.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                prettyAttendanceStatus(record.status),
                style: TextStyle(color: accent, fontWeight: FontWeight.w800),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TimeButton(
                    label: 'In Time',
                    value: noTime ? '' : record.inTime,
                    icon: Icons.login_rounded,
                    enabled: !noTime,
                    onTap: onPickInTime,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TimeButton(
                    label: 'Out Time',
                    value: noTime ? '' : record.outTime,
                    icon: Icons.logout_rounded,
                    enabled: !noTime,
                    onTap: onPickOutTime,
                  ),
                ),
                IconButton(
                  tooltip: 'Clear time',
                  onPressed: noTime ? null : onClearTimes,
                  icon: const Icon(Icons.backspace_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: record.remarks,
              minLines: 1,
              maxLines: 2,
              textInputAction: TextInputAction.done,
              onChanged: onRemarksChanged,
              decoration: InputDecoration(
                hintText: record.status == 'holiday'
                    ? 'Holiday name / reason'
                    : 'Optional remarks',
                prefixIcon: const Icon(Icons.notes_rounded),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _TimeButton({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFFF8FAFC) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: enabled ? const Color(0xFF0F766E) : Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: enabled ? const Color(0xFF64748B) : Colors.grey,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    enabled ? (value.isEmpty ? 'Select' : value) : 'Not required',
                    style: TextStyle(
                      color: enabled ? const Color(0xFF0F172A) : Colors.grey,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF64748B)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF475569),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeCalendarSheet extends StatefulWidget {
  final EmployeeLite employee;
  final DateTime initialMonth;
  final List<EmployeeAttendanceOption> options;

  const _EmployeeCalendarSheet({
    required this.employee,
    required this.initialMonth,
    required this.options,
  });

  @override
  State<_EmployeeCalendarSheet> createState() => _EmployeeCalendarSheetState();
}

class _EmployeeCalendarSheetState extends State<_EmployeeCalendarSheet> {
  final DateFormat _monthFmt = DateFormat('MMMM yyyy');
  late DateTime _month;
  bool _loading = true;
  String? _error;
  EmployeeMonthlyAttendanceSummary? _summary;

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.initialMonth.year, widget.initialMonth.month);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await EmployeeAttendanceApi.fetchEmployeeMonthSummary(
        employeeId: widget.employee.id,
        month: _month,
      );
      if (!mounted) return;
      setState(() => _summary = summary);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  Color _colorFor(String status) {
    final normalized = normalizeAttendanceStatus(status);
    for (final option in widget.options) {
      if (option.value == normalized) return option.color;
    }
    return const Color(0xFFCBD5E1);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: .88,
      minChildSize: .55,
      maxChildSize: .96,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF16A34A).withOpacity(.12),
                    child: const Icon(Icons.calendar_month_rounded, color: Color(0xFF16A34A)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.employee.name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                        Text(
                          '${widget.employee.departmentName} • Attendance Calendar',
                          style: const TextStyle(color: Color(0xFF64748B)),
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
              const SizedBox(height: 16),
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => _changeMonth(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        _monthFmt.format(_month),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => _changeMonth(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 50),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _ErrorBox(message: _error!, onRetry: _load)
              else if (_summary != null) ...[
                _CalendarSummary(summary: _summary!),
                const SizedBox(height: 14),
                _MonthGrid(
                  month: _month,
                  records: _summary!.records,
                  colorFor: _colorFor,
                ),
                const SizedBox(height: 14),
                _CalendarLegend(options: widget.options),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _CalendarSummary extends StatelessWidget {
  final EmployeeMonthlyAttendanceSummary summary;

  const _CalendarSummary({required this.summary});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.7,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: [
        _SmallStat(title: 'Working Days', value: '${summary.workingDays}', icon: Icons.work_history_rounded),
        _SmallStat(title: 'Present', value: '${summary.presentDays}', icon: Icons.done_rounded),
        _SmallStat(title: 'Absent', value: '${summary.absentDays}', icon: Icons.person_off_rounded),
        _SmallStat(title: 'Leaves Eqv.', value: _numText(summary.leaveDaysEquivalent), icon: Icons.beach_access_rounded),
        _SmallStat(title: 'Holiday', value: '${summary.holidayRows}', icon: Icons.celebration_rounded),
        _SmallStat(title: 'Unmarked', value: '${summary.unmarkedDays}', icon: Icons.help_outline_rounded),
      ],
    );
  }

  static String _numText(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }
}

class _SmallStat extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _SmallStat({required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF0F766E)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
                Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final List<EmployeeAttendanceDayRecord> records;
  final Color Function(String status) colorFor;

  const _MonthGrid({required this.month, required this.records, required this.colorFor});

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(month.year, month.month, 1);
    final start = firstDay.subtract(Duration(days: firstDay.weekday % 7));
    final recordMap = {for (final record in records) record.dateKey: record};

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            children: const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                .map((day) => Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF64748B), fontSize: 11),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 42,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemBuilder: (context, index) {
              final date = start.add(Duration(days: index));
              final key = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
              final record = recordMap[key];
              final inMonth = date.month == month.month;
              final status = record?.status ?? 'unmarked';
              final color = record == null ? const Color(0xFFCBD5E1) : colorFor(status);

              return Tooltip(
                message: record == null
                    ? '$key • Unmarked'
                    : '$key • ${prettyAttendanceStatus(record.status)}${record.remarks.isNotEmpty ? ' • ${record.remarks}' : ''}',
                child: Container(
                  decoration: BoxDecoration(
                    color: inMonth ? Colors.white : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withOpacity(.50)),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 6,
                        left: 7,
                        child: Text(
                          '${date.day}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: inMonth ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  final List<EmployeeAttendanceOption> options;

  const _CalendarLegend({required this.options});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...options.map(
          (option) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: option.color.withOpacity(.10),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(color: option.color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(option.abbreviation, style: TextStyle(color: option.color, fontWeight: FontWeight.w900, fontSize: 12)),
                const SizedBox(width: 4),
                Text(option.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: const [
        SizedBox(height: 160),
        Center(child: CircularProgressIndicator()),
        SizedBox(height: 16),
        Center(child: Text('Loading employee attendance...')),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBody({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 90),
        _ErrorBox(message: message, onRetry: onRetry),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 42),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}

class _EmptyEmployees extends StatelessWidget {
  const _EmptyEmployees();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A).withOpacity(.10),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Icon(Icons.people_outline_rounded, color: Color(0xFF16A34A), size: 44),
            ),
            const SizedBox(height: 16),
            const Text(
              'No active employees found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try changing the department/search filter or add employees from HR Employee Management.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}