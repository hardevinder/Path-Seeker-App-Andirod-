// lib/screens/common/academic_calendar_view_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/academic_calendar_models.dart';
import '../../services/academic_calendar_api.dart';

class AcademicCalendarViewScreen extends StatefulWidget {
  final String roleLabel;

  const AcademicCalendarViewScreen({
    super.key,
    this.roleLabel = 'School',
  });

  @override
  State<AcademicCalendarViewScreen> createState() =>
      _AcademicCalendarViewScreenState();
}

class _AcademicCalendarViewScreenState extends State<AcademicCalendarViewScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _sessionController = TextEditingController();

  bool _loading = true;
  bool _downloading = false;
  String? _error;
  List<AcademicCalendarModel> _calendars = [];

  static const Color _primary = Color(0xFF2563EB);
  static const Color _purple = Color(0xFF7C3AED);
  static const Color _green = Color(0xFF16A34A);
  static const Color _softBg = Color(0xFFF8FAFC);
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _text = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _loadCalendars();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _sessionController.dispose();
    super.dispose();
  }

  Future<void> _loadCalendars() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await AcademicCalendarApi.fetchPublishedCalendars(
        search: _searchController.text,
        academicSession: _sessionController.text,
      );
      if (!mounted) return;
      setState(() => _calendars = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEvents(AcademicCalendarModel calendar) async {
    final id = calendar.id;
    if (id == null) {
      _toast('Calendar ID missing.');
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CalendarEventsSheet(calendar: calendar),
    );
  }

  Future<void> _downloadPdf(AcademicCalendarModel calendar) async {
    final id = calendar.id;
    if (id == null) {
      _toast('Calendar ID missing.');
      return;
    }

    setState(() => _downloading = true);
    try {
      final bytes = await AcademicCalendarApi.downloadPdfBytes(id);
      final dir = await getTemporaryDirectory();
      final safeSession = _safeFileName(calendar.academicSession.isEmpty
          ? '${calendar.id}'
          : calendar.academicSession);
      final file = File('${dir.path}/Academic_Calendar_$safeSession.pdf');
      await file.writeAsBytes(bytes, flush: true);
      await OpenFilex.open(file.path);
    } catch (e) {
      _toast(_cleanError(e));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _clearFilters() {
    _searchController.clear();
    _sessionController.clear();
    _loadCalendars();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _cleanError(Object error) {
    var text = error.toString();
    if (text.startsWith('Exception: ')) text = text.substring(11);
    return text;
  }

  String _safeFileName(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
  }

  String _prettyDate(String raw) {
    if (raw.trim().isEmpty) return '-';
    try {
      final parsed = DateTime.parse(raw);
      return DateFormat('dd MMM yyyy').format(parsed);
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _softBg,
      appBar: AppBar(
        title: const Text('Academic Calendar'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadCalendars,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadCalendars,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _heroCard(),
            const SizedBox(height: 14),
            _filterCard(),
            const SizedBox(height: 14),
            if (_loading) ...[
              const SizedBox(height: 120),
              const Center(child: CircularProgressIndicator()),
            ] else if (_error != null) ...[
              _messageCard(
                icon: Icons.error_outline_rounded,
                title: 'Could not load calendar',
                message: _error!,
                actionText: 'Retry',
                onAction: _loadCalendars,
              ),
            ] else if (_calendars.isEmpty) ...[
              _messageCard(
                icon: Icons.event_busy_rounded,
                title: 'No published academic calendar',
                message:
                    'No published calendar is available for the selected filters yet.',
                actionText: 'Clear filters',
                onAction: _clearFilters,
              ),
            ] else ...[
              _summaryStrip(),
              const SizedBox(height: 12),
              ..._calendars.map(_calendarCard),
            ],
          ],
        ),
      ),
    );
  }

  Widget _heroCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_primary, _purple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -24,
            right: -18,
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.18)),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.roleLabel} Calendar',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'View holidays, exams, PTMs, events and academic planning in one place.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.84),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _loadCalendars(),
            decoration: InputDecoration(
              hintText: 'Search title / remarks',
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _sessionController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _loadCalendars(),
                  decoration: InputDecoration(
                    hintText: 'Session e.g. 2026-27',
                    prefixIcon: const Icon(Icons.school_rounded),
                    border:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _loadCalendars,
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryStrip() {
    final totalEvents = _calendars.length;
    final sessions = _calendars.map((e) => e.academicSession).toSet().length;

    return Row(
      children: [
        Expanded(
          child: _miniSummary(
            icon: Icons.calendar_today_rounded,
            label: 'Calendars',
            value: '$totalEvents',
            color: _primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _miniSummary(
            icon: Icons.school_rounded,
            label: 'Sessions',
            value: '$sessions',
            color: _green,
          ),
        ),
      ],
    );
  }

  Widget _miniSummary({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
                Text(
                  value,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _calendarCard(AcademicCalendarModel calendar) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _openEvents(calendar),
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_primary, _purple],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.event_available_rounded,
                        color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          calendar.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: _text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          calendar.schoolName.isEmpty
                              ? 'Academic Session ${calendar.academicSession}'
                              : '${calendar.schoolName} • ${calendar.academicSession}',
                          style: const TextStyle(color: _muted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _green.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      'Published',
                      style: TextStyle(
                        color: _green,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _infoPill(
                      Icons.play_circle_outline_rounded,
                      'Start',
                      _prettyDate(calendar.startDate),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _infoPill(
                      Icons.flag_circle_rounded,
                      'End',
                      _prettyDate(calendar.endDate),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _infoPill(
                Icons.work_history_rounded,
                'Working Days',
                calendar.totalWorkingDays == null
                    ? '-'
                    : '${calendar.totalWorkingDays}',
              ),
              if (calendar.remarks.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  calendar.remarks,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, height: 1.35),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openEvents(calendar),
                      icon: const Icon(Icons.list_alt_rounded),
                      label: const Text('View Events'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _downloading ? null : () => _downloadPdf(calendar),
                      icon: _downloading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf_rounded),
                      label: const Text('PDF'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoPill(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _softBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Icon(icon, color: _primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageCard({
    required IconData icon,
    required String title,
    required String message,
    required String actionText,
    required VoidCallback onAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Icon(icon, color: _muted, size: 42),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: _text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, height: 1.35),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(actionText),
          ),
        ],
      ),
    );
  }
}

class _CalendarEventsSheet extends StatefulWidget {
  final AcademicCalendarModel calendar;

  const _CalendarEventsSheet({required this.calendar});

  @override
  State<_CalendarEventsSheet> createState() => _CalendarEventsSheetState();
}

class _CalendarEventsSheetState extends State<_CalendarEventsSheet> {
  bool _loading = true;
  String? _error;
  List<AcademicCalendarEventModel> _events = [];

  static const Color _primary = Color(0xFF2563EB);
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _text = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.calendar.id;
    if (id == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AcademicCalendarApi.fetchEvents(id);
      if (!mounted) return;
      setState(() => _events = rows);
    } catch (e) {
      if (!mounted) return;
      var text = e.toString();
      if (text.startsWith('Exception: ')) text = text.substring(11);
      setState(() => _error = text);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _typeColor(String type) {
    switch (type.trim().toUpperCase()) {
      case 'HOLIDAY':
      case 'VACATION':
        return const Color(0xFF16A34A);
      case 'EXAM':
      case 'RESULT':
        return const Color(0xFFDC2626);
      case 'PTM':
      case 'TRAINING':
        return const Color(0xFFD97706);
      case 'ACTIVITY':
      case 'EVENT':
        return const Color(0xFF7C3AED);
      default:
        return _primary;
    }
  }

  String _pretty(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return '-';
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(clean));
    } catch (_) {
      return clean;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.calendar.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _text,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${widget.calendar.academicSession} • Events',
                          style: const TextStyle(color: _muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    color: _muted, size: 40),
                                const SizedBox(height: 10),
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: _muted),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _load,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _events.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Text(
                                  'No events added in this calendar yet.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: _muted),
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: controller,
                              padding: const EdgeInsets.all(16),
                              itemCount: _events.length,
                              itemBuilder: (context, index) {
                                final event = _events[index];
                                final color = _typeColor(event.type);
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: _border),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: color.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: Icon(Icons.event_note_rounded,
                                            color: color),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    event.title,
                                                    style: const TextStyle(
                                                      color: _text,
                                                      fontWeight: FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: color.withOpacity(0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(99),
                                                  ),
                                                  child: Text(
                                                    event.type.replaceAll('_', ' '),
                                                    style: TextStyle(
                                                      color: color,
                                                      fontSize: 10.5,
                                                      fontWeight: FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 5),
                                            Text(
                                              _pretty(event.displayDate),
                                              style: const TextStyle(
                                                color: _muted,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            if (event.venue.isNotEmpty) ...[
                                              const SizedBox(height: 5),
                                              Text(
                                                'Venue: ${event.venue}',
                                                style:
                                                    const TextStyle(color: _muted),
                                              ),
                                            ],
                                            if (event.description.isNotEmpty) ...[
                                              const SizedBox(height: 7),
                                              Text(
                                                event.description,
                                                style: const TextStyle(
                                                  color: _muted,
                                                  height: 1.35,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}