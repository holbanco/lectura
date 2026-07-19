import 'package:flutter_test/flutter_test.dart';
import 'package:lectura/services/text_chunker.dart';

void main() {
  group('TextChunker', () {
    test('splits long text at natural sentence boundaries', () {
      final text = List.generate(
        80,
        (index) => 'Aceasta este propoziția numărul $index și trebuie citită natural.',
      ).join(' ');

      final chunks = TextChunker.split(text, targetLength: 260);

      expect(chunks.length, greaterThan(5));
      expect(chunks.first.start, 0);
      expect(chunks.last.end, text.length);
      expect(chunks.every((chunk) => chunk.text.trim().isNotEmpty), isTrue);
      expect(chunks.every((chunk) => chunk.text.length <= 270), isTrue);
      expect(chunks.map((chunk) => chunk.index), orderedEquals(
        List.generate(chunks.length, (index) => index),
      ));
    });

    test('finds the chunk containing a saved offset', () {
      final text = List.generate(20, (index) => 'Paragraf $index.').join('\n\n');
      final chunks = TextChunker.split(text, targetLength: 60);
      final target = chunks[2].start + 3;

      expect(TextChunker.chunkIndexForOffset(chunks, target), 2);
      expect(TextChunker.chunkIndexForOffset(chunks, text.length), chunks.length - 1);
    });

    test('returns no chunks for blank input', () {
      expect(TextChunker.split('   \n\n'), isEmpty);
    });
  });
}
