import 'package:flutter/material.dart';

class StudentDrawerMenu extends StatelessWidget {
  const StudentDrawerMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.blue),
            child: Text(
              'Student Menu',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            onTap: () => Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (route) => false),
          ),
          ListTile(
            leading: const Icon(Icons.assignment),
            title: const Text('Assignments'),
            onTap: () => Navigator.of(context).pushNamed('/assignments'),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('Time Table'),
            onTap: () => Navigator.of(context).pushNamed('/timetable'),
          ),
          ListTile(
            leading: const Icon(Icons.money),
            title: const Text('Fee Details'),
            onTap: () => Navigator.of(context).pushNamed('/fee-details'),
          ),
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('Circulars'),
            onTap: () => Navigator.of(context).pushNamed('/circulars'),
          ),
          ListTile(
            leading: const Icon(Icons.access_time),
            title: const Text('Attendance'),
            onTap: () => Navigator.of(context).pushNamed('/attendance'),
          ),
          ListTile(
            leading: const Icon(Icons.event_note),
            title: const Text('Leave Requests'),
            onTap: () => Navigator.of(context).pushNamed('/leave'),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () => Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false),
          ),
        ],
      ),
    );
  }
}
