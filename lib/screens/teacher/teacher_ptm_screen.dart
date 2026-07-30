import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/role_manager.dart';
import '../../services/ptm_api.dart';
import '../../widgets/teacher_drawer_menu.dart';

class TeacherPtmScreen extends StatefulWidget {
  const TeacherPtmScreen({super.key});

  @override
  State<TeacherPtmScreen> createState() => _TeacherPtmScreenState();
}

class _TeacherPtmScreenState extends State<TeacherPtmScreen> {
  bool _loadingMeetings = true;
  bool _loadingDashboard = false;
  bool _loadingStudents = false;
  int? _uploadingFormId;
  String? _activeRole;

  List<Map<String, dynamic>> _meetings = [];
  List<Map<String, dynamic>> _summaries = [];
  List<Map<String, dynamic>> _forms = [];
  Map<String, dynamic>? _meeting;
  Map<String, dynamic>? _meetingClass;
  int? _selectedMeetingId;
  int? _selectedMeetingClassId;

  @override
  void initState() {
    super.initState();
    _loadActiveRole();
    _loadMeetings();
  }

  int? _asInt(dynamic value) => int.tryParse(value?.toString() ?? '');

  Future<void> _loadActiveRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = AppRoles.normalize(
      prefs.getString('activeRole') ??
          prefs.getString('selectedRole') ??
          prefs.getString('role'),
    );
    if (mounted) setState(() => _activeRole = role);
  }

  Map<String, dynamic> _map(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : <String, dynamic>{};

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  String _messageFrom(Object error) {
    final text = error.toString().replaceFirst('PtmApiException: ', '').trim();
    return text.isEmpty ? 'Something went wrong.' : text;
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Colors.red.shade700 : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _loadMeetings() async {
    setState(() => _loadingMeetings = true);
    try {
      final meetings = await PtmApi.listMeetings();
      if (!mounted) return;
      setState(() {
        _meetings = meetings;
        _selectedMeetingId = meetings.isEmpty ? null : _asInt(meetings.first['id']);
      });
      if (_selectedMeetingId != null) {
        await _loadDashboard(_selectedMeetingId!);
      }
    } catch (error) {
      _snack(_messageFrom(error), error: true);
    } finally {
      if (mounted) setState(() => _loadingMeetings = false);
    }
  }

  Future<void> _loadDashboard(int meetingId) async {
    setState(() {
      _loadingDashboard = true;
      _forms = [];
      _meetingClass = null;
      _selectedMeetingClassId = null;
    });
    try {
      final data = await PtmApi.dashboard(meetingId);
      final summaries = _mapList(data['summaries']);
      if (!mounted) return;
      setState(() {
        _meeting = _map(data['meeting']);
        _summaries = summaries;
        _selectedMeetingClassId =
            summaries.isEmpty ? null : _asInt(summaries.first['id']);
      });
      if (_selectedMeetingClassId != null) {
        await _loadStudents(_selectedMeetingClassId!);
      }
    } catch (error) {
      _snack(_messageFrom(error), error: true);
    } finally {
      if (mounted) setState(() => _loadingDashboard = false);
    }
  }

  Future<void> _loadStudents(int meetingClassId) async {
    setState(() => _loadingStudents = true);
    try {
      final data = await PtmApi.classStudents(meetingClassId);
      if (!mounted) return;
      setState(() {
        _meetingClass = _map(data['meetingClass']);
        _forms = _mapList(data['forms']);
      });
    } catch (error) {
      _snack(_messageFrom(error), error: true);
    } finally {
      if (mounted) setState(() => _loadingStudents = false);
    }
  }

  Future<void> _scanAndUpload(Map<String, dynamic> form) async {
    if (!Platform.isAndroid || _uploadingFormId != null) {
      if (!Platform.isAndroid) {
        _snack('Document scanning is available on Android.', error: true);
      }
      return;
    }

    final formId = _asInt(form['id']);
    if (formId == null) return;

    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.pdf},
        mode: ScannerMode.full,
        pageLimit: 3,
        isGalleryImport: true,
      ),
    );

    try {
      final result = await scanner.scanDocument();
      final pdfPath = result.pdf?.uri.trim() ?? '';
      if (pdfPath.isEmpty) return;
      final file = File(pdfPath);
      if (!await file.exists()) {
        throw const FileSystemException('Scanned PDF was not created.');
      }

      if (mounted) setState(() => _uploadingFormId = formId);
      final response = await PtmApi.uploadScan(formId, file);
      _snack(
        response['message']?.toString() ??
            'PTM form scanned and uploaded successfully.',
      );
      if (_selectedMeetingClassId != null) {
        await _loadStudents(_selectedMeetingClassId!);
      }
    } on PlatformException catch (error) {
      if (!error.message.toString().toLowerCase().contains('cancel')) {
        _snack(
          'Could not scan document: ${error.message ?? error.code}',
          error: true,
        );
      }
    } catch (error) {
      _snack(_messageFrom(error), error: true);
    } finally {
      await scanner.close();
      if (mounted) setState(() => _uploadingFormId = null);
    }
  }

  Future<void> _openReview(Map<String, dynamic> form) async {
    final formId = _asInt(form['id']);
    if (formId == null) return;

    final student = _map(form['student']);
    final feedback = _map(form['feedback']);
    final attendance = _map(form['attendance']);

    final parentName = TextEditingController(
      text: feedback['parent_name']?.toString() ?? '',
    );
    final relation = TextEditingController(
      text: feedback['relation']?.toString() ?? '',
    );
    final parentRemarks = TextEditingController(
      text: feedback['parent_remarks']?.toString() ?? '',
    );
    final teacherRemarks = TextEditingController(
      text: feedback['teacher_remarks']?.toString() ?? '',
    );
    final actionPoints = TextEditingController(
      text: feedback['action_points']?.toString() ?? '',
    );
    final attendanceReason = TextEditingController(
      text: attendance['reason']?.toString() ?? '',
    );

    int? academic = _asInt(feedback['academic_rating']);
    int? behaviour = _asInt(feedback['behaviour_rating']);
    int? communication = _asInt(feedback['communication_rating']);
    bool signature = feedback['signature_detected'] == true ||
        attendance['signature_detected'] == true;
    String status = attendance['status']?.toString().toUpperCase() ?? 'PENDING';
    if (status == 'PRESENT_SUGGESTED') status = 'PRESENT';
    if (!const ['PENDING', 'PRESENT', 'ABSENT', 'EXCUSED'].contains(status)) {
      status = 'PENDING';
    }

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Widget ratingField(String label, int? value, ValueChanged<int?> onChanged) {
              return DropdownButtonFormField<int>(
                value: value,
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                ),
                items: const [1, 2, 3, 4, 5]
                    .map(
                      (rating) => DropdownMenuItem(
                        value: rating,
                        child: Text('$rating / 5'),
                      ),
                    )
                    .toList(),
                onChanged: onChanged,
              );
            }

            return AlertDialog(
              title: Text('Review ${student['name'] ?? 'PTM Form'}'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: parentName,
                        decoration: const InputDecoration(
                          labelText: 'Parent / Guardian Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: relation,
                        decoration: const InputDecoration(
                          labelText: 'Relation',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ratingField('Academic Rating', academic, (value) {
                        setDialogState(() => academic = value);
                      }),
                      const SizedBox(height: 12),
                      ratingField('Behaviour Rating', behaviour, (value) {
                        setDialogState(() => behaviour = value);
                      }),
                      const SizedBox(height: 12),
                      ratingField('Communication Rating', communication, (value) {
                        setDialogState(() => communication = value);
                      }),
                      const SizedBox(height: 12),
                      TextField(
                        controller: parentRemarks,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Parent Remarks',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: teacherRemarks,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Teacher Remarks',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: actionPoints,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Action Points',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: signature,
                        title: const Text('Parent signature is present'),
                        subtitle: const Text(
                          'This confirms signature presence only, not identity.',
                        ),
                        onChanged: (value) {
                          setDialogState(() => signature = value);
                        },
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: status,
                        decoration: const InputDecoration(
                          labelText: 'PTM Attendance',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'PENDING', child: Text('Pending')),
                          DropdownMenuItem(value: 'PRESENT', child: Text('Present')),
                          DropdownMenuItem(value: 'ABSENT', child: Text('Absent')),
                          DropdownMenuItem(value: 'EXCUSED', child: Text('Excused')),
                        ],
                        onChanged: (value) {
                          if (value != null) setDialogState(() => status = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: attendanceReason,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Attendance Note / Reason',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      await PtmApi.saveForm(formId, {
                        'parent_name': parentName.text.trim(),
                        'relation': relation.text.trim(),
                        'academic_rating': academic,
                        'behaviour_rating': behaviour,
                        'communication_rating': communication,
                        'parent_remarks': parentRemarks.text.trim(),
                        'teacher_remarks': teacherRemarks.text.trim(),
                        'action_points': actionPoints.text.trim(),
                        'signature_detected': signature,
                        'attendance_status': status,
                        'attendance_reason': attendanceReason.text.trim(),
                      });
                      if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                    } catch (error) {
                      _snack(_messageFrom(error), error: true);
                    }
                  },
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save & Verify'),
                ),
              ],
            );
          },
        );
      },
    );

    parentName.dispose();
    relation.dispose();
    parentRemarks.dispose();
    teacherRemarks.dispose();
    actionPoints.dispose();
    attendanceReason.dispose();

    if (saved == true && _selectedMeetingClassId != null) {
      _snack('PTM feedback and attendance saved.');
      await _loadStudents(_selectedMeetingClassId!);
    }
  }

  String _meetingLabel(Map<String, dynamic> meeting) {
    final title = meeting['title']?.toString() ?? 'PTM';
    final rawDate = meeting['meeting_date']?.toString() ?? '';
    DateTime? date;
    try {
      date = DateTime.parse(rawDate);
    } catch (_) {}
    return date == null ? title : '$title • ${DateFormat('dd MMM yyyy').format(date)}';
  }

  String _classLabel(Map<String, dynamic> summary) {
    final className = _map(summary['class'])['class_name']?.toString() ?? '';
    final sectionName =
        _map(summary['section'])['section_name']?.toString() ?? '';
    return '$className-$sectionName';
  }

  Color _attendanceColor(String status) {
    switch (status) {
      case 'PRESENT':
        return Colors.green.shade700;
      case 'PRESENT_SUGGESTED':
        return Colors.orange.shade800;
      case 'ABSENT':
        return Colors.red.shade700;
      case 'EXCUSED':
        return Colors.blueGrey.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  Widget _summaryCard(Map<String, dynamic> summary) {
    final selected = _asInt(summary['id']) == _selectedMeetingClassId;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final id = _asInt(summary['id']);
        if (id == null) return;
        setState(() => _selectedMeetingClassId = id);
        await _loadStudents(id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 210,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEEAFE) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFF6C63FF) : Colors.grey.shade300,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _classLabel(summary),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text('Strength: ${summary['strength'] ?? 0}'),
            Text('Scanned: ${summary['scanned'] ?? 0}'),
            Text('Present: ${summary['present'] ?? 0}'),
            Text(
              'Verified ${summary['verified_present'] ?? 0} • AI ${summary['suggested_present'] ?? 0}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            Text('Pending: ${summary['pending'] ?? 0}'),
          ],
        ),
      ),
    );
  }

  Widget _studentCard(Map<String, dynamic> form) {
    final student = _map(form['student']);
    final feedback = _map(form['feedback']);
    final attendance = _map(form['attendance']);
    final scans = _mapList(form['scans']);
    final status = attendance['status']?.toString().toUpperCase() ?? 'PENDING';
    final isUploading = _uploadingFormId == _asInt(form['id']);
    final confidence = double.tryParse(feedback['ai_confidence']?.toString() ?? '');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFEEEAFE),
                  child: Text(
                    (student['name']?.toString().trim().isNotEmpty == true)
                        ? student['name'].toString().trim()[0].toUpperCase()
                        : 'S',
                    style: const TextStyle(
                      color: Color(0xFF6C63FF),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student['name']?.toString() ?? 'Student',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Adm. ${student['admission_number'] ?? '-'}  •  Roll ${student['roll_number'] ?? '-'}',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: _attendanceColor(status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.replaceAll('_', ' '),
                    style: TextStyle(
                      color: _attendanceColor(status),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(
                    scans.isEmpty ? Icons.file_upload_outlined : Icons.task_rounded,
                    size: 17,
                  ),
                  label: Text(scans.isEmpty ? 'Not scanned' : 'Scan saved'),
                ),
                Chip(
                  avatar: const Icon(Icons.fact_check_outlined, size: 17),
                  label: Text('Form: ${form['status'] ?? 'GENERATED'}'),
                ),
                if (confidence != null)
                  Chip(
                    avatar: const Icon(Icons.auto_awesome_rounded, size: 17),
                    label: Text('AI ${(confidence * 100).round()}%'),
                  ),
              ],
            ),
            if ((feedback['parent_remarks']?.toString().trim().isNotEmpty ?? false)) ...[
              const SizedBox(height: 8),
              Text(
                'Parent: ${feedback['parent_remarks']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isUploading ? null : () => _scanAndUpload(form),
                    icon: isUploading
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.document_scanner_outlined),
                    label: Text(scans.isEmpty ? 'Scan Form' : 'Scan Again'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _openReview(form),
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('Review'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: TeacherDrawerMenu(activeRole: _activeRole),
      appBar: AppBar(
        title: const Text('PTM Feedback'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadingMeetings ? null : _loadMeetings,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadMeetings,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_loadingMeetings)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_meetings.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(
                  child: Text('No PTM has been assigned to you yet.'),
                ),
              )
            else ...[
              DropdownButtonFormField<int>(
                value: _selectedMeetingId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Parent Meeting',
                  prefixIcon: Icon(Icons.groups_2_outlined),
                  border: OutlineInputBorder(),
                ),
                items: _meetings
                    .map(
                      (meeting) => DropdownMenuItem<int>(
                        value: _asInt(meeting['id']),
                        child: Text(
                          _meetingLabel(meeting),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) async {
                  if (value == null) return;
                  setState(() => _selectedMeetingId = value);
                  await _loadDashboard(value);
                },
              ),
              const SizedBox(height: 14),
              if (_meeting != null)
                Card(
                  elevation: 0,
                  color: const Color(0xFFF7F5FF),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(Icons.event_available_rounded,
                            color: Color(0xFF6C63FF)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_meeting!['venue'] ?? 'Venue not specified'}  •  ${_meeting!['start_time'] ?? ''}',
                              ),
                              if ((_meeting!['agenda']?.toString().trim() ?? '').isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text('Agenda: ${_meeting!['agenda']}'),
                              ],
                              if ((_meeting!['instructions']?.toString().trim() ?? '').isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text('Instructions: ${_meeting!['instructions']}'),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              if (_loadingDashboard)
                const Center(child: CircularProgressIndicator())
              else if (_summaries.isNotEmpty) ...[
                const Text(
                  'Assigned Classes',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 148,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _summaries.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, index) => _summaryCard(_summaries[index]),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _meetingClass == null
                            ? 'Student Forms'
                            : '${_map(_meetingClass!['class'])['class_name'] ?? ''}-${_map(_meetingClass!['section'])['section_name'] ?? ''} Student Forms',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text('${_forms.length} students'),
                  ],
                ),
                const SizedBox(height: 10),
                if (_loadingStudents)
                  const Center(child: CircularProgressIndicator())
                else if (_forms.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No student forms found.')),
                  )
                else
                  ..._forms.map(_studentCard),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
