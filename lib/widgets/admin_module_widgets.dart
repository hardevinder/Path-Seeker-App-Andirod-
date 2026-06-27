import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/role_manager.dart';
import '../services/api_service.dart';
import 'role_dashboard_drawer.dart';
import 'role_switcher.dart';

class AdminMetric {
  final String label;
  final String value;
  final String helper;
  final IconData icon;
  final Color color;

  const AdminMetric({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
    required this.color,
  });
}

class AdminAction {
  final String title;
  final String subtitle;
  final String? badge;
  final IconData icon;
  final Color color;
  final String? routeName;

  const AdminAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.badge,
    this.routeName,
  });
}

class AdminActionSection {
  final String title;
  final List<AdminAction> actions;
  final bool compact;

  const AdminActionSection({
    required this.title,
    required this.actions,
    this.compact = false,
  });
}

class AdminFeedItem {
  final String title;
  final String subtitle;
  final String meta;
  final IconData icon;
  final Color color;

  const AdminFeedItem({
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.icon,
    required this.color,
  });
}

class AdminDashboardPayload {
  final List<AdminMetric>? metrics;
  final List<AdminFeedItem>? highlights;
  final List<AdminFeedItem>? timeline;

  const AdminDashboardPayload({
    this.metrics,
    this.highlights,
    this.timeline,
  });
}

class AdminDashboardScaffold extends StatefulWidget {
  final String activeRole;
  final String title;
  final String fallbackName;
  final String heroTitle;
  final String heroSubtitle;
  final IconData heroIcon;
  final Color accent;
  final List<AdminMetric> metrics;
  final List<AdminAction> primaryActions;
  final List<AdminAction> secondaryActions;
  final List<AdminActionSection> actionSections;
  final List<AdminFeedItem> highlights;
  final List<AdminFeedItem> timeline;
  final String primaryActionTitle;
  final String secondaryActionTitle;
  final String highlightsTitle;
  final String timelineTitle;
  final Future<AdminDashboardPayload> Function()? dataLoader;

  const AdminDashboardScaffold({
    super.key,
    required this.activeRole,
    required this.title,
    required this.fallbackName,
    required this.heroTitle,
    required this.heroSubtitle,
    required this.heroIcon,
    required this.accent,
    required this.metrics,
    required this.primaryActions,
    this.secondaryActions = const [],
    this.actionSections = const [],
    this.highlights = const [],
    this.timeline = const [],
    this.primaryActionTitle = 'Quick Actions',
    this.secondaryActionTitle = 'More Tools',
    this.highlightsTitle = 'Today Snapshot',
    this.timelineTitle = 'Recent Work',
    this.dataLoader,
  });

  @override
  State<AdminDashboardScaffold> createState() => _AdminDashboardScaffoldState();
}

