import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';

class StudentBusLiveScreen extends StatefulWidget {
  const StudentBusLiveScreen({super.key});

  @override
  State<StudentBusLiveScreen> createState() => _StudentBusLiveScreenState();
}

class _StudentBusLiveScreenState extends State<StudentBusLiveScreen> {
  static const Duration _pollInterval = Duration(seconds: 20);
  static const String _authTokenKey = 'authToken';

  bool _loading = true;
  bool _refreshing = false;
  bool _socketConnected = false;

  String? _error;
  String? _joinedBusId;
  String? _locationName;
  String? _lastGeocodedPosition;
  bool _locationNameLoading = false;

  Map<String, dynamic>? _payload;

  Timer? _timer;
  io.Socket? _socket;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _load();

    if (!mounted) return;

    await _connectSocket();

    _timer = Timer.periodic(_pollInterval, (_) {
      _load(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();

    if (_joinedBusId != null) {
      _socket?.emit('leaveBusRoom', {'busId': _joinedBusId});
    }

    _socket?.off('connect');
    _socket?.off('disconnect');
    _socket?.off('connect_error');
    _socket?.off('busLocationUpdated');
    _socket?.off('busTripStarted');
    _socket?.off('busTripEnded');
    _socket?.dispose();
    _mapController.dispose();

    super.dispose();
  }

  Future<String?> _getAuthToken() async {
    final preferences = await SharedPreferences.getInstance();
    final token = preferences.getString(_authTokenKey)?.trim();

    if (token == null || token.isEmpty) {
      return null;
    }

    return token;
  }

  Future<void> _connectSocket() async {
    final token = await _getAuthToken();

    if (!mounted) return;

    if (token == null) {
      setState(() {
        _socketConnected = false;
      });
      return;
    }

    final origin = Uri.parse(ApiService.baseUrl).origin;

    _socket?.dispose();

    _socket = io.io(
      origin,
      <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
        'reconnection': true,
        'reconnectionAttempts': 1000000,
        'reconnectionDelay': 2000,
        'auth': {'token': token},
        'extraHeaders': {
          'Authorization': 'Bearer $token',
        },
      },
    );

    _socket!
      ..on('connect', (_) {
        if (!mounted) return;

        setState(() {
          _socketConnected = true;
        });

        _joinAssignedBusRoom();
      })
      ..on('disconnect', (_) {
        if (!mounted) return;

        setState(() {
          _socketConnected = false;
        });
      })
      ..on('connect_error', (error) {
        debugPrint('Bus socket connection error: $error');

        if (!mounted) return;

        setState(() {
          _socketConnected = false;
        });
      })
      ..on('busLocationUpdated', _handleBusLocationUpdated)
      ..on('busTripStarted', (_) {
        _load(silent: true);
      })
      ..on('busTripEnded', (data) {
        final event = _asStringMap(data);
        final currentBusId = _payload?['bus']?['id'];

        if (event == null ||
            currentBusId == null ||
            event['busId']?.toString() == currentBusId.toString()) {
          _load(silent: true);
        }
      })
      ..connect();
  }

  Map<String, dynamic>? _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return null;
  }

  void _joinAssignedBusRoom() {
    if (_socket?.connected != true) return;

    final busId = _payload?['bus']?['id'];
    if (busId == null) return;

    final nextBusId = busId.toString();

    if (_joinedBusId == nextBusId) return;

    if (_joinedBusId != null) {
      _socket?.emit('leaveBusRoom', {'busId': _joinedBusId});
    }

    _socket?.emit('joinBusRoom', {'busId': busId});
    _joinedBusId = nextBusId;
  }

