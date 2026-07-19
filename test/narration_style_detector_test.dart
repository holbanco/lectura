import 'package:flutter_test/flutter_test.dart';
import 'package:lectura/models/narration_preset.dart';
import 'package:lectura/services/narration_style_detector.dart';

void main() {
  test('detects a business document', () {
    const text = 'Strategia de afacere pornește de la client și piață. '
        'Managementul urmărește venit, profit, leadership și obiectiv.';
    expect(
      NarrationStyleDetector.detect(text, 'strategie-companie.docx'),
      NarrationPreset.business,
    );
  });

  test('detects technical instructions before generic long text', () {
    const text = 'Instrucțiuni de configurare. Parametrul API trebuie validat. '
        'Procedura și specificațiile tehnice sunt descrise în capitolul următor.';
    expect(
      NarrationStyleDetector.detect(text, 'manual_tehnic.pdf'),
      NarrationPreset.technical,
    );
  });

  test('detects an evening story from its title', () {
    expect(
      NarrationStyleDetector.detect('A fost odată un iepure blând.', 'poveste_de_seara.epub'),
      NarrationPreset.evening,
    );
  });
}
