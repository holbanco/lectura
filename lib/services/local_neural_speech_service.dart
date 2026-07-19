import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:supertonic_flutter/supertonic_flutter.dart';

import '../models/narration_preset.dart';

class LocalModelMissingException implements Exception {
  const LocalModelMissingException();

  @override
  String toString() =>
      'Descarcă mai întâi vocea neurală locală din Setări (aprox. 400 MB).';
}

class LocalNeuralSpeechException implements Exception {
  const LocalNeuralSpeechException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LocalVoiceOption {
  const LocalVoiceOption(this.id, this.label, this.description);

  final String id;
  final String label;
  final String description;
}

class LocalNeuralSpeechService {
  LocalNeuralSpeechService({required Directory cacheDirectory})
      : _cacheDirectory = cacheDirectory;

  static const voices = <LocalVoiceOption>[
    LocalVoiceOption('F1', 'Elena', 'caldă și clară'),
    LocalVoiceOption('F2', 'Mara', 'expresivă, recomandată pentru cărți'),
    LocalVoiceOption('F3', 'Iris', 'luminoasă și energică'),
    LocalVoiceOption('F4', 'Daria', 'matură și liniștită'),
    LocalVoiceOption('F5', 'Sofia', 'intimă și delicată'),
    LocalVoiceOption('M1', 'Andrei', 'naturală și echilibrată'),
    LocalVoiceOption('M2', 'Victor', 'caldă și cinematografică'),
    LocalVoiceOption('M3', 'Matei', 'sigură și energică'),
    LocalVoiceOption('M4', 'Radu', 'gravă și dramatică'),
    LocalVoiceOption('M5', 'Luca', 'calmă și apropiată'),
  ];

  final Directory _cacheDirectory;
  SupertonicTTS? _tts;
  Future<void>? _initializing;
  Future<void> _serial = Future<void>.value();

  static Future<bool> modelsReady() => SupertonicTTS.modelsReady();

  static Future<void> downloadModels({
    void Function(int completed, int total, String file, double progress)?
        onProgress,
  }) {
    return SupertonicTTS.preDownloadModels(onProgress: onProgress);
  }

  Future<File> audioFor({
    required String bookId,
    required String text,
    required String voice,
    required NarrationPreset preset,
  }) async {
    if (!await modelsReady()) throw const LocalModelMissingException();
    await _cacheDirectory.create(recursive: true);
    final safeVoice = voices.any((option) => option.id == voice) ? voice : 'F2';
    final digest = sha256
        .convert(utf8.encode('supertonic3|$safeVoice|${preset.key}|$text'))
        .toString()
        .substring(0, 28);
    final output = File(
      path.join(_cacheDirectory.path, '${bookId}_local_$digest.wav'),
    );
    if (await output.exists() && await output.length() > 1024) return output;

    final completer = Completer<File>();
    _serial = _serial.then((_) async {
      try {
        if (await output.exists() && await output.length() > 1024) {
          completer.complete(output);
          return;
        }
        await _ensureInitialized();
        final result = await _tts!.synthesize(
          text,
          language: 'ro',
          voiceStyle: safeVoice,
          config: TTSConfig(
            denoisingSteps: 5,
            speechSpeed: _synthesisRate(preset),
            silenceDuration: 0.08,
          ),
        );
        final temporary = File('${output.path}.tmp');
        await temporary.writeAsBytes(result.toWavBytes(), flush: true);
        if (await output.exists()) await output.delete();
        await temporary.rename(output.path);
        completer.complete(output);
      } on Object catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(
            LocalNeuralSpeechException(
              'Vocea locală nu a putut genera fragmentul: $error',
            ),
            stackTrace,
          );
        }
      }
    });
    return completer.future;
  }

  Future<void> _ensureInitialized() {
    if (_tts?.isInitialized ?? false) return Future<void>.value();
    return _initializing ??= () async {
      final tts = SupertonicTTS();
      try {
        await tts.initialize();
        _tts = tts;
      } on Object {
        tts.dispose();
        rethrow;
      } finally {
        _initializing = null;
      }
    }();
  }

  static double _synthesisRate(NarrationPreset preset) {
    switch (preset) {
      case NarrationPreset.dramatic:
        return 0.94;
      case NarrationPreset.evening:
        return 0.90;
      case NarrationPreset.technical:
        return 0.97;
      case NarrationPreset.business:
        return 1.04;
      case NarrationPreset.fiction:
        return 0.97;
      case NarrationPreset.neutral:
        return 1.0;
    }
  }

  void dispose() {
    _tts?.dispose();
    _tts = null;
  }
}
