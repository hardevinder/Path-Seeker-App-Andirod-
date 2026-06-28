import 'package:flutter/material.dart';

import '../../models/employee_leave_request_model.dart';
import '../../services/employee_leave_request_api.dart';

class HrEmployeeLeaveRequestsScreen extends StatefulWidget {
  const HrEmployeeLeaveRequestsScreen({super.key});

  @override
  State<HrEmployeeLeaveRequestsScreen> createState() =>
      _HrEmployeeLeaveRequestsScreenState();
}

class _HrEmployeeLeaveRequestsScreenState
    extends State<HrEmployeeLeaveRequestsScreen> {
  static const Color _accent = Color(0xFFD97706);

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String _status = 'pending';
  String _search = '';
  List<EmployeeLeaveRequest> _requests = [];

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<EmployeeLeaveRequest> get _filteredRequests {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return _requests;

    return _requests.where((request) {
      final blob = [
        request.employeeName,
        request.employeeCode,
        request.departmentName,
        request.designation,
        request.leaveTypeName,
        request.reason,
        request.status,
      ].join(' ').toLowerCase();
      return blob.contains(query);
    }).toList();
  }

  EmployeeLeaveRequest? get _latestPending {
    for (final request in _requests) {
      if (request.isPending) return request;
    }
    return null;
  }

  int get _pendingCount => _requests.where((r) => r.status == 'pending').length;
  int get _approvedCount => _requests.where((r) => r.status == 'approved').length;
  int get _rejectedCount => _requests.where((r) => r.status == 'rejected').length;
  int get _withoutPayCount => _requests.where((r) => r.isWithoutPay).length;

  Future<void> _loadRequests() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await EmployeeLeaveRequestApi.fetchRequests(status: _status);
      if (!mounted) return;
      setState(() => _requests = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(String value) async {
    if (_status == value) return;
    setState(() => _status = value);
    await _loadRequests();
  }

  Future<void> _handleAction(
    EmployeeLeaveRequest request,
    String action,
  ) async {
    final remarks = await _askRemarks(
      action == 'approved' ? 'Approve Leave' : 'Reject Leave',
      action == 'approved'
          ? 'Add approval remarks, if required.'
          : 'Add rejection reason, if required.',
      action == 'approved' ? 'Approve' : 'Reject',
      action == 'approved' ? Colors.green : Colors.red,
    );

    if (remarks == null) return;

    setState(() => _busy = true);
    try {
      await EmployeeLeaveRequestApi.updateStatus(
        id: request.id,
        status: action,
        remarks: remarks,
      );
      if (!mounted) return;
      _showSnack(
        action == 'approved'
            ? 'Leave request approved successfully.'
            : 'Leave request rejected successfully.',
        success: true,
      );
      await _loadRequests();
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askRemarks(
    String title,
    String subtitle,
    String buttonLabel,
    Color buttonColor,
  ) async {
    final controller = TextEditingController();
    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    labelText: 'Remarks',
                    hintText: 'Optional remarks',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, controller.text.trim()),
                        style: FilledButton.styleFrom(
                          backgroundColor: buttonColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(buttonLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    controller.dispose();
    return result;
  }

  void _showSnack(String message, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRequests;
    final latest = _latestPending;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('Employee Leave Requests'),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _loadRequests,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadRequests,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(
                    latest: latest,
                    total: _requests.length,
                    pending: _pendingCount,
                    approved: _approvedCount,
                    rejected: _rejectedCount,
                    withoutPay: _withoutPayCount,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _FilterPanel(
                    selectedStatus: _status,
                    searchController: _searchController,
                    onStatusChanged: _setStatus,
                    onSearchChanged: (value) => setState(() => _search = value),
                  ),
                ),
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _ErrorState(
                      message: _error!,
                      onRetry: _loadRequests,
                    ),
                  )
                else if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(status: _status),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 22),
                    sliver: SliverList.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final request = filtered[index];
                        return _LeaveRequestCard(
                          request: request,
                          onApprove: request.isPending && !_busy
                              ? () => _handleAction(request, 'approved')
                              : null,
                          onReject: request.isPending && !_busy
                              ? () => _handleAction(request, 'rejected')
                              : null,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (_busy)
            Container(
              color: Colors.black.withOpacity(0.08),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final EmployeeLeaveRequest? latest;
  final int total;
  final int pending;
  final int approved;
  final int rejected;
  final int withoutPay;

  const _Header({
    required this.latest,
    required this.total,
    required this.pending,
    required this.approved,
    required this.rejected,
    required this.withoutPay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Review staff leave requests with quick HR approval control.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (latest == null)
            _LatestCard.empty()
          else
            _LatestCard(request: latest!),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _KpiTile(
                  label: 'Total',
                  value: total,
                  icon: Icons.article_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KpiTile(
                  label: 'Pending',
                  value: pending,
                  icon: Icons.pending_actions_rounded,
                  color: const Color(0xFFFFFBEB),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _KpiTile(
                  label: 'Approved',
                  value: approved,
                  icon: Icons.verified_rounded,
                  color: const Color(0xFFECFDF5),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KpiTile(
                  label: 'Rejected',
                  value: rejected,
                  icon: Icons.cancel_rounded,
                  color: const Color(0xFFFEF2F2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KpiTile(
                  label: 'WOP',
                  value: withoutPay,
                  icon: Icons.money_off_rounded,
                  color: const Color(0xFFF5F3FF),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LatestCard extends StatelessWidget {
  final EmployeeLeaveRequest? request;
  final bool isEmpty;

  const _LatestCard({required this.request}) : isEmpty = false;
  const _LatestCard.empty()
      : request = null,
        isEmpty = true;

  @override
  Widget build(BuildContext context) {
    if (isEmpty || request == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: _boxDecoration(),
        child: const Row(
          children: [
            CircleAvatar(
              backgroundColor: Color(0xFFDCFCE7),
              child: Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A)),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'All clear. No pending leave requests right now.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    final item = request!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(name: item.employeeName, color: const Color(0xFFFEF3C7)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Latest Pending Request',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                    Text(
                      item.employeeName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    Text(
                      '${item.departmentName} · ${item.employeeCode.isEmpty ? item.designation : 'Code: ${item.employeeCode}'}',
                      style: const TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _StatusBadge(status: item.status),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(icon: Icons.category_rounded, label: item.leaveTypeName),
              _InfoChip(icon: Icons.date_range_rounded, label: item.dateRange),
              _InfoChip(
                icon: item.isWithoutPay
                    ? Icons.money_off_rounded
                    : Icons.payments_rounded,
                label: item.isWithoutPay ? 'Without Pay' : 'Paid Leave',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Reason: ${item.reason}',
            style: const TextStyle(color: Colors.black87),
          ),
        ],
      ),
    );
  }

  BoxDecoration _boxDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  const _KpiTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF92400E)),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _FilterPanel extends StatelessWidget {
  final String selectedStatus;
  final TextEditingController searchController;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onSearchChanged;

  const _FilterPanel({
    required this.selectedStatus,
    required this.searchController,
    required this.onStatusChanged,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    const options = [
      ('pending', 'Pending'),
      ('approved', 'Approved'),
      ('rejected', 'Rejected'),
      ('all', 'All'),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search employee, department, leave type...',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: options.map((option) {
                final selected = selectedStatus == option.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: selected,
                    label: Text(option.$2),
                    showCheckmark: false,
                    selectedColor: const Color(0xFFFFEDD5),
                    side: BorderSide(
                      color: selected ? const Color(0xFFD97706) : Colors.grey.shade300,
                    ),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected ? const Color(0xFF92400E) : Colors.black87,
                    ),
                    onSelected: (_) => onStatusChanged(option.$1),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaveRequestCard extends StatelessWidget {
  final EmployeeLeaveRequest request;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _LeaveRequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _borderColor(request.status)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Avatar(name: request.employeeName, color: const Color(0xFFEFF6FF)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.employeeName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${request.departmentName} · ${request.designation}',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                      if (request.employeeCode.isNotEmpty)
                        Text(
                          'Code: ${request.employeeCode}',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                _StatusBadge(status: request.status),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(icon: Icons.category_rounded, label: request.leaveTypeName),
                _InfoChip(icon: Icons.date_range_rounded, label: request.dateRange),
                _InfoChip(
                  icon: request.isWithoutPay
                      ? Icons.money_off_rounded
                      : Icons.payments_rounded,
                  label: request.isWithoutPay ? 'Without Pay' : 'Paid Leave',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reason',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(request.reason),
                  if (request.remarks.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'HR Remarks',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(request.remarks),
                  ],
                ],
              ),
            ),
            if (request.isPending) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onApprove,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Approve'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _borderColor(String status) {
    switch (status) {
      case 'approved':
        return const Color(0xFFBBF7D0);
      case 'rejected':
        return const Color(0xFFFECACA);
      default:
        return const Color(0xFFFDE68A);
    }
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final Color color;

  const _Avatar({required this.name, required this.color});

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return CircleAvatar(
      radius: 24,
      backgroundColor: color,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: const TextStyle(
          color: Color(0xFF1E3A8A),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final meta = _meta(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: meta.$2,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        meta.$1,
        style: TextStyle(
          color: meta.$3,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }

  (String, Color, Color) _meta(String status) {
    switch (status) {
      case 'approved':
        return ('APPROVED', const Color(0xFFDCFCE7), const Color(0xFF166534));
      case 'rejected':
        return ('REJECTED', const Color(0xFFFEE2E2), const Color(0xFF991B1B));
      default:
        return ('PENDING', const Color(0xFFFFF7ED), const Color(0xFF9A3412));
    }
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF64748B)),
          const SizedBox(width: 5),
          Text(
            label.isEmpty ? '—' : label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 52, color: Colors.red.shade600),
            const SizedBox(height: 12),
            const Text(
              'Could not load leave requests',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String status;

  const _EmptyState({required this.status});

  @override
  Widget build(BuildContext context) {
    final label = status == 'all' ? 'leave requests' : '$status leave requests';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inbox_rounded,
              size: 62,
              color: Color(0xFFD97706),
            ),
            const SizedBox(height: 12),
            Text(
              'No $label found',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Pull down to refresh or change the status filter.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}