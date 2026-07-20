import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('background audio uses exactly one AudioPlayer instance', () {
    final constructors = <String>[];
    final pattern = RegExp(r'\bAudioPlayer\s*\(');

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final count = pattern.allMatches(entity.readAsStringSync()).length;
      for (var index = 0; index < count; index++) {
        constructors.add(entity.path);
      }
    }

    expect(constructors, hasLength(1));
    expect(
      constructors.single.replaceAll('\\', '/'),
      endsWith('lib/services/app_audio_player.dart'),
    );
  });
}
