import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/role_manager.dart';
import '../services/api_service.dart';
import '../widgets/role_dashboard_drawer.dart';
import '../widgets/role_switcher.dart';

class TransportDashboard extends StatefulWidget {
  const TransportDashboard({super.key});

  @override
  State<TransportDashboard> createState() => _TransportDashboardState();
}

class _TransportDashboardState extends State<TransportDashboard> {
  bool _isLoading = true;
  String _displayName = 'Transport';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('name') ?? prefs.getString('username') ?? 'Transport';
    if (!mounted) return;
    setState(() {
      _displayName = name;
      _isLoading = false;
    });
  }

  Future<void> _logout() async {
    await ApiService.clearLocalSession();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transport Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.switch_account_rounded),
            tooltip: 'Switch Role',
            onPressed: () => RoleSwitcher.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      drawer: const RoleDashboardDrawer(activeRole: AppRoles.transport),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome, $_displayName',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This is the Transport dashboard placeholder.\nAdd route, vehicle, and student transport tracking widgets here.',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  _dashboardCard(
                    icon: Icons.directions_bus_rounded,
                    title: 'Route Management',
                    subtitle: 'Manage buses, routes, and stop schedules.',
                  ),
                  _dashboardCard(
                    icon: Icons.people_rounded,
                    title: 'Student Pickup Status',
                    subtitle: 'Track which students are checked in or on route.',
                  ),
                ],
              ),
            ),
    );
  }

  Widget _dashboardCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, size: 32, color: Theme.of(context).primaryColor),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
      ),
    );
  }
}
