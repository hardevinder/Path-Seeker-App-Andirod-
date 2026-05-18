// lib/screens/student_messages_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/student_message.dart';
import '../services/api_service.dart';

class StudentMessagesScreen extends StatefulWidget {
  final int? openThreadId;

  const StudentMessagesScreen({
    super.key,
    this.openThreadId,
  });

  @override
  State<StudentMessagesScreen> createState() => _StudentMessagesScreenState();
}

class _StudentMessagesScreenState extends State<StudentMessagesScreen> {
  List<StudentMessageInboxItem> _messages = [];
  bool _loading = true;
  bool _unreadOnly = false;
  String _type = '';
  String _query = '';

  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      final id = widget.openThreadId;
      if (id != null && id > 0 && mounted) {
        _openThreadById(id);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final rows = await ApiService.fetchStudentMessages(
        page: 1,
        limit: 50,
        type: _type.isEmpty ? null : _type,
        search: _query.trim().isEmpty ? null : _query.trim(),
        unreadOnly: _unreadOnly,
      );

      if (!mounted) return;
      setState(() => _messages = rows);
    } catch (e, st) {
      debugPrint('Student messages load error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't load messages. ${_shortError(e)}")),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _query = value);
      _load();
    });
  }

  Future<void> _openThreadById(int threadId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudentMessageThreadScreen(threadId: threadId),
      ),
    );
    if (mounted) _load();
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    return DateFormat('dd MMM, hh:mm a').format(dt.toLocal());
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'FEE_REMINDER':
        return const Color(0xFFDC2626);
      case 'TEACHER_MESSAGE':
        return const Color(0xFF2563EB);
      case 'STUDENT_QUERY':
        return const Color(0xFF16A34A);
      case 'ACCOUNT_MESSAGE':
        return const Color(0xFFD97706);
      case 'ADMIN_MESSAGE':
        return const Color(0xFF111827);
      default:
        return const Color(0xFF64748B);
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'FEE_REMINDER':
        return Icons.receipt_long_rounded;
      case 'TEACHER_MESSAGE':
        return Icons.school_rounded;
      case 'STUDENT_QUERY':
        return Icons.question_answer_rounded;
      case 'ACCOUNT_MESSAGE':
        return Icons.account_balance_wallet_rounded;
      case 'ADMIN_MESSAGE':
        return Icons.admin_panel_settings_rounded;
      default:
        return Icons.chat_bubble_rounded;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'FEE_REMINDER':
        return 'Fee Reminder';
      case 'TEACHER_MESSAGE':
        return 'Teacher';
      case 'STUDENT_QUERY':
        return 'Query';
      case 'ACCOUNT_MESSAGE':
        return 'Accounts';
      case 'ADMIN_MESSAGE':
        return 'Admin';
      default:
        return 'General';
    }
  }

  Widget _buildMessageCard(StudentMessageInboxItem row, int index) {
    final thread = row.thread;
    final latest = thread.latestMessage;
    final color = _typeColor(thread.type);
    final preview = latest?.body.trim().isNotEmpty == true
        ? latest!.body.trim()
        : 'Tap to view message details';

    return InkWell(
      onTap: () => _openThreadById(thread.id),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: row.isUnread ? color.withOpacity(.28) : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: row.isUnread ? color.withOpacity(.12) : const Color(0x0F000000),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withOpacity(.70)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(_typeIcon(thread.type), color: Colors.white),
                ),
                if (row.isUnread)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        thread.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: row.isUnread ? FontWeight.w900 : FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDate(thread.lastMessageAt ?? thread.createdAt),
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    height: 1.35,
                    color: Color(0xFF475569),
                    fontSize: 13.2,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _Pill(
                      text: _typeLabel(thread.type),
                      color: color,
                      icon: _typeIcon(thread.type),
                    ),
                    const SizedBox(width: 8),
                    if (latest?.attachments.isNotEmpty == true)
                      const _SoftIconLabel(
                        icon: Icons.attach_file_rounded,
                        text: 'Attachment',
                      ),
                    const Spacer(),
                    const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
                  ],
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadingList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
      itemBuilder: (_, __) => Container(
        height: 112,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [Color(0xFFF1F5F9), Color(0xFFEAF1FF), Color(0xFFF8FAFC)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
      ),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemCount: 5,
    );
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _messages.where((x) => x.isUnread).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FF),
      appBar: AppBar(
        elevation: 0,
        title: const Text('Messages'),
        backgroundColor: const Color(0xFF1F7AE0),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1F7AE0), Color(0xFF7C3AED)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(26),
                  bottomRight: Radius.circular(26),
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text(
                          'Student Messages',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Fee reminders, teacher messages & replies',
                          style: TextStyle(color: Colors.white.withOpacity(.92)),
                        ),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.18),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withOpacity(.18)),
                      ),
                      child: const Icon(Icons.mark_chat_unread_rounded, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _HeroStat(label: 'Total', value: '${_messages.length}', icon: Icons.inbox_rounded),
                    const SizedBox(width: 10),
                    _HeroStat(label: 'Unread', value: '$unreadCount', icon: Icons.notifications_active_rounded),
                  ],
                ),
              ]),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'Search messages…',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () {
                        setState(() => _unreadOnly = !_unreadOnly);
                        _load();
                      },
                      child: Container(
                        height: 48,
                        width: 48,
                        decoration: BoxDecoration(
                          color: _unreadOnly ? const Color(0xFFE7F0FF) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _unreadOnly
                                ? const Color(0xFF1F7AE0)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Icon(
                          Icons.mark_email_unread_rounded,
                          color: _unreadOnly ? const Color(0xFF1F7AE0) : const Color(0xFF64748B),
                        ),
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _FilterChip2(label: 'All', selected: _type.isEmpty, onTap: () => _setType('')),
                    const SizedBox(width: 8),
                    _FilterChip2(label: 'Fee', selected: _type == 'FEE_REMINDER', onTap: () => _setType('FEE_REMINDER')),
                    const SizedBox(width: 8),
                    _FilterChip2(label: 'Teacher', selected: _type == 'TEACHER_MESSAGE', onTap: () => _setType('TEACHER_MESSAGE')),
                    const SizedBox(width: 8),
                    _FilterChip2(label: 'Accounts', selected: _type == 'ACCOUNT_MESSAGE', onTap: () => _setType('ACCOUNT_MESSAGE')),
                    const SizedBox(width: 8),
                    _FilterChip2(label: 'Admin', selected: _type == 'ADMIN_MESSAGE', onTap: () => _setType('ADMIN_MESSAGE')),
                  ]),
                ),
              ]),
            ),

            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: _loading
                    ? _loadingList()
                    : _messages.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.fromLTRB(16, 45, 16, 20),
                            children: const [
                              Icon(Icons.chat_bubble_outline_rounded, size: 62, color: Colors.black26),
                              SizedBox(height: 14),
                              Center(
                                child: Text(
                                  'No messages found',
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                ),
                              ),
                              SizedBox(height: 6),
                              Center(
                                child: Text(
                                  'Try refresh or change filters.',
                                  style: TextStyle(color: Colors.black54),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: _messages.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (_, i) => _buildMessageCard(_messages[i], i),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setType(String value) {
    setState(() => _type = value);
    _load();
  }
}

class StudentMessageThreadScreen extends StatefulWidget {
  final int threadId;

  const StudentMessageThreadScreen({
    super.key,
    required this.threadId,
  });

  @override
  State<StudentMessageThreadScreen> createState() => _StudentMessageThreadScreenState();
}

class _StudentMessageThreadScreenState extends State<StudentMessageThreadScreen> {
  StudentMessageThread? _thread;
  bool _loading = true;
  bool _sending = false;
  bool _hasReplyText = false;
  final _replyController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _replyController.addListener(() {
      final hasText = _replyController.text.trim().isNotEmpty;
      if (hasText != _hasReplyText && mounted) {
        setState(() => _hasReplyText = hasText);
      }
    });
    _load();
  }

  @override
  void dispose() {
    _replyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final thread = await ApiService.fetchStudentMessageThread(widget.threadId);
      if (!mounted) return;
      setState(() => _thread = thread);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } catch (e, st) {
      debugPrint('Thread load error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't load thread. ${_shortError(e)}")),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendReply() async {
    final body = _replyController.text.trim();
    if (body.isEmpty || _sending) return;

    setState(() => _sending = true);

    try {
      await ApiService.replyToStudentMessageThread(
        threadId: widget.threadId,
        body: body,
      );
      _replyController.clear();
      await _load();
    } catch (e, st) {
      debugPrint('Reply error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't send reply. ${_shortError(e)}")),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('dd MMM, hh:mm a').format(dt.toLocal());
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'FEE_REMINDER':
        return const Color(0xFFDC2626);
      case 'TEACHER_MESSAGE':
        return const Color(0xFF2563EB);
      case 'ACCOUNT_MESSAGE':
        return const Color(0xFFD97706);
      case 'ADMIN_MESSAGE':
        return const Color(0xFF111827);
      default:
        return const Color(0xFF64748B);
    }
  }

  Future<void> _openAttachment(StudentMessageAttachment a) async {
    final fileUrl = _absoluteFileUrl(a.url);
    if (fileUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attachment URL is missing')),
        );
      }
      return;
    }

    final uri = Uri.tryParse(fileUrl);
    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid attachment URL')),
        );
      }
      return;
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open attachment')),
      );
    }
  }

  Widget _messageBubble(StudentThreadMessage m) {
    final isMe = m.senderRole.toLowerCase() == 'student';
    final color = isMe ? const Color(0xFF1F7AE0) : const Color(0xFFFFFFFF);
    final textColor = isMe ? Colors.white : const Color(0xFF0F172A);
    final borderColor = isMe ? const Color(0xFF1F7AE0) : const Color(0xFFE2E8F0);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: EdgeInsets.only(
          left: isMe ? 42 : 0,
          right: isMe ? 0 : 42,
          bottom: 12,
        ),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
          border: Border.all(color: borderColor),
          boxShadow: const [
            BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  m.displaySender,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Color(0xFF1F7AE0),
                  ),
                ),
              ),
            Text(
              m.body,
              style: TextStyle(color: textColor, fontSize: 14.5, height: 1.38),
            ),
            if (m.attachments.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...m.attachments.map((a) => _AttachmentTile(
                    attachment: a,
                    isMe: isMe,
                    onTap: () => _openAttachment(a),
                  )),
            ],
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                _formatDate(m.createdAt),
                style: TextStyle(
                  color: isMe ? Colors.white.withOpacity(.78) : const Color(0xFF64748B),
                  fontSize: 10.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thread = _thread;
    final color = thread == null ? const Color(0xFF1F7AE0) : _typeColor(thread.type);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FF),
      appBar: AppBar(
        backgroundColor: color,
        elevation: 0,
        title: Text(thread?.subject ?? 'Message'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : thread == null
                ? const Center(child: Text('Message not found'))
                : Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(24),
                            bottomRight: Radius.circular(24),
                          ),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            thread.subject,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _WhitePill(text: _typeLabel(thread.type)),
                              _WhitePill(text: thread.status),
                              if (thread.admissionNumber != null)
                                _WhitePill(text: 'Adm ${thread.admissionNumber}'),
                            ],
                          ),
                        ]),
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                            children: thread.messages.isEmpty
                                ? const [
                                    SizedBox(height: 80),
                                    Center(child: Text('No messages yet')),
                                  ]
                                : thread.messages.map(_messageBubble).toList(),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -4)),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _replyController,
                                minLines: 1,
                                maxLines: 4,
                                textInputAction: TextInputAction.newline,
                                decoration: InputDecoration(
                                  hintText: 'Type your reply…',
                                  filled: true,
                                  fillColor: const Color(0xFFF1F5F9),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              height: 48,
                              width: 48,
                              child: ElevatedButton(
                                onPressed: (_sending || !_hasReplyText) ? null : _sendReply,
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  backgroundColor: color,
                                ),
                                child: _sending
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.send_rounded),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'FEE_REMINDER':
        return 'Fee Reminder';
      case 'TEACHER_MESSAGE':
        return 'Teacher Message';
      case 'ACCOUNT_MESSAGE':
        return 'Accounts';
      case 'ADMIN_MESSAGE':
        return 'Admin';
      default:
        return 'General';
    }
  }
}

