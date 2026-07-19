class DocumentChapter {
  const DocumentChapter({required this.title, required this.start});

  final String title;
  final int start;

  Map<String, Object?> toJson() => {
        'title': title,
        'start': start,
      };

  factory DocumentChapter.fromJson(Map<String, Object?> json) {
    return DocumentChapter(
      title: json['title'] as String? ?? 'Capitol',
      start: (json['start'] as num?)?.toInt() ?? 0,
    );
  }
}
