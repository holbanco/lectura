import '../models/text_chunk.dart';

abstract class TextChunker {
  static List<TextChunk> split(String text, {int targetLength = 2100}) {
    if (text.trim().isEmpty) return const [];

    final chunks = <TextChunk>[];
    var cursor = 0;
    var index = 0;

    while (cursor < text.length) {
      while (cursor < text.length && _isWhitespace(text.codeUnitAt(cursor))) {
        cursor++;
      }
      if (cursor >= text.length) break;

      final hardEnd = (cursor + targetLength).clamp(0, text.length).toInt();
      var end = hardEnd;
      if (hardEnd < text.length) {
        end = _bestBoundary(text, cursor, hardEnd);
      }
      if (end <= cursor) end = hardEnd;

      final raw = text.substring(cursor, end);
      final leading = raw.length - raw.trimLeft().length;
      final trailing = raw.length - raw.trimRight().length;
      final actualStart = cursor + leading;
      final actualEnd = end - trailing;
      if (actualEnd > actualStart) {
        chunks.add(
          TextChunk(
            index: index++,
            start: actualStart,
            end: actualEnd,
            text: text.substring(actualStart, actualEnd),
          ),
        );
      }
      cursor = end;
    }

    return chunks;
  }

  static int chunkIndexForOffset(List<TextChunk> chunks, int offset) {
    if (chunks.isEmpty) return 0;
    var low = 0;
    var high = chunks.length - 1;
    final safeOffset = offset.clamp(0, chunks.last.end).toInt();
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      final chunk = chunks[middle];
      if (safeOffset < chunk.start) {
        high = middle - 1;
      } else if (safeOffset >= chunk.end) {
        low = middle + 1;
      } else {
        return middle;
      }
    }
    return low.clamp(0, chunks.length - 1).toInt();
  }

  static int _bestBoundary(String text, int start, int hardEnd) {
    final lowerBound = start + ((hardEnd - start) * 0.55).round();
    for (var i = hardEnd; i > lowerBound; i--) {
      if (_isSentenceEnd(text, i)) return i;
    }
    for (var i = hardEnd; i > lowerBound; i--) {
      if (text.codeUnitAt(i - 1) == 10) return i;
    }
    for (var i = hardEnd; i > lowerBound; i--) {
      if (_isWhitespace(text.codeUnitAt(i - 1))) return i;
    }
    return hardEnd;
  }

  static bool _isSentenceEnd(String text, int index) {
    if (index <= 0) return false;
    final unit = text.codeUnitAt(index - 1);
    if (unit != 46 && unit != 33 && unit != 63 && unit != 8221 && unit != 187) {
      return false;
    }
    return index >= text.length || _isWhitespace(text.codeUnitAt(index));
  }

  static bool _isWhitespace(int codeUnit) =>
      codeUnit == 32 || codeUnit == 9 || codeUnit == 10 || codeUnit == 13;
}
