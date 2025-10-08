// lib/models/circular.dart
class Circular {
  final String id;
  final String title;
  final String? description;
  final String audience;
  final String? fileUrl;
  final DateTime createdAt;

  Circular({
    required this.id,
    required this.title,
    this.description,
    required this.audience,
    this.fileUrl,
    required this.createdAt,
  });

  factory Circular.fromJson(Map<String, dynamic> j) {
    return Circular(
      id: j['id']?.toString() ?? '',
      title: j['title']?.toString() ?? 'Untitled',
      description: j['description'] as String?,
      audience: j['audience']?.toString() ?? 'student',
      fileUrl: j['fileUrl'] as String?,
      createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
