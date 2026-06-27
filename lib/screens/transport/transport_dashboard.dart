import 'package:flutter/material.dart';

import '../../auth/role_manager.dart';
import '../../services/role_dashboard_api.dart';
import '../../widgets/admin_module_widgets.dart';

class TransportDashboardScreen extends StatelessWidget {
  const TransportDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminDashboardScaffold(
      activeRole: AppRoles.transport,
      title: 'Transport Dashboard',
      fallbackName: 'Transport',
      heroTitle: 'Transport Control Room',
      heroSubtitle:
          'Manage routes, buses, student assignments, staff and pickup attendance like the PITS transport portal.',
      heroIcon: Icons.directions_bus_rounded,
      accent: const Color(0xFF0891B2),
      dataLoader: RoleDashboardApi.transport,
      metrics: const [
        AdminMetric(
          label: 'Routes',
          value: 'Session',
          helper: 'Active transportations',
          icon: Icons.alt_route_rounded,
          color: Color(0xFF0891B2),
        ),
        AdminMetric(
          label: 'Buses',
          value: 'Fleet',
          helper: 'Vehicle readiness',
          icon: Icons.directions_bus_filled_rounded,
          color: Color(0xFF16A34A),
        ),
        AdminMetric(
          label: 'Students',
          value: 'Mapped',
          helper: 'Route assignments',
          icon: Icons.person_pin_circle_rounded,
          color: Color(0xFF4F46E5),
        ),
        AdminMetric(
          label: 'Attendance',
          value: 'Mobile',
          helper: 'Pickup and drop',
          icon: Icons.check_circle_rounded,
          color: Color(0xFFD97706),
        ),
      ],
      primaryActionTitle: 'Transport Actions',
      primaryActions: const [
        AdminAction(
          title: 'Routes',
          subtitle: 'Villages, cost and fine rules',
          icon: Icons.signpost_rounded,
          color: Color(0xFF0891B2),
          routeName: '/transport/routes',
        ),
        AdminAction(
          title: 'Buses',
          subtitle: 'Fleet and active vehicle status',
          icon: Icons.directions_bus_rounded,
          color: Color(0xFF16A34A),
          routeName: '/transport/buses',
        ),
        AdminAction(
          title: 'Assign Students',
          subtitle: 'Route and stop assignments',
          icon: Icons.person_pin_circle_rounded,
          color: Color(0xFF4F46E5),
          routeName: '/transport/student-assignments',
        ),
        AdminAction(
          title: 'Transport Staff',
          subtitle: 'Drivers, conductors and accounts',
          icon: Icons.badge_rounded,
          color: Color(0xFFE11D48),
          routeName: '/transport/staff',
        ),
        AdminAction(
          title: 'Mark Attendance',
          subtitle: 'Pickup and drop mobile marking',
          icon: Icons.check_circle_rounded,
          color: Color(0xFFD97706),
          routeName: '/transport/attendance',
        ),
        AdminAction(
          title: 'Attendance Report',
          subtitle: 'Bus-wise daily summary',
          icon: Icons.assessment_rounded,
          color: Color(0xFF0F766E),
          routeName: '/transport/attendance-report',
        ),
      ],
      highlights: const [
        AdminFeedItem(
          title: 'Driver and conductor ready',
          subtitle:
              'Mobile flow matches PITS: transport staff can mark pickup and drop attendance.',
          meta: 'Mobile',
          icon: Icons.phone_android_rounded,
          color: Color(0xFFD97706),
        ),
        AdminFeedItem(
          title: 'Session-aware assignments',
          subtitle:
              'Student route assignment, bus setup and fee overrides stay grouped for the active session.',
          meta: 'Routes',
          icon: Icons.route_rounded,
          color: Color(0xFF0891B2),
        ),
      ],
      secondaryActionTitle: 'Transport Tools',
      secondaryActions: const [
        AdminAction(
          title: 'Pickup Tracking',
          subtitle: 'Student boarding monitor',
          icon: Icons.people_rounded,
          color: Color(0xFFD97706),
          routeName: '/transport/pickup-tracking',
        ),
        AdminAction(
          title: 'Vehicle Status',
          subtitle: 'Fleet readiness review',
          icon: Icons.map_rounded,
          color: Color(0xFF16A34A),
          routeName: '/transport/vehicle-status',
        ),
        AdminAction(
          title: 'Fee Overrides',
          subtitle: 'Student transport fee changes',
          icon: Icons.payments_rounded,
          color: Color(0xFF7C3AED),
          routeName: '/transport/fee-overrides',
        ),
      ],
      timeline: const [
        AdminFeedItem(
          title: 'Before marking attendance',
          subtitle:
              'Confirm bus, route, driver, conductor and active student assignment mapping.',
          meta: 'Daily',
          icon: Icons.fact_check_rounded,
          color: Color(0xFF0F766E),
        ),
      ],
    );
  }
}
