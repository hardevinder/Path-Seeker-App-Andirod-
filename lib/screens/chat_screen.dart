// File: lib/screens/chat_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/constants.dart'; // must define baseUrl

class ChatScreen extends StatefulWidget {
  final String currentUserId;
  /// contactId may be empty when screen opened from floating button — in that case we show contacts list
  final String contactId;
  final String currentUserName;
  final String contactName;

  const ChatScreen({
    super.key,
    required this.currentUserId,
    required this.contactId,
    required this.currentUserName,
    required this.contactName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  // UI controllers
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // internal chat state
  String? threadId;
  List<Map<String, dynamic>> messages = [];
  bool loading = true;
  bool sending = false;
  String? error;

  // contacts fallback (when widget.contactId is empty)
  List<Map<String, dynamic>> contacts = [];
  bool loadingContacts = false;

  // attachments
  File? _attachment;
  String? _attachmentName;
  String? _attachmentMime;
  final ImagePicker _picker = ImagePicker();

  // server config & polling
  late final String _serverPrefix;
  late final String _uploadEndpoint;
  Timer? _pollTimer;
  // longer intervals to avoid aggressive refresh
  final Duration pollIntervalVisible = const Duration(milliseconds: 5000);
  final Duration pollIntervalHidden = const Duration(milliseconds: 15000);
  Duration currentPollInterval = const Duration(seconds: 5);
  bool _isAppVisible = true;

  // audio recorder
  final FlutterSoundRecorder _audioRecorder = FlutterSoundRecorder();
  bool _isRecording = false;
  bool _isStudent = false;

  // chosen contact (when starting from contact list)
  String? _selectedContactId;
  String? _selectedContactName;

  // store the effective contact id used to open this chat (useful as fallback)
  String? _effectiveContactId;

  // keep last fetch snapshot so we can detect new unread messages locally
  Set<String> _seenMessageIds = {};

  // unread counter for current thread (messages from others not seen by user)
  int _unreadCount = 0;

  // global unread from server
  int _globalUnread = 0;

  // internal: lastThreadStats - { count, latestAt(ms), idSet }
  int _lastThreadCount = 0;
  int _lastThreadLatestAt = 0; // epoch ms
  Set<String> _lastThreadIdSet = {};

  // contact refresh tick counter
  int _pollTick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _serverPrefix = baseUrl; // from constants.dart
    _uploadEndpoint = '$_serverPrefix/chat/upload';
    _audioRecorder.openRecorder();

    if ((widget.contactId.trim()).isNotEmpty) {
      _effectiveContactId = widget.contactId.trim();
      _determineThreadAndLoad(effectiveContactId: widget.contactId);
    } else {
      _fetchContacts();
      setState(() => loading = false);
    }

    _fetchUserRole();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _audioRecorder.closeRecorder();
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppVisible = true;
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _isAppVisible = false;
      _stopPolling();
    }
  }

