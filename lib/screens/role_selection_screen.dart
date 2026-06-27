import 'package:flutter/material.dart';

import '../widgets/role_switcher.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  bool _loading = true;
  List<String> _roles = [];
  String _activeRole = '';

  @override
  void initState() {
    super.initState();
    _loadRoles();
  }

  Future<void> _loadRoles() async {
    final roles = await RoleSwitcher.loadSupportedRoles();
    final activeRole = await RoleSwitcher.loadActiveRole();

    if (!mounted) return;

    setState(() {
      _roles = roles;
      _activeRole = activeRole;
      _loading = false;
    });
  }

  Future<void> _selectRole(String role) async {
    await RoleSwitcher.switchTo(context, role);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose Role')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RoleSwitcherSheet(
              roles: _roles,
              activeRole: _activeRole,
              onSelected: _selectRole,
            ),
    );
  }
}
