// lib/models/student_message.dart

class StudentMessageInboxItem {
  final int id;
  final DateTime? lastReadAt;
  final StudentMessageThread thread;

  StudentMessageInboxItem({
    required this.id,
    required this.lastReadAt,
    required this.thread,
  });

  bool get isUnread => lastReadAt == null;

  factory StudentMessageInboxItem.fromJson(Map<String, dynamic> json) {
    return StudentMessageInboxItem(
      id: _toInt(json['id']),
      lastReadAt: _parseDate(json['lastReadAt'] ?? json['last_read_at']),
      thread: StudentMessageThread.fromJson(
        Map<String, dynamic>.from(json['thread'] ?? {}),
      ),
    );
  }
}

class StudentMessageThread {
  final int id;
  final String type;
  final String subject;
  final String status;
  final String priority;
  final String? admissionNumber;
  final int? studentId;
  final DateTime? lastMessageAt;
  final DateTime? createdAt;
  final List<StudentThreadMessage> messages;
  final List<StudentMessageParticipant> participants;

  StudentMessageThread({
    required this.id,
    required this.type,
    required this.subject,
    required this.status,
    required this.priority,
    this.admissionNumber,
    this.studentId,
    this.lastMessageAt,
    this.createdAt,
    this.messages = const [],
    this.participants = const [],
  });