class _AttachmentTile extends StatelessWidget {
  final StudentMessageAttachment attachment;
  final bool isMe;
  final VoidCallback onTap;

  const _AttachmentTile({
    required this.attachment,
    required this.isMe,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = attachment.isPdf
        ? Icons.picture_as_pdf_rounded
        : attachment.isImage
            ? Icons.image_rounded
            : Icons.insert_drive_file_rounded;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: isMe ? Colors.white.withOpacity(.14) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isMe ? Colors.white.withOpacity(.18) : const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isMe ? Colors.white : const Color(0xFF1F7AE0)),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isMe ? Colors.white : const Color(0xFF0F172A),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _HeroStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.16),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(.14)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 19),
            const SizedBox(width: 8),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(color: Colors.white.withOpacity(.86), fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;

  const _Pill({
    required this.text,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }
}

class _WhitePill extends StatelessWidget {
  final String text;
  const _WhitePill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.16)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _SoftIconLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SoftIconLabel({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: const Color(0xFF64748B)),
      const SizedBox(width: 3),
      Text(text, style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
    ]);
  }
}

class _FilterChip2 extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip2({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1F7AE0) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? const Color(0xFF1F7AE0) : const Color(0xFFE2E8F0)),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF1F7AE0).withOpacity(.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF334155),
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}


String _absoluteFileUrl(String url) {
  final clean = url.trim();
  if (clean.isEmpty) return clean;

  final lower = clean.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return clean;
  }

  final base = ApiService.baseUrl.replaceAll(RegExp(r'/+$'), '');
  if (clean.startsWith('/')) return '$base$clean';
  return '$base/$clean';
}

String _shortError(Object e) {
  final s = e.toString();
  if (s.length <= 90) return s;
  return '${s.substring(0, 90)}...';
}