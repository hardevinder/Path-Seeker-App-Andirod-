import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/library_api.dart';
import '../widgets/student_drawer_menu.dart';
import '../widgets/teacher_drawer_menu.dart';

enum LibraryAudience { student, teacher }

class LibraryScreen extends StatefulWidget {
  final LibraryAudience audience;

  const LibraryScreen({
    super.key,
    required this.audience,
  });

  const LibraryScreen.student({super.key}) : audience = LibraryAudience.student;

  const LibraryScreen.teacher({super.key}) : audience = LibraryAudience.teacher;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const Color _primary = Color(0xFF1D4ED8);
  static const Color _ink = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _line = Color(0xFFE3E9F2);

  final _searchController = TextEditingController();
  final _money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  bool _loading = true;
  String? _error;
  String _query = '';
  Map<String, dynamic> _totals = <String, dynamic>{};
  List<Map<String, dynamic>> _issues = <Map<String, dynamic>>[];

  bool get _isTeacher => widget.audience == LibraryAudience.teacher;

  String get _title => _isTeacher ? 'Teacher Library' : 'My Library';

  String get _subtitle => _isTeacher
      ? 'Books issued to you, return status, dues and fines.'
      : 'Your issued books, due dates, returns and pending fines.';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
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
      final payload = await LibraryApi.fetchMyLibrary();
      final issues =
          List<Map<String, dynamic>>.from(payload['issues'] ?? const []);
      final active =
          List<Map<String, dynamic>>.from(payload['active'] ?? const []);
      final distinctBooks = <String>{};

      for (final issue in issues) {
        final id = _string(issue['book_id'] ?? _map(issue['book'])?['id']);
        if (id.isNotEmpty) distinctBooks.add(id);
      }

