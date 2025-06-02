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
            onTap: () => Navigator.pushNamed(context, '/dashboard'),
          ),
          ListTile(
            leading: const Icon(Icons.assignment),
            title: const Text('Assignments'),
            onTap: () => Navigator.pushNamed(context, '/assignments'),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('Time Table'),
            onTap: () => Navigator.pushNamed(context, '/timetable'),
          ),
          ListTile(
            leading: const Icon(Icons.money),
            title: const Text('Fee Details'),
            onTap: () => Navigator.pushNamed(context, '/fee-details'),
          ),
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('Circulars'),
            onTap: () => Navigator.pushNamed(context, '/circulars'),
          ),
          ListTile(
            leading: const Icon(Icons.access_time),
            title: const Text('Attendance'),
            onTap: () => Navigator.pushNamed(context, '/attendance'),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () => Navigator.pushReplacementNamed(context, '/login'),
          ),
        ],
      ),
    );
  }
}
