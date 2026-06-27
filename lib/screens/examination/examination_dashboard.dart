import 'package:flutter/material.dart';

import '../../auth/role_manager.dart';
import '../../services/role_dashboard_api.dart';
import '../../widgets/admin_module_widgets.dart';

class ExaminationDashboardScreen extends StatelessWidget {
  const ExaminationDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminDashboardScaffold(
      activeRole: AppRoles.examination,
      title: 'Examination Dashboard',
      fallbackName: 'Examination',
      heroTitle: 'Examination Workspace',
      heroSubtitle:
          'Manage exams, schemes, marks, co-scholastic entries, report cards and final result analytics.',
      heroIcon: Icons.fact_check_rounded,
      accent: const Color(0xFF7C3AED),
      dataLoader: RoleDashboardApi.examination,
      metrics: const [
        AdminMetric(
          label: 'Exams',
          value: 'Manage',
          helper: 'Create and lock',
          icon: Icons.edit_calendar_rounded,
          color: Color(0xFF2563EB),
        ),
        AdminMetric(
          label: 'Schemes',
          value: 'Setup',
          helper: 'Components and weightage',
          icon: Icons.schema_rounded,
          color: Color(0xFF7C3AED),
        ),
        AdminMetric(
          label: 'Entries',
          value: 'Marks',
          helper: 'Marks and grades',
          icon: Icons.edit_note_rounded,
          color: Color(0xFF0F766E),
        ),
        AdminMetric(
          label: 'Reports',
          value: 'Final',
          helper: 'Cards and summaries',
          icon: Icons.emoji_events_rounded,
          color: Color(0xFFD97706),
        ),
      ],
      primaryActionTitle: 'Manage',
      primaryActions: const [
        AdminAction(
          title: 'Manage Exams',
          subtitle: 'Create, edit and lock exams',
          icon: Icons.edit_calendar_rounded,
          color: Color(0xFF2563EB),
          routeName: '/examination/exams',
        ),
        AdminAction(
          title: 'Exam Schedule',
          subtitle: 'Dates, sessions and classes',
          icon: Icons.event_rounded,
          color: Color(0xFF0891B2),
          routeName: '/examination/schedule',
        ),
        AdminAction(
          title: 'Exam Schemes',
          subtitle: 'Components and weightage',
          icon: Icons.schema_rounded,
          color: Color(0xFF7C3AED),
          routeName: '/examination/schemes',
        ),
        AdminAction(
          title: 'Marks Entry',
          subtitle: 'Subject marks entry',
          icon: Icons.edit_note_rounded,
          color: Color(0xFF2563EB),
          badge: 'ENTRY',
          routeName: '/examination/marks-entry',
        ),
        AdminAction(
          title: 'Co-Scholastic',
          subtitle: 'Grades and area mapping',
          icon: Icons.extension_rounded,
          color: Color(0xFF0F766E),
          badge: 'ENTRY',
          routeName: '/examination/co-scholastic',
        ),
        AdminAction(
          title: 'Final Result',
          subtitle: 'Weighted totals and ranking',
          icon: Icons.emoji_events_rounded,
          color: Color(0xFFD97706),
          badge: 'REPORT',
          routeName: '/examination/final-result',
        ),
      ],
      highlights: const [
        AdminFeedItem(
          title: 'PITS-style quick entries',
          subtitle:
              'Marks, co-scholastic grades, remarks and promotion decisions are grouped for exam teams.',
          meta: 'Entry',
          icon: Icons.edit_note_rounded,
          color: Color(0xFF2563EB),
        ),
        AdminFeedItem(
          title: 'Final result summary',
          subtitle:
              'Class-wise weighted totals, grades, Excel export and toppers ranking are surfaced as a main workflow.',
          meta: 'Report',
          icon: Icons.emoji_events_rounded,
          color: Color(0xFFD97706),
        ),
      ],
      secondaryActionTitle: 'Entries & Reports',
      secondaryActions: const [
        AdminAction(
          title: 'Remarks',
          subtitle: 'Student report comments',
          icon: Icons.rate_review_rounded,
          color: Color(0xFFD97706),
          routeName: '/examination/remarks',
        ),
        AdminAction(
          title: 'Promotion',
          subtitle: 'Promotion decision entry',
          icon: Icons.school_rounded,
          color: Color(0xFF4F46E5),
          routeName: '/examination/promotion',
        ),
        AdminAction(
          title: 'Report Cards',
          subtitle: 'Generate student PDFs',
          icon: Icons.picture_as_pdf_rounded,
          color: Color(0xFFE11D48),
          routeName: '/examination/report-cards',
        ),
        AdminAction(
          title: 'Result Moderation',
          subtitle: 'Review and approve results',
          icon: Icons.grade_rounded,
          color: Color(0xFFE11D48),
          routeName: '/examination/result-moderation',
        ),
        AdminAction(
          title: 'Exam Reports',
          subtitle: 'Summaries and analytics',
          icon: Icons.assignment_turned_in_rounded,
          color: Color(0xFF16A34A),
          routeName: '/examination/reports',
        ),
      ],
      timeline: const [
        AdminFeedItem(
          title: 'Before report cards',
          subtitle:
              'Verify schemes, marks, co-scholastic grades, remarks and result moderation.',
          meta: 'Ready',
          icon: Icons.checklist_rounded,
          color: Color(0xFF16A34A),
        ),
      ],
    );
  }
}