class _AdminDashboardScaffoldState extends State<AdminDashboardScaffold> {
  bool _isLoading = true;
  bool _isSyncing = false;
  String? _dataError;
  DateTime? _lastSynced;
  late String _displayName = widget.fallbackName;
  List<AdminMetric>? _liveMetrics;
  List<AdminFeedItem>? _liveHighlights;
  List<AdminFeedItem>? _liveTimeline;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadProfile(showLoader: false),
      _loadDashboardData(),
    ]);
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _loadProfile({bool showLoader = true}) async {
    if (showLoader) setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('name') ??
        prefs.getString('username') ??
        widget.fallbackName;
    if (!mounted) return;
    setState(() {
      _displayName = name;
      if (showLoader) _isLoading = false;
    });
  }

  Future<void> _loadDashboardData() async {
    final loader = widget.dataLoader;
    if (loader == null) return;

    if (mounted) {
      setState(() {
        _isSyncing = true;
        _dataError = null;
      });
    }

    try {
      final payload = await loader();
      if (!mounted) return;
      setState(() {
        _liveMetrics = payload.metrics;
        _liveHighlights = payload.highlights;
        _liveTimeline = payload.timeline;
        _lastSynced = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dataError = 'Live dashboard data could not be loaded.';
      });
    } finally {
      if (!mounted) return;
      setState(() => _isSyncing = false);
    }
  }

  Future<void> _logout() async {
    await ApiService.clearLocalSession();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  void _openAction(AdminAction action) {
    if (action.routeName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${action.title} is available on the web portal.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.of(context).pushNamed(action.routeName!);
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _liveMetrics ?? widget.metrics;
    final highlights = _liveHighlights ?? widget.highlights;
    final timeline = _liveTimeline ?? widget.timeline;
    final actionSections = widget.actionSections.isNotEmpty
        ? widget.actionSections
        : [
            AdminActionSection(
              title: widget.primaryActionTitle,
              actions: widget.primaryActions,
            ),
            if (widget.secondaryActions.isNotEmpty)
              AdminActionSection(
                title: widget.secondaryActionTitle,
                actions: widget.secondaryActions,
                compact: true,
              ),
          ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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
      drawer: RoleDashboardDrawer(activeRole: widget.activeRole),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshAll,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  _HeroPanel(
                    title: widget.heroTitle,
                    subtitle: widget.heroSubtitle,
                    displayName: _displayName,
                    icon: widget.heroIcon,
                    accent: widget.accent,
                  ),
                  if (widget.dataLoader != null) ...[
                    const SizedBox(height: 10),
                    _SyncStrip(
                      isSyncing: _isSyncing,
                      error: _dataError,
                      lastSynced: _lastSynced,
                    ),
                  ],
                  const SizedBox(height: 16),
                  _MetricGrid(metrics: metrics),
                  for (final section in actionSections)
                    if (section.actions.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      _SectionTitle(title: section.title),
                      const SizedBox(height: 10),
                      _ActionGrid(
                        actions: section.actions,
                        onTap: _openAction,
                        compact: section.compact,
                      ),
                    ],
                  if (highlights.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _SectionTitle(title: widget.highlightsTitle),
                    const SizedBox(height: 10),
                    _FeedList(items: highlights),
                  ],
                  if (timeline.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _SectionTitle(title: widget.timelineTitle),
                    const SizedBox(height: 10),
                    _FeedList(items: timeline),
                  ],
                ],
              ),
            ),
    );
  }
}

class _SyncStrip extends StatelessWidget {
  final bool isSyncing;
  final String? error;
  final DateTime? lastSynced;

  const _SyncStrip({
    required this.isSyncing,
    required this.error,
    required this.lastSynced,
  });

