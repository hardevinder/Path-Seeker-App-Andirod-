import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/role_manager.dart';

class RoleSwitcher {
  static Future<List<String>> loadSupportedRoles() async {
    final prefs = await SharedPreferences.getInstance();
    final storedRoles = AppRoles.decodeStoredRoles(prefs.getString('roles'));
    return AppRoles.supportedFrom(storedRoles);
  }

  static Future<String> loadActiveRole() async {
    final prefs = await SharedPreferences.getInstance();
    return AppRoles.normalize(prefs.getString('activeRole'));
  }

  static Future<void> switchTo(BuildContext context, String role) async {
    final normalized = AppRoles.normalize(role);
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('activeRole', normalized);
    await prefs.setString('selectedRole', normalized);

    if (!context.mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoles.dashboardRoute(normalized),
      (route) => false,
    );
  }

  static Future<void> show(BuildContext context) async {
    final roles = await loadSupportedRoles();
    final activeRole = await loadActiveRole();

    if (!context.mounted) return;

    if (roles.length <= 1) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other role available')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return RoleSwitcherSheet(
          roles: roles,
          activeRole: activeRole,
          onSelected: (role) async {
            Navigator.of(sheetContext).pop();
            await switchTo(context, role);
          },
        );
      },
    );
  }
}

class RoleSwitcherSheet extends StatelessWidget {
  final List<String> roles;
  final String activeRole;
  final ValueChanged<String> onSelected;

  const RoleSwitcherSheet({
    super.key,
    required this.roles,
    required this.activeRole,
    required this.onSelected,
  });

  IconData _iconFor(String role) {
    switch (AppRoles.normalize(role)) {
      case AppRoles.superadmin:
        return Icons.security_rounded;
      case AppRoles.accounts:
        return Icons.account_balance_wallet_rounded;
      case AppRoles.hr:
        return Icons.people_rounded;
      case AppRoles.transport:
        return Icons.directions_bus_rounded;
      case AppRoles.examination:
        return Icons.school_rounded;
      case AppRoles.coordinator:
        return Icons.manage_accounts_rounded;
      case AppRoles.teacher:
        return Icons.school_rounded;
      case AppRoles.student:
      default:
        return Icons.person_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxSheetHeight = screenHeight * 0.86;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Switch Role',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Continue as one of your assigned roles',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: Scrollbar(
                  thumbVisibility: true,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: roles.length,
                    itemBuilder: (context, index) {
                      final role = roles[index];
                      final normalized = AppRoles.normalize(role);
                      final selected = normalized == activeRole;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : const Color(0xFFE5E7EB),
                            ),
                          ),
                          leading: Icon(_iconFor(role)),
                          title: Text(
                            AppRoles.label(role),
                            style:
                                const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle:
                              selected ? const Text('Current role') : null,
                          trailing: selected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : const Icon(Icons.chevron_right_rounded),
                          onTap: selected ? null : () => onSelected(normalized),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
