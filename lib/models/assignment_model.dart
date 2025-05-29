class Assignment {
  final String title;
  final String fileUrl;

  Assignment({required this.title, required this.fileUrl});

  factory Assignment.fromJson(Map<String, dynamic> json) {
    return Assignment(
      title: json['title'],
      fileUrl: json['file_url'],
    );
  }
}