      if (!mounted) return;
      setState(() {
        _issues = issues;
        _totals = _map(payload['totals']) ??
            {
              'books': distinctBooks.length,
              'copies': issues.length,
              'issuedCopies': active.length,
              'overdueIssues': active.where(_isOverdue).length,
              'lostCopies': issues
                  .where((issue) =>
                      _string(issue['status']).toLowerCase() == 'lost')
                  .length,
            };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredIssues {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _issues;

    return _issues.where((issue) {
      final book = _map(issue['book']);
      final copy = _map(issue['copy']);
      final haystack = [
        book?['title'],
        book?['author'],
        copy?['barcode'],
        issue['borrower_name'],
        issue['borrower_identifier'],
        issue['status'],
      ].map(_string).join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  Map<String, dynamic>? _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  String _string(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text;
  }

  int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(_string(value)) ?? 0;
  }

  num _num(dynamic value) {
    if (value is num) return value;
    return num.tryParse(_string(value).replaceAll(',', '')) ?? 0;
  }

  DateTime? _date(dynamic value) {
    final text = _string(value);
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  String _formatDate(dynamic value) {
    final parsed = _date(value);
    if (parsed == null) return '-';
    return DateFormat('dd MMM yyyy').format(parsed.toLocal());
  }

  bool _isOverdue(Map<String, dynamic> issue) {
    if (issue['is_overdue'] == true) return true;
    final status = _string(issue['status']).toLowerCase();
    final due = _date(issue['due_date']);
    return status == 'issued' && due != null && due.isBefore(DateTime.now());
  }

  Color _statusColor(Map<String, dynamic> issue) {
    final status = _statusLabel(issue).toLowerCase();
    if (status == 'available' || status == 'returned' || status == 'active') {
      return const Color(0xFF0F9D58);
    }
    if (status == 'issued') return _primary;
    if (status == 'overdue') return const Color(0xFFF59E0B);
    if (status == 'lost' || status == 'damaged') return const Color(0xFFEF4444);
    return _muted;
  }

  String _statusLabel(Map<String, dynamic> issue) {
    final status = _string(issue['status']);
    if (_isOverdue(issue) && status.toLowerCase() == 'issued') return 'Overdue';
    return status.isEmpty ? '-' : status;
  }

  Widget _drawer() {
    return _isTeacher ? const TeacherDrawerMenu() : const StudentDrawerMenu();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _drawer(),
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF7F9FC), Color(0xFFEFF4FA)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading && _issues.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    _buildHeader(),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _buildError(),
                    ],
                    const SizedBox(height: 16),
                    _buildStatsGrid(),
                    const SizedBox(height: 16),
                    _buildSearch(),
                    const SizedBox(height: 12),
                    _buildIssueList(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_library_rounded, color: _primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _subtitle,
                  style: const TextStyle(color: _muted, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        border: Border.all(color: const Color(0xFFFECACA)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFF991B1B)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    final active = _int(_totals['issuedCopies']);
    final totalRecords = _int(_totals['copies']);
    final returned = totalRecords - active;
    final stats = [
      _StatData('Borrowed', _int(_totals['books']), Icons.menu_book_rounded,
          _primary),
      _StatData('Records', totalRecords, Icons.receipt_long_rounded,
          const Color(0xFF0F766E)),
      _StatData('Returned', returned < 0 ? 0 : returned,
          Icons.check_circle_rounded, const Color(0xFF0F9D58)),
      _StatData(
          'Issued', active, Icons.outbound_rounded, const Color(0xFF2563EB)),
      _StatData('Overdue', _int(_totals['overdueIssues']),
          Icons.warning_rounded, const Color(0xFFF59E0B)),
      _StatData('Lost', _int(_totals['lostCopies']), Icons.cancel_rounded,
          const Color(0xFFEF4444)),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 700 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stats.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: constraints.maxWidth > 700 ? 2.45 : 1.55,
          ),
          itemBuilder: (context, index) => _buildStatCard(stats[index]),
        );
      },
    );
  }

  Widget _buildStatCard(_StatData stat) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: stat.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(stat.icon, color: stat.color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  '${stat.value}',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _query = value),
      decoration: InputDecoration(
        hintText: 'Search book, barcode or status',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _line),
        ),
      ),
    );
  }

  Widget _buildIssueList() {
    final issues = _filteredIssues;
    if (issues.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _line),
        ),
        child: Column(
          children: const [
            Icon(Icons.local_library_outlined, size: 44, color: _muted),
            SizedBox(height: 10),
            Text(
              'No library records found.',
              style: TextStyle(color: _muted, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isTeacher ? 'Issued To Me' : 'My Issued Books',
          style: const TextStyle(
            color: _ink,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 10),
        ...issues.map(_buildIssueCard),
      ],
    );
  }

  Widget _buildIssueCard(Map<String, dynamic> issue) {
    final book = _map(issue['book']);
    final copy = _map(issue['copy']);
    final title = _string(book?['title']).isEmpty
        ? 'Untitled book'
        : _string(book?['title']);
    final author = _string(book?['author']);
    final barcode =
        _string(copy?['barcode']).isEmpty ? '-' : _string(copy?['barcode']);
    final fine = _num(
        issue['fine_due'] ?? issue['calculated_fine'] ?? issue['fine_amount']);
    final color = _statusColor(issue);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isOverdue(issue) ? const Color(0xFFFBBF24) : _line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.book_rounded, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    if (author.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(author, style: const TextStyle(color: _muted)),
                    ],
                  ],
                ),
              ),
              _StatusPill(label: _statusLabel(issue), color: color),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(Icons.qr_code_rounded, 'Barcode $barcode'),
              _MetaChip(Icons.event_available_rounded,
                  'Issued ${_formatDate(issue['issue_date'])}'),
              _MetaChip(Icons.event_busy_rounded,
                  'Due ${_formatDate(issue['due_date'])}'),
              _MetaChip(Icons.payments_rounded, 'Fine ${_money.format(fine)}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatData {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  const _StatData(this.label, this.value, this.icon, this.color);
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE3E9F2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF6B7280)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF374151),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