  void _handleBusLocationUpdated(dynamic data) {
    final event = _asStringMap(data);

    if (event == null || !mounted) return;

    final assignedBusId = _payload?['bus']?['id'];
    final eventBusId = event['busId'];
    final activeTripId = _payload?['trip']?['id'];
    final eventTripId = event['tripId'];

    if (assignedBusId == null ||
        eventBusId == null ||
        eventBusId.toString() != assignedBusId.toString() ||
        activeTripId == null ||
        eventTripId == null ||
        eventTripId.toString() != activeTripId.toString()) {
      return;
    }

    final latitude = _toDouble(event['latitude']);
    final longitude = _toDouble(event['longitude']);

    if (latitude == null || longitude == null) return;

    setState(() {
      _payload ??= <String, dynamic>{};

      _payload!['tracking_status'] = 'live';
      _payload!['location'] = {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_meters': event['accuracyMeters'] ?? event['accuracy_meters'],
        'recorded_at': event['recordedAt'] ??
            event['recorded_at'] ??
            DateTime.now().toIso8601String(),
        'is_fresh': true,
      };

      final currentTrip = _asStringMap(_payload!['trip']);
      if (currentTrip != null) {
        currentTrip['status'] = 'started';
        _payload!['trip'] = currentTrip;
      }
    });

    _updateLocationDetails(latitude, longitude);
  }

