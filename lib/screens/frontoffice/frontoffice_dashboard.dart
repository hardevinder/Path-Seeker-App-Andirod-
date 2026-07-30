import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class FrontOfficeDashboard extends StatelessWidget {
  const FrontOfficeDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Front Office'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ApiService.clearLocalSession();
              if (context.mounted) {
                Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Visitor Management', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Scan an ID, notify the employee and track the complete meeting.'),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(18)),
              onPressed: () => Navigator.pushNamed(context, '/frontoffice/visitor-checkin'),
              icon: const Icon(Icons.document_scanner),
              label: const Text('Scan ID & Check In Visitor'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(18)),
              onPressed: () => Navigator.pushNamed(context, '/my-visitors'),
              icon: const Icon(Icons.history),
              label: const Text('Visitor Records'),
            ),
          ],
        ),
      ),
    );
  }
}
