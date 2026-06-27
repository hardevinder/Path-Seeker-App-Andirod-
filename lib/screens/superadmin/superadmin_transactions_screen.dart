import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';

class SuperAdminTransactionsScreen extends StatefulWidget {
  const SuperAdminTransactionsScreen({super.key});

  @override
  State<SuperAdminTransactionsScreen> createState() =>
      _SuperAdminTransactionsScreenState();
}

class _SuperAdminTransactionsScreenState
    extends State<SuperAdminTransactionsScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  bool _loading = true;
  bool _summaryLoading = false;
  String _query = '';
  String _range = '30'; // today, 7, 30, all
  String _status = 'all'; // all, active, cancelled
  String _paymentMode = 'all';

  int _visibleLimit = 30;

  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _sessions = [];
  Map<String, dynamic> _daySummary = {};
  int? _selectedSessionId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);

    try {
      await _loadSessions();
      await Future.wait([
        _loadTransactions(showLoader: false),
        _loadDaySummary(),
      ]);
    } catch (e) {
      _toast('Unable to load transactions.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSessions() async {
    try {
      final list = await ApiService.fetchSuperAdminSessions();

      final normalized = list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      int? activeId;

      for (final s in normalized) {
        final isActive = s['is_active'] == true || s['isActive'] == true;
        if (isActive) {
          activeId = _toInt(s['id']);
          break;
        }
      }

      if (activeId == null && normalized.isNotEmpty) {
        activeId = _toInt(normalized.first['id']);
      }

      _sessions = normalized;
      _selectedSessionId ??= activeId;
    } catch (_) {
      _sessions = [];
    }
  }

  Future<void> _loadTransactions({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() => _loading = true);
    }

    try {
      final rows = await ApiService.fetchSuperAdminTransactions(
        sessionId: _selectedSessionId,
      );

      if (!mounted) return;

      setState(() {
        _transactions = rows;
        _visibleLimit = 30;
      });
    } catch (e) {
      _toast('Transactions load nahi ho payi.');
    } finally {
      if (showLoader && mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadDaySummary() async {
    if (mounted) setState(() => _summaryLoading = true);

    try {
      final summary = await ApiService.fetchSuperAdminTransactionDaySummary(
        sessionId: _selectedSessionId,
      );

      if (!mounted) return;
      setState(() => _daySummary = summary);
    } catch (_) {
      if (!mounted) return;
      setState(() => _daySummary = {});
    } finally {
      if (mounted) setState(() => _summaryLoading = false);
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadTransactions(showLoader: false),
      _loadDaySummary(),
    ]);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _query = value.trim().toLowerCase();
        _visibleLimit = 30;
      });
    });
  }

  List<Map<String, dynamic>> get _processed {
    final now = DateTime.now();

    DateTime? since;
    if (_range == 'today') {
      since = DateTime(now.year, now.month, now.day);
    } else if (_range != 'all') {
      since = now.subtract(Duration(days: int.tryParse(_range) ?? 30));
    }

    final rows = _transactions.where((t) {
      final statusText = _text(t, ['status']).toLowerCase();
      final cancelled = statusText == 'cancelled';

      if (_status == 'active' && cancelled) return false;
      if (_status == 'cancelled' && !cancelled) return false;

      final mode = _text(t, ['PaymentMode', 'paymentMode', 'payment_mode'])
          .toLowerCase();

      if (_paymentMode != 'all' && mode != _paymentMode.toLowerCase()) {
        return false;
      }

      if (since != null) {
        final d = _date(t);
        if (d != null && d.isBefore(since)) return false;
      }

      if (_query.isEmpty) return true;

      final hay = [
        _text(t, ['Student.name', 'Student_Name', 'student_name', 'name']),
        _text(t, ['AdmissionNumber', 'admission_number', 'Admission_No']),
        _text(t, ['Slip_ID', 'slipId', 'slip_id', 'ReceiptNo', 'receipt_no']),
        _text(t, ['PaymentMode', 'paymentMode', 'payment_mode']),
        _text(t, ['Fee_Heading_Name', 'fee_head_name', 'FeeHead.name']),
      ].join(' ').toLowerCase();

      return hay.contains(_query);
    }).toList();

    rows.sort((a, b) {
      final da = _date(a);
      final db = _date(b);

      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;

      return db.compareTo(da);
    });

    return rows;
  }

  List<String> get _paymentModes {
    final modes = <String>{};

    for (final t in _transactions) {
      final mode = _text(t, ['PaymentMode', 'paymentMode', 'payment_mode']);
      if (mode.isNotEmpty && mode != '—') modes.add(mode);
    }

    final list = modes.toList();
    list.sort();
    return list;
  }

  num get _todayTotal {
    final direct = _num(_daySummary, [
      'grandTotal',
      'total',
      'todayTotal',
      'totalAmount',
    ]);

    if (direct > 0) return direct;

    final now = DateTime.now();

    return _transactions.where((t) {
      final d = _date(t);
      if (d == null) return false;
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).fold<num>(0, (sum, t) => sum + _amount(t));
  }

  num get _cashTotal {
    final paymentSummary = _daySummary['paymentSummary'];

    if (paymentSummary is List) {
      return paymentSummary.fold<num>(0, (sum, row) {
        if (row is! Map) return sum;

        final mode = _text(Map<String, dynamic>.from(row), [
          'PaymentMode',
          'paymentMode',
          'payment_mode',
          'mode',
          'name',
        ]).toLowerCase();

        if (mode != 'cash') return sum;

        return sum +
            _num(Map<String, dynamic>.from(row), [
              'TotalAmountCollected',
              'totalAmountCollected',
              'total_amount_collected',
              'amount',
            ]);
      });
    }

    return 0;
  }

  num get _onlineTotal {
    final paymentSummary = _daySummary['paymentSummary'];

    if (paymentSummary is List) {
      return paymentSummary.fold<num>(0, (sum, row) {
        if (row is! Map) return sum;

        final map = Map<String, dynamic>.from(row);

        final mode = _text(map, [
          'PaymentMode',
          'paymentMode',
          'payment_mode',
          'mode',
          'name',
        ]).toLowerCase();

        if (mode == 'cash') return sum;

        return sum +
            _num(map, [
              'TotalAmountCollected',
              'totalAmountCollected',
              'total_amount_collected',
              'amount',
            ]);
      });
    }

    return 0;
  }

  void _openFilters() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        String localStatus = _status;
        String localMode = _paymentMode;
        int? localSessionId = _selectedSessionId;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Transaction Filters',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        )
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_sessions.isNotEmpty)
                      _SheetDropdown<int?>(
                        label: 'Academic Session',
                        value: localSessionId,
                        items: _sessions.map((s) {
                          final id = _toInt(s['id']);
                          final name = _text(s, [
                            'name',
                            'session_name',
                            'label',
                            'title',
                          ]);
                          return DropdownMenuItem<int?>(
                            value: id,
                            child: Text(name == '—' ? 'Session $id' : name),
                          );
                        }).toList(),
                        onChanged: (v) {
                          setSheetState(() => localSessionId = v);
                        },
                      ),
                    const SizedBox(height: 12),
                    _SheetDropdown<String>(
                      label: 'Status',
                      value: localStatus,
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All')),
                        DropdownMenuItem(
                            value: 'active', child: Text('Active')),
                        DropdownMenuItem(
                            value: 'cancelled', child: Text('Cancelled')),
                      ],
                      onChanged: (v) {
                        setSheetState(() => localStatus = v ?? 'all');
                      },
                    ),
                    const SizedBox(height: 12),
                    _SheetDropdown<String>(
                      label: 'Payment Mode',
                      value: localMode,
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('All Modes'),
                        ),
                        ..._paymentModes.map(
                          (m) => DropdownMenuItem(
                            value: m.toLowerCase(),
                            child: Text(m),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        setSheetState(() => localMode = v ?? 'all');
                      },
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _status = 'all';
                                _paymentMode = 'all';
                                _visibleLimit = 30;
                              });
                              Navigator.pop(context);
                            },
                            child: const Text('Reset'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              setState(() {
                                _selectedSessionId = localSessionId;
                                _status = localStatus;
                                _paymentMode = localMode;
                                _visibleLimit = 30;
                              });
                              Navigator.pop(context);
                              await _refreshAll();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1F7AE0),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Apply'),
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
      },
    );
  }

  void _showDetails(Map<String, dynamic> t) {
    final cancelled = _isCancelled(t);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 0.92,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(50),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Receipt ${_receiptNo(t)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      _StatusBadge(cancelled: cancelled),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _DetailCard(
                            title: 'Student Details',
                            children: [
                              _InfoRow(
                                label: 'Student',
                                value: _studentName(t),
                              ),
                              _InfoRow(
                                label: 'Admission No.',
                                value: _admissionNo(t),
                              ),
                              _InfoRow(
                                label: 'Class',
                                value:
                                    '${_className(t)} ${_sectionName(t) == '—' ? '' : '- ${_sectionName(t)}'}',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _DetailCard(
                            title: 'Fee Details',
                            children: [
                              _InfoRow(
                                label: 'Fee Head',
                                value: _text(t, [
                                  'Fee_Heading_Name',
                                  'fee_head_name',
                                  'FeeHead.name',
                                  'FeeHead.Fee_Heading_Name',
                                ]),
                              ),
                              _InfoRow(
                                label: 'Fee Received',
                                value: _inr(_num(t, ['Fee_Recieved'])),
                              ),
                              _InfoRow(
                                label: 'Fine',
                                value: _inr(_num(t, ['Fine_Amount'])),
                              ),
                              _InfoRow(
                                label: 'Transport',
                                value: _inr(_num(t, ['VanFee'])),
                              ),
                              _InfoRow(
                                label: 'Concession',
                                value: _inr(_num(t, ['Concession'])),
                              ),
                              const Divider(),
                              _InfoRow(
                                label: 'Total Amount',
                                value: _inr(_amount(t)),
                                bold: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _DetailCard(
                            title: 'Payment Details',
                            children: [
                              _InfoRow(
                                label: 'Payment Mode',
                                value: _text(t, [
                                  'PaymentMode',
                                  'paymentMode',
                                  'payment_mode',
                                ]),
                              ),
                              _InfoRow(
                                label: 'Reference ID',
                                value: _text(t, [
                                  'Transaction_ID',
                                  'reference_no',
                                  'referenceNo',
                                ]),
                              ),
                              _InfoRow(
                                label: 'Bank',
                                value: _text(t, ['BankName', 'bank_name']),
                              ),
                              _InfoRow(
                                label: 'Cheque No.',
                                value: _text(t, ['ChequeNumber', 'cheque_no']),
                              ),
                              _InfoRow(
                                label: 'Cheque Date',
                                value: _displayDate(_text(t, ['ChequeDate'])),
                              ),
                              _InfoRow(
                                label: 'Date',
                                value: _displayDate(
                                  _text(t, ['DateOfTransaction', 'createdAt']),
                                ),
                              ),
                              _InfoRow(
                                label: 'Remarks',
                                value: _text(t, ['Remarks', 'remarks']),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (!cancelled)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _confirmCancel(t),
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Cancel'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orange.shade800,
                            ),
                          ),
                        ),
                      if (!cancelled) const SizedBox(width: 12),
                      if (cancelled)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _confirmDelete(t),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                          ),
                        ),
                      if (cancelled) const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.check),
                          label: const Text('Done'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1F7AE0),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmCancel(Map<String, dynamic> t) async {
    final id = _toInt(_pick(t, ['id', 'Transaction_ID_ID', 'transaction_id']));

    if (id == null) {
      _toast('Transaction ID missing.');
      return;
    }

    final ok = await _confirm(
      title: 'Cancel Transaction?',
      message: 'This transaction will be marked as cancelled.',
      action: 'Cancel Transaction',
      danger: false,
    );

    if (!ok) return;

    try {
      await ApiService.cancelSuperAdminTransaction(id);
      if (!mounted) return;
      Navigator.pop(context);
      _toast('Transaction cancelled.');
      await _refreshAll();
    } catch (_) {
      _toast('Cancel failed.');
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> t) async {
    final id = _toInt(_pick(t, ['id', 'Transaction_ID_ID', 'transaction_id']));

    if (id == null) {
      _toast('Transaction ID missing.');
      return;
    }

    final ok = await _confirm(
      title: 'Delete Transaction?',
      message: 'Cancelled transaction permanently delete ho jayegi.',
      action: 'Delete',
      danger: true,
    );

    if (!ok) return;

    try {
      await ApiService.deleteSuperAdminTransaction(id);
      if (!mounted) return;
      Navigator.pop(context);
      _toast('Transaction deleted.');
      await _refreshAll();
    } catch (_) {
      _toast('Delete failed.');
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    bool danger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: danger ? Colors.red : const Color(0xFF1F7AE0),
              foregroundColor: Colors.white,
            ),
            child: Text(action),
          ),
        ],
      ),
    );

    return result == true;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Widget _summarySection() {
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _SummaryCard(
            title: 'Today',
            value: _summaryLoading ? '...' : _inr(_todayTotal),
            icon: Icons.today,
            color: const Color(0xFF1F7AE0),
          ),
          _SummaryCard(
            title: 'Cash',
            value: _summaryLoading ? '...' : _inr(_cashTotal),
            icon: Icons.payments_outlined,
            color: const Color(0xFF1C9C63),
          ),
          _SummaryCard(
            title: 'Online',
            value: _summaryLoading ? '...' : _inr(_onlineTotal),
            icon: Icons.account_balance_wallet_outlined,
            color: const Color(0xFF8956E2),
          ),
          _SummaryCard(
            title: 'Records',
            value: '${_processed.length}',
            icon: Icons.receipt_long,
            color: const Color(0xFFE27B2D),
          ),
        ],
      ),
    );
  }

  Widget _filtersSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search receipt, student, admission no...',
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.search),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: _openFilters,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x11000000),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      )
                    ],
                  ),
                  child: const Icon(Icons.tune, color: Color(0xFF1F7AE0)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _RangeChip(
                label: 'Today',
                selected: _range == 'today',
                onTap: () => setState(() {
                  _range = 'today';
                  _visibleLimit = 30;
                }),
              ),
              const SizedBox(width: 8),
              _RangeChip(
                label: '7d',
                selected: _range == '7',
                onTap: () => setState(() {
                  _range = '7';
                  _visibleLimit = 30;
                }),
              ),
              const SizedBox(width: 8),
              _RangeChip(
                label: '30d',
                selected: _range == '30',
                onTap: () => setState(() {
                  _range = '30';
                  _visibleLimit = 30;
                }),
              ),
              const SizedBox(width: 8),
              _RangeChip(
                label: 'All',
                selected: _range == 'all',
                onTap: () => setState(() {
                  _range = 'all';
                  _visibleLimit = 30;
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _transactionCard(Map<String, dynamic> t) {
    final cancelled = _isCancelled(t);

    return InkWell(
      onTap: () => _showDetails(t),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: cancelled
                ? Colors.red.withOpacity(0.18)
                : const Color(0xFFE8EEF8),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            )
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Receipt ${_receiptNo(t)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  _inr(_amount(t)),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: Color(0xFF1F7AE0),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person_outline,
                    size: 18, color: Colors.black45),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _studentName(t),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                _StatusBadge(cancelled: cancelled),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Adm: ${_admissionNo(t)}  •  ${_className(t)} ${_sectionName(t) == '—' ? '' : _sectionName(t)}',
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _MiniTag(
                  icon: Icons.payments_outlined,
                  text: _text(t, [
                    'PaymentMode',
                    'paymentMode',
                    'payment_mode',
                  ]),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniTag(
                    icon: Icons.calendar_today_outlined,
                    text: _displayDate(
                      _text(t, ['DateOfTransaction', 'createdAt']),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      children: const [
        Center(
          child: Column(
            children: [
              Icon(Icons.receipt_long, size: 60, color: Colors.black26),
              SizedBox(height: 12),
              Text(
                'No transactions found',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 6),
              Text(
                'Try changing search or filters.',
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        )
      ],
    );
  }

  Widget _loadingList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemBuilder: (_, __) => Container(
        height: 118,
        decoration: BoxDecoration(
          color: const Color(0xFFEFF5FF),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemCount: 5,
    );
  }

  @override
  Widget build(BuildContext context) {
    final processed = _processed;
    final visible = processed.take(_visibleLimit).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FF),
      appBar: AppBar(
        title: const Text('Transactions'),
        backgroundColor: const Color(0xFF1F7AE0),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          )
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1F7AE0), Color(0xFF6AA7FF)],
                ),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(22),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Super Admin Transactions',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                            SizedBox(height: 5),
                            Text(
                              'Fee collection, receipts and payment records',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child:
                            const Icon(Icons.receipt_long, color: Colors.white),
                      )
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context)
                            .pushNamed('/accounts/collect-fee');
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Collect Fee'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1F7AE0),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _summarySection(),
            _filtersSection(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshAll,
                child: _loading
                    ? _loadingList()
                    : processed.isEmpty
                        ? _emptyState()
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                            itemBuilder: (_, i) {
                              if (i == visible.length) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      setState(() => _visibleLimit += 30);
                                    },
                                    icon: const Icon(Icons.expand_more),
                                    label: const Text('Load more'),
                                  ),
                                );
                              }

                              return _transactionCard(visible[i]);
                            },
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemCount: visible.length +
                                (processed.length > visible.length ? 1 : 0),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static dynamic _pick(Map<String, dynamic> map, List<String> paths) {
    for (final path in paths) {
      dynamic cur = map;

      for (final part in path.split('.')) {
        if (cur is Map && cur.containsKey(part)) {
          cur = cur[part];
        } else {
          cur = null;
          break;
        }
      }

      if (cur != null && cur.toString().trim().isNotEmpty) return cur;
    }

    return null;
  }

  static String _text(Map<String, dynamic> map, List<String> paths) {
    final v = _pick(map, paths);
    final s = (v ?? '').toString().trim();

    if (s.isEmpty ||
        s.toLowerCase() == 'null' ||
        s.toLowerCase() == 'undefined') {
      return '—';
    }

    return s;
  }

  static num _num(Map<String, dynamic> map, List<String> paths) {
    final v = _pick(map, paths);

    if (v == null) return 0;

    if (v is num) return v;

    return num.tryParse(v.toString().replaceAll(',', '').trim()) ?? 0;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  static DateTime? _date(Map<String, dynamic> t) {
    final raw = _text(t, ['DateOfTransaction', 'createdAt', 'updatedAt']);
    if (raw == '—') return null;
    return DateTime.tryParse(raw);
  }

  static String _displayDate(String raw) {
    if (raw == '—') return '—';

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;

    return DateFormat('dd MMM yyyy').format(parsed);
  }

  static String _inr(num value) {
    final f = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: value % 1 == 0 ? 0 : 2,
    );
    return f.format(value);
  }

  static num _amount(Map<String, dynamic> t) {
    final direct = _num(t, [
      'TotalAmount',
      'totalAmount',
      'amount',
      'Amount',
      'Total',
      'total',
    ]);

    if (direct > 0) return direct;

    return _num(t, ['Fee_Recieved']) +
        _num(t, ['Fine_Amount']) +
        _num(t, ['VanFee']);
  }

  static bool _isCancelled(Map<String, dynamic> t) {
    return _text(t, ['status']).toLowerCase() == 'cancelled';
  }

  static String _receiptNo(Map<String, dynamic> t) {
    return _text(t, [
      'Slip_ID',
      'slipId',
      'slip_id',
      'ReceiptNo',
      'receipt_no',
      'id',
    ]);
  }

  static String _studentName(Map<String, dynamic> t) {
    return _text(t, [
      'Student.name',
      'Student.student_name',
      'Student.Student_Name',
      'student.name',
      'Student_Name',
      'student_name',
      'name',
    ]);
  }

  static String _admissionNo(Map<String, dynamic> t) {
    return _text(t, [
      'AdmissionNumber',
      'admission_number',
      'Admission_No',
      'Student.admission_number',
      'Student.AdmissionNumber',
    ]);
  }

  static String _className(Map<String, dynamic> t) {
    return _text(t, [
      'Class.class_name',
      'Class.Class_Name',
      'class_name',
      'Class_Name',
      'Student.Class.class_name',
    ]);
  }

  static String _sectionName(Map<String, dynamic> t) {
    return _text(t, [
      'Section.section_name',
      'Section.Section_Name',
      'section_name',
      'Section_Name',
      'Student.Section.section_name',
    ]);
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 146,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: color.withOpacity(0.12),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1F7AE0) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFE6EEF9)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool cancelled;

  const _StatusBadge({required this.cancelled});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: cancelled ? const Color(0xFFFFE9E9) : const Color(0xFFE9F8F0),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        cancelled ? 'Cancelled' : 'Active',
        style: TextStyle(
          color: cancelled ? Colors.red : const Color(0xFF16834F),
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniTag({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF1F7AE0)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black87,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _DetailCard({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7EEF9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _InfoRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '—' : value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _SheetDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF6F9FF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
