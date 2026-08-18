import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_service.dart';
import 'driver_trip_screen.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _buses = const [];
  String _name = 'Driver';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final response =
          await ApiService.rawGet('/transport-attendance/my-buses');
      final decoded = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(decoded is Map
            ? decoded['message'] ?? 'Unable to load assigned bus'
            : 'Unable to load assigned bus');
      }
      final dynamic raw = decoded is List
          ? decoded
          : decoded is Map
              ? decoded['buses'] ?? decoded['data'] ?? []
              : [];
      if (!mounted) return;
      setState(() {
        _name = prefs.getString('name')?.trim().isNotEmpty == true
            ? prefs.getString('name')!.trim()
            : 'Driver';
        _buses = raw is List
            ? raw
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
            : [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    await ApiService.clearLocalSession();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        actions: [
          IconButton(
              onPressed: _logout,
              tooltip: 'Logout',
              icon: const Icon(Icons.logout))
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text('Welcome, $_name',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Your assigned school transport'),
            const SizedBox(height: 20),
            if (_loading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator()))
            else if (_error != null)
              _MessageCard(
                  icon: Icons.error_outline,
                  message: _error!,
                  color: Colors.red)
            else if (_buses.isEmpty)
              const _MessageCard(
                  icon: Icons.directions_bus_outlined,
                  message: 'No active bus is assigned to this driver.',
                  color: Colors.orange)
            else
              ..._buses.map(_busCard),
            if (!_loading && _error == null) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/document-vault'),
                  icon: const Icon(Icons.shield_outlined, size: 26),
                  label: const Text('MY DOCUMENTS',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
            if (!_loading && _error == null && _buses.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 58,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DriverTripScreen()),
                  ),
                  icon: const Icon(Icons.route, size: 28),
                  label: const Text('OPEN TRIP & ATTENDANCE',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _busCard(Map<String, dynamic> bus) {
    final busNo =
        bus['bus_no'] ?? bus['busNo'] ?? bus['name'] ?? 'Assigned Bus';
    final registration =
        bus['reg_no'] ?? bus['registration_no'] ?? bus['regNo'];
    final capacity = bus['capacity'];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: const CircleAvatar(child: Icon(Icons.directions_bus)),
        title: Text(busNo.toString(),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text([
          if (registration != null) 'Registration: $registration',
          if (capacity != null) 'Capacity: $capacity',
        ].join('\n')),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard(
      {required this.icon, required this.message, required this.color});
  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Icon(icon, size: 44, color: color),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center)
          ]),
        ),
      );
}
