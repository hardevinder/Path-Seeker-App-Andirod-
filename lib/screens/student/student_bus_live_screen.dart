import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';

class StudentBusLiveScreen extends StatefulWidget {
  const StudentBusLiveScreen({super.key});

  @override
  State<StudentBusLiveScreen> createState() => _StudentBusLiveScreenState();
}

class _StudentBusLiveScreenState extends State<StudentBusLiveScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _payload;
  Timer? _timer;
  io.Socket? _socket;

  @override
  void initState() {
    super.initState();
    _load();
    _connectSocket();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_socket?.connected != true) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _socket?.dispose();
    super.dispose();
  }

  void _connectSocket() {
    final origin = Uri.parse(ApiService.baseUrl).origin;
    _socket = io.io(
        origin,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .build());
    _socket!
      ..onConnect((_) {
        final busId = _payload?['bus']?['id'];
        if (busId != null) _socket!.emit('joinBusRoom', {'busId': busId});
      })
      ..on('busLocationUpdated', (data) {
        if (data is! Map || !mounted) return;
        final assignedBusId = _payload?['bus']?['id'];
        if (assignedBusId == null ||
            data['busId'].toString() != assignedBusId.toString()) return;
        setState(() {
          _payload?['location'] = {
            'latitude': data['latitude'],
            'longitude': data['longitude'],
            'accuracy_meters': data['accuracyMeters'],
            'recorded_at': data['recordedAt'],
          };
        });
      })
      ..on('busTripEnded', (_) => _load(silent: true))
      ..connect();
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (!silent)
      setState(() {
        _loading = true;
        _error = null;
      });

    try {
      final response = await ApiService.rawGet('/bus-trips/my-bus-live');
      dynamic decoded;
      final contentType = response.headers['content-type'] ?? '';
      if (contentType.contains('application/json')) {
        try {
          decoded = jsonDecode(response.body);
        } on FormatException {
          decoded = null;
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const _BusTrackingException();
      }
      if (decoded is! Map) {
        throw const _BusTrackingException();
      }

      if (!mounted) return;
      setState(() {
        _payload = decoded is Map ? Map<String, dynamic>.from(decoded) : {};
        _loading = false;
      });
      final busId = _payload?['bus']?['id'];
      if (_socket?.connected == true && busId != null)
        _socket!.emit('joinBusRoom', {'busId': busId});
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'Live bus tracking is temporarily unavailable.\nPlease try again shortly.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = _payload?['student'];
    final bus = _payload?['bus'];
    final trip = _payload?['trip'];
    final location = _payload?['location'];
    final assignment = _payload?['assignment'];
    final lat = double.tryParse(location?['latitude']?.toString() ?? '');
    final lon = double.tryParse(location?['longitude']?.toString() ?? '');
    final hasLocation = lat != null && lon != null;
    final tripStatus = trip?['status']?.toString().toLowerCase();
    final friendlyStatus = trip == null
        ? 'Trip not started'
        : tripStatus == 'completed'
            ? 'Trip completed'
            : hasLocation
                ? 'Bus is on the way'
                : 'Location temporarily unavailable';

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bus Live Track'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(Icons.error_outline,
                          size: 40, color: Colors.red),
                      const SizedBox(height: 10),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try Again'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student?['name']?.toString() ?? 'Student',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text('Admission: ${student?['admission_number'] ?? '-'}'),
                      const SizedBox(height: 8),
                      Text('Assigned bus: ${bus?['bus_no'] ?? 'Not assigned'}'),
                      const SizedBox(height: 4),
                      Text(friendlyStatus,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: friendlyStatus == 'Bus is on the way'
                                  ? Colors.green
                                  : Colors.orange)),
                      Text(_socket?.connected == true
                          ? 'Live updates connected'
                          : 'Refreshing automatically'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.directions_bus,
                              color: Colors.indigo),
                          const SizedBox(width: 8),
                          Text('Current bus location',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (hasLocation)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                                height: 260,
                                child: GoogleMap(
                                  initialCameraPosition: CameraPosition(
                                      target: LatLng(lat, lon), zoom: 15),
                                  markers: {
                                    Marker(
                                        markerId: const MarkerId('bus'),
                                        position: LatLng(lat, lon),
                                        infoWindow: const InfoWindow(
                                            title: 'School bus'))
                                  },
                                  myLocationButtonEnabled: false,
                                  zoomControlsEnabled: true,
                                )),
                            const SizedBox(height: 10),
                            if (location['accuracy_meters'] != null)
                              Text(
                                  'Accuracy: ${location['accuracy_meters']} m'),
                            if (location['recorded_at'] != null)
                              Text('Updated: ${location['recorded_at']}'),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final uri = Uri.parse(
                                      'https://www.google.com/maps?q=$lat,$lon');
                                  if (!await launchUrl(uri,
                                      mode: LaunchMode.externalApplication)) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('Unable to open maps')));
                                  }
                                },
                                icon: const Icon(Icons.map_outlined),
                                label: const Text('Open in Google Maps'),
                              ),
                            ),
                          ],
                        )
                      else
                        const Text(
                            'The bus location is not available right now. Please wait for the driver to share it.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pickup / Drop details',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      if (assignment != null) ...[
                        _detailRow('Pickup stop', assignment['pickup_stop']),
                        _detailRow(
                            'Pickup address', assignment['pickup_address']),
                        _detailRow('Drop stop', assignment['drop_stop']),
                        _detailRow('Drop address', assignment['drop_address']),
                      ] else
                        const Text('No transport assignment found for today.'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, dynamic value) {
    final text = value == null || value.toString().trim().isEmpty
        ? '—'
        : value.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
              flex: 2,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(flex: 3, child: Text(text)),
        ],
      ),
    );
  }
}

class _BusTrackingException implements Exception {
  const _BusTrackingException();
}
