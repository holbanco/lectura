import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../models/narration_preset.dart';

class StudioNotConfiguredException implements Exception {
  const StudioNotConfiguredException();

  @override
  String toString() => 'Configurează cheia pentru vocea Studio din Setări.';
}

class SpeechGenerationException implements Exception {
  const SpeechGenerationException(this.message);
  final String message;

  @override
  String toString() => message;
}

class NeuralSpeechService {
  NeuralSpeechService({
    required Directory cacheDirectory,
    http.Client? client,
  })  : _cacheDirectory = cacheDirectory,
        _client = client ?? http.Client();

  static const voices = <String>[
    'marin',
    'cedar',
    'fable',
    'coral',
    'alloy',
    'ash',
    'ballad',
    'echo',
    'nova',
    'onyx',
    'sage',
    'shimmer',
    'verse',
  ];

  static const _apiKeyName = 'openai_tts_api_key';
  static const _storage = FlutterSecureStorage();
  final Directory _cacheDirectory;
  final http.Client _client;

  Future<bool> get isConfigured async {
    final value = await _storage.read(key: _apiKeyName);
    return value != null && value.trim().isNotEmpty;
  }

  Future<String?> readMaskedKey() async {
    final value = await _storage.read(key: _apiKeyName);
    if (value == null || value.length < 9) return null;
    return '${value.substring(0, 5)}••••${value.substring(value.length - 4)}';
  }

  Future<void> saveApiKey(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _storage.delete(key: _apiKeyName);
      return;
    }
    if (!trimmed.startsWith('sk-') || trimmed.length < 20) {
      throw const SpeechGenerationException(
        'Cheia nu pare validă. Trebuie să înceapă cu „sk-”.',
      );
    }
    await _storage.write(key: _apiKeyName, value: trimmed);
  }

  Future<void> deleteApiKey() => _storage.delete(key: _apiKeyName);

  Future<File> audioFor({
    required String bookId,
    required String text,
    required String voice,
    required NarrationPreset preset,
    required double preferredRate,
  }) async {
    final key = await _storage.read(key: _apiKeyName);
    if (key == null || key.trim().isEmpty) {
      throw const StudioNotConfiguredException();
    }
    await _cacheDirectory.create(recursive: true);
    final digest = sha256
        .convert(utf8.encode('$voice|${preset.key}|$preferredRate|$text'))
        .toString()
        .substring(0, 28);
    final output = File(path.join(_cacheDirectory.path, '${bookId}_$digest.mp3'));
    if (await output.exists() && await output.length() > 1024) return output;

    final response = await _client
        .post(
          Uri.parse('https://api.openai.com/v1/audio/speech'),
          headers: {
            HttpHeaders.authorizationHeader: 'Bearer $key',
            HttpHeaders.contentTypeHeader: 'application/json',
          },
          body: jsonEncode({
            'model': 'gpt-4o-mini-tts',
            'voice': voices.contains(voice) ? voice : 'marin',
            'input': text,
            'instructions': _instructions(preset, preferredRate),
            'response_format': 'mp3',
          }),
        )
        .timeout(const Duration(seconds: 90));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SpeechGenerationException(_friendlyError(response));
    }
    final temporary = File('${output.path}.tmp');
    await temporary.writeAsBytes(response.bodyBytes, flush: true);
    if (await output.exists()) await output.delete();
    await temporary.rename(output.path);
    return output;
  }

  static String _instructions(NarrationPreset preset, double rate) {
    final cadence = rate < 0.9
        ? 'Use a relaxed, unhurried cadence.'
        : rate > 1.15
            ? 'Use a brisk cadence while remaining natural and fully intelligible.'
            : 'Use a natural audiobook cadence.';
    return '${preset.studioInstructions} $cadence '
        'Speak in the same language as the supplied text. Read every supplied word '
        'faithfully; do not summarize, translate, add commentary, or announce these instructions. '
        'Pronounce Romanian diacritics, names, numbers, punctuation and abbreviations carefully.';
  }

  static String _friendlyError(http.Response response) {
    var detail = '';
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final error = decoded['error'];
      if (error is Map<String, dynamic>) detail = error['message'] as String? ?? '';
    } on Object {
      // The response may be audio/proxy text rather than JSON.
    }
    if (response.statusCode == 401) {
      return 'Cheia Studio nu este validă sau a fost revocată.';
    }
    if (response.statusCode == 429) {
      return 'Limita serviciului vocal a fost atinsă. Încearcă din nou puțin mai târziu.';
    }
    if (response.statusCode >= 500) {
      return 'Serviciul vocal este temporar indisponibil.';
    }
    return detail.isEmpty
        ? 'Vocea nu a putut fi generată (cod ${response.statusCode}).'
        : detail;
  }

  void dispose() => _client.close();
}
