import '../models/narration_preset.dart';

abstract class NarrationStyleDetector {
  static NarrationPreset detect(String text, String fileName) {
    final sample = text
        .substring(0, text.length.clamp(0, 10000).toInt())
        .toLowerCase();
    final name = fileName.toLowerCase();

    if (_containsAny(name, ['manual', 'procedur', 'tehnic', 'specification']) ||
        _countAny(sample, [' capitolul ', ' procedur', 'configur', 'parametr',
                'specificaț', 'instrucțiuni', 'warning', 'api ']) >=
            4) {
      return NarrationPreset.technical;
    }
    if (_containsAny(name, ['business', 'management', 'leadership', 'strategie']) ||
        _countAny(sample, ['afacere', 'strategie', 'client', 'venit', 'profit',
                'leadership', 'management', 'piață', 'obiectiv']) >=
            5) {
      return NarrationPreset.business;
    }
    if (_containsAny(name, ['poveste', 'basm', 'somn', 'seara', 'bedtime'])) {
      return NarrationPreset.evening;
    }

    final dialogueMarks = RegExp('[„“”«»"]').allMatches(sample).length;
    final dramaticWords = _countAny(sample, [
      'strigă',
      'șopti',
      'întuneric',
      'teamă',
      'tăcere',
      'sânge',
      'fugi',
    ]);
    if (dialogueMarks >= 14 && dramaticWords >= 3) {
      return NarrationPreset.dramatic;
    }
    if (dialogueMarks >= 8 || sample.length > 6000) {
      return NarrationPreset.fiction;
    }
    return NarrationPreset.neutral;
  }

  static bool _containsAny(String text, List<String> needles) =>
      needles.any(text.contains);

  static int _countAny(String text, List<String> needles) =>
      needles.where(text.contains).length;
}
