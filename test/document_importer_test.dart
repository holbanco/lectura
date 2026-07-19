import 'package:flutter_test/flutter_test.dart';
import 'package:lectura/services/document_importer.dart';

void main() {
  test('normalizes whitespace while preserving paragraphs', () {
    const source = 'Primul   paragraf.\r\n\r\n\r\n Al doilea\tparagraf.';
    expect(
      DocumentImporter.normalizeText(source),
      'Primul paragraf.\n\nAl doilea paragraf.',
    );
  });

  test('joins words hyphenated across a line break', () {
    expect(
      DocumentImporter.normalizeText('O aplica-\nție utilă.'),
      'O aplicație utilă.',
    );
  });
}
