import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/role_manager.dart';
import '../services/api_service.dart';
import '../widgets/role_dashboard_drawer.dart';
import '../widgets/role_switcher.dart';

class ExaminationDashboard extends StatefulWidget {
  const ExaminationDashboard({super.key});

  @override
  State<ExaminationDashboard> createState() => _ExaminationDashboardState();
}

class _ExaminationDashboardState extends State<ExaminationDashboard> {
  bool _isLoading = true;
  String _displayName = 'Examination';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('name') ?? prefs.getString('username') ?? 'Examination';
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
        title: const Text('Examination Dashboard'),
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
      drawer: const RoleDashboardDrawer(activeRole: AppRoles.examination),
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
                    'This is the Examination dashboard placeholder.\nAdd exam schedule, result moderation, and grading widgets here.',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  _dashboardCard(
                    icon: Icons.event_rounded,
                    title: 'Exam Schedule',
                    subtitle: 'View and manage upcoming exams and dates.',
                  ),
                  _dashboardCard(
                    icon: Icons.grade_rounded,
                    title: 'Result Moderation',
                    subtitle: 'Review and publish exam marks.',
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
