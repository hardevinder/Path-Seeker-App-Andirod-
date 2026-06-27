import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/role_manager.dart';
import '../services/api_service.dart';
import '../widgets/role_dashboard_drawer.dart';
import '../widgets/role_switcher.dart';

class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({super.key});

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard> {
  bool _isLoading = true;
  String _displayName = 'Super Admin';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('name') ?? prefs.getString('username') ?? 'Super Admin';
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
        title: const Text('Super Admin Dashboard'),
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
      drawer: const RoleDashboardDrawer(activeRole: AppRoles.superadmin),
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
                    'This is the Super Admin dashboard placeholder.\nAdd role-specific widgets, reports and quick actions here.',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  _dashboardCard(
                    icon: Icons.shield_rounded,
                    title: 'Manage School Settings',
                    subtitle: 'View and configure global school settings.',
                  ),
                  _dashboardCard(
                    icon: Icons.group_rounded,
                    title: 'User & Role Management',
                    subtitle: 'Manage user access, roles, and permissions.',
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