  factory StudentMessageThread.fromJson(Map<String, dynamic> json) {
    final messagesRaw = json['messages'];
    final participantsRaw = json['participants'];

    return StudentMessageThread(
      id: _toInt(json['id']),
      type: _s(json['type'], fallback: 'GENERAL'),
      subject: _s(json['subject'], fallback: 'Untitled'),
      status: _s(json['status'], fallback: 'OPEN'),
      priority: _s(json['priority'], fallback: 'NORMAL'),
      admissionNumber: _nullableS(json['admissionNumber'] ?? json['admission_number']),
      studentId: _toNullableInt(json['studentId'] ?? json['student_id']),
      lastMessageAt: _parseDate(json['lastMessageAt'] ?? json['last_message_at']),
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
      messages: messagesRaw is List
          ? messagesRaw
              .whereType<Map>()
              .map((e) => StudentThreadMessage.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      participants: participantsRaw is List
          ? participantsRaw
              .whereType<Map>()
              .map((e) => StudentMessageParticipant.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }

  StudentThreadMessage? get latestMessage {
    if (messages.isEmpty) return null;
    return messages.first;
  }
}

class StudentThreadMessage {
  final int id;
  final int threadId;
  final int? senderUserId;
  final int? senderStudentId;
  final String senderRole;
  final String body;
  final DateTime? createdAt;
  final StudentMessagePerson? senderUser;
  final StudentMessageStudent? senderStudent;
  final List<StudentMessageAttachment> attachments;

  StudentThreadMessage({
    required this.id,
    required this.threadId,
    this.senderUserId,
    this.senderStudentId,
    required this.senderRole,
    required this.body,
    this.createdAt,
    this.senderUser,
    this.senderStudent,
    this.attachments = const [],
  });

  factory StudentThreadMessage.fromJson(Map<String, dynamic> json) {
    final attachmentsRaw = json['attachments'];

    return StudentThreadMessage(
      id: _toInt(json['id']),
      threadId: _toInt(json['threadId'] ?? json['thread_id']),
      senderUserId: _toNullableInt(json['senderUserId'] ?? json['sender_user_id']),
      senderStudentId: _toNullableInt(json['senderStudentId'] ?? json['sender_student_id']),
      senderRole: _s(json['senderRole'] ?? json['sender_role'], fallback: 'user'),
      body: _s(json['body']),
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
      senderUser: json['senderUser'] is Map
          ? StudentMessagePerson.fromJson(Map<String, dynamic>.from(json['senderUser']))
          : null,
      senderStudent: json['senderStudent'] is Map
          ? StudentMessageStudent.fromJson(Map<String, dynamic>.from(json['senderStudent']))
          : null,
      attachments: attachmentsRaw is List
          ? attachmentsRaw
              .whereType<Map>()
              .map((e) => StudentMessageAttachment.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }

  String get displaySender {
    if (senderStudent != null) return senderStudent!.displayName;
    if (senderUser != null) return senderUser!.displayName;

    final role = senderRole.trim();
    if (role.isEmpty) return 'User';
    return role[0].toUpperCase() + role.substring(1).replaceAll('_', ' ');
  }
}

class StudentMessageParticipant {
  final int id;
  final int? participantUserId;
  final int? participantStudentId;
  final String participantRole;
  final String? admissionNumber;
  final DateTime? lastReadAt;
  final StudentMessagePerson? participantUser;
  final StudentMessageStudent? participantStudent;

  StudentMessageParticipant({
    required this.id,
    this.participantUserId,
    this.participantStudentId,
    required this.participantRole,
    this.admissionNumber,
    this.lastReadAt,
    this.participantUser,
    this.participantStudent,
  });

  factory StudentMessageParticipant.fromJson(Map<String, dynamic> json) {
    return StudentMessageParticipant(
      id: _toInt(json['id']),
      participantUserId: _toNullableInt(json['participantUserId'] ?? json['participant_user_id']),
      participantStudentId: _toNullableInt(json['participantStudentId'] ?? json['participant_student_id']),
      participantRole: _s(json['participantRole'] ?? json['participant_role'], fallback: 'user'),
      admissionNumber: _nullableS(json['admissionNumber'] ?? json['admission_number']),
      lastReadAt: _parseDate(json['lastReadAt'] ?? json['last_read_at']),
      participantUser: json['participantUser'] is Map
          ? StudentMessagePerson.fromJson(Map<String, dynamic>.from(json['participantUser']))
          : null,
      participantStudent: json['participantStudent'] is Map
          ? StudentMessageStudent.fromJson(Map<String, dynamic>.from(json['participantStudent']))
          : null,
    );
  }

  String get displayName {
    if (participantStudent != null) return participantStudent!.displayName;
    if (participantUser != null) return participantUser!.displayName;
    if ((admissionNumber ?? '').isNotEmpty) return 'Student ($admissionNumber)';

    final role = participantRole.trim();
    if (role.isEmpty) return 'User';
    return role[0].toUpperCase() + role.substring(1).replaceAll('_', ' ');
  }
}

class StudentMessagePerson {
  final int id;
  final String name;
  final String username;

  StudentMessagePerson({
    required this.id,
    required this.name,
    required this.username,
  });

  factory StudentMessagePerson.fromJson(Map<String, dynamic> json) {
    return StudentMessagePerson(
      id: _toInt(json['id']),
      name: _s(json['name']),
      username: _s(json['username']),
    );
  }

  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    if (username.trim().isNotEmpty) return username.trim();
    return 'User $id';
  }
}

class StudentMessageStudent {
  final int id;
  final String name;
  final String admissionNumber;
  final int? classId;
  final int? sectionId;

  StudentMessageStudent({
    required this.id,
    required this.name,
    required this.admissionNumber,
    this.classId,
    this.sectionId,
  });

  factory StudentMessageStudent.fromJson(Map<String, dynamic> json) {
    return StudentMessageStudent(
      id: _toInt(json['id']),
      name: _s(json['name']),
      admissionNumber: _s(json['admission_number'] ?? json['admissionNumber']),
      classId: _toNullableInt(json['class_id'] ?? json['classId']),
      sectionId: _toNullableInt(json['section_id'] ?? json['sectionId']),
    );
  }

  String get displayName {
    if (name.trim().isNotEmpty && admissionNumber.trim().isNotEmpty) {
      return '$name ($admissionNumber)';
    }
    if (name.trim().isNotEmpty) return name.trim();
    if (admissionNumber.trim().isNotEmpty) return 'Student ($admissionNumber)';
    return 'Student $id';
  }
}

class StudentMessageAttachment {
  final int id;
  final String url;
  final String name;
  final String kind;
  final int? sizeBytes;

  StudentMessageAttachment({
    required this.id,
    required this.url,
    required this.name,
    required this.kind,
    this.sizeBytes,
  });

  factory StudentMessageAttachment.fromJson(Map<String, dynamic> json) {
    return StudentMessageAttachment(
      id: _toInt(json['id']),
      url: _s(json['url']),
      name: _s(json['name'] ?? json['filename'], fallback: 'Attachment'),
      kind: _s(json['kind'] ?? json['mime_type']),
      sizeBytes: _toNullableInt(json['sizeBytes'] ?? json['size_bytes']),
    );
  }

  bool get isImage {
    final clean = url.split('?').first.split('#').first.toLowerCase();
    return clean.endsWith('.png') ||
        clean.endsWith('.jpg') ||
        clean.endsWith('.jpeg') ||
        clean.endsWith('.webp') ||
        clean.endsWith('.gif');
  }

  bool get isPdf {
    final clean = url.split('?').first.split('#').first.toLowerCase();
    return clean.endsWith('.pdf') || kind.toLowerCase().contains('pdf');
  }
}

String _s(dynamic v, {String fallback = ''}) {
  if (v == null) return fallback;
  final s = v.toString().trim();
  return s.isEmpty ? fallback : s;
}

String? _nullableS(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

int? _toNullableInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse('$v');
}