  Future<String?> _getToken() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final keys = [
        'token',
        'jwt',
        'accessToken',
        'authToken',
        'userToken',
        'idToken',
        'firebaseToken',
      ];
      for (final k in keys) {
        final v = sp.getString(k);
        if (v != null && v.trim().isNotEmpty) {
          return v;
        }
      }
      final userJson = sp.getString('user') ?? sp.getString('me') ?? sp.getString('profile');
      if (userJson != null && userJson.isNotEmpty) {
        try {
          final Map<String, dynamic> j = jsonDecode(userJson);
          final candidates = [j['token'], j['jwt'], j['accessToken'], j['idToken']];
          for (final c in candidates) {
            if (c is String && c.trim().isNotEmpty) return c;
          }
        } catch (_) {}
      }
      return null;
    } catch (e) {
      debugPrint('🔴 _getToken() error: $e');
      return null;
    }
  }

  Future<String?> _getCurrentUserIdFromPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final keys = [
        'userId',
        'studentId',
        'teacherId',
        'uid',
        'id',
        'currentUserId',
        'user_id',
        'student_id',
        'teacher_id'
      ];
      for (final k in keys) {
        final v = sp.getString(k);
        if (v != null && v.trim().isNotEmpty) return v;
      }
      final userJson = sp.getString('user') ?? sp.getString('me') ?? sp.getString('profile');
      if (userJson != null && userJson.isNotEmpty) {
        try {
          final Map<String, dynamic> j = jsonDecode(userJson);
          final candidates = [j['id'], j['userId'], j['studentId'], j['teacherId']];
          for (final c in candidates) {
            if (c != null) return c.toString();
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('🔴 _getCurrentUserIdFromPrefs error: $e');
    }
    return null;
  }

  Map<String, String> _authHeaders(String? token) {
    final h = <String, String>{'Accept': 'application/json'};
    if (token != null && token.isNotEmpty) h['Authorization'] = 'Bearer $token';
    return h;
  }

  Future<void> _ensureCanonicalThreadForContact(String contactId) async {
    if (contactId.trim().isEmpty) return;
    try {
      final token = await _getToken();
      final url = Uri.parse('$_serverPrefix/chat/start-direct');
      final res = await http.post(url,
          headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
          body: jsonEncode({'toUserId': contactId}));
      debugPrint('ensureCanonical start-direct status ${res.statusCode} -> ${res.body}');
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body);
        final serverThread = j['id']?.toString() ?? j['threadId']?.toString() ?? j['thread']?['id']?.toString();
        if (serverThread != null && serverThread.isNotEmpty) {
          if (threadId != serverThread) {
            debugPrint('🔁 _ensureCanonicalThreadForContact: switching threadId "$threadId" -> "$serverThread"');
            setState(() {
              threadId = serverThread;
            });
          } else {
            debugPrint('🔁 _ensureCanonicalThreadForContact: already using canonical threadId $threadId');
          }
        } else {
          debugPrint('ensureCanonical start-direct: did not find serverThread in response: $j');
        }
      } else {
        debugPrint('ensureCanonical start-direct non-200: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('ensureCanonical start-direct error: $e');
    }
  }

  Future<void> _determineThreadAndLoad({required String effectiveContactId}) async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final cid = effectiveContactId.trim();
      _effectiveContactId = cid;
      String uid = widget.currentUserId.trim();
      if (uid.isEmpty) {
        final fallback = await _getCurrentUserIdFromPrefs();
        if (fallback != null && fallback.trim().isNotEmpty) uid = fallback.trim();
      }

      debugPrint('🧭 _determineThreadAndLoad: cid="$cid" uid="$uid"');

      if (cid.isEmpty || uid.isEmpty) {
        setState(() {
          error = 'Invalid chat parameters';
          loading = false;
        });
        return;
      }

      if (cid.startsWith('group-')) {
        threadId = cid;
      } else {
        await _ensureCanonicalThreadForContact(cid);

        if (threadId == null) {
          final parts = <String>[uid, cid]..sort();
          threadId = parts.join('-');
          debugPrint('fallback threadId -> $threadId');
        }
      }

      _lastThreadCount = 0;
      _lastThreadLatestAt = 0;
      _lastThreadIdSet = {};

      await _fetchThreadOnce();
      await _markThreadRead();
      setState(() {
        _unreadCount = 0;
      });
      _startPolling();
    } catch (e) {
      debugPrint('determineThread error: $e');
      setState(() {
        error = 'Failed to open chat';
      });
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> _fetchUserRole() async {
    try {
      final token = await _getToken();
      if (token == null) return;
      final url = Uri.parse('$_serverPrefix/users/me');
      final res = await http.get(url, headers: _authHeaders(token));
      debugPrint('users/me -> ${res.statusCode}');
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body);
        final role = (j['role'] ?? j['user']?['role'])?.toString().toLowerCase();
        if (role == 'student') setState(() => _isStudent = true);
      }
    } catch (e) {
      debugPrint('fetchUserRole error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAllContacts({int limit = 5000}) async {
    final token = await _getToken();
    final tried = <String>[
      '$_serverPrefix/chat/contacts?fillUsers=1&limit=$limit',
      '$_serverPrefix/api/chat/contacts?fillUsers=1&limit=$limit',
      '$_serverPrefix/chat/users?limit=$limit',
      '$_serverPrefix/api/chat/users?limit=$limit'
    ];

    for (final u in tried) {
      try {
        final url = Uri.parse(u);
        final res = await http.get(url, headers: _authHeaders(token));
        if (res.statusCode == 200) {
          final j = jsonDecode(res.body);
          final arr = (j is List)
              ? j
              : (j['items'] ?? j['data'] ?? j['results'] ?? j['users'] ?? j['contacts'] ?? []);
          if (arr is List && arr.isNotEmpty) {
            final out = <Map<String, dynamic>>[];
            for (final it in arr) {
              if (it is Map) out.add(Map<String, dynamic>.from(it));
            }
            return out;
          }
        } else {
          debugPrint('contacts endpoint ${url.toString()} returned ${res.statusCode}');
        }
      } catch (e) {
        debugPrint('contacts try error: $e');
      }
    }
    return [];
  }

  Future<void> _fetchContacts() async {
    setState(() {
      loadingContacts = true;
      contacts = [];
    });

    try {
      final found = await _fetchAllContacts();
      if (found.isNotEmpty) {
        final filtered = found.where((c) => !(c.containsKey('student') && c['student'] != null)).toList();
        setState(() => contacts = filtered);
      }
    } catch (e) {
      debugPrint('fetchContacts fatal error: $e');
    } finally {
      setState(() => loadingContacts = false);
    }
  }

  Future<dynamic> _tryGetThreadEndpoint(String urlStr) async {
    try {
      final token = await _getToken();
      final url = Uri.parse(urlStr);
      debugPrint('trying thread endpoint -> $url');
      final res = await http.get(url, headers: _authHeaders(token));
      debugPrint('endpoint $url -> status ${res.statusCode} content-type: ${res.headers['content-type']} headers: ${res.headers}');

      final bodyTrim = res.body.trimLeft();
      if ((res.headers['content-type'] ?? '').toLowerCase().contains('text/html') ||
          bodyTrim.startsWith('<!doctype') ||
          bodyTrim.startsWith('<html')) {
        debugPrint('endpoint $url returned HTML page - skipping.');
        return {'__status': res.statusCode, '__html': true, '__body': res.body};
      }

      if (res.statusCode == 304) {
        return {'__status': 304, 'messages': []};
      }

      if (res.statusCode == 200) {
        try {
          final parsed = jsonDecode(res.body);
          return parsed;
        } catch (e) {
          debugPrint('JSON decode failed for $url: $e');
          return {'__status': 200, '__body': res.body};
        }
      }

      try {
        final err = jsonDecode(res.body);
        return err;
      } catch (_) {
        return {'__status': res.statusCode, '__body': res.body};
      }
    } catch (e) {
      debugPrint('_tryGetThreadEndpoint error for $urlStr : $e');
      return null;
    }
  }

  Future<void> _fetchThreadOnce() async {
    if ((threadId == null || threadId!.isEmpty) && (_effectiveContactId == null || _effectiveContactId!.isEmpty)) return;
    setState(() => loading = true);
    try {
      Future<dynamic> _fetchUsingBestPath(String idToTry) async {
        final tried = await _tryGetThreadEndpoint('$_serverPrefix/chat/threads/${Uri.encodeComponent(idToTry)}');
        if (tried == null) return {'__status': 500, '__body': 'no-response'};
        if (tried is Map && (tried['__html'] == true || (tried['__status'] != null && (tried['__status'] as int) >= 400))) {
          return tried;
        }
        return tried;
      }

      dynamic tried;
      if (threadId != null && threadId!.isNotEmpty) {
        tried = await _fetchUsingBestPath(threadId!);
      }

      if (tried == null || (tried is Map && ((tried['__status'] ?? 0) >= 400 || tried['__html'] == true))) {
        final fallbackId = _effectiveContactId ?? _selectedContactId ?? widget.contactId;
        if (fallbackId != null && fallbackId.isNotEmpty) {
          debugPrint('fetchThreadOnce: falling back to contact-id path for id=$fallbackId');
          final tried2 = await _tryGetThreadEndpoint('$_serverPrefix/chat/threads/${Uri.encodeComponent(fallbackId)}');
          if (tried2 != null) tried = tried2;
        }
      }

      if (tried == null) {
        debugPrint('fetchThreadOnce: all fetch attempts returned null.');
        return;
      }

      debugPrint('fetchThreadOnce: got response (type=${tried.runtimeType})');

      if (tried is Map && tried['__status'] == 304) {
        debugPrint('fetchThreadOnce: 304 no change');
        return;
      }

      dynamic raw;
      if (tried is List) raw = tried;
      else if (tried is Map && (tried.containsKey('messages') || tried.containsKey('data') || tried.containsKey('items'))) {
        raw = tried['messages'] ?? tried['data'] ?? tried['items'];
      } else if (tried is Map && tried['__body'] != null) {
        try {
          final parsed = jsonDecode(tried['__body']);
          raw = parsed is Map && parsed['messages'] != null ? parsed['messages'] : parsed;
        } catch (_) {
          raw = [];
        }
      } else {
        raw = [];
      }

      debugPrint('fetchThreadOnce: raw message array length = ${raw is List ? raw.length : 0}');

      final list = _normalizeMessages(raw);

      // --- NEW: adopt server canonical thread id if present in response or messages ---
      try {
        String? serverThreadFromResponse;
        // 1) if API returned a map containing thread id at top-level
        if (tried is Map) {
          serverThreadFromResponse = (tried['thread_id'] ?? tried['threadId'] ?? tried['thread']?['id'])?.toString();
        }
        // 2) else try messages' thread_id
        if ((serverThreadFromResponse == null || serverThreadFromResponse.isEmpty) && raw is List && raw.isNotEmpty) {
          final firstRaw = raw.first;
          serverThreadFromResponse = (firstRaw['thread_id'] ?? firstRaw['threadId'])?.toString();
        }
        // 3) fallback: normalized message raw
        if ((serverThreadFromResponse == null || serverThreadFromResponse.isEmpty) && list.isNotEmpty) {
          final first = list.first;
          serverThreadFromResponse = (first['raw']?['thread_id'] ?? first['raw']?['threadId'])?.toString();
        }

        if (serverThreadFromResponse != null && serverThreadFromResponse.isNotEmpty) {
          if (threadId == null || threadId!.toString() != serverThreadFromResponse) {
            debugPrint('fetchThreadOnce: adopting server thread id $serverThreadFromResponse (was: $threadId)');
            setState(() {
              threadId = serverThreadFromResponse;
            });
          }
        }
      } catch (e) {
        debugPrint('fetchThreadOnce: error while detecting server thread id: $e');
      }
      // --- end adopt thread id ---

      // dedupe and replace messages list (ensure we don't add duplicates)
      final merged = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final m in [...messages, ...list]) {
        final id = (m['id']?.toString() ?? '');
        if (id.isNotEmpty) {
          if (!seen.contains(id)) {
            merged.add(m);
            seen.add(id);
          }
        } else {
          // include messages without id but unique by createdAt+text
          final key = '${m['createdAt']}_${m['text']}';
          if (!seen.contains(key)) {
            merged.add(m);
            seen.add(key);
          }
        }
      }

      merged.sort((a, b) => DateTime.parse(a['createdAt']).compareTo(DateTime.parse(b['createdAt'])));

      setState(() {
        messages = merged;
        _seenMessageIds = messages.map((m) => m['id']?.toString() ?? '').where((s) => s.isNotEmpty).toSet();
      });

      final latestAt = messages.isNotEmpty ? DateTime.parse(messages.last['createdAt']).toUtc().millisecondsSinceEpoch : _lastThreadLatestAt;
      _lastThreadCount = messages.length;
      _lastThreadLatestAt = latestAt;
      _lastThreadIdSet = messages.map((m) => m['id']?.toString() ?? '').where((s) => s.isNotEmpty).toSet();

      debugPrint('fetchThreadOnce: messages count now ${messages.length}, latestAt=$_lastThreadLatestAt');

      _scrollToBottom(animate: false);
    } catch (e) {
      debugPrint('fetchThreadOnce error: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _pollLoop() async {
    if (threadId == null && (widget.contactId.trim().isEmpty && _selectedContactId == null)) return;
    try {
      final token = await _getToken();

      // 1) unread total
      try {
        final url = Uri.parse('$_serverPrefix/chat/unread-count');
        final res = await http.get(url, headers: _authHeaders(token));
        if (res.statusCode == 200) {
          final payload = jsonDecode(res.body);
          final parsed = _parseUnreadTotal(payload);
          if (parsed != _globalUnread) {
            debugPrint('pollLoop: global unread changed ${_globalUnread} -> $parsed');
            setState(() => _globalUnread = parsed);
          }
        }
      } catch (e) {
        debugPrint('unread-count fetch error: $e');
      }

      // 2) refresh contacts every 3 ticks
      _pollTick++;
      final shouldRefreshContacts = (_pollTick % 3 == 0);
      if (shouldRefreshContacts) {
        try {
          final fetched = await _fetchAllContacts();
          if (fetched.isNotEmpty) {
            final filtered = fetched.where((c) => !(c.containsKey('student') && c['student'] != null)).toList();
            final candidate = _diffContactsForNewUnread(contacts, filtered);
            setState(() {
              contacts = filtered;
            });
            if (candidate != null && candidate.isNotEmpty) {
              final last = _buildLastFromContact(candidate);
              debugPrint('pollLoop: contact refresh found new unread from ${last['fromName']}');

              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${last['fromName']}: ${last['text']}')));

              final openedId = (widget.contactId.trim()).isNotEmpty ? widget.contactId : _selectedContactId;
              final candidateId = candidate['id']?.toString() ?? candidate['userId']?.toString() ?? '';
              
              debugPrint('pollLoop: candidate raw keys: ${candidate.keys.toList()}');
              debugPrint('pollLoop: candidate id set: ${{
                'id': candidate['id']?.toString(),
                'userId': candidate['userId']?.toString(),
                'threadId': candidate['threadId']?.toString(),
                'lastMessage.from': candidate['lastMessage']?['from']?.toString()
              }}');
              debugPrint('pollLoop: openedId = ${ (widget.contactId.trim()).isNotEmpty ? widget.contactId : _selectedContactId }, effectiveContactId=$_effectiveContactId, threadId=$threadId');

             if (candidateId.isNotEmpty && _contactMatchesOpened(candidate, openedId: openedId)) {
                debugPrint('pollLoop: candidate is currently opened; forcing canonical + full fetch (safe sync).');
                try {
                  // ensure server canonical thread is set
                  await _ensureCanonicalThreadForContact(candidateId);
                } catch (e) {
                  debugPrint('ensureCanonical in contacts-refresh failed: $e');
                }

                // Force a full fetch of the thread (no since param) via fetchThreadOnce()
                // This is reliable — it will pick up messages even if delta or 304 logic misses them.
                try {
                  await _fetchThreadOnce();
                } catch (e) {
                  debugPrint('pollLoop: forced full fetch failed: $e');
                }
              }

            }
          }
        } catch (e) {
          debugPrint('contacts refresh error: $e');
        }
      }

      // 3) poll active thread
      final activeThreadId = threadId;
      if (activeThreadId != null && activeThreadId.isNotEmpty) {
        try {
          String sinceParam = '';
          if (_lastThreadLatestAt > 0) {
            final iso = DateTime.fromMillisecondsSinceEpoch(_lastThreadLatestAt, isUtc: true).toUtc().toIso8601String();
            sinceParam = '?since=${Uri.encodeComponent(iso)}';
          }

          final urlCandidate = '$_serverPrefix/chat/threads/${Uri.encodeComponent(activeThreadId)}$sinceParam';
          debugPrint('pollLoop: polling delta -> $urlCandidate');
          dynamic tried = await _tryGetThreadEndpoint(urlCandidate);

          // If server returned 304 for the delta, force a fresh fetch (no since param + cache-buster)
          if (tried is Map && tried['__status'] == 304) {
            debugPrint('pollLoop: got 304 for delta; forcing full fetch without since param (cache-buster).');
            final freshUrl = '$_serverPrefix/chat/threads/${Uri.encodeComponent(activeThreadId)}?cb=${DateTime.now().millisecondsSinceEpoch}';
            final triedFresh = await _tryGetThreadEndpoint(freshUrl);
            if (triedFresh != null) {
              debugPrint('pollLoop: forced fresh fetch returned type=${triedFresh.runtimeType}');
              tried = triedFresh;
            } else {
              debugPrint('pollLoop: forced fresh fetch returned null, falling back to original 304 result');
            }
          }

          if (tried == null || (tried is Map && ((tried['__status'] ?? 0) >= 400 || tried['__html'] == true))) {
            final fallbackId = _effectiveContactId ?? _selectedContactId ?? widget.contactId;
            if (fallbackId != null && fallbackId.isNotEmpty) {
              final urlFallback = '$_serverPrefix/chat/threads/${Uri.encodeComponent(fallbackId)}$sinceParam';
              debugPrint('pollLoop: falling back to contact-id fetch -> $urlFallback');
              final tried2 = await _tryGetThreadEndpoint(urlFallback);

              // If fallback returned 304, try forcing full fallback fetch too
              if (tried2 is Map && tried2['__status'] == 304) {
                debugPrint('pollLoop: fallback 304; forcing fallback full fetch without since param (cache-buster).');
                final freshFallback = '$_serverPrefix/chat/threads/${Uri.encodeComponent(fallbackId)}?cb=${DateTime.now().millisecondsSinceEpoch}';
                final tried2Fresh = await _tryGetThreadEndpoint(freshFallback);
                if (tried2Fresh != null) {
                  debugPrint('pollLoop: forced fallback fresh fetch returned type=${tried2Fresh.runtimeType}');
                  tried = tried2Fresh;
                } else {
                  debugPrint('pollLoop: forced fallback fresh fetch returned null, keeping tried2');
                  tried = tried2;
                }
              } else {
                if (tried2 != null) tried = tried2;
              }
            }
          }

          if (tried == null) {
            debugPrint('poll thread: no response for $activeThreadId (and fallback)');
            return;
          }

          debugPrint('pollLoop: delta response type ${tried.runtimeType}');

          if (tried is Map && tried['__status'] == 304) {
            debugPrint('poll thread: 304 not modified for $activeThreadId');
            return;
          }

          dynamic raw;
          if (tried is List) raw = tried;
          else if (tried is Map && (tried.containsKey('messages') || tried.containsKey('data') || tried.containsKey('items'))) {
            raw = tried['messages'] ?? tried['data'] ?? tried['items'];
          } else if (tried is Map && tried['__body'] != null) {
            try {
              final parsed = jsonDecode(tried['__body']);
              raw = parsed is Map && parsed['messages'] != null ? parsed['messages'] : parsed;
            } catch (_) {
              raw = [];
            }
          } else {
            raw = [];
          }

          debugPrint('pollLoop: delta raw length = ${raw is List ? raw.length : 0}');

          final list = _normalizeMessages(raw);
          debugPrint('pollLoop: normalized delta length = ${list.length}');

          final newOnes = <Map<String, dynamic>>[];
          final existingIds = _lastThreadIdSet;

          for (final m in list) {
            final mid = m['id']?.toString() ?? '';
            if (mid.isNotEmpty) {
              if (!existingIds.contains(mid)) newOnes.add(m);
            } else {
              final createdAtMs = DateTime.tryParse(m['createdAt'] ?? '')?.toUtc().millisecondsSinceEpoch ?? 0;
              if (createdAtMs > _lastThreadLatestAt) newOnes.add(m);
            }
          }

          debugPrint('pollLoop: identified newOnes length = ${newOnes.length}');
          if (newOnes.isNotEmpty) {
            newOnes.sort((a, b) => DateTime.parse(a['createdAt']).compareTo(DateTime.parse(b['createdAt'])));

            // avoid duplicates: only append IDs we don't have
            final filteredAppend = <Map<String, dynamic>>[];
            for (final m in newOnes) {
              final mid = m['id']?.toString() ?? '';
              if (mid.isNotEmpty) {
                if (!_lastThreadIdSet.contains(mid)) filteredAppend.add(m);
              } else {
                filteredAppend.add(m);
              }
            }

            debugPrint('pollLoop: filteredAppend length = ${filteredAppend.length}');
            debugPrint('pollLoop: filteredAppend preview: ${jsonEncode(filteredAppend.length <= 5 ? filteredAppend : filteredAppend.sublist(0, 5))}');

            if (filteredAppend.isNotEmpty) {
              setState(() {
                messages = [...messages, ...filteredAppend];
                _lastThreadIdSet = messages.map((m) => m['id']?.toString() ?? '').where((s) => s.isNotEmpty).toSet();
                _lastThreadCount = messages.length;
                _lastThreadLatestAt = messages.isNotEmpty ? DateTime.parse(messages.last['createdAt']).toUtc().millisecondsSinceEpoch : _lastThreadLatestAt;
              });

              final incomingFromOthers = filteredAppend.where((m) => m['from']?.toString() != widget.currentUserId).length;
              if (incomingFromOthers > 0) {
                setState(() {
                  _unreadCount += incomingFromOthers;
                });
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$_unreadCount unread message${_unreadCount > 1 ? 's' : ''}')));
              }

              _scrollToBottom();
            } else {
              debugPrint('pollLoop: filteredAppend empty after dedupe');
              await _fetchThreadOnce();
            }
          } else {
            debugPrint('pollLoop: no new messages in delta; if server returned items perform full sync once');
            if (list.isNotEmpty) {
              await _fetchThreadOnce();
            }
          }
        } catch (e) {
          debugPrint('active thread poll error: $e');
          try {
            debugPrint('pollLoop: attempting full fetchThreadOnce() due to poll error');
            await _fetchThreadOnce();
          } catch (e2) {
            debugPrint('pollLoop: full fetch attempt failed: $e2');
          }
        }
      }
    } catch (e) {
      debugPrint('pollLoop error: $e');
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTick = 0;
    currentPollInterval = _isAppVisible ? pollIntervalVisible : pollIntervalHidden;
    _pollTimer = Timer.periodic(currentPollInterval, (_) => _pollLoop());
    debugPrint('polling started, interval: ${currentPollInterval.inMilliseconds}ms');
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    debugPrint('polling stopped');
  }

  List<Map<String, dynamic>> _normalizeMessages(dynamic raw) {
    final arr = (raw is List)
        ? raw
        : (raw is Map && raw['data'] is List)
            ? raw['data']
            : <dynamic>[];
    final out = <Map<String, dynamic>>[];
    for (final item in arr) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final id = m['id']?.toString() ?? (m['tempId']?.toString() ?? '');
      // Try many possible created fields:
      dynamic createdRaw = m['createdAt'] ?? m['created_at'] ?? m['time'] ?? m['timestamp'] ?? m['sentAt'] ?? m['sent_at'];
      String created;
      try {
        if (createdRaw == null) {
          created = DateTime.now().toUtc().toIso8601String();
        } else if (createdRaw is int) {
          final n = createdRaw;
          created = (n > 1000000000000) ? DateTime.fromMillisecondsSinceEpoch(n).toUtc().toIso8601String() : DateTime.fromMillisecondsSinceEpoch(n * 1000).toUtc().toIso8601String();
        } else {
          final s = createdRaw.toString();
          if (RegExp(r'^\d+$').hasMatch(s)) {
            final n = int.parse(s);
            created = (n > 1000000000000) ? DateTime.fromMillisecondsSinceEpoch(n).toUtc().toIso8601String() : DateTime.fromMillisecondsSinceEpoch(n * 1000).toUtc().toIso8601String();
          } else {
            created = DateTime.parse(s).toUtc().toIso8601String();
          }
        }
      } catch (_) {
        created = DateTime.now().toUtc().toIso8601String();
      }

      out.add({
        'id': id.isNotEmpty ? id : UniqueKey().toString(),
        'tempId': m['tempId'],
        'from': m['from'] ?? m['sender_id'] ?? m['sender'] ?? m['userId'] ?? m['user_id'],
        'to': m['to'] ?? m['receiver_id'] ?? m['receiver'],
        'text': m['text'] ?? m['content'] ?? m['message'] ?? '',
        'content': m['content'] ?? m['fileUrl'] ?? m['url'],
        'createdAt': created,
        'message_type': m['message_type'] ?? m['fileType'] ?? m['attachmentType'],
        'meta': m['meta'] ?? {},
        'raw': m,
      });
    }
    out.sort((a, b) => DateTime.parse(a['createdAt']).compareTo(DateTime.parse(b['createdAt'])));
    return out;
  }

  String _normalizeCreated(dynamic raw) {
    try {
      if (raw is int) {
        final n = raw;
        return (n > 1000000000000)
            ? DateTime.fromMillisecondsSinceEpoch(n).toUtc().toIso8601String()
            : DateTime.fromMillisecondsSinceEpoch(n * 1000).toUtc().toIso8601String();
      }
      final s = raw.toString();
      if (RegExp(r'^\d+$').hasMatch(s)) {
        final n = int.parse(s);
        return (n > 1000000000000)
            ? DateTime.fromMillisecondsSinceEpoch(n).toUtc().toIso8601String()
            : DateTime.fromMillisecondsSinceEpoch(n * 1000).toUtc().toIso8601String();
      }
      return DateTime.parse(s).toUtc().toIso8601String();
    } catch (_) {
      return DateTime.now().toUtc().toIso8601String();
    }
  }

  Future<String?> _uploadAttachment(File file) async {
    try {
      final token = await _getToken();
      final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
      final parts = mimeType.split('/');
      final contentType = (parts.length == 2) ? MediaType(parts[0], parts[1]) : MediaType('application', 'octet-stream');

      final uri = Uri.parse(_uploadEndpoint);
      final req = http.MultipartRequest('POST', uri);
      req.headers.addAll(_authHeaders(token));
      req.files.add(await http.MultipartFile.fromPath('file', file.path, contentType: contentType));
      debugPrint('Uploading file to $uri (mime=$mimeType)');
      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      debugPrint('uploadAttachment -> ${res.statusCode}');
      if (res.statusCode == 200 || res.statusCode == 201) {
        final j = jsonDecode(res.body);
        final url = j['url'] ?? j['fileUrl'] ?? j['data']?['url'] ?? j['data']?['fileUrl'];
        if (url != null && url is String) {
          if (!url.startsWith('http')) return '$_serverPrefix${url.startsWith('/') ? '' : '/'}$url';
          return url;
        }
      } else {
        debugPrint('uploadAttachment error status ${res.statusCode}: ${res.body}');
      }
      return null;
    } catch (e) {
      debugPrint('uploadAttachment error: $e');
      return null;
    }
  }

  Future<void> _markThreadRead() async {
    if (threadId == null) return;
    try {
      final token = await _getToken();
      final url = Uri.parse('$_serverPrefix/chat/threads/${Uri.encodeComponent(threadId!)}/read');
      final res = await http.post(url, headers: _authHeaders(token));
      debugPrint('markThreadRead status ${res.statusCode}');
      if (res.statusCode == 200) {
        setState(() {
          _unreadCount = 0;
        });
        setState(() {
          contacts = contacts.map((c) {
            final id = c['id']?.toString() ?? c['userId']?.toString() ?? '';
            if (id.isNotEmpty && (threadId == id || threadId == c['threadId']?.toString())) {
              final copy = Map<String, dynamic>.from(c);
              copy['unreadCount'] = 0;
              return copy;
            }
            return c;
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('markThreadRead error: $e');
    }
  }

  Future<void> _sendTextOrAttachment({String? text}) async {
    if (threadId == null || threadId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No thread selected')));
      return;
    }
    if ((_attachment == null) && (text == null || text.trim().isEmpty)) return;
    if (_isStudent && threadId!.startsWith('group-')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Broadcasts are read-only for students')));
      return;
    }

    setState(() => sending = true);
    try {
      String? contentUrl;
      String? mtype;
      if (_attachment != null) {
        final url = await _uploadAttachment(_attachment!);
        if (url == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attachment upload failed')));
          setState(() => sending = false);
          return;
        } else {
          contentUrl = url;
          final guessed = (_attachmentMime ?? lookupMimeType(_attachment!.path) ?? '');
          mtype = guessed.startsWith('image/') ? 'image' : 'file';
        }
      }

      final token = await _getToken();
      final payload = <String, dynamic>{
        'threadId': threadId,
        'content': contentUrl ?? (text ?? '').trim(),
        'message_type': contentUrl != null ? mtype : 'text',
      };
      if (contentUrl != null) {
        payload['meta'] = {
          'original': _attachmentName ?? _attachment?.path.split('/').last,
          'mime': _attachmentMime ?? lookupMimeType(_attachment?.path ?? '') ?? '',
          'size': _attachment?.lengthSync() ?? 0
        };
      }

      final sendUrl = Uri.parse('$_serverPrefix/chat/send');
      debugPrint('send payload -> $payload');
      final res = await http.post(sendUrl, headers: {..._authHeaders(token), 'Content-Type': 'application/json'}, body: jsonEncode(payload));
      debugPrint('send status ${res.statusCode} -> ${res.body}');
      if (res.statusCode == 200 || res.statusCode == 201) {
        final j = jsonDecode(res.body);
        final newMsgRaw = j is Map && (j['id'] != null || j['message'] != null) ? (j['message'] ?? j) : j;
        final normalized = _normalizeMessages([newMsgRaw]).first;
        setState(() {
          messages = [...messages, normalized];
          _messageController.clear();
          _attachment = null;
          _attachmentMime = null;
          _attachmentName = null;
          _seenMessageIds.add(normalized['id']?.toString() ?? '');
          _lastThreadIdSet = messages.map((m) => m['id']?.toString() ?? '').where((s) => s.isNotEmpty).toSet();
          _lastThreadLatestAt = DateTime.parse(messages.last['createdAt']).toUtc().millisecondsSinceEpoch;
        });
        _scrollToBottom();

        await _ensureCanonicalThreadForContact(_effectiveContactId ?? widget.contactId);
        await _fetchThreadOnce();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Send failed')));
      }

      await _markThreadRead();
    } catch (e) {
      debugPrint('send error: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error sending message')));
    } finally {
      setState(() => sending = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        _attachment = File(picked.path);
        _attachmentMime = lookupMimeType(picked.path);
        _attachmentName = picked.path.split('/').last;
        setState(() {});
      }
    } catch (e) {
      debugPrint('pickImage error: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image pick failed')));
    }
  }

  Future<void> _pickDocument() async {
    try {
      final params = OpenFileDialogParams(dialogType: OpenFileDialogType.document);
      final path = await FlutterFileDialog.pickFile(params: params);
      if (path != null) {
        _attachment = File(path);
        _attachmentMime = lookupMimeType(path);
        _attachmentName = path.split('/').last;
        setState(() {});
      }
    } catch (e) {
      debugPrint('pickDocument error: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document pick failed')));
    }
  }

  Future<void> startRecording() async {
    var status = await Permission.microphone.request();
    if (!status.isGranted) return;
    final path = '${Directory.systemTemp.path}/recording_${DateTime.now().millisecondsSinceEpoch}.aac';
    try {
      await _audioRecorder.startRecorder(toFile: path);
      setState(() => _isRecording = true);
    } catch (e) {
      debugPrint('startRecording error: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recorder error')));
    }
  }

  Future<void> stopRecording() async {
    try {
      final path = await _audioRecorder.stopRecorder();
      setState(() => _isRecording = false);
      if (path != null) {
        _attachment = File(path);
        _attachmentName = path.split('/').last;
        _attachmentMime = lookupMimeType(path);
        setState(() {});
      }
    } catch (e) {
      debugPrint('stopRecording error: $e');
    }
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) {
        Future.delayed(const Duration(milliseconds: 80), () {
          if (!mounted) return;
          if (_scrollController.hasClients) {
            try {
              _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
            } catch (_) {}
          }
        });
        return;
      }
      try {
        final pos = _scrollController.position.maxScrollExtent;
        if (animate) {
          _scrollController.animateTo(pos, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        } else {
          _scrollController.jumpTo(pos);
        }
      } catch (_) {}
    });
  }

  Widget _buildMessageItem(Map<String, dynamic> m) {
    final mine = m['from']?.toString() == widget.currentUserId;
    final url = (m['content'] ?? m['text'])?.toString() ?? '';
    final isImage = (m['message_type'] == 'image') || (url.isNotEmpty && RegExp(r'\.(jpg|jpeg|png|gif|webp)$', caseSensitive: false).hasMatch(url));
    final isFile = (m['message_type'] == 'file') || (url.isNotEmpty && RegExp(r'\.(pdf|docx?|xlsx?|zip|aac|m4a|mp3)$', caseSensitive: false).hasMatch(url));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (m['raw']?['replyToText'] != null)
            Text('↪ ${m['raw']?['replyToSender'] ?? ''}: ${m['raw']?['replyToText'] ?? ''}', style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
          if (isImage)
            Container(constraints: BoxConstraints(maxHeight: 220, maxWidth: 260), child: Image.network(url, fit: BoxFit.cover))
          else if (isFile)
            ElevatedButton.icon(
              onPressed: () async {
                try {
                  final response = await http.get(Uri.parse(url));
                  if (response.statusCode == 200) {
                    final filePath = '${Directory.systemTemp.path}/${m['raw']?['fileName'] ?? Uri.parse(url).pathSegments.last}';
                    final file = File(filePath);
                    await file.writeAsBytes(response.bodyBytes);
                    await OpenFilex.open(file.path);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download failed')));
                  }
                } catch (e) {
                  debugPrint('open file error: $e');
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to open file')));
                }
              },
              icon: const Icon(Icons.download),
              label: Text(m['raw']?['fileName'] ?? url.split('/').last),
            )
          else
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: mine ? Colors.blue[100] : Colors.grey[200], borderRadius: BorderRadius.circular(10)), child: Text(m['text'] ?? '')),
          const SizedBox(height: 4),
          Text((m['raw']?['senderName'] ?? (m['from']?.toString() == widget.currentUserId ? widget.currentUserName : widget.contactName)) ?? '', style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text(DateTime.tryParse(m['createdAt'] ?? '') != null ? _formatTime(m['createdAt']) : '', style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  String _formatTime(String? iso) {
    try {
      final d = DateTime.parse(iso ?? DateTime.now().toIso8601String()).toLocal();
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    } catch (_) {
      return '';
    }
  }

  Widget _contactsListView() {
    if (loadingContacts) return const Center(child: CircularProgressIndicator());
    if (contacts.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('No contacts found'), const SizedBox(height: 8), ElevatedButton(onPressed: _fetchContacts, child: const Text('Retry'))]));
    return ListView.separated(
      itemCount: contacts.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, idx) {
        final c = contacts[idx];
        final name = c['name'] ?? c['title'] ?? 'User ${c['id']}';
        final id = c['id']?.toString() ?? c['userId']?.toString() ?? c['uid']?.toString() ?? '';
        final subtitle = c['subtitle'] ?? c['student']?['class_name'] ?? c['student']?['class'] ?? '';
        final unread = _getUnreadFromContact(c);
        final lastMsg = c['lastMessage'] ?? c['last_message'] ?? {};
        return ListTile(
          title: Text(name),
          subtitle: subtitle != null && subtitle.toString().isNotEmpty ? Text(subtitle.toString()) : (lastMsg != null && lastMsg['text'] != null ? Text(lastMsg['text']) : null),
          trailing: unread > 0 ? Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)), child: Text(unread > 99 ? '99+' : '$unread', style: const TextStyle(color: Colors.white))) : null,
          onTap: () async {
            if (id.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid contact id')));
              return;
            }
            setState(() {
              _selectedContactId = id;
              _selectedContactName = name;
              _lastThreadCount = 0;
              _lastThreadLatestAt = 0;
              _lastThreadIdSet = {};
              _unreadCount = 0;
              messages = [];
              threadId = null;
              _effectiveContactId = id;
            });

            if (widget.currentUserId.trim().isEmpty) {
              final fallbackUid = await _getCurrentUserIdFromPrefs();
              if (fallbackUid == null || fallbackUid.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot open chat: missing current user id')));
                return;
              }
            }

            _determineThreadAndLoad(effectiveContactId: id);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveContactId = (widget.contactId.trim()).isNotEmpty ? widget.contactId : _selectedContactId;
    final effectiveContactName = (widget.contactId.trim()).isNotEmpty ? widget.contactName : (_selectedContactName ?? 'Contact');

    return WillPopScope(
      onWillPop: () async {
        _stopPolling();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Expanded(child: Text(effectiveContactName)),
              if (_unreadCount > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      '$_unreadCount',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              if (_globalUnread > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.deepPurple, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      'All: $_globalUnread',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if ((widget.contactId.trim()).isEmpty && effectiveContactId == null)
                Expanded(child: _contactsListView())
              else if (loading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (threadId == null)
                Expanded(child: Center(child: Text(error ?? 'Unable to open chat')))
              else
                Expanded(
                  // give the list a changing key so Flutter rebuilds when messages/lastThreadLatestAt changes
                  child: ListView.builder(
                    key: Key('messages_${messages.length}_${_lastThreadLatestAt}'),
                    controller: _scrollController,
                    itemCount: messages.length,
                    itemBuilder: (context, idx) => _buildMessageItem(messages[idx]),
                  ),
                ),

              if (_attachment != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(child: Text('Attachment: ${_attachmentName ?? _attachment!.path.split('/').last}')),
                      IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        onPressed: () {
                          setState(() {
                            _attachment = null;
                            _attachmentMime = null;
                            _attachmentName = null;
                          });
                        },
                      )
                    ],
                  ),
                ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.photo), onPressed: _pickImage),
                    IconButton(icon: const Icon(Icons.insert_drive_file), onPressed: _pickDocument),
                    IconButton(
                      icon: Icon(_isRecording ? Icons.stop : Icons.mic, color: _isRecording ? Colors.red : Colors.black54),
                      onPressed: _isRecording ? stopRecording : startRecording,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        minLines: 1,
                        maxLines: 6,
                        decoration: InputDecoration(hintText: 'Type a message', border: OutlineInputBorder(borderRadius: BorderRadius.circular(20))),
                        onSubmitted: (_) => _sendTextOrAttachment(text: _messageController.text),
                      ),
                    ),
                    IconButton(
                      icon: sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
                      onPressed: sending ? null : () => _sendTextOrAttachment(text: _messageController.text),
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- helpers ----------
  int _getUnreadFromContact(Map<String, dynamic> c) {
    final candidates = [c['unreadCount'], c['unread'], c['unread_count'], c['unread_messages'], c['unreadMessages']];
    for (final v in candidates) {
      if (v != null) {
        final n = int.tryParse(v.toString());
        if (n != null) return n;
      }
    }
    return 0;
  }

  int _parseUnreadTotal(dynamic payload) {
    if (payload == null) return 0;
    if (payload is int) return payload;
    if (payload is String) return int.tryParse(payload) ?? 0;
    final candidates = [payload['total'], payload['count'], payload['unread'], payload['unreadCount']];
    for (final c in candidates) {
      if (c != null) {
        final n = int.tryParse(c.toString());
        if (n != null) return n;
      }
    }
    return 0;
  }

  Map<String, dynamic>? _diffContactsForNewUnread(List<Map<String, dynamic>> prev, List<Map<String, dynamic>> next) {
    final prevMap = <String, int>{};
    for (final c in prev) {
      final id = c['id']?.toString() ?? '';
      prevMap[id] = _getUnreadFromContact(c);
    }
    Map<String, dynamic>? candidate;
    for (final c in next) {
      final id = c['id']?.toString() ?? '';
      final before = prevMap[id] ?? 0;
      final after = _getUnreadFromContact(c);
      if (after > before) {
        if (candidate == null) {
          candidate = c;
        } else {
          final candTs = candidate['lastMessage']?['createdAt'] ?? candidate['last_message']?['createdAt'] ?? '';
          final newTs = c['lastMessage']?['createdAt'] ?? c['last_message']?['createdAt'] ?? '';
          final candTime = candTs.isNotEmpty ? DateTime.tryParse(candTs)?.millisecondsSinceEpoch ?? 0 : 0;
          final newTime = newTs.isNotEmpty ? DateTime.tryParse(newTs)?.millisecondsSinceEpoch ?? 0 : 0;
          if (newTime > candTime) candidate = c;
        }
      }
    }
    return candidate;
  }

  Map<String, dynamic> _buildLastFromContact(Map<String, dynamic> contact) {
    final last = contact['lastMessage'] ?? contact['last_message'] ?? {};
    return {
      'fromName': contact['name'] ?? contact['title'] ?? 'User ${contact['id']}',
      'from': contact['id'],
      'text': last['text'] ?? '',
      'createdAt': last['createdAt'] ?? last['created_at'] ?? DateTime.now().toIso8601String()
    };
  }

  /// Robust match helper to identify whether the provided contact (from contacts list)
  /// corresponds to the currently opened chat. Compares multiple fields and trims values.
  bool _contactMatchesOpened(Map<String, dynamic> contact, {String? openedId}) {
    final open = (openedId ?? _effectiveContactId ?? widget.contactId).toString().trim();
    if (open.isEmpty) return false;

    final candIds = <String>{
      contact['id']?.toString() ?? '',
      contact['userId']?.toString() ?? '',
      contact['uid']?.toString() ?? '',
      contact['threadId']?.toString() ?? '',
      contact['contactId']?.toString() ?? '',
      contact['lastMessage']?['from']?.toString() ?? '',
      contact['last_message']?['from']?.toString() ?? ''
    }.where((s) => s.isNotEmpty).map((s) => s.trim()).toSet();

    // direct threadId match
    if (threadId != null && threadId!.trim().isNotEmpty && threadId!.trim() == open) return true;

    if (candIds.contains(open)) return true;

    // maybe threadId contains both user ids like "123-456"
    if (contact['threadId'] != null) {
      final t = contact['threadId'].toString();
      if (t.contains(open)) return true;
    }

    // fallback: maybe opened id is thread and candidate has user ids inside name fields
    final candidateComposite = '${contact['id'] ?? ''}:${contact['userId'] ?? ''}:${contact['threadId'] ?? ''}';
    if (candidateComposite.contains(open)) return true;

    return false;
  }
}