  Future<void> _updateLocationDetails(double latitude, double longitude) async {
    final positionKey =
        '${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}';
    if (_lastGeocodedPosition == positionKey) return;

    _lastGeocodedPosition = positionKey;
    if (mounted) setState(() => _locationNameLoading = true);

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': latitude.toString(),
        'lon': longitude.toString(),
        'zoom': '18',
        'addressdetails': '1',
      });
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'SMCIS-School-App/1.0',
          'Accept-Language': 'en',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return;
      final result = _asStringMap(jsonDecode(response.body));
      final name = result?['display_name']?.toString().trim();
      if (!mounted || name == null || name.isEmpty) return;
      setState(() => _locationName = name);
    } catch (error) {
      debugPrint('Unable to resolve bus location name: $error');
    } finally {
      if (mounted) setState(() => _locationNameLoading = false);
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;

    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() {
        _refreshing = true;
      });
    }

    try {
      final response = await ApiService.rawGet('/bus-trips/my-bus-live');

      dynamic decoded;

      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = null;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const _BusTrackingException(
          'Your session has expired. Please log in again.',
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final responseMap = _asStringMap(decoded);
        final message = responseMap?['message'] ??
            responseMap?['error'] ??
            'Live bus tracking is temporarily unavailable.';

        throw _BusTrackingException(message.toString());
      }

      final responseMap = _asStringMap(decoded);

      if (responseMap == null) {
        throw const _BusTrackingException(
          'The server returned an invalid tracking response.',
        );
      }

      if (!mounted) return;

      setState(() {
        _payload = responseMap;
        _loading = false;
        _refreshing = false;
        _error = null;
      });

      _joinAssignedBusRoom();

      final location = _asStringMap(_payload?['location']);
      final latitude = _toDouble(location?['latitude']);
      final longitude = _toDouble(location?['longitude']);
      if (latitude != null && longitude != null) {
        _updateLocationDetails(latitude, longitude);
      }
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _error =
            'The request took too long.\nPlease check your internet connection and try again.';
        _loading = false;
        _refreshing = false;
      });
    } on _BusTrackingException catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.message;
        _loading = false;
        _refreshing = false;
      });
    } catch (error) {
      debugPrint('Student live bus tracking error: $error');

      if (!mounted) return;

      setState(() {
        _error =
            'Live bus tracking is temporarily unavailable.\nPlease try again shortly.';
        _loading = false;
        _refreshing = false;
      });
    }
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    return double.tryParse(value.toString());
  }

  String _formatDateTime(dynamic value) {
    if (value == null) return '—';

    final date = DateTime.tryParse(value.toString())?.toLocal();
    if (date == null) return value.toString();

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$day-$month-$year $hour:$minute';
  }

  String _friendlyTripType(dynamic value) {
    final type = value?.toString().trim().toLowerCase();

    if (type == 'pickup') return 'Pickup';
    if (type == 'drop') return 'Drop';

    return '—';
  }

  String _friendlyTrackingStatus({
    required String trackingStatus,
    required Map<String, dynamic>? trip,
    required bool hasLocation,
  }) {
    switch (trackingStatus) {
      case 'not_assigned':
        return 'Bus not assigned';
      case 'trip_not_started':
        return 'Trip not started';
      case 'waiting_for_location':
        return 'Waiting for driver location';
      case 'stale':
        return 'Location may be delayed';
      case 'live':
        return 'Bus is on the way';
      default:
        if (trip == null) return 'Trip not started';
        if (hasLocation) return 'Bus is on the way';
        return 'Location temporarily unavailable';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'live':
        return Colors.green;
      case 'stale':
        return Colors.orange;
      case 'waiting_for_location':
        return Colors.blue;
      case 'not_assigned':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Future<void> _openMaps(double latitude, double longitude) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open Google Maps'),
        ),
      );
    }
  }

  Future<void> _openAssignedStopInMaps({
    required dynamic latitude,
    required dynamic longitude,
    required dynamic address,
  }) async {
    final lat = _toDouble(latitude);
    final lng = _toDouble(longitude);

    String query;

    if (lat != null && lng != null) {
      query = '$lat,$lng';
    } else {
      query = address?.toString().trim() ?? '';
    }

    if (query.isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location is not available'),
        ),
      );
      return;
    }

    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
    );

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open Google Maps'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = _asStringMap(_payload?['person']) ??
        _asStringMap(_payload?['employee']) ??
        _asStringMap(_payload?['student']);
    final bus = _asStringMap(_payload?['bus']);
    final trip = _asStringMap(_payload?['trip']);
    final location = _asStringMap(_payload?['location']);
    final assignment = _asStringMap(_payload?['assignment']);

    final latitude = _toDouble(location?['latitude']);
    final longitude = _toDouble(location?['longitude']);
    final hasLocation = latitude != null && longitude != null;

    final trackingStatus =
        _payload?['tracking_status']?.toString().trim().toLowerCase() ??
            (hasLocation ? 'live' : 'trip_not_started');

    final friendlyStatus = _friendlyTrackingStatus(
      trackingStatus: trackingStatus,
      trip: trip,
      hasLocation: hasLocation,
    );

    final statusColor = _statusColor(trackingStatus);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bus Live Track'),
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => _load(),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              _buildErrorCard()
            else ...[
              _buildPassengerAndBusCard(
                person: person,
                bus: bus,
                trip: trip,
                friendlyStatus: friendlyStatus,
                trackingStatus: trackingStatus,
                statusColor: statusColor,
              ),
              const SizedBox(height: 12),
              _buildLiveLocationCard(
                latitude: latitude,
                longitude: longitude,
                location: location,
                hasLocation: hasLocation,
                trackingStatus: trackingStatus,
              ),
              const SizedBox(height: 12),
              _buildAssignmentCard(assignment),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(
              Icons.error_outline,
              size: 42,
              color: Colors.red,
            ),
            const SizedBox(height: 10),
            Text(
              _error!,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _load(),
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPassengerAndBusCard({
    required Map<String, dynamic>? person,
    required Map<String, dynamic>? bus,
    required Map<String, dynamic>? trip,
    required String friendlyStatus,
    required String trackingStatus,
    required Color statusColor,
  }) {
    final busNumber = bus?['bus_no']?.toString().trim();
    final registrationNumber = bus?['reg_no']?.toString().trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              person?['name']?.toString() ?? 'Passenger',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              person?['person_type'] == 'employee'
                  ? 'Employee ID: ${person?['employee_id'] ?? '—'}'
                  : 'Admission: ${person?['admission_number'] ?? '—'}',
            ),
            const Divider(height: 24),
            Row(
              children: [
                const Icon(
                  Icons.directions_bus,
                  color: Colors.indigo,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    busNumber == null || busNumber.isEmpty
                        ? 'Bus not assigned'
                        : registrationNumber == null ||
                                registrationNumber.isEmpty
                            ? 'Bus $busNumber'
                            : 'Bus $busNumber • $registrationNumber',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (trip != null) ...[
              const SizedBox(height: 8),
              Text(
                '${_friendlyTripType(trip['trip_type'])} trip • Started ${_formatDateTime(trip['started_at'])}',
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: statusColor.withValues(alpha: 0.30),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    trackingStatus == 'live'
                        ? Icons.location_on
                        : Icons.info_outline,
                    color: statusColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      friendlyStatus,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _socketConnected ? Icons.wifi : Icons.sync,
                  size: 17,
                  color: _socketConnected ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 6),
                Text(
                  _socketConnected
                      ? 'Live updates connected'
                      : 'Refreshing automatically',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveLocationCard({
    required double? latitude,
    required double? longitude,
    required Map<String, dynamic>? location,
    required bool hasLocation,
    required String trackingStatus,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  color: Colors.indigo,
                ),
                const SizedBox(width: 8),
                Text(
                  'Current bus location',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (hasLocation)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 250,
                      child: FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: LatLng(latitude!, longitude!),
                          initialZoom: 15,
                          minZoom: 4,
                          maxZoom: 19,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.smcis.app',
                            maxZoom: 19,
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: LatLng(latitude, longitude),
                                width: 52,
                                height: 52,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.indigo,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.directions_bus,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const RichAttributionWidget(
                            attributions: [
                              TextSourceAttribution(
                                  'OpenStreetMap contributors'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_locationNameLoading)
                    const LinearProgressIndicator()
                  else if (_locationName != null) ...[
                    Text(
                      _locationName!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    'Coordinates: ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (location?['accuracy_meters'] != null)
                    Text(
                      'GPS accuracy: ${location?['accuracy_meters']} m',
                    ),
                  if (location?['recorded_at'] != null)
                    Text(
                      'Last updated: ${_formatDateTime(location?['recorded_at'])}',
                    ),
                  if (trackingStatus == 'stale')
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'This location may be delayed. The app will update automatically when a fresh location is received.',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _openMaps(
                        latitude,
                        longitude,
                      ),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Open in Google Maps'),
                    ),
                  ),
                ],
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.location_off_outlined,
                      size: 36,
                      color: Colors.orange,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'The bus location is not available right now. Please wait for the driver to start sharing it.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentCard(Map<String, dynamic>? assignment) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pickup / Drop details',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            if (assignment == null)
              const Text(
                'No transport assignment found for today.',
              )
            else ...[
              _buildStopSection(
                title: 'Pickup',
                icon: Icons.login,
                color: Colors.green,
                stop: assignment['pickup_stop'],
                address: assignment['pickup_address'],
                latitude: assignment['pickup_latitude'],
                longitude: assignment['pickup_longitude'],
              ),
              const SizedBox(height: 12),
              _buildStopSection(
                title: 'Drop',
                icon: Icons.logout,
                color: Colors.blue,
                stop: assignment['drop_stop'],
                address: assignment['drop_address'],
                latitude: assignment['drop_latitude'],
                longitude: assignment['drop_longitude'],
              ),
              const SizedBox(height: 12),
              _detailRow(
                'Notification radius',
                assignment['notification_radius_meters'] == null
                    ? '1500 m'
                    : '${assignment['notification_radius_meters']} m',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStopSection({
    required String title,
    required IconData icon,
    required Color color,
    required dynamic stop,
    required dynamic address,
    required dynamic latitude,
    required dynamic longitude,
  }) {
    final hasMapLocation =
        (_toDouble(latitude) != null && _toDouble(longitude) != null) ||
            (address != null && address.toString().trim().isNotEmpty);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _detailRow('$title stop', stop),
          _detailRow('$title address', address),
          if (hasMapLocation)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _openAssignedStopInMaps(
                  latitude: latitude,
                  longitude: longitude,
                  address: address,
                ),
                icon: const Icon(Icons.map_outlined),
                label: Text('Open $title location'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, dynamic value) {
    final text = value == null || value.toString().trim().isEmpty
        ? '—'
        : value.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(text),
          ),
        ],
      ),
    );
  }
}

class _BusTrackingException implements Exception {
  final String message;

  const _BusTrackingException(this.message);

  @override
  String toString() => message;
}
