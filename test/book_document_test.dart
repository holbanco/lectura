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
      engine: ReadingEngine.openAiPremium,
      studioVoice: 'fable',
      localVoice: 'F3',
      offlineVoiceName: 'Ioana',
      offlineVoiceLocale: 'ro-RO',
      colorSeed: 3,
    );

    final restored = BookDocument.fromJson(book.toJson());

    expect(restored.title, book.title);
    expect(restored.preset, NarrationPreset.fiction);
    expect(restored.engine, ReadingEngine.openAiPremium);
    expect(restored.studioVoice, 'fable');
    expect(restored.localVoice, 'F3');
    expect(restored.progress, 0.25);
  });

  test('migrates the old paid studio mode to the free local engine', () {
    final json = BookDocument(
      id: 'legacy',
      title: 'Legacy',
      originalFileName: 'legacy.pdf',
      format: 'PDF',
      textFileName: 'legacy.txt',
      importedAt: DateTime.utc(2026),
      lastOpenedAt: DateTime.utc(2026),
      characterCount: 100,
    ).toJson()
      ..['engine'] = 'studio';

    expect(
      BookDocument.fromJson(json).engine,
      ReadingEngine.localNeural,
    );
  });
}
