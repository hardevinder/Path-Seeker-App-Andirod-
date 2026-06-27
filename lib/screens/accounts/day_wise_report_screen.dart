import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_service.dart';

const List<Map<String, dynamic>> _defaultModes = [
  {
    'id': 'cash',
    'name': 'Cash',
    'code': 'CASH',
    'requires_bank': false,
    'requires_reference_no': false,
    'requires_cheque_no': false,
    'requires_cheque_date': false,
    'sort_order': 1,
    'active': true,
  },
  {
    'id': 'upi',
    'name': 'UPI',
    'code': 'UPI',
    'requires_bank': true,
    'requires_reference_no': true,
    'requires_cheque_no': false,
    'requires_cheque_date': false,
    'sort_order': 2,
    'active': true,
  },
  {
    'id': 'cheque',
    'name': 'Cheque',
    'code': 'CHEQUE',
    'requires_bank': true,
    'requires_reference_no': false,
    'requires_cheque_no': true,
    'requires_cheque_date': true,
    'sort_order': 3,
    'active': true,
  },
  {
    'id': 'card',
    'name': 'Card',
    'code': 'CARD',
    'requires_bank': true,
    'requires_reference_no': true,
    'requires_cheque_no': false,
    'requires_cheque_date': false,
    'sort_order': 4,
    'active': true,
  },
  {
    'id': 'netbanking',
    'name': 'Net Banking',
    'code': 'NETBANKING',
    'requires_bank': true,
    'requires_reference_no': true,
    'requires_cheque_no': false,
    'requires_cheque_date': false,
    'sort_order': 5,
    'active': true,
  },
  {
    'id': 'online',
    'name': 'Online',
    'code': 'ONLINE',
    'requires_bank': false,
    'requires_reference_no': true,
    'requires_cheque_no': false,
    'requires_cheque_date': false,
    'sort_order': 6,
    'active': true,
  },
];

class AccountsDayWiseReportScreen extends StatefulWidget {
  const AccountsDayWiseReportScreen({super.key});

  @override
  State<AccountsDayWiseReportScreen> createState() =>
      _AccountsDayWiseReportScreenState();
}

