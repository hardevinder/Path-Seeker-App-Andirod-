import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/visitor_api.dart';

class VisitorCheckinScreen extends StatefulWidget {
  const VisitorCheckinScreen({super.key});
  @override
  State<VisitorCheckinScreen> createState() => _VisitorCheckinScreenState();
}

class _VisitorCheckinScreenState extends State<VisitorCheckinScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _idType = TextEditingController();
  final _idNo = TextEditingController();
  final _address = TextEditingController();
  final _purpose = TextEditingController();
  List<Map<String, dynamic>> _employees = [];
  int? _employeeId;
  String? _proofFile;
  String? _proofExpiry;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    VisitorApi.employees().then((value) {
      if (mounted) {
        setState(() => _employees = value
            .where((e) => '${e['status']}'.toLowerCase() != 'disabled')
            .toList());
      }
    }).catchError((_) {});
  }

  Future<void> _scan() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (photo == null) return;
    setState(() => _busy = true);
    try {
      final result = await VisitorApi.scanId(File(photo.path));
      final fields = Map<String, dynamic>.from(result['extracted'] ?? {});
      _name.text = '${fields['full_name'] ?? ''}';
      _idType.text = '${fields['document_type'] ?? 'Other'}';
      _idNo.text = '${fields['id_number'] ?? ''}';
      _address.text = '${fields['address'] ?? ''}';
      _proofFile = '${result['id_proof_file'] ?? ''}';
      _proofExpiry = '${result['id_proof_expires_at'] ?? ''}';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ID read successfully. Please review the details.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_proofFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please scan an ID proof.')));
      return;
    }
    if (_employeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select the person to meet.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final employee = _employees.firstWhere((e) => int.tryParse('${e['id']}') == _employeeId);
      await VisitorApi.create({
        'name': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'address': _address.text.trim(),
        'id_proof_type': _idType.text.trim().isEmpty ? 'Other' : _idType.text.trim(),
        'id_proof_no': _idNo.text.trim(),
        'id_proof_file': _proofFile,
        'id_proof_expires_at': _proofExpiry,
        'purpose': _purpose.text.trim(),
        'employee_id': _employeeId,
        'whom_to_meet': employee['name'],
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Visitor checked in and employee notified.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController controller, String label, {bool required = false, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        validator: required ? (v) => (v ?? '').trim().isEmpty ? '$label is required' : null : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Visitor')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _scan,
              icon: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.camera_alt),
              label: Text(_proofFile == null ? 'Scan Any ID Proof' : 'Rescan ID Proof'),
            ),
            const SizedBox(height: 8),
            if (_proofFile != null) const Text('Stored securely • automatically deleted after 30 days', textAlign: TextAlign.center),
            const SizedBox(height: 18),
            _field(_name, 'Visitor name', required: true),
            _field(_phone, 'Phone number', keyboard: TextInputType.phone),
            _field(_idType, 'ID proof type'),
            _field(_idNo, 'ID proof number'),
            _field(_address, 'Address'),
            _field(_purpose, 'Purpose of visit', required: true),
            DropdownButtonFormField<int>(
              initialValue: _employeeId,
              decoration: const InputDecoration(labelText: 'Person to meet', border: OutlineInputBorder()),
              isExpanded: true,
              items: _employees.map((e) => DropdownMenuItem(
                value: int.tryParse('${e['id']}'),
                child: Text('${e['name'] ?? 'Employee'}${e['designation'] == null ? '' : ' — ${e['designation']}'}'),
              )).toList(),
              onChanged: (value) => setState(() => _employeeId = value),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _busy ? null : _save, child: const Text('Check In & Send Alert')),
          ],
        ),
      ),
    );
  }
}
