import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/school_chat_service.dart';

class SchoolChatScreen extends StatefulWidget {
  final int? openThreadId;
  const SchoolChatScreen({super.key, this.openThreadId});

  @override
  State<SchoolChatScreen> createState() => _SchoolChatScreenState();
}

class _SchoolChatScreenState extends State<SchoolChatScreen> {
  final SchoolChatService service = SchoolChatService();
  List<Map<String, dynamic>> threads = [];
  bool loading = true;
  bool _deepLinkOpened = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    service.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    await service.connect(
      onMessage: (_) => _load(),
      onThreadUpdated: (_) => _load(),
      onTyping: (_) {},
      onSeen: (_) => _load(),
      onPresence: (p) {
        if (!mounted) return;
        final identity = Map<String, dynamic>.from(p['identity'] ?? {});
        setState(() {
          threads = threads.map((t) {
            final o = Map<String, dynamic>.from(t['otherParticipant'] ?? {});
            final same = o['kind'] == 'student'
                ? '${identity['studentId']}' == '${o['id']}'
                : '${identity['userId']}' == '${o['id']}';
            return same ? <String, dynamic>{...t, 'online': p['online'] == true} : t;
          }).toList();
        });
      },
    );
    await _load();
    if (!_deepLinkOpened && widget.openThreadId != null && mounted) {
      final matches = threads.where((t) => '${t['id']}' == '${widget.openThreadId}').toList();
      if (matches.isNotEmpty) {
        _deepLinkOpened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _open(matches.first); });
      }
    }
  }

  Future<void> _load() async {
    try {
      final r = await service.threads();
      if (mounted) setState(() { threads = r; loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _newChat() async {
    try {
      final recipients = await service.recipients();
      if (!mounted) return;
      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: .75,
            minChildSize: .45,
            maxChildSize: .92,
            builder: (_, c) => Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Start Secure Chat', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: c,
                    itemCount: recipients.length,
                    itemBuilder: (_, i) {
                      final r = recipients[i];
                      final name = '${r['name'] ?? 'User'}';
                      final username = '${r['username'] ?? ''}';
                      return ListTile(
                        leading: CircleAvatar(child: Text(name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?')),
                        title: Text(name),
                        subtitle: Text('${r['group'] ?? ''}${username.isNotEmpty ? ' • $username' : ''}'),
                        onTap: () => Navigator.pop(ctx, r),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (selected == null) return;
      final thread = await service.start(selected);
      await _load();
      if (mounted) _open(thread);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _open(Map<String, dynamic> thread) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SchoolChatThreadScreen(service: service, thread: thread)),
    ).then((_) => _load());
  }

  String _time(dynamic v) {
    if (v == null) return '';
    try { return DateFormat('dd MMM, hh:mm a').format(DateTime.parse('$v').toLocal()); } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure School Chat'),
        actions: [
          IconButton(onPressed: _newChat, icon: const Icon(Icons.add_comment_rounded)),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : threads.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.forum_rounded, size: 64, color: Colors.indigo),
                      const SizedBox(height: 12),
                      const Text('No chats yet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      const SizedBox(height: 8),
                      FilledButton.icon(onPressed: _newChat, icon: const Icon(Icons.add), label: const Text('Start Chat')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: threads.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final t = threads[i];
                      final other = Map<String, dynamic>.from(t['otherParticipant'] ?? {});
                      final unread = (t['unreadCount'] ?? 0) as num;
                      final name = '${other['name'] ?? 'Chat'}';
                      return Card(
                        child: ListTile(
                          onTap: () => _open(t),
                          leading: Stack(
                            children: [
                              CircleAvatar(backgroundColor: Colors.indigo.shade100, child: Text(name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?')),
                              if (t['online'] == true)
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 11,
                                    height: 11,
                                    decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                                  ),
                                ),
                            ],
                          ),
                          title: Text(name, style: TextStyle(fontWeight: unread > 0 ? FontWeight.w900 : FontWeight.w700)),
                          subtitle: Text('${t['lastMessage']?['body'] ?? 'Start conversation'}', maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(_time(t['lastMessageAt']), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                              if (unread > 0)
                                Container(
                                  margin: const EdgeInsets.only(top: 5),
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                                  child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class SchoolChatThreadScreen extends StatefulWidget {
  final SchoolChatService service;
  final Map<String, dynamic> thread;

  const SchoolChatThreadScreen({super.key, required this.service, required this.thread});

  @override
  State<SchoolChatThreadScreen> createState() => _SchoolChatThreadScreenState();
}

class _SchoolChatThreadScreenState extends State<SchoolChatThreadScreen> {
  List<Map<String, dynamic>> messages = [];
  bool loading = true;
  bool sending = false;
  String typingText = '';
  final controller = TextEditingController();
  final scroll = ScrollController();
  Timer? typingTimer;
  late final int threadId;

  @override
  void initState() {
    super.initState();
    threadId = (widget.thread['id'] as num).toInt();
    _load();
    widget.service.socket?.on('schoolchat:message', _onMessage);
    widget.service.socket?.on('schoolchat:typing', _onTyping);
    widget.service.socket?.on('schoolchat:seen', _onReceiptChanged);
    widget.service.socket?.on('schoolchat:delivered', _onReceiptChanged);
  }

  @override
  void dispose() {
    widget.service.leave(threadId);
    widget.service.socket?.off('schoolchat:message', _onMessage);
    widget.service.socket?.off('schoolchat:typing', _onTyping);
    widget.service.socket?.off('schoolchat:seen', _onReceiptChanged);
    widget.service.socket?.off('schoolchat:delivered', _onReceiptChanged);
    typingTimer?.cancel();
    controller.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await widget.service.messages(threadId);
      if (!mounted) return;
      setState(() { messages = r; loading = false; });
      final last = r.isNotEmpty ? (r.last['id'] as num?)?.toInt() : null;
      widget.service.join(threadId, uptoMessageId: last);
      if (r.isNotEmpty && r.last['own'] != true && last != null) widget.service.seen(threadId, last);
      _bottom();
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  void _onMessage(dynamic d) {
    if (d is! Map || '${d['threadId']}' != '$threadId') return;
    final m = Map<String, dynamic>.from(d['message'] ?? {});
    if (m.isEmpty) return;
    if (mounted) {
      setState(() {
        if (!messages.any((x) => '${x['id']}' == '${m['id']}')) messages.add(m);
      });
    }
    if (m['own'] != true && m['id'] != null) widget.service.seen(threadId, (m['id'] as num).toInt());
    _bottom();
  }

  void _onTyping(dynamic d) {
    if (d is! Map || '${d['threadId']}' != '$threadId') return;
    if (mounted) setState(() => typingText = d['isTyping'] == true ? '${d['name'] ?? 'Someone'} is typing…' : '');
  }

  void _onReceiptChanged(dynamic d) {
    if (d is Map && '${d['threadId']}' == '$threadId') _load();
  }

  void _bottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    });
  }

  void _typing(String value) {
    widget.service.typing(threadId, true);
    typingTimer?.cancel();
    typingTimer = Timer(const Duration(milliseconds: 900), () => widget.service.typing(threadId, false));
  }

  Future<void> _send() async {
    final body = controller.text.trim();
    if (body.isEmpty) return;
    setState(() => sending = true);
    try {
      controller.clear();
      final m = await widget.service.send(threadId, body);
      if (mounted && !messages.any((x) => '${x['id']}' == '${m['id']}')) setState(() => messages.add(m));
      widget.service.typing(threadId, false);
      _bottom();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _attach() async {
    final files = await openFiles(acceptedTypeGroups: [
      const XTypeGroup(label: 'School chat files', extensions: ['jpg','jpeg','png','webp','pdf','doc','docx','xls','xlsx','txt']),
    ]);
    if (files.isEmpty) return;
    setState(() => sending = true);
    try {
      await widget.service.sendFiles(threadId, files, body: controller.text.trim());
      controller.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  String _time(dynamic v) {
    if (v == null) return '';
    try { return DateFormat('hh:mm a').format(DateTime.parse('$v').toLocal()); } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    final other = Map<String, dynamic>.from(widget.thread['otherParticipant'] ?? {});
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${other['name'] ?? 'Chat'}'),
          Text(widget.thread['online'] == true ? 'Online' : 'Secure school chat', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
        ]),
      ),
      body: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final m = messages[i];
                      final own = m['own'] == true;
                      final attachments = (m['attachments'] as List? ?? []).whereType<Map>().map((e) => Map<String,dynamic>.from(e)).toList();
                      return Align(
                        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(color: own ? Colors.indigo.shade50 : Colors.white, border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(16)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (!own) Text('${m['sender']?['name'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.indigo, fontWeight: FontWeight.w800)),
                            Text('${m['body'] ?? ''}'),
                            for (final a in attachments)
                              TextButton.icon(
                                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                                onPressed: () async { try { await widget.service.openAttachment(a); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); } },
                                icon: const Icon(Icons.attach_file, size: 17),
                                label: Text('${a['name'] ?? 'Attachment'}', overflow: TextOverflow.ellipsis),
                              ),
                            Align(alignment: Alignment.centerRight, child: Text('${_time(m['createdAt'])}${own ? ' • ${m['deliveryStatus'] ?? 'sent'}' : ''}', style: const TextStyle(fontSize: 10, color: Colors.grey))),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
          SizedBox(height: 22, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Align(alignment: Alignment.centerLeft, child: Text(typingText, style: const TextStyle(fontSize: 11, color: Colors.grey))))),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(children: [
                IconButton(onPressed: sending ? null : _attach, icon: const Icon(Icons.attach_file_rounded)),
                Expanded(child: TextField(controller: controller, onChanged: _typing, minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: 'Type a message…', border: OutlineInputBorder()))),
                const SizedBox(width: 6),
                IconButton.filled(onPressed: sending ? null : _send, icon: sending ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)) : const Icon(Icons.send_rounded)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
