import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/school_chat_service.dart';

class SchoolChatFloatingOverlay extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final ValueListenable<String?> currentRoute;

  const SchoolChatFloatingOverlay({
    super.key,
    required this.child,
    required this.navigatorKey,
    required this.currentRoute,
  });

  @override
  State<SchoolChatFloatingOverlay> createState() =>
      _SchoolChatFloatingOverlayState();
}

class _SchoolChatFloatingOverlayState extends State<SchoolChatFloatingOverlay> {
  static const Set<String> _allowedRoles = {
    'student',
    'teacher',
    'principal',
    'superadmin',
    'super_admin',
    'admin',
    'academic_coordinator',
    'academic-coordinator',
    'coordinator',
    'hr',
    'accounts',
    'accountant',
  };

  SchoolChatService? _service;
  Timer? _pollTimer;
  bool _eligible = false;
  bool _connecting = false;
  bool _connected = false;
  int _unread = 0;

  String? get _route => widget.currentRoute.value;
  bool get _hiddenRoute =>
      _route == '/login' ||
      _route == '/choose-role' ||
      _route == '/school-chat';

  @override
  void initState() {
    super.initState();
    widget.currentRoute.addListener(_routeChanged);
    _bootstrap();
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_eligible && !_hiddenRoute) _loadUnread();
    });
  }

  @override
  void dispose() {
    widget.currentRoute.removeListener(_routeChanged);
    _pollTimer?.cancel();
    _service?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final token =
        (prefs.getString('authToken') ?? prefs.getString('token') ?? '').trim();
    final role = (prefs.getString('activeRole') ?? '').trim().toLowerCase();
    final eligible = token.isNotEmpty && _allowedRoles.contains(role);

    if (!mounted) return;
    if (_eligible != eligible) setState(() => _eligible = eligible);

    if (!eligible) {
      _disconnect();
      if (_unread != 0 && mounted) setState(() => _unread = 0);
      return;
    }

    await _syncConnection();
    if (!_hiddenRoute) await _loadUnread();
  }

  void _routeChanged() {
    _bootstrap();
    if (mounted) setState(() {});
  }

  Future<void> _syncConnection() async {
    if (!_eligible || _hiddenRoute) {
      _disconnect();
      return;
    }
    if (_connected || _connecting) return;

    _connecting = true;
    final service = _service ??= SchoolChatService();
    try {
      await service.connect(
        onMessage: (_) => _loadUnread(),
        onThreadUpdated: (_) => _loadUnread(),
        onTyping: (_) {},
        onSeen: (_) => _loadUnread(),
        onPresence: (_) {},
      );
      _connected = true;
    } catch (e) {
      debugPrint('School chat floating socket connect failed: $e');
    } finally {
      _connecting = false;
    }
  }

  void _disconnect() {
    _service?.dispose();
    _service = null;
    _connected = false;
    _connecting = false;
  }

  Future<void> _loadUnread() async {
    if (!_eligible || _hiddenRoute) return;
    final service = _service ??= SchoolChatService();
    try {
      final threads = await service.threads();
      final total = threads.fold<int>(
          0, (sum, row) => sum + ((row['unreadCount'] as num?)?.toInt() ?? 0));
      if (mounted && total != _unread) setState(() => _unread = total);
    } catch (e) {
      debugPrint('School chat floating unread refresh failed: $e');
    }
  }

  void _openChat() {
    widget.navigatorKey.currentState?.pushNamed('/school-chat');
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: widget.currentRoute,
      builder: (context, route, _) {
        final hide = !_eligible ||
            route == '/login' ||
            route == '/choose-role' ||
            route == '/school-chat';
        return Stack(
          children: [
            widget.child,
            if (!hide)
              Positioned(
                right: 18,
                bottom: 82 + MediaQuery.of(context).padding.bottom,
                child: Material(
                  type: MaterialType.transparency,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      InkWell(
                        onTap: _openChat,
                        customBorder: const CircleBorder(),
                        child: Ink(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF2563EB), Color(0xFF4F46E5)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2563EB).withOpacity(.32),
                                blurRadius: 22,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.chat_bubble_rounded,
                              color: Colors.white, size: 27),
                        ),
                      ),
                      if (_unread > 0)
                        Positioned(
                          top: -6,
                          right: -6,
                          child: Container(
                            constraints: const BoxConstraints(
                                minWidth: 24, minHeight: 24),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.red.shade600,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: Text(
                              _unread > 99 ? '99+' : '$_unread',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
