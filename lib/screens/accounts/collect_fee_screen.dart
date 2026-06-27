import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';

class CollectFeeScreen extends StatefulWidget {
  const CollectFeeScreen({super.key});

  @override
  State<CollectFeeScreen> createState() => _CollectFeeScreenState();
}

class _CollectFeeScreenState extends State<CollectFeeScreen> {
  final _searchController = TextEditingController();
  final _remarksController = TextEditingController();
  final _referenceController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _chequeNoController = TextEditingController();
  Timer? _debounce;

  bool _loading = true;
  bool _studentLoading = false;
  bool _feeLoading = false;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _sections = [];
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _feeRows = [];
  List<Map<String, dynamic>> _paymentModes = [];
  List<Map<String, dynamic>> _bankAccounts = [];

  int? _sessionId;
  int? _classId;
  int? _sectionId;
  int? _studentId;
  DateTime _transactionDate = DateTime.now();
  Map<String, dynamic>? _selectedStudent;
  Map<String, dynamic>? _selectedMode;
  int? _bankAccountId;

  final Map<int, TextEditingController> _receivedControllers = {};
  final Map<int, TextEditingController> _concessionControllers = {};
  final Map<int, TextEditingController> _fineControllers = {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _remarksController.dispose();
    _referenceController.dispose();
    _bankNameController.dispose();
    _chequeNoController.dispose();
    for (final controller in [
      ..._receivedControllers.values,
      ..._concessionControllers.values,
      ..._fineControllers.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _getList('/sessions'),
        _getList('/classes'),
        _getList('/mode-of-transactions'),
        _getList('/school-bank-accounts?active_only=true'),
      ]);

      final sessions = results[0];
      final modes = _normalizeModes(results[2]);

      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _classes = results[1];
        _paymentModes = modes;
        _bankAccounts = results[3];
        _sessionId = _toInt(
              sessions.firstWhere(
                (s) => s['is_active'] == true || s['isActive'] == true,
                orElse: () => sessions.isNotEmpty ? sessions.first : {},
              )['id'],
            ) ??
            (sessions.isNotEmpty ? _toInt(sessions.first['id']) : null);
        _selectedMode = modes.firstWhere(
          (m) => _label(m).toLowerCase() == 'cash',
          orElse: () => modes.isNotEmpty ? modes.first : _cashMode,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Collect fee options load nahi ho paye.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSections() async {
    setState(() {
      _sections = [];
      _sectionId = null;
      _students = [];
      _studentId = null;
    });

    if (_classId == null) return;

    final rows = await _getList('/sections?class_id=$_classId');
    if (!mounted) return;
    setState(() => _sections = rows);
  }

  Future<void> _loadStudentsByClass() async {
    if (_classId == null || _sectionId == null) return;

    setState(() {
      _studentLoading = true;
      _students = [];
      _studentId = null;
    });

    try {
      final query = {
        'class_id': '$_classId',
        'section_id': '$_sectionId',
        if (_sessionId != null) 'session_id': '$_sessionId',
      };
      final rows =
          await _getList(_endpoint('/students/searchByClassAndSection', query));
      if (!mounted) return;
      setState(() => _students = rows.map(_normalizeStudent).toList());
    } finally {
      if (mounted) setState(() => _studentLoading = false);
    }
  }

  void _queueSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _searchStudents(value);
    });
  }

  Future<void> _searchStudents(String value) async {
    final q = value.trim();
    if (q.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _studentLoading = true);
    try {
      final rows = await _getList(_endpoint('/students/search', {
        'q': q,
        'limit': '25',
        if (_sessionId != null) 'session_id': '$_sessionId',
      }));
      if (!mounted) return;
      setState(() => _searchResults = rows.map(_normalizeStudent).toList());
    } finally {
      if (mounted) setState(() => _studentLoading = false);
    }
  }

  Future<void> _selectStudent(Map<String, dynamic> student) async {
    setState(() {
      _selectedStudent = student;
      _studentId = _toInt(student['id']);
      _classId = _toInt(student['class_id']);
      _sectionId = _toInt(student['section_id']);
      _searchResults = [];
      _searchController.text =
          '${_label(student)} (${student['admission_number'] ?? '-'})';
    });
    await _loadFeeDetails();
  }

  Future<void> _loadFeeDetails() async {
    if (_sessionId == null || _studentId == null) {
      setState(() => _error = 'Please select session and student first.');
      return;
    }

    setState(() {
      _feeLoading = true;
      _error = null;
      _feeRows = [];
    });

    try {
      final resp = await ApiService.rawGet(
        '/students/$_studentId/fee-details?session_id=$_sessionId',
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception(_apiError(resp.body, 'Fee details load nahi ho paye.'));
      }

      final decoded = jsonDecode(resp.body);
      final rows =
          _listFrom(decoded['feeDetails'] ?? decoded['data'] ?? decoded);
      final normalized = rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .where(
              (row) => _toInt(row['fee_heading_id'] ?? row['Fee_Head']) != null)
          .toList();

      _resetFeeControllers(normalized);

      if (!mounted) return;
      setState(() {
        _feeRows = normalized;
        if (decoded is Map && decoded['student'] is Map) {
          _selectedStudent = _normalizeStudent(
            Map<String, dynamic>.from(decoded['student'] as Map),
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _feeLoading = false);
    }
  }

  void _resetFeeControllers(List<Map<String, dynamic>> rows) {
    for (final controller in [
      ..._receivedControllers.values,
      ..._concessionControllers.values,
      ..._fineControllers.values,
    ]) {
      controller.dispose();
    }
    _receivedControllers.clear();
    _concessionControllers.clear();
    _fineControllers.clear();

    for (final row in rows) {
      final headId = _headId(row);
      if (headId == null) continue;
      final due = _amount(row['feeDue'] ?? row['due'] ?? row['amount_due']);
      final fine = _amount(row['fineAmount'] ?? row['Fine_Amount']);
      _receivedControllers[headId] =
          TextEditingController(text: due > 0 ? _plainAmount(due) : '');
      _concessionControllers[headId] = TextEditingController();
      _fineControllers[headId] =
          TextEditingController(text: fine > 0 ? _plainAmount(fine) : '');
    }
  }

  Future<void> _save() async {
    final student = _selectedStudent;
    final mode = _selectedMode;
    if (_sessionId == null || student == null || _studentId == null) {
      _toast('Please select session and student.');
      return;
    }
    if (mode == null) {
      _toast('Please select payment mode.');
      return;
    }

    final requiresReference = mode['requires_reference_no'] == true;
    final requiresBank = mode['requires_bank'] == true;
    final requiresChequeNo = mode['requires_cheque_no'] == true;
    final requiresChequeDate = mode['requires_cheque_date'] == true;

    if (requiresReference && _referenceController.text.trim().isEmpty) {
      _toast('Reference number required for this mode.');
      return;
    }
    if (requiresBank && _bankAccountId == null) {
      _toast('Bank account required for this mode.');
      return;
    }
    if (requiresChequeNo && _chequeNoController.text.trim().isEmpty) {
      _toast('Cheque number required.');
      return;
    }

    final transactions = <Map<String, dynamic>>[];
    for (final row in _feeRows) {
      final headId = _headId(row);
      if (headId == null) continue;

      final received = _amount(_receivedControllers[headId]?.text);
      final concession = _amount(_concessionControllers[headId]?.text);
      final fine = _amount(_fineControllers[headId]?.text);

      if (received <= 0 && concession <= 0 && fine <= 0) continue;

      transactions.add({
        'AdmissionNumber': student['admission_number'],
        'Student_ID': _studentId,
        'Class_ID': _toInt(student['class_id']) ?? _classId,
        'Section_ID': _toInt(student['section_id']) ?? _sectionId,
        'DateOfTransaction': DateFormat('yyyy-MM-dd').format(_transactionDate),
        'Fee_Head': headId,
        'Fee_Recieved': received,
        'Concession': concession,
        'VanFee': null,
        'Van_Fee_Concession': null,
        'Route_ID': null,
        'PaymentMode': _label(mode),
        'mode_of_transaction_id': mode['id'],
        'bank_account_id': requiresBank ? _bankAccountId : null,
        'reference_no':
            requiresReference ? _referenceController.text.trim() : null,
        'Transaction_ID':
            requiresReference ? _referenceController.text.trim() : null,
        'bank_name': (requiresChequeNo || requiresChequeDate)
            ? _bankNameController.text.trim()
            : null,
        'BankName': (requiresChequeNo || requiresChequeDate)
            ? _bankNameController.text.trim()
            : null,
        'cheque_no': requiresChequeNo ? _chequeNoController.text.trim() : null,
        'ChequeNumber':
            requiresChequeNo ? _chequeNoController.text.trim() : null,
        'cheque_date': requiresChequeDate
            ? DateFormat('yyyy-MM-dd').format(_transactionDate)
            : null,
        'ChequeDate': requiresChequeDate
            ? DateFormat('yyyy-MM-dd').format(_transactionDate)
            : null,
        'Fine_Amount': fine,
        'session_id': _sessionId,
        'Remarks': _remarksController.text.trim().isEmpty
            ? null
            : _remarksController.text.trim(),
      });
    }

    if (transactions.isEmpty) {
      _toast('Enter amount in at least one fee row.');
      return;
    }

    setState(() => _saving = true);
    try {
      final resp = await ApiService.rawPost('/transactions/bulk', {
        'transactions': transactions,
      });
      final decoded = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      if (resp.statusCode < 200 ||
          resp.statusCode >= 300 ||
          (decoded is Map && decoded['success'] == false)) {
        throw Exception(_apiError(resp.body, 'Fee collect nahi ho payi.'));
      }

      if (!mounted) return;
      final slipId =
          decoded is Map ? decoded['slipId'] ?? decoded['Slip_ID'] : null;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Fee Collected'),
          content: Text(
            slipId == null
                ? 'Transaction saved successfully.'
                : 'Transaction saved successfully.\nSlip ID: $slipId',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      await _loadFeeDetails();
    } catch (e) {
      if (!mounted) return;
      _toast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FF),
      appBar: AppBar(
        title: const Text('Collect Fee'),
        backgroundColor: const Color(0xFF1F7AE0),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loading ? null : _bootstrap,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  _headerCard(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _notice(_error!, Colors.red.shade700),
                  ],
                  const SizedBox(height: 14),
                  _sessionAndStudentCard(),
                  const SizedBox(height: 14),
                  _paymentCard(),
                  const SizedBox(height: 14),
                  _feeDetailsCard(),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_rounded),
                    label: Text(_saving ? 'Saving...' : 'Save Collection'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _headerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F7AE0),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          Icon(Icons.currency_rupee_rounded, color: Colors.white),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Select student, fill fee amounts, choose mode and save receipt.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sessionAndStudentCard() {
    return _panel(
      title: 'Student Selection',
      icon: Icons.person_search_rounded,
      children: [
        DropdownButtonFormField<int>(
          value: _sessionId,
          decoration: const InputDecoration(labelText: 'Session'),
          items: _sessions
              .map(
                (s) => DropdownMenuItem(
                  value: _toInt(s['id']),
                  child: Text(_sessionLabel(s)),
                ),
              )
              .toList(),
          onChanged: (value) {
            setState(() {
              _sessionId = value;
              _feeRows = [];
              _selectedStudent = null;
              _studentId = null;
              _searchResults = [];
              _students = [];
            });
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            labelText: 'Search name / admission no.',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _studentLoading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          onChanged: _queueSearch,
        ),
        if (_searchResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._searchResults.take(6).map(_studentResultTile),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _classId,
                decoration: const InputDecoration(labelText: 'Class'),
                items: _classes
                    .map(
                      (c) => DropdownMenuItem(
                        value: _toInt(c['id']),
                        child: Text(_classLabel(c)),
                      ),
                    )
                    .toList(),
                onChanged: (value) async {
                  setState(() => _classId = value);
                  await _loadSections();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _sectionId,
                decoration: const InputDecoration(labelText: 'Section'),
                items: _sections
                    .map(
                      (s) => DropdownMenuItem(
                        value: _toInt(s['id']),
                        child: Text(_sectionLabel(s)),
                      ),
                    )
                    .toList(),
                onChanged: (value) async {
                  setState(() => _sectionId = value);
                  await _loadStudentsByClass();
                },
              ),
            ),
          ],
        ),
        if (_students.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: _studentId,
            decoration: const InputDecoration(labelText: 'Student'),
            items: _students
                .map(
                  (s) => DropdownMenuItem(
                    value: _toInt(s['id']),
                    child:
                        Text('${_label(s)} - ${s['admission_number'] ?? '-'}'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              final student = _students.firstWhere(
                (s) => _toInt(s['id']) == value,
                orElse: () => {},
              );
              if (student.isNotEmpty) _selectStudent(student);
            },
          ),
        ],
        if (_selectedStudent != null) ...[
          const SizedBox(height: 12),
          _selectedStudentStrip(),
        ],
      ],
    );
  }

  Widget _studentResultTile(Map<String, dynamic> student) {
    return InkWell(
      onTap: () => _selectStudent(student),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_rounded, color: Color(0xFF1F7AE0)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${_label(student)} - ${student['admission_number'] ?? '-'}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectedStudentStrip() {
    final s = _selectedStudent!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAFBF0),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${_label(s)}\nAdm: ${s['admission_number'] ?? '-'}  Class: ${s['class_name'] ?? '-'}  Section: ${s['section_name'] ?? '-'}',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _paymentCard() {
    final mode = _selectedMode;
    final requiresBank = mode?['requires_bank'] == true;
    final requiresReference = mode?['requires_reference_no'] == true;
    final requiresChequeNo = mode?['requires_cheque_no'] == true;

    return _panel(
      title: 'Payment Details',
      icon: Icons.payments_rounded,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<Map<String, dynamic>>(
                value: _selectedMode,
                decoration: const InputDecoration(labelText: 'Payment Mode'),
                items: _paymentModes
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(_label(m)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _selectedMode = value),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _transactionDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (date != null) setState(() => _transactionDate = date);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date'),
                  child:
                      Text(DateFormat('dd MMM yyyy').format(_transactionDate)),
                ),
              ),
            ),
          ],
        ),
        if (requiresReference) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _referenceController,
            decoration: const InputDecoration(labelText: 'Reference / UTR No.'),
          ),
        ],
        if (requiresBank) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: _bankAccountId,
            decoration: const InputDecoration(labelText: 'Bank Account'),
            items: _bankAccounts
                .map(
                  (b) => DropdownMenuItem(
                    value: _toInt(b['id']),
                    child: Text(_bankLabel(b)),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _bankAccountId = value),
          ),
        ],
        if (requiresChequeNo) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _chequeNoController,
            decoration: const InputDecoration(labelText: 'Cheque No.'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bankNameController,
            decoration: const InputDecoration(labelText: 'Cheque Bank Name'),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _remarksController,
          decoration: const InputDecoration(labelText: 'Remarks'),
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _feeDetailsCard() {
    return _panel(
      title: 'Fee Details',
      icon: Icons.receipt_long_rounded,
      children: [
        if (_feeLoading)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_selectedStudent == null)
          _notice('Select a student to load fee heads.', Colors.blue.shade700)
        else if (_feeRows.isEmpty)
          _notice('No fee heads found for this student/session.',
              Colors.orange.shade700)
        else
          ..._feeRows.map(_feeRowCard),
      ],
    );
  }

  Widget _feeRowCard(Map<String, dynamic> row) {
    final headId = _headId(row)!;
    final due = _amount(row['feeDue'] ?? row['due'] ?? row['amount_due']);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _feeHeadLabel(row),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                'Due ${_inr(due)}',
                style: const TextStyle(
                  color: Color(0xFFE11D48),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _receivedControllers[headId],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Received'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _concessionControllers[headId],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Concession'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _fineControllers[headId],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Fine'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panel({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF1F7AE0)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _notice(String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(55)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _getList(String endpoint) async {
    final resp = await ApiService.rawGet(endpoint);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_apiError(resp.body, 'Request failed.'));
    }
    final decoded = jsonDecode(resp.body);
    return _listFrom(decoded)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static List<dynamic> _listFrom(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      for (final key in [
        'data',
        'rows',
        'results',
        'items',
        'list',
        'records',
        'classes',
        'sections',
        'students',
        'sessions',
      ]) {
        final value = decoded[key];
        if (value is List) return value;
      }
      final data = decoded['data'];
      if (data is Map) return _listFrom(data);
    }
    return [];
  }

  static String _endpoint(String path, Map<String, String> params) {
    final query = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return query.isEmpty ? path : '$path?$query';
  }

  static Map<String, dynamic> _normalizeStudent(Map<String, dynamic> s) {
    final classMap = s['Class'] is Map ? s['Class'] as Map : const {};
    final sectionMap = s['Section'] is Map ? s['Section'] as Map : const {};
    return {
      ...s,
      'id': _toInt(s['id'] ?? s['student_id'] ?? s['Student_ID']),
      'name': _first(s['name'], s['student_name'], s['Student_Name']),
      'admission_number': _first(
        s['admission_number'],
        s['AdmissionNumber'],
        s['adm_no'],
      ),
      'class_id': _toInt(s['class_id'] ?? s['Class_ID'] ?? classMap['id']),
      'section_id':
          _toInt(s['section_id'] ?? s['Section_ID'] ?? sectionMap['id']),
      'class_name': _first(
        s['class_name'],
        s['Class_Name'],
        classMap['class_name'],
        classMap['Class_Name'],
        classMap['name'],
      ),
      'section_name': _first(
        s['section_name'],
        s['Section_Name'],
        sectionMap['section_name'],
        sectionMap['Section_Name'],
        sectionMap['name'],
      ),
    };
  }

  static List<Map<String, dynamic>> _normalizeModes(
      List<Map<String, dynamic>> rows) {
    final source = rows.isEmpty ? [_cashMode] : rows;
    final modes = source
        .map((row) {
          return {
            'id': row['id'] ?? row['code'] ?? row['name'],
            'name':
                _first(row['name'], row['label'], row['title'], row['code']),
            'code': row['code'],
            'requires_bank': row['requires_bank'] == true,
            'requires_reference_no': row['requires_reference_no'] == true,
            'requires_cheque_no': row['requires_cheque_no'] == true,
            'requires_cheque_date': row['requires_cheque_date'] == true,
            'sort_order': _toInt(row['sort_order']) ?? 0,
            'active': row['active'] != false,
          };
        })
        .where((m) => m['active'] != false)
        .toList();
    modes.sort((a, b) {
      final order = (_toInt(a['sort_order']) ?? 0).compareTo(
        _toInt(b['sort_order']) ?? 0,
      );
      if (order != 0) return order;
      return _label(a).compareTo(_label(b));
    });
    return modes;
  }

  static const Map<String, dynamic> _cashMode = {
    'id': 'cash',
    'name': 'Cash',
    'code': 'CASH',
    'requires_bank': false,
    'requires_reference_no': false,
    'requires_cheque_no': false,
    'requires_cheque_date': false,
    'sort_order': 1,
    'active': true,
  };

  static int? _headId(Map<String, dynamic> row) {
    return _toInt(row['fee_heading_id'] ?? row['Fee_Head'] ?? row['id']);
  }

  static String _feeHeadLabel(Map<String, dynamic> row) {
    return _first(
      row['fee_heading'],
      row['Fee_Heading_Name'],
      row['name'],
      row['label'],
    );
  }

  static String _sessionLabel(Map<String, dynamic> row) {
    return _first(
      row['name'],
      row['label'],
      '${_first(row['start_date'])} - ${_first(row['end_date'])}',
    );
  }

  static String _classLabel(Map<String, dynamic> row) {
    return _first(
        row['class_name'], row['Class_Name'], row['name'], row['label']);
  }

  static String _sectionLabel(Map<String, dynamic> row) {
    return _first(
      row['section_name'],
      row['Section_Name'],
      row['name'],
      row['label'],
    );
  }

  static String _bankLabel(Map<String, dynamic> row) {
    return _first(
      row['display_name'],
      row['account_name'],
      row['bank_name'],
      row['name'],
      row['account_number'],
    );
  }

  static String _label(Map<String, dynamic> row) {
    return _first(row['name'], row['label'], row['title'], row['code']);
  }

  static String _first(
      [dynamic a, dynamic b, dynamic c, dynamic d, dynamic e]) {
    for (final value in [a, b, c, d, e]) {
      final text = '${value ?? ''}'.trim();
      if (text.isNotEmpty && text != 'null' && text != '-') return text;
    }
    return '-';
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}');
  }

  static double _amount(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}'.replaceAll(',', '').trim()) ?? 0;
  }

  static String _plainAmount(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  static String _inr(double value) {
    return NumberFormat.currency(
            locale: 'en_IN', symbol: 'Rs ', decimalDigits: 0)
        .format(value);
  }

  static String _apiError(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return '${decoded['message'] ?? decoded['error'] ?? fallback}';
      }
    } catch (_) {}
    return fallback;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