  @override
  Widget build(BuildContext context) {
    final color = error != null
        ? Colors.orange.shade700
        : isSyncing
            ? Colors.blue.shade700
            : Colors.green.shade700;
    final text = error ??
        (isSyncing
            ? 'Syncing live data...'
            : lastSynced == null
                ? 'Live data ready'
                : 'Live data synced ${_timeLabel(lastSynced!)}');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(55)),
      ),
      child: Row(
        children: [
          if (isSyncing)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(
              error != null
                  ? Icons.cloud_off_rounded
                  : Icons.cloud_done_rounded,
              color: color,
              size: 18,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _timeLabel(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class AdminFeatureScreen extends StatefulWidget {
  final String activeRole;
  final String title;
  final String fallbackName;
  final String summary;
  final IconData icon;
  final Color accent;
  final List<AdminMetric> metrics;
  final List<AdminAction> actions;
  final List<AdminFeedItem> checklist;
  final List<AdminFeedItem> records;
  final String checklistTitle;
  final String recordsTitle;
  final Future<AdminDashboardPayload> Function()? dataLoader;

  const AdminFeatureScreen({
    super.key,
    required this.activeRole,
    required this.title,
    required this.fallbackName,
    required this.summary,
    required this.icon,
    required this.accent,
    this.metrics = const [],
    this.actions = const [],
    this.checklist = const [],
    this.records = const [],
    this.checklistTitle = 'Workflow',
    this.recordsTitle = 'Focus Items',
    this.dataLoader,
  });

  @override
  State<AdminFeatureScreen> createState() => _AdminFeatureScreenState();
}

class _AdminFeatureScreenState extends State<AdminFeatureScreen> {
  bool _isLoading = true;
  bool _isSyncing = false;
  String? _dataError;
  DateTime? _lastSynced;
  late String _displayName = widget.fallbackName;
  List<AdminMetric>? _liveMetrics;
  List<AdminFeedItem>? _liveChecklist;
  List<AdminFeedItem>? _liveRecords;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadProfile(showLoader: false),
      _loadFeatureData(),
    ]);
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _loadProfile({bool showLoader = true}) async {
    if (showLoader) setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('name') ??
        prefs.getString('username') ??
        widget.fallbackName;
    if (!mounted) return;
    setState(() {
      _displayName = name;
      if (showLoader) _isLoading = false;
    });
  }

  Future<void> _loadFeatureData() async {
    final loader = widget.dataLoader;
    if (loader == null) return;

    if (mounted) {
      setState(() {
        _isSyncing = true;
        _dataError = null;
      });
    }

    try {
      final payload = await loader();
      if (!mounted) return;
      setState(() {
        _liveMetrics = payload.metrics;
        _liveChecklist = payload.highlights;
        _liveRecords = payload.timeline;
        _lastSynced = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _dataError = 'Live records could not be loaded.');
    } finally {
      if (!mounted) return;
      setState(() => _isSyncing = false);
    }
  }

  Future<void> _logout() async {
    await ApiService.clearLocalSession();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  void _openAction(AdminAction action) {
    if (action.routeName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${action.title} is available on the web portal.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.of(context).pushNamed(action.routeName!);
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _liveMetrics ?? widget.metrics;
    final checklist = _liveChecklist ?? widget.checklist;
    final records = _liveRecords ?? widget.records;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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
      drawer: RoleDashboardDrawer(activeRole: widget.activeRole),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshAll,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  _HeroPanel(
                    title: widget.title,
                    subtitle: widget.summary,
                    displayName: _displayName,
                    icon: widget.icon,
                    accent: widget.accent,
                  ),
                  if (widget.dataLoader != null) ...[
                    const SizedBox(height: 10),
                    _SyncStrip(
                      isSyncing: _isSyncing,
                      error: _dataError,
                      lastSynced: _lastSynced,
                    ),
                  ],
                  if (metrics.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _MetricGrid(metrics: metrics),
                  ],
                  if (widget.actions.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    const _SectionTitle(title: 'Actions'),
                    const SizedBox(height: 10),
                    _ActionGrid(actions: widget.actions, onTap: _openAction),
                  ],
                  if (checklist.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _SectionTitle(title: widget.checklistTitle),
                    const SizedBox(height: 10),
                    _FeedList(items: checklist),
                  ],
                  if (records.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _SectionTitle(title: widget.recordsTitle),
                    const SizedBox(height: 10),
                    _FeedList(items: records),
                  ],
                ],
              ),
            ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final String displayName;
  final IconData icon;
  final Color accent;

  const _HeroPanel({
    required this.title,
    required this.subtitle,
    required this.displayName,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final dark = HSLColor.fromColor(accent)
        .withLightness(0.24)
        .withSaturation(0.72)
        .toColor();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [dark, accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: accent.withAlpha(52),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(38),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withAlpha(52)),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, $displayName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    height: 1.35,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  final List<AdminMetric> metrics;

  const _MetricGrid({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 840
            ? 4
            : width >= 560
                ? 3
                : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: metrics.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: width < 360 ? 1.12 : 1.28,
          ),
          itemBuilder: (context, index) => _MetricCard(metric: metrics[index]),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final AdminMetric metric;

  const _MetricCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: metric.color.withAlpha(22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: metric.color.withAlpha(48)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(metric.icon, size: 20, color: metric.color),
                const Spacer(),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: metric.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const Spacer(),
            FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                metric.value,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              metric.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              metric.helper,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  final List<AdminAction> actions;
  final ValueChanged<AdminAction> onTap;
  final bool compact;

  const _ActionGrid({
    required this.actions,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = compact
            ? width >= 720
                ? 3
                : width >= 460
                    ? 2
                    : 1
            : width >= 800
                ? 3
                : width >= 520
                    ? 2
                    : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: compact ? 2.55 : 2.25,
          ),
          itemBuilder: (context, index) {
            final action = actions[index];
            return Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: action.color.withAlpha(46)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onTap(action),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: action.color.withAlpha(28),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(action.icon, color: action.color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    action.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                if (action.badge != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: action.color.withAlpha(30),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      action.badge!,
                                      style: TextStyle(
                                        color: action.color,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              action.subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 12,
                                height: 1.22,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        action.routeName == null
                            ? Icons.public_rounded
                            : Icons.chevron_right_rounded,
                        color: Colors.grey.shade500,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _FeedList extends StatelessWidget {
  final List<AdminFeedItem> items;

  const _FeedList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items
          .map(
            (item) => Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: item.color.withAlpha(24),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(item.icon, color: item.color, size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.subtitle,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              height: 1.3,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.meta,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: item.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: Colors.grey.shade300)),
      ],
    );
  }
}
