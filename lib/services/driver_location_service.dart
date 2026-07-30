import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

import 'api_service.dart';

/// Owns driver tracking independently of the trip screen.
///
/// Keeping the position subscription here prevents normal navigation from
/// stopping an active trip. The timer also acts as a heartbeat and retries the
/// latest position when an upload failed or the bus has not moved far enough
/// to trigger the distance filter.
class DriverLocationService {
  DriverLocationService._();

  static final DriverLocationService instance = DriverLocationService._();
  static const Duration _uploadInterval = Duration(seconds: 20);

  StreamSubscription<Position>? _positionSubscription;
  Timer? _heartbeat;
  Position? _latestPosition;
  int? _tripId;
  bool _uploading = false;

  bool get isTracking => _tripId != null;
  int? get tripId => _tripId;

  Future<String?> start(int tripId) async {
    if (_tripId == tripId && _positionSubscription != null) return null;

    await _cancelPositionSubscription();
    _tripId = tripId;

    if (!await Geolocator.isLocationServiceEnabled()) {
      _tripId = null;
      return 'Turn on Location Services to share the bus location.';
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _tripId = null;
      return 'Location permission is required while a trip is active. Enable it in phone settings.';
    }

    await _subscribe();
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_uploadInterval, (_) => _heartbeatUpload());
    return null;
  }

  Future<void> stop() async {
    _tripId = null;
    _latestPosition = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    await _cancelPositionSubscription();
  }

  Future<void> _subscribe() async {
    if (_tripId == null) return;

    final LocationSettings settings;
    if (Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 12),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Bus trip in progress',
          notificationText: 'Sharing the bus location with the school',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else if (Platform.isIOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 10,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
    }

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        _latestPosition = position;
        _upload(position);
      },
      onError: (_) {
        _positionSubscription = null;
        _scheduleStreamRestart();
      },
      onDone: () {
        _positionSubscription = null;
        _scheduleStreamRestart();
      },
    );
  }

  void _scheduleStreamRestart() {
    if (_tripId == null) return;
    Timer(const Duration(seconds: 5), () async {
      if (_tripId != null && _positionSubscription == null) {
        await _subscribe();
      }
    });
  }

  Future<void> _heartbeatUpload() async {
    if (_tripId == null) return;

    var position = _latestPosition;
    if (position == null) {
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 15));
        _latestPosition = position;
      } catch (_) {
        if (_positionSubscription == null) _scheduleStreamRestart();
        return;
      }
    }
    await _upload(position);
  }

  Future<void> _upload(Position position) async {
    final activeTripId = _tripId;
    if (activeTripId == null || _uploading) return;

    _uploading = true;
    try {
      final response =
          await ApiService.rawPost('/bus-trips/$activeTripId/location', {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy_meters': position.accuracy,
        'speed_kmh': position.speed < 0 ? null : position.speed * 3.6,
        'heading': position.heading < 0 ? null : position.heading,
        // This upload is also a connection heartbeat. The location history
        // model still records when the server received each update.
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }
    } catch (_) {
      // The heartbeat retries the latest known position on the next tick.
    } finally {
      _uploading = false;
    }
  }

  Future<void> _cancelPositionSubscription() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }
}