class _AccountsDayWiseReportScreenState
    extends State<AccountsDayWiseReportScreen> {
  final DateFormat _apiDate = DateFormat('yyyy-MM-dd');
  final DateFormat _displayDate = DateFormat('dd MMM yyyy');
  final DateFormat _displayDateTime = DateFormat('dd/MM/yyyy hh:mm a');
  final TextEditingController _searchController = TextEditingController();

  DateTime? _startDate = DateTime.now();
  DateTime? _endDate = DateTime.now();
  bool _loading = false;
  bool _busy = false;
  String? _error;
  String _activeRole = '';

  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _modes = _defaultModes;
  List<Map<String, dynamic>> _banks = [];
  Map<String, dynamic>? _school;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasData => _rows.isNotEmpty;
  bool get _canManage => [
        'admin',
        'superadmin',
        'account',
        'accounts',
        'accountant'
      ].contains(_activeRole.toLowerCase());
  bool get _canDelete => _activeRole.toLowerCase() == 'superadmin';

  List<Map<String, dynamic>> get _filteredRows {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows.where((row) {
      final haystack = [
        _studentName(row),
        _studentAdmission(row),
        row['Slip_ID'],
        row['feeHeadingName'],
        row['PaymentMode'],
        row['DateOfTransaction'],
        row['status'],
        row['reference_no'],
        row['Transaction_ID'],
        row['bank_name'],
        row['BankName'],
        row['cheque_no'],
        row['ChequeNumber'],
      ].map(_safe).join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  Map<String, num> get _totalSummary {
    return _filteredRows.fold(
      {
        'fee': 0,
        'concession': 0,
        'van': 0,
        'vanConcession': 0,
        'fine': 0,
        'received': 0,
      },
      (acc, row) {
        final fee = _amount(row['totalFeeReceived'] ?? row['Fee_Recieved']);
        final concession = _amount(row['totalConcession'] ?? row['Concession']);
        final van = _amount(row['totalVanFee'] ?? row['VanFee']);
        final vanConcession = _amount(row['totalVanFeeConcession']);
        final fine = _amount(row['totalFine'] ?? row['Fine_Amount']);
        acc['fee'] = acc['fee']! + fee;
        acc['concession'] = acc['concession']! + concession;
        acc['van'] = acc['van']! + van;
        acc['vanConcession'] = acc['vanConcession']! + vanConcession;
        acc['fine'] = acc['fine']! + fine;
        acc['received'] = acc['received']! + fee + van + fine;
        return acc;
      },
    );
  }

  Map<String, Map<String, num>> get _paymentModeSummary {
    final summary = <String, Map<String, num>>{};
    for (final row in _filteredRows) {
      final key = _isOnline(row['PaymentMode'])
          ? 'Online'
          : _isCash(row['PaymentMode'])
              ? 'Cash'
              : _safe(row['PaymentMode'], 'Other');
      summary.putIfAbsent(
        key,
        () => {'count': 0, 'received': 0, 'fee': 0, 'van': 0, 'fine': 0},
      );
      final fee = _amount(row['totalFeeReceived'] ?? row['Fee_Recieved']);
      final van = _amount(row['totalVanFee'] ?? row['VanFee']);
      final fine = _amount(row['totalFine'] ?? row['Fine_Amount']);
      summary[key]!['count'] = summary[key]!['count']! + 1;
      summary[key]!['fee'] = summary[key]!['fee']! + fee;
      summary[key]!['van'] = summary[key]!['van']! + van;
      summary[key]!['fine'] = summary[key]!['fine']! + fine;
      summary[key]!['received'] = summary[key]!['received']! + fee + van + fine;
    }
    return summary;
  }

  List<_HeadingSummary> get _headingSummary {
    final byHeading = <String, List<Map<String, dynamic>>>{};
    for (final row in _filteredRows) {
      final heading = _safe(row['feeHeadingName'], '-');
      byHeading.putIfAbsent(heading, () => []).add(row);
    }

    return byHeading.entries.map((entry) {
      final cash =
          _sumRows(entry.value.where((row) => _isCash(row['PaymentMode'])));
      final online =
          _sumRows(entry.value.where((row) => _isOnline(row['PaymentMode'])));
      return _HeadingSummary(entry.key, cash, online);
    }).toList()
      ..sort((a, b) => a.heading.compareTo(b.heading));
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _activeRole = prefs.getString('activeRole') ?? '');
    await Future.wait([
      _loadMasters(),
      _loadSchool(),
    ]);
    await _generateReport();
  }

  Future<void> _loadSchool() async {
    try {
      final response = await ApiService.rawGet('/schools');
      if (!_ok(response.statusCode)) return;
      final decoded = jsonDecode(response.body);
      final rows = _extractRows(decoded, preferredKeys: const ['schools']);
      if (!mounted) return;
      setState(() {
        if (rows.isNotEmpty) {
          _school = rows.first;
        } else if (decoded is Map) {
          final school = decoded['school'] ?? decoded['data'];
          if (school is Map) _school = Map<String, dynamic>.from(school);
        }
      });
    } catch (_) {}
  }

  Future<void> _loadMasters() async {
    try {
      final results = await Future.wait([
        _getList('/mode-of-transactions'),
        _getList('/school-bank-accounts?active_only=true'),
      ]);
      if (!mounted) return;
      setState(() {
        final modes = results[0].map(_normalizeMode).where(_isActive).toList();
        _modes = modes.isEmpty ? _defaultModes : modes
          ..sort(_sortByOrderName);
        _banks = results[1].map(_normalizeBank).where(_isActive).toList()
          ..sort(_sortByOrderName);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _modes = _defaultModes);
    }
  }

  Future<List<Map<String, dynamic>>> _getList(String endpoint) async {
    final response = await ApiService.rawGet(endpoint);
    if (!_ok(response.statusCode)) return <Map<String, dynamic>>[];
    return _extractRows(jsonDecode(response.body));
  }

  Future<void> _generateReport() async {
    if (_startDate == null || _endDate == null) {
      _showSnack('Please select both start and end dates.');
      return;
    }
    if (_startDate!.isAfter(_endDate!)) {
      _showSnack('Start date cannot be after end date.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final start = _apiDate.format(_startDate!);
      final end = _apiDate.format(_endDate!);
      final response = await ApiService.rawGet(
        '/reports/day-wise?startDate=$start&endDate=$end&includeCancelled=true',
      );
      if (!_ok(response.statusCode)) {
        throw Exception(
            _apiError(response.body, 'Error fetching report data.'));
      }
      final decoded = jsonDecode(response.body);
      if (!mounted) return;
      setState(() => _rows = _extractRows(decoded));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadExcel() async {
    if (_startDate == null || _endDate == null) {
      _showSnack('Please select both start and end dates.');
      return;
    }
    setState(() => _busy = true);
    try {
      final start = _apiDate.format(_startDate!);
      final end = _apiDate.format(_endDate!);
      final response = await ApiService.rawGet(
        '/reports/day-wise?startDate=$start&endDate=$end&format=excel&includeCancelled=true',
        extraHeaders: const {
          'Accept':
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        },
      );
      if (!_ok(response.statusCode) || response.bodyBytes.isEmpty) {
        _showSnack(
            _apiError(response.body, 'Failed to download Excel report.'));
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/DayWiseReport_${start}_to_$end.xlsx');
      await file.writeAsBytes(response.bodyBytes, flush: true);
      await OpenFilex.open(file.path);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openReceipt(dynamic slipId) async {
    if (_safe(slipId).isEmpty) return;
    setState(() => _busy = true);
    try {
      final rows = await _fetchReceiptRows(slipId);
      if (!mounted) return;
      if (rows.isEmpty) {
        _showSnack('Server returned no receipt data.');
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _ReceiptSheet(
          slipId: _safe(slipId),
          rows: rows,
          displayDateTime: _displayDateTime,
          onPrint: () => _printReceipt(slipId),
        ),
      );
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchReceiptRows(dynamic slipId) async {
    final response = await ApiService.rawGet('/transactions/slip/$slipId');
    if (!_ok(response.statusCode)) {
      throw Exception(_apiError(response.body, 'Failed to load receipt.'));
    }
    final decoded = jsonDecode(response.body);
    return _extractRows(decoded, preferredKeys: const ['receipt', 'data']);
  }

  Future<void> _printReceipt(dynamic slipId) async {
    setState(() => _busy = true);
    try {
      final receipt = await _fetchReceiptRows(slipId);
      if (receipt.isEmpty) {
        _showSnack('Server returned no receipt data.');
        return;
      }
      final school = _school ?? _schoolFromReceipt(receipt.first);
      final payload = {
        'receipt': receipt,
        'school': school,
        'fileName': 'Receipt-$slipId',
      };
      final response = await ApiService.rawPost(
        '/receipt-pdf/receipt/generate-pdf',
        payload,
        extraHeaders: const {'Accept': 'application/pdf'},
      );
      final bytes = response.bodyBytes;
      final isPdf = bytes.length > 4 &&
          bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46;
      if (!_ok(response.statusCode) || !isPdf) {
        _showSnack(_apiError(response.body, 'Failed to generate receipt PDF.'));
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/Receipt-$slipId.pdf');
      await file.writeAsBytes(bytes, flush: true);
      await OpenFilex.open(file.path);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelTransaction(Map<String, dynamic> row) async {
    final serial = _txnSerial(row);
    if (serial == null) {
      _showSnack('Serial missing in report row.');
      return;
    }
    final confirmed = await _confirm(
      'Cancel transaction?',
      'This transaction will be marked as cancelled.',
      'Cancel Transaction',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      final response =
          await ApiService.rawPost('/transactions/$serial/cancel', {});
      if (!_ok(response.statusCode)) {
        _showSnack(_apiError(response.body, 'Unable to cancel transaction.'));
        return;
      }
      _showSnack('Transaction cancelled.');
      await _generateReport();
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteTransaction(Map<String, dynamic> row) async {
    final serial = _txnSerial(row);
    if (serial == null) {
      _showSnack('Serial missing in report row.');
      return;
    }
    final confirmed = await _confirm(
      'Delete transaction permanently?',
      'This action cannot be undone.',
      'Delete',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      final response = await ApiService.rawDelete('/transactions/$serial');
      if (!_ok(response.statusCode)) {
        _showSnack(_apiError(response.body, 'Unable to delete transaction.'));
        return;
      }
      _showSnack('Transaction deleted.');
      await _generateReport();
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openEditSheet(Map<String, dynamic> row) async {
    final serial = _txnSerial(row);
    if (serial == null) {
      _showSnack('Serial missing in report row.');
      return;
    }
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _TransactionEditSheet(
        row: row,
        modes: _modes,
        banks: _banks,
        displayDate: _displayDate,
        onSave: _saveEditedTransaction,
      ),
    );
    if (saved == true) await _generateReport();
  }

  Future<bool> _saveEditedTransaction(
    int serial,
    Map<String, dynamic> payload,
  ) async {
    setState(() => _busy = true);
    try {
      final response =
          await ApiService.rawPut('/transactions/$serial', payload);
      if (!_ok(response.statusCode)) {
        _showSnack(_apiError(response.body, 'Unable to update transaction.'));
        return false;
      }
      _showSnack('Transaction updated.');
      return true;
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows;
    final totals = _totalSummary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Day Wise Report'),
        actions: [
          IconButton(
            tooltip: 'Download Excel',
            onPressed: _hasData && !_busy ? _downloadExcel : null,
            icon: const Icon(Icons.download_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _generateReport,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _generateReport,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
              children: [
                _hero(rows.length, totals),
                const SizedBox(height: 12),
                _filters(),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _notice(_error!, Colors.red.shade700),
                ],
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (!_hasData)
                  _emptyState()
                else ...[
                  _paymentSummary(),
                  const SizedBox(height: 12),
                  _headingSummaryCard(),
                  const SizedBox(height: 12),
                  Text(
                    'Collection Report',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  ...rows.map(_transactionCard),
                ],
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

  Widget _hero(int shownCount, Map<String, num> totals) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.calendar_today_rounded, color: Colors.white, size: 34),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Day Wise Report',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _heroStat('Records', '$shownCount'),
              _heroStat('Received', _money(totals['received'])),
              _heroStat('Concession', _money(totals['concession'])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filters() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _dateButton(
                  'Start Date',
                  _startDate,
                  (date) => setState(() => _startDate = date),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dateButton(
                  'End Date',
                  _endDate,
                  (date) => setState(() => _endDate = date),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchController,
            enabled: _hasData,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Search: name / adm / slip / heading / mode',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _generateReport,
              icon: const Icon(Icons.analytics_rounded),
              label: Text(_loading ? 'Generating...' : 'Generate Report'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateButton(
    String label,
    DateTime? value,
    ValueChanged<DateTime> onChanged,
  ) {
    return OutlinedButton.icon(
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
        );
        if (picked != null) onChanged(picked);
      },
      icon: const Icon(Icons.calendar_month_rounded, size: 18),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          value == null ? label : _displayDate.format(value),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _paymentSummary() {
    final summary = _paymentModeSummary;
    if (summary.isEmpty) return const SizedBox.shrink();
    return _sectionCard(
      title: 'Payment Mode Summary',
      subtitle: 'HDFC and UPI/Card/Net Banking are counted under Online',
      child: Column(
        children: summary.entries
            .map(
              (entry) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.key,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${entry.value['count']?.round() ?? 0} records'),
                trailing: Text(
                  _money(entry.value['received']),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _headingSummaryCard() {
    final rows = _headingSummary;
    if (rows.isEmpty) return const SizedBox.shrink();
    return _sectionCard(
      title: 'Fee Heading Summary',
      subtitle: 'Cash vs Online vs Overall',
      child: Column(
        children: rows
            .take(12)
            .map(
              (row) => ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  row.heading,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('Overall: ${_money(row.overall.received)}'),
                children: [
                  _summaryLine('Cash', row.cash),
                  _summaryLine('Online', row.online),
                  _summaryLine('Overall', row.overall),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _summaryLine(String label, _Amounts amounts) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 74, child: Text(label)),
          Expanded(child: Text('Fee ${_money(amounts.fee)}')),
          Expanded(child: Text('Fine ${_money(amounts.fine)}')),
          Expanded(child: Text('Total ${_money(amounts.received)}')),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _transactionCard(Map<String, dynamic> row) {
    final fee = _amount(row['totalFeeReceived'] ?? row['Fee_Recieved']);
    final van = _amount(row['totalVanFee'] ?? row['VanFee']);
    final fine = _amount(row['totalFine'] ?? row['Fine_Amount']);
    final total = fee + van + fine;
    final serial = _txnSerial(row);
    final cancelled = _isCancelled(row);
    final modeLabel = _safe(
        row['modeOfTransaction'] is Map
            ? row['modeOfTransaction']['name']
            : row['PaymentMode'],
        'Other');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _studentName(row),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Slip ${_safe(row['Slip_ID'], '-')} • ${_studentAdmission(row)}',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                _modeChip(modeLabel, cancelled),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _infoChip(Icons.school_rounded, _studentClass(row)),
                _infoChip(
                    Icons.bookmark_rounded, _safe(row['feeHeadingName'], '-')),
                _infoChip(Icons.schedule_rounded, _formatTxnDate(row)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _amountBox('Fee', fee),
                _amountBox('Van', van),
                _amountBox('Fine', fine),
                _amountBox('Total', total, strong: true),
              ],
            ),
            if (_safe(row['Remarks']).isNotEmpty ||
                _safe(row['reference_no'] ?? row['Transaction_ID'])
                    .isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                [
                  if (_safe(row['reference_no'] ?? row['Transaction_ID'])
                      .isNotEmpty)
                    'Ref: ${_safe(row['reference_no'] ?? row['Transaction_ID'])}',
                  if (_safe(row['bank_name'] ?? row['BankName']).isNotEmpty)
                    'Bank: ${_safe(row['bank_name'] ?? row['BankName'])}',
                  if (_safe(row['Remarks']).isNotEmpty)
                    'Remarks: ${_safe(row['Remarks'])}',
                ].join(' • '),
              ),
            ],
            if (serial == null) ...[
              const SizedBox(height: 8),
              _notice('Serial missing in report row.', Colors.red.shade700),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openReceipt(row['Slip_ID']),
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text('View'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _printReceipt(row['Slip_ID']),
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: const Text('Print'),
                ),
                if (_canManage && !cancelled)
                  OutlinedButton.icon(
                    onPressed:
                        serial == null ? null : () => _openEditSheet(row),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Edit'),
                  ),
                if (_canManage && !cancelled)
                  OutlinedButton.icon(
                    onPressed:
                        serial == null ? null : () => _cancelTransaction(row),
                    icon: const Icon(Icons.cancel_rounded, size: 18),
                    label: const Text('Cancel'),
                  ),
                if (_canDelete && cancelled)
                  OutlinedButton.icon(
                    onPressed:
                        serial == null ? null : () => _deleteTransaction(row),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Delete'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeChip(String mode, bool cancelled) {
    final color = cancelled
        ? const Color(0xFFDC2626)
        : _isCash(mode)
            ? const Color(0xFF16A34A)
            : _isOnline(mode)
                ? const Color(0xFF2563EB)
                : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        cancelled ? 'CANCELLED' : mode,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF475569)),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _amountBox(String label, num value, {bool strong = false}) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: strong ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 11)),
            Text(
              _money(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notice(String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: color)),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(Icons.receipt_long_rounded,
              size: 46, color: Colors.grey.shade500),
          const SizedBox(height: 10),
          const Text(
            'No data available',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Select a date range and generate the report.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  String _formatTxnDate(Map<String, dynamic> row) {
    final raw = _safe(row['DateOfTransaction'] ?? row['createdAt']);
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw.isEmpty ? '-' : raw;
    return _displayDateTime.format(parsed.toLocal());
  }

  Map<String, dynamic> _schoolFromReceipt(Map<String, dynamic> item) {
    final school = item['School'] ?? item['school'];
    if (school is Map) return Map<String, dynamic>.from(school);
    return {
      'name':
          _safe(item['schoolName'] ?? item['institute_name'], 'Your School'),
      'address': _safe(item['schoolAddress'] ?? item['address']),
      'logo': item['logo'],
    };
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _TransactionEditSheet extends StatefulWidget {
  const _TransactionEditSheet({
    required this.row,
    required this.modes,
    required this.banks,
    required this.displayDate,
    required this.onSave,
  });

  final Map<String, dynamic> row;
  final List<Map<String, dynamic>> modes;
  final List<Map<String, dynamic>> banks;
  final DateFormat displayDate;
  final Future<bool> Function(int serial, Map<String, dynamic> payload) onSave;

  @override
  State<_TransactionEditSheet> createState() => _TransactionEditSheetState();
}

class _TransactionEditSheetState extends State<_TransactionEditSheet> {
  late DateTime _transactionDate;
  late Map<String, dynamic> _mode;
  int? _bankId;

  late final TextEditingController _reference;
  late final TextEditingController _bankName;
  late final TextEditingController _chequeNo;
  late final TextEditingController _chequeDate;
  late final TextEditingController _fee;
  late final TextEditingController _concession;
  late final TextEditingController _van;
  late final TextEditingController _fine;
  late final TextEditingController _remarks;

  @override
  void initState() {
    super.initState();
    final modes = widget.modes.isEmpty ? _defaultModes : widget.modes;
    _mode = _findMode(widget.row['mode_of_transaction_id'], modes) ??
        _findMode(widget.row['PaymentMode'], modes) ??
        modes.first;
    _bankId = _toInt(widget.row['bank_account_id']);
    _transactionDate =
        DateTime.tryParse(_safe(widget.row['DateOfTransaction'])) ??
            DateTime.now();
    _reference = TextEditingController(
      text: _safe(widget.row['reference_no'] ?? widget.row['Transaction_ID']),
    );
    _bankName = TextEditingController(
      text: _safe(widget.row['bank_name'] ?? widget.row['BankName']),
    );
    _chequeNo = TextEditingController(
      text: _safe(widget.row['cheque_no'] ?? widget.row['ChequeNumber']),
    );
    _chequeDate = TextEditingController(
      text:
          _normalizeDate(widget.row['cheque_date'] ?? widget.row['ChequeDate']),
    );
    _fee = TextEditingController(
      text:
          '${_amount(widget.row['Fee_Recieved'] ?? widget.row['totalFeeReceived'])}',
    );
    _concession = TextEditingController(
      text:
          '${_amount(widget.row['Concession'] ?? widget.row['totalConcession'])}',
    );
    _van = TextEditingController(
      text: '${_amount(widget.row['VanFee'] ?? widget.row['totalVanFee'])}',
    );
    _fine = TextEditingController(
      text: '${_amount(widget.row['Fine_Amount'] ?? widget.row['totalFine'])}',
    );
    _remarks = TextEditingController(text: _safe(widget.row['Remarks']));
  }

  @override
  void dispose() {
    _reference.dispose();
    _bankName.dispose();
    _chequeNo.dispose();
    _chequeDate.dispose();
    _fee.dispose();
    _concession.dispose();
    _van.dispose();
    _fine.dispose();
    _remarks.dispose();
    super.dispose();
  }

  bool get _needsBank => _asBool(_mode['requires_bank']);
  bool get _needsReference => _asBool(_mode['requires_reference_no']);
  bool get _needsChequeNo => _asBool(_mode['requires_cheque_no']);
  bool get _needsChequeDate => _asBool(_mode['requires_cheque_date']);
  bool get _needsChequeFields => _needsChequeNo || _needsChequeDate;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Edit Transaction',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text('Slip ${_safe(widget.row['Slip_ID'], '-')}'),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month_rounded),
              label: Text(widget.displayDate.format(_transactionDate)),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _safe(_mode['id']),
              decoration: const InputDecoration(
                labelText: 'Payment Mode',
                border: OutlineInputBorder(),
              ),
              items: widget.modes
                  .map(
                    (mode) => DropdownMenuItem(
                      value: _safe(mode['id']),
                      child: Text(_safe(mode['name'], 'Mode')),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                final mode = widget.modes.firstWhere(
                  (m) => _safe(m['id']) == value,
                  orElse: () => widget.modes.first,
                );
                setState(() => _mode = mode);
              },
            ),
            if (_needsBank) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: _bankId,
                decoration: const InputDecoration(
                  labelText: 'Receiving Bank Account',
                  border: OutlineInputBorder(),
                ),
                items: widget.banks
                    .map(
                      (bank) => DropdownMenuItem(
                        value: _toInt(bank['id']),
                        child: Text(_bankLabel(bank)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  final bank =
                      widget.banks.where((b) => _toInt(b['id']) == value);
                  setState(() {
                    _bankId = value;
                    if (bank.isNotEmpty)
                      _bankName.text = _safe(bank.first['bank_name']);
                  });
                },
              ),
            ],
            if (_needsReference) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _reference,
                decoration: const InputDecoration(
                  labelText: 'Reference / Transaction ID',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_needsChequeNo) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _chequeNo,
                decoration: const InputDecoration(
                  labelText: 'Cheque Number',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_needsChequeDate) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _chequeDate,
                decoration: const InputDecoration(
                  labelText: 'Cheque Date (yyyy-MM-dd)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_needsBank || _needsChequeFields) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _bankName,
                decoration: const InputDecoration(
                  labelText: 'Bank Name / Instrument Bank',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _amountField('Fee Received', _fee)),
                const SizedBox(width: 8),
                Expanded(child: _amountField('Concession', _concession)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _amountField('Van Fee', _van)),
                const SizedBox(width: 8),
                Expanded(child: _amountField('Fine', _fine)),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _remarks,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Remarks',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration:
          InputDecoration(labelText: label, border: const OutlineInputBorder()),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _transactionDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _transactionDate = picked);
  }

  Future<void> _save() async {
    if (_needsBank && _bankId == null) {
      _snack('Receiving bank account is required for this payment mode.');
      return;
    }
    if (_needsReference && _reference.text.trim().isEmpty) {
      _snack('Reference / Transaction ID is required for this payment mode.');
      return;
    }
    if (_needsChequeNo && _chequeNo.text.trim().isEmpty) {
      _snack('Cheque number is required for cheque payment.');
      return;
    }
    if (_needsChequeDate && _chequeDate.text.trim().isEmpty) {
      _snack('Cheque date is required for cheque payment.');
      return;
    }

    final serial = _txnSerial(widget.row);
    if (serial == null) {
      _snack('Transaction Serial not found.');
      return;
    }

    final payload = {
      'Fee_Recieved': _amount(_fee.text),
      'Concession': _amount(_concession.text),
      'VanFee': _amount(_van.text),
      'Fine_Amount': _amount(_fine.text),
      'PaymentMode': _safe(_mode['name'], 'Cash'),
      'mode_of_transaction_id': _mode['id'],
      'bank_account_id': _needsBank ? _bankId : null,
      'reference_no': _needsReference ? _reference.text.trim() : null,
      'Transaction_ID': _needsReference ? _reference.text.trim() : null,
      'bank_name':
          (_needsBank || _needsChequeFields) ? _bankName.text.trim() : null,
      'BankName':
          (_needsBank || _needsChequeFields) ? _bankName.text.trim() : null,
      'cheque_no': _needsChequeNo ? _chequeNo.text.trim() : null,
      'ChequeNumber': _needsChequeNo ? _chequeNo.text.trim() : null,
      'cheque_date': _needsChequeDate ? _chequeDate.text.trim() : null,
      'ChequeDate': _needsChequeDate ? _chequeDate.text.trim() : null,
      'DateOfTransaction': _transactionDate.toIso8601String(),
      'Remarks': _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
    };

    final ok = await widget.onSave(serial, payload);
    if (ok && mounted) Navigator.pop(context, true);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _ReceiptSheet extends StatelessWidget {
  const _ReceiptSheet({
    required this.slipId,
    required this.rows,
    required this.displayDateTime,
    required this.onPrint,
  });

  final String slipId;
  final List<Map<String, dynamic>> rows;
  final DateFormat displayDateTime;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final total = rows.fold<num>(0, (sum, row) {
      return sum +
          _amount(row['Fee_Recieved'] ?? row['totalFeeReceived']) +
          _amount(row['VanFee'] ?? row['totalVanFee']) +
          _amount(row['Fine_Amount'] ?? row['totalFine']);
    });
    final first = rows.first;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, controller) {
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Receipt $slipId',
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
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  children: [
                    _detail('Student', _studentName(first)),
                    _detail('Admission', _studentAdmission(first)),
                    _detail('Class', _studentClass(first)),
                    _detail('Date', _formatDate(first)),
                    const SizedBox(height: 10),
                    ...rows.map(_receiptRow),
                    const Divider(height: 22),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Total Received',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        Text(
                          _money(total),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: onPrint,
                        icon: const Icon(Icons.print_rounded),
                        label: const Text('Print Receipt PDF'),
                      ),
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

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 94,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _receiptRow(Map<String, dynamic> row) {
    final fee = _amount(row['Fee_Recieved'] ?? row['totalFeeReceived']);
    final van = _amount(row['VanFee'] ?? row['totalVanFee']);
    final fine = _amount(row['Fine_Amount'] ?? row['totalFine']);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(_safe(
            row['feeHeadingName'] ?? row['FeeHeading'] ?? row['fee_heading'],
            '-')),
        subtitle: Text(_safe(row['PaymentMode'], 'Cash')),
        trailing: Text(_money(fee + van + fine)),
      ),
    );
  }

  String _formatDate(Map<String, dynamic> row) {
    final parsed =
        DateTime.tryParse(_safe(row['DateOfTransaction'] ?? row['createdAt']));
    if (parsed == null) return '-';
    return displayDateTime.format(parsed.toLocal());
  }
}

class _HeadingSummary {
  _HeadingSummary(this.heading, this.cash, this.online);
  final String heading;
  final _Amounts cash;
  final _Amounts online;
  _Amounts get overall => cash + online;
}

class _Amounts {
  const _Amounts({
    this.fee = 0,
    this.concession = 0,
    this.van = 0,
    this.vanConcession = 0,
    this.fine = 0,
    this.received = 0,
  });

  final num fee;
  final num concession;
  final num van;
  final num vanConcession;
  final num fine;
  final num received;

  _Amounts operator +(_Amounts other) {
    return _Amounts(
      fee: fee + other.fee,
      concession: concession + other.concession,
      van: van + other.van,
      vanConcession: vanConcession + other.vanConcession,
      fine: fine + other.fine,
      received: received + other.received,
    );
  }
}

_Amounts _sumRows(Iterable<Map<String, dynamic>> rows) {
  num fee = 0;
  num concession = 0;
  num van = 0;
  num vanConcession = 0;
  num fine = 0;
  for (final row in rows) {
    fee += _amount(row['totalFeeReceived'] ?? row['Fee_Recieved']);
    concession += _amount(row['totalConcession'] ?? row['Concession']);
    van += _amount(row['totalVanFee'] ?? row['VanFee']);
    vanConcession += _amount(row['totalVanFeeConcession']);
    fine += _amount(row['totalFine'] ?? row['Fine_Amount']);
  }
  return _Amounts(
    fee: fee,
    concession: concession,
    van: van,
    vanConcession: vanConcession,
    fine: fine,
    received: fee + van + fine,
  );
}

List<Map<String, dynamic>> _extractRows(
  dynamic decoded, {
  List<String> preferredKeys = const [],
}) {
  if (decoded is List) {
    return decoded
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
  if (decoded is Map) {
    for (final key in [
      ...preferredKeys,
      'data',
      'rows',
      'results',
      'items',
      'list',
      'records',
      'modes',
      'bankAccounts',
    ]) {
      final value = decoded[key];
      if (value is List) return _extractRows(value);
      final data = decoded['data'];
      if (data is Map && data[key] is List) return _extractRows(data[key]);
    }
    if (decoded['data'] is Map)
      return [Map<String, dynamic>.from(decoded['data'])];
    if (decoded['receipt'] is Map) {
      return [Map<String, dynamic>.from(decoded['receipt'])];
    }
  }
  return <Map<String, dynamic>>[];
}

Map<String, dynamic> _normalizeMode(Map<String, dynamic> row) {
  return {
    'id': row['id'] ?? row['code'] ?? row['name'],
    'name': _first(row['name'], row['label'], row['title'], row['code']),
    'code': _first(row['code'], row['short_code'], row['slug']),
    'description': _safe(row['description']),
    'requires_bank': _asBool(row['requires_bank']),
    'requires_reference_no': _asBool(row['requires_reference_no']),
    'requires_cheque_no': _asBool(row['requires_cheque_no']),
    'requires_cheque_date': _asBool(row['requires_cheque_date']),
    'sort_order': _toInt(row['sort_order']) ?? 0,
    'active': row['active'] != false,
  };
}

Map<String, dynamic> _normalizeBank(Map<String, dynamic> row) {
  return {
    'id': _toInt(row['id'] ?? row['bank_account_id'] ?? row['bankAccountId']),
    'bank_name': _first(row['bank_name'], row['bankName'], row['name']),
    'account_name':
        _first(row['account_name'], row['accountName'], row['title']),
    'account_number': _first(row['account_number'], row['accountNumber']),
    'sort_order': _toInt(row['sort_order']) ?? 0,
    'active': row['active'] != false,
  };
}

int _sortByOrderName(Map<String, dynamic> a, Map<String, dynamic> b) {
  final byOrder =
      (_toInt(a['sort_order']) ?? 0).compareTo(_toInt(b['sort_order']) ?? 0);
  if (byOrder != 0) return byOrder;
  return _safe(a['name'] ?? a['bank_name'])
      .compareTo(_safe(b['name'] ?? b['bank_name']));
}

bool _isActive(Map<String, dynamic> row) =>
    row['active'] != false && _safe(row['name'] ?? row['bank_name']).isNotEmpty;

String _bankLabel(Map<String, dynamic> bank) {
  final left = _safe(bank['bank_name']);
  final right = _safe(bank['account_name']);
  final account = _safe(bank['account_number']);
  final last4 =
      account.isEmpty ? '' : ' • ${account.substring(account.length - 4)}';
  return [left, right].where((v) => v.isNotEmpty).join(' - ') + last4;
}

Map<String, dynamic>? _findMode(
    dynamic value, List<Map<String, dynamic>> modes) {
  final needle = _safe(value).toLowerCase();
  if (needle.isEmpty) return null;
  for (final mode in modes) {
    if (_safe(mode['id']).toLowerCase() == needle ||
        _safe(mode['name']).toLowerCase() == needle ||
        _safe(mode['code']).toLowerCase() == needle) {
      return mode;
    }
  }
  return null;
}

String _studentName(Map<String, dynamic> row) {
  final student = row['Student'] ?? row['student'];
  if (student is Map) return _safe(student['name'], '-');
  return _safe(row['student_name'] ?? row['name'], '-');
}

String _studentAdmission(Map<String, dynamic> row) {
  final student = row['Student'] ?? row['student'];
  if (student is Map) return _safe(student['admission_number'], '-');
  return _safe(row['admission_number'], '-');
}

String _studentClass(Map<String, dynamic> row) {
  final student = row['Student'] ?? row['student'];
  if (student is Map) {
    final cls = student['Class'] ?? student['class'];
    if (cls is Map) return _safe(cls['class_name'] ?? cls['name'], '-');
    return _safe(student['class_name'], '-');
  }
  return _safe(row['class_name'], '-');
}

int? _txnSerial(Map<String, dynamic> row) {
  final raw =
      row['Serial'] ?? row['serial'] ?? row['serial_no'] ?? row['serialNo'];
  final serial = _toInt(raw);
  return serial != null && serial > 0 ? serial : null;
}

bool _isCancelled(Map<String, dynamic> row) =>
    _norm(row['status']) == 'cancelled';

bool _isCash(dynamic mode) => _norm(mode) == 'cash';

bool _isOnline(dynamic mode) {
  final key = _norm(mode);
  return key == 'online' ||
      key == 'hdfc' ||
      key == 'smart_hdfc' ||
      key == 'smartgateway' ||
      key == 'upi' ||
      key.contains('upi') ||
      key == 'card' ||
      key.contains('card') ||
      key == 'netbanking' ||
      key == 'net_banking' ||
      key.contains('net') ||
      key.contains('bank_transfer');
}

String _norm(dynamic value) =>
    _safe(value).toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');

String _money(dynamic value) {
  final amount = _amount(value);
  if (amount == 0) return '0';
  final formatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: 'Rs ',
    decimalDigits: amount % 1 == 0 ? 0 : 2,
  );
  return formatter.format(amount);
}

num _amount(dynamic value) {
  if (value is num) return value;
  return num.tryParse(_safe(value).replaceAll(',', '')) ?? 0;
}

int? _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(_safe(value));
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = _safe(value).toLowerCase();
  return text == 'true' || text == '1' || text == 'yes';
}

String _first(dynamic a, [dynamic b, dynamic c, dynamic d]) {
  for (final value in [a, b, c, d]) {
    final text = _safe(value);
    if (text.isNotEmpty &&
        text != '-' &&
        text.toLowerCase() != 'null' &&
        text.toLowerCase() != 'undefined') {
      return text;
    }
  }
  return '';
}

String _safe(dynamic value, [String fallback = '']) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

String _normalizeDate(dynamic value) {
  final text = _safe(value);
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return text;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return '';
  return DateFormat('yyyy-MM-dd').format(parsed);
}

bool _ok(int statusCode) => statusCode >= 200 && statusCode < 300;

String _apiError(String body, String fallback) {
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
