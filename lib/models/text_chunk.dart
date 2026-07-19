class TextChunk {
  const TextChunk({
    required this.index,
    required this.start,
    required this.end,
    required this.text,
  });

  final int index;
  final int start;
  final int end;
  final String text;

  int get length => end - start;
}
