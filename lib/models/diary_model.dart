// lib/models/diary_model.dart
class DiaryAttachment {
  final String? id;
  final String? name;
  final String? url;

  DiaryAttachment({this.id, this.name, this.url});

  factory DiaryAttachment.fromJson(Map<String, dynamic> j) => DiaryAttachment(
        id: j['id']?.toString(),
        name: j['name']?.toString(),
        url: j['url']?.toString(),
      );
}

class DiaryItem {
  final String id;
  final String? title;
  final String? content;
  final String? date;
  final String? type;
  final String? createdAt;
  final String? updatedAt;
  final Map<String, dynamic>? classObj;
  final Map<String, dynamic>? section;
  final Map<String, dynamic>? subject;
  final List<DiaryAttachment> attachments;
  final List<dynamic>? acknowledgements;

  DiaryItem({
    required this.id,
    this.title,
    this.content,
    this.date,
    this.type,
    this.createdAt,
    this.updatedAt,
    this.classObj,
    this.section,
    this.subject,
    this.attachments = const [],
    this.acknowledgements,
  });

  factory DiaryItem.fromJson(Map<String, dynamic> j) {
    final attachmentsRaw = j['attachments'];
    List<DiaryAttachment> attachments = [];
    if (attachmentsRaw is List) {
      attachments = attachmentsRaw.map((a) => DiaryAttachment.fromJson(Map<String, dynamic>.from(a))).toList();
    }
    return DiaryItem(
      id: j['id']?.toString() ?? '',
      title: j['title']?.toString(),
      content: j['content']?.toString(),
      date: j['date']?.toString(),
      type: j['type']?.toString(),
      createdAt: j['createdAt']?.toString(),
      updatedAt: j['updatedAt']?.toString(),
      classObj: j['class'] is Map ? Map<String, dynamic>.from(j['class']) : null,
      section: j['section'] is Map ? Map<String, dynamic>.from(j['section']) : null,
      subject: j['subject'] is Map ? Map<String, dynamic>.from(j['subject']) : null,
      attachments: attachments,
      acknowledgements: j['acknowledgements'] is List ? List<dynamic>.from(j['acknowledgements']) : null,
    );
  }
}
