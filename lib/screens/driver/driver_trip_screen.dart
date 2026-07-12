import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';

class DriverTripScreen extends StatefulWidget {
  const DriverTripScreen({super.key});
  @override
  State<DriverTripScreen> createState() => _DriverTripScreenState();
}

class _DriverTripScreenState extends State<DriverTripScreen> {
  bool _loading = true, _saving = false, _tracking = false;
  String _tripType = 'pickup';
  String? _message;
  Map<String, dynamic>? _trip;
  List<Map<String, dynamic>> _buses = [], _students = [];
  int? _busId;
  StreamSubscription<Position>? _positionSub;
  DateTime? _lastUpload;
  double? _accuracy;
  Position? _pending;
  final Map<int, String> _status = {};
  final Map<int, TextEditingController> _notes = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    for (final controller in _notes.values) {
      controller.dispose();
    }
    super.dispose();
  }

  dynamic _decode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return {};
    }
  }

  String _friendly(dynamic body, String fallback) {
    final decoded = _decode(body.toString());
    return decoded is Map
        ? (decoded['message'] ?? decoded['error'] ?? fallback).toString()
        : fallback;
  }

  Future<void> _load() async {
    if (mounted)
      setState(() {
        _loading = true;
        _message = null;
      });
    try {
      final results = await Future.wait([
        ApiService.rawGet('/transport-attendance/my-buses'),
        ApiService.rawGet('/bus-trips/my-active'),
      ]);
      for (final response in results) {
        if (response.statusCode < 200 || response.statusCode >= 300)
          throw Exception(
              _friendly(response.body, 'Unable to load transport details.'));
      }
      final busesJson = _decode(results[0].body);
      final tripJson = _decode(results[1].body);
      final buses = busesJson is Map && busesJson['data'] is List
          ? (busesJson['data'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      final active = tripJson is Map && tripJson['trip'] is Map
          ? Map<String, dynamic>.from(tripJson['trip'])
          : null;
      _trip = active;
      _buses = buses;
      _tripType = active?['trip_type']?.toString() ?? _tripType;
      _busId = active?['bus_id'] as int? ??
          _busId ??
          (buses.length == 1 ? buses.first['id'] as int? : null);
      await _loadStudents();
      if (active != null) await _startTracking();
    } catch (_) {
      _message =
          'Transport details could not be loaded. Pull down to try again.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadStudents() async {
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final response = await ApiService.rawGet(
        '/transport-attendance/my-list?trip_type=$_tripType&date=$date');
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw Exception('students');
    final decoded = _decode(response.body);
    _students = decoded is Map && decoded['students'] is List
        ? (decoded['students'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((e) => _busId == null || e['bus_id'] == _busId)
            .toList()
        : [];
    for (final row in _students) {
      final id = row['student_id'] as int;
      _status[id] =
          row['attendance']?['status']?.toString() ?? _status[id] ?? 'present';
      _notes.putIfAbsent(
          id,
          () => TextEditingController(
              text: row['attendance']?['notes']?.toString() ?? ''));
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
          context: context,
          builder: (c) =>
              AlertDialog(title: Text(title), content: Text(body), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Confirm'))
              ])) ??
      false;

  Future<void> _startTrip() async {
    if (_busId == null) {
      _snack('Select your assigned bus first.');
      return;
    }
    if (!await _confirm(
        'Start ${_tripType == 'pickup' ? 'Pickup' : 'Drop'} trip?',
        'Live location sharing will begin.')) return;
    setState(() => _saving = true);
    final response = await ApiService.rawPost(
        '/bus-trips/start', {'bus_id': _busId, 'trip_type': _tripType});
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = _decode(response.body);
      _trip = Map<String, dynamic>.from(decoded['trip']);
      await _startTracking();
      _snack('Trip started. GPS tracking is active.');
    } else {
      _snack(_friendly(response.body, 'Trip could not be started.'));
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _startTracking() async {
    if (_positionSub != null) return;
    if (!await Geolocator.isLocationServiceEnabled()) {
      _message = 'Turn on Location Services to share the bus location.';
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied)
      permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _message =
          'Location permission is required while a trip is active. Enable it in phone settings.';
      return;
    }
    _tracking = true;
    _positionSub = Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high, distanceFilter: 25))
        .listen(_onPosition, onError: (_) {
      if (mounted)
        setState(() => _message =
            'GPS is temporarily unavailable. Tracking will retry automatically.');
    });
    if (mounted) setState(() {});
  }

  Future<void> _onPosition(Position position) async {
    if (_trip == null) return;
    if (_lastUpload != null &&
        DateTime.now().difference(_lastUpload!) < const Duration(seconds: 12)) {
      _pending = position;
      return;
    }
    final response =
        await ApiService.rawPost('/bus-trips/${_trip!['id']}/location', {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy_meters': position.accuracy,
      'speed_kmh': position.speed < 0 ? null : position.speed * 3.6,
      'heading': position.heading < 0 ? null : position.heading,
      'recorded_at': position.timestamp.toUtc().toIso8601String(),
    });
    if (response.statusCode >= 200 && response.statusCode < 300) {
      _lastUpload = DateTime.now();
      _accuracy = position.accuracy;
      _pending = null;
      if (mounted) setState(() => _message = null);
    } else {
      _pending = position;
    }
  }

  Future<void> _endTrip() async {
    if (!await _confirm('End trip?',
        'Location sharing will stop and this trip will be completed.')) return;
    setState(() => _saving = true);
    if (_pending != null) await _onPosition(_pending!);
    final response =
        await ApiService.rawPost('/bus-trips/${_trip!['id']}/end', {});
    if (response.statusCode >= 200 && response.statusCode < 300) {
      await _positionSub?.cancel();
      _positionSub = null;
      _tracking = false;
      _trip = null;
      _lastUpload = null;
      _snack('Trip completed successfully.');
    } else {
      _snack(_friendly(response.body, 'Trip could not be ended.'));
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _saveAttendance() async {
    if (_students.isEmpty) return;
    setState(() => _saving = true);
    final response =
        await ApiService.rawPost('/transport-attendance/mark-bulk', {
      'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'trip_type': _tripType,
      'records': _students.map((e) {
        final id = e['student_id'] as int;
        return {
          'student_id': id,
          'status': _status[id] ?? 'present',
          'notes': _notes[id]?.text.trim() ?? ''
        };
      }).toList(),
    });
    _snack(response.statusCode >= 200 && response.statusCode < 300
        ? 'Attendance saved.'
        : _friendly(response.body, 'Attendance could not be saved.'));
    if (mounted) setState(() => _saving = false);
  }

  void _markAll(String value) => setState(() {
        for (final row in _students) {
          _status[row['student_id'] as int] = value;
        }
      });
  void _snack(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Bus Trip & Attendance')),
        body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.all(14), children: [
              if (_loading)
                const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()))
              else ...[
                SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'pickup',
                          label: Text('PICKUP'),
                          icon: Icon(Icons.school)),
                      ButtonSegment(
                          value: 'drop',
                          label: Text('DROP'),
                          icon: Icon(Icons.home))
                    ],
                    selected: {
                      _tripType
                    },
                    onSelectionChanged: _trip != null
                        ? null
                        : (v) async {
                            setState(() => _tripType = v.first);
                            await _loadStudents();
                            if (mounted) setState(() {});
                          }),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                    value: _busId,
                    decoration: const InputDecoration(
                        labelText: 'Assigned bus',
                        border: OutlineInputBorder()),
                    items: _buses
                        .map((b) => DropdownMenuItem(
                            value: b['id'] as int,
                            child: Text(
                                '${b['bus_no'] ?? 'Bus'} • ${b['reg_no'] ?? ''}')))
                        .toList(),
                    onChanged: _trip != null
                        ? null
                        : (v) async {
                            _busId = v;
                            await _loadStudents();
                            if (mounted) setState(() {});
                          }),
                const SizedBox(height: 12),
                SizedBox(
                    height: 64,
                    child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor:
                                _trip == null ? Colors.green : Colors.red),
                        onPressed: _saving
                            ? null
                            : (_trip == null ? _startTrip : _endTrip),
                        icon: Icon(
                            _trip == null ? Icons.play_arrow : Icons.stop,
                            size: 34),
                        label: Text(_trip == null ? 'START TRIP' : 'END TRIP',
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)))),
                const SizedBox(height: 8),
                Card(
                    color: _tracking
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    child: ListTile(
                        leading: Icon(
                            _tracking ? Icons.gps_fixed : Icons.gps_off,
                            color: _tracking ? Colors.green : Colors.orange),
                        title: Text(_tracking
                            ? 'GPS tracking active'
                            : 'GPS tracking inactive'),
                        subtitle: Text(_lastUpload == null
                            ? 'Waiting for location update'
                            : 'Last update ${DateFormat('h:mm:ss a').format(_lastUpload!)} • Accuracy ${_accuracy!.round()} m'))),
                if (_message != null)
                  Card(
                      color: Colors.orange.shade50,
                      child: ListTile(
                          leading: const Icon(Icons.warning_amber,
                              color: Colors.orange),
                          title: Text(_message!))),
                const SizedBox(height: 10),
                Row(children: [
                  const Expanded(
                      child: Text('Students',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold))),
                  PopupMenuButton<String>(
                      onSelected: _markAll,
                      itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'present',
                                child: Text('Mark all Present')),
                            PopupMenuItem(
                                value: 'absent',
                                child: Text('Mark all Absent')),
                            PopupMenuItem(
                                value: 'leave', child: Text('Mark all Leave'))
                          ],
                      child: const Chip(label: Text('MARK ALL')))
                ]),
                if (_students.isEmpty)
                  const Card(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No students assigned for this trip.')))
                else
                  ..._students.map(_studentCard),
                SizedBox(
                    height: 58,
                    child: FilledButton.icon(
                        onPressed: _saving ? null : _saveAttendance,
                        icon: const Icon(Icons.save),
                        label: const Text('SAVE ATTENDANCE',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold)))),
              ]
            ])),
      );

  Widget _studentCard(Map<String, dynamic> row) {
    final s = row['student'] as Map? ?? {};
    final id = row['student_id'] as int;
    final className = s['Class']?['class_name'] ?? '-';
    final section = s['Section']?['section_name'] ?? '-';
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s['name'] ?? 'Student'}',
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.bold)),
              Text(
                  'Admission ${s['admission_number'] ?? '-'} • $className-$section'),
              const Divider(),
              Text(
                  'Pickup: ${row['pickup_stop'] ?? '-'}\n${row['pickup_address'] ?? '-'}'),
              const SizedBox(height: 6),
              Text(
                  'Drop: ${row['drop_stop'] ?? '-'}\n${row['drop_address'] ?? '-'}'),
              TextButton.icon(
                  onPressed: row['maps_url'] == null
                      ? null
                      : () => launchUrl(Uri.parse(row['maps_url'].toString()),
                          mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.map),
                  label: const Text('OPEN LOCATION')),
              SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'present', label: Text('Present')),
                    ButtonSegment(value: 'absent', label: Text('Absent')),
                    ButtonSegment(value: 'leave', label: Text('Leave'))
                  ],
                  selected: {
                    _status[id] ?? 'present'
                  },
                  onSelectionChanged: (v) =>
                      setState(() => _status[id] = v.first)),
              const SizedBox(height: 8),
              TextField(
                  controller: _notes[id],
                  decoration: const InputDecoration(
                      labelText: 'Optional note', border: OutlineInputBorder()),
                  maxLines: 1),
            ])));
  }
}
