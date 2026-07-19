import 'package:flutter_test/flutter_test.dart';
import 'package:lectura/models/book_document.dart';
import 'package:lectura/models/narration_preset.dart';

void main() {
  test('book metadata survives a JSON round trip', () {
    final book = BookDocument(
      id: 'book-1',
      title: 'Test',
      originalFileName: 'test.epub',
      format: 'EPUB',
      textFileName: 'book-1.txt',
      importedAt: DateTime.utc(2026, 7, 19),
      lastOpenedAt: DateTime.utc(2026, 7, 19, 12),
      characterCount: 1000,
      progressCharacter: 250,
      preset: NarrationPreset.fiction,
      engine: ReadingEngine.studio,
      studioVoice: 'fable',
      offlineVoiceName: 'Ioana',
      offlineVoiceLocale: 'ro-RO',
      colorSeed: 3,
    );

    final restored = BookDocument.fromJson(book.toJson());

    expect(restored.title, book.title);
    expect(restored.preset, NarrationPreset.fiction);
    expect(restored.engine, ReadingEngine.studio);
    expect(restored.studioVoice, 'fable');
    expect(restored.progress, 0.25);
  });
}
