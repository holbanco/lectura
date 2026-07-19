import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import '../models/book_document.dart';
import '../models/narration_preset.dart';
import '../models/text_chunk.dart';
import 'library_repository.dart';
import 'neural_speech_service.dart';
import 'text_chunker.dart';

enum PlaybackStatus { idle, loading, playing, paused, completed, error }

class DeviceVoice {
  const DeviceVoice({
    required this.name,
    required this.locale,
    this.networkRequired = false,
  });

  final String name;
  final String locale;
  final bool networkRequired;

  String get label => '$name · $locale${networkRequired ? ' · online' : ''}';
}

class ReaderSession extends ChangeNotifier {
  ReaderSession({required this.repository, required BookDocument book})
      : _book = book,
        neuralSpeech = NeuralSpeechService(
          cacheDirectory: repository.audioDirectory,
        );

  final LibraryRepository repository;
  final NeuralSpeechService neuralSpeech;
  final FlutterTts _offlineTts = FlutterTts();
  final AudioPlayer _studioPlayer = AudioPlayer();
  final List<StreamSubscription<Object?>> _subscriptions = [];

  BookDocument _book;
  String _text = '';
  List<TextChunk> _chunks = const [];
  List<DeviceVoice> _deviceVoices = const [];
  PlaybackStatus _status = PlaybackStatus.idle;
  int _chunkIndex = 0;
  int _currentCharacter = 0;
  int _spokenBase = 0;
  int? _loadedStudioChunk;
  double _playbackRate = 1.0;
  String? _errorMessage;
  bool _initialized = false;
  bool _disposed = false;
  bool _manualStop = false;

  BookDocument get book => _book;
  String get text => _text;
  List<TextChunk> get chunks => _chunks;
  List<DeviceVoice> get deviceVoices => _deviceVoices;
  PlaybackStatus get status => _status;
  bool get isPlaying => _status == PlaybackStatus.playing;
  bool get isLoading => _status == PlaybackStatus.loading;
  bool get isStudio => _book.engine == ReadingEngine.studio;
  int get currentCharacter => _currentCharacter;
  int get currentChunkIndex => _chunkIndex;
  double get playbackRate => _playbackRate;
  String? get errorMessage => _errorMessage;

  double get progress => _text.isEmpty
      ? 0
      : (_currentCharacter / _text.length).clamp(0.0, 1.0).toDouble();

  TextChunk? get currentChunk =>
      _chunks.isEmpty
          ? null
          : _chunks[_chunkIndex.clamp(0, _chunks.length - 1).toInt()];

  int get remainingMinutes {
    final remaining =
        (_text.length - _currentCharacter).clamp(0, _text.length).toInt();
    final charactersPerMinute = (930 * _playbackRate).round();
    return charactersPerMinute == 0 ? 0 : (remaining / charactersPerMinute).ceil();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _text = await repository.readText(_book);
    _chunks = TextChunker.split(_text);
    _currentCharacter = _book.progressCharacter.clamp(0, _text.length).toInt();
    _chunkIndex = TextChunker.chunkIndexForOffset(_chunks, _currentCharacter);
    if (_chunks.isNotEmpty && _currentCharacter < _chunks[_chunkIndex].start) {
      _currentCharacter = _chunks[_chunkIndex].start;
    }
    await _configureOfflineTts();
    _configureStudioPlayer();
    _book = _book.copyWith(lastOpenedAt: DateTime.now());
    await repository.update(_book);
    _initialized = true;
    _safeNotify();
  }

  Future<void> playPause() async {
    if (isPlaying || isLoading) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> play() async {
    if (!_initialized || _chunks.isEmpty) return;
    _errorMessage = null;
    if (_status == PlaybackStatus.completed) {
      _chunkIndex = 0;
      _currentCharacter = _chunks.first.start;
    }
    try {
      if (_book.engine == ReadingEngine.offline) {
        await _playOffline();
      } else {
        await _playStudio();
      }
    } on Object catch (error) {
      _status = PlaybackStatus.error;
      _errorMessage = error.toString();
      _safeNotify();
    }
  }

  Future<void> pause() async {
    _manualStop = true;
    if (_book.engine == ReadingEngine.offline) {
      await _offlineTts.stop();
    } else {
      await _studioPlayer.pause();
    }
    _manualStop = false;
    _status = PlaybackStatus.paused;
    await _persistProgress();
    _safeNotify();
  }

  Future<void> next() async {
    if (_chunks.isEmpty || _chunkIndex >= _chunks.length - 1) return;
    final resume = isPlaying || isLoading;
    await _stopActive();
    _chunkIndex++;
    _currentCharacter = _chunks[_chunkIndex].start;
    _loadedStudioChunk = null;
    _status = PlaybackStatus.paused;
    await _persistProgress();
    _safeNotify();
    if (resume) await play();
  }

  Future<void> previous() async {
    if (_chunks.isEmpty) return;
    final resume = isPlaying || isLoading;
    await _stopActive();
    final current = _chunks[_chunkIndex];
    if (_currentCharacter - current.start > 220 || _chunkIndex == 0) {
      _currentCharacter = current.start;
    } else {
      _chunkIndex--;
      _currentCharacter = _chunks[_chunkIndex].start;
    }
    _loadedStudioChunk = null;
    _status = PlaybackStatus.paused;
    await _persistProgress();
    _safeNotify();
    if (resume) await play();
  }

  Future<void> seekTo(double normalized) async {
    if (_chunks.isEmpty) return;
    final resume = isPlaying || isLoading;
    await _stopActive();
    _currentCharacter = (_text.length * normalized.clamp(0.0, 1.0)).round();
    _chunkIndex = TextChunker.chunkIndexForOffset(_chunks, _currentCharacter);
    _currentCharacter = _currentCharacter.clamp(
      _chunks[_chunkIndex].start,
      _chunks[_chunkIndex].end - 1,
    ).toInt();
    _loadedStudioChunk = null;
    _status = PlaybackStatus.paused;
    await _persistProgress();
    _safeNotify();
    if (resume) await play();
  }

  Future<void> setEngine(ReadingEngine engine) async {
    if (_book.engine == engine) return;
    final resume = isPlaying || isLoading;
    await _stopActive();
    _book = _book.copyWith(engine: engine, lastOpenedAt: DateTime.now());
    _loadedStudioChunk = null;
    _status = PlaybackStatus.paused;
    await repository.update(_book);
    _safeNotify();
    if (resume) await play();
  }

  Future<void> setPreset(NarrationPreset preset) async {
    if (_book.preset == preset) return;
    final resume = isPlaying || isLoading;
    await _stopActive();
    _book = _book.copyWith(
      preset: preset,
      studioVoice: preset.recommendedVoice,
      lastOpenedAt: DateTime.now(),
    );
    _loadedStudioChunk = null;
    await repository.update(_book);
    _status = PlaybackStatus.paused;
    _safeNotify();
    if (resume) await play();
  }

  Future<void> setStudioVoice(String voice) async {
    if (_book.studioVoice == voice || !NeuralSpeechService.voices.contains(voice)) {
      return;
    }
    final resume = isPlaying || isLoading;
    await _stopActive();
    _book = _book.copyWith(studioVoice: voice, lastOpenedAt: DateTime.now());
    _loadedStudioChunk = null;
    await repository.update(_book);
    _status = PlaybackStatus.paused;
    _safeNotify();
    if (resume) await play();
  }

  Future<void> setDeviceVoice(DeviceVoice? voice) async {
    final resume = isPlaying || isLoading;
    await _stopActive();
    if (voice == null) {
      _book = _book.copyWith(clearOfflineVoice: true, lastOpenedAt: DateTime.now());
    } else {
      _book = _book.copyWith(
        offlineVoiceName: voice.name,
        offlineVoiceLocale: voice.locale,
        lastOpenedAt: DateTime.now(),
      );
      await _offlineTts.setVoice({'name': voice.name, 'locale': voice.locale});
    }
    await repository.update(_book);
    _status = PlaybackStatus.paused;
    _safeNotify();
    if (resume) await play();
  }

  Future<void> setPlaybackRate(double value) async {
    final safe = value.clamp(0.75, 1.5).toDouble();
    if ((safe - _playbackRate).abs() < 0.01) return;
    _playbackRate = safe;
    if (_book.engine == ReadingEngine.studio) {
      await _studioPlayer.setSpeed(safe);
      _safeNotify();
      return;
    }
    final resume = isPlaying;
    if (resume) {
      await _stopActive();
      await play();
    } else {
      _safeNotify();
    }
  }

  Future<void> _playOffline() async {
    final chunk = _chunks[_chunkIndex];
    final from = _currentCharacter.clamp(chunk.start, chunk.end - 1).toInt();
    _spokenBase = from;
    await _offlineTts.setSpeechRate(
      (_book.preset.offlineRate * _playbackRate)
          .clamp(0.25, 0.75)
          .toDouble(),
    );
    await _offlineTts.setPitch(_book.preset.offlinePitch);
    if (_book.offlineVoiceName != null && _book.offlineVoiceLocale != null) {
      await _offlineTts.setVoice({
        'name': _book.offlineVoiceName!,
        'locale': _book.offlineVoiceLocale!,
      });
    } else {
      final locale = _detectLocale(_text);
      await _offlineTts.setLanguage(locale);
      for (final voice in _deviceVoices) {
        if (voice.locale.toLowerCase().startsWith(locale.substring(0, 2).toLowerCase())) {
          await _offlineTts.setVoice({'name': voice.name, 'locale': voice.locale});
          break;
        }
      }
    }
    _status = PlaybackStatus.playing;
    _safeNotify();
    final result = await _offlineTts.speak(_text.substring(from, chunk.end));
    if (result != 1) {
      throw const SpeechGenerationException(
        'Motorul vocal al telefonului nu a putut porni.',
      );
    }
  }

  Future<void> _playStudio() async {
    if (_loadedStudioChunk == _chunkIndex &&
        _studioPlayer.processingState == ProcessingState.ready &&
        _studioPlayer.position > Duration.zero) {
      _status = PlaybackStatus.playing;
      await _studioPlayer.setSpeed(_playbackRate);
      _safeNotify();
      unawaited(_studioPlayer.play());
      return;
    }

    _status = PlaybackStatus.loading;
    _safeNotify();
    final chunk = _chunks[_chunkIndex];
    final file = await neuralSpeech.audioFor(
      bookId: _book.id,
      text: chunk.text,
      voice: _book.studioVoice,
      preset: _book.preset,
      preferredRate: _playbackRate,
    );
    await _studioPlayer.setFilePath(file.path);
    await _studioPlayer.setSpeed(_playbackRate);
    _loadedStudioChunk = _chunkIndex;
    _status = PlaybackStatus.playing;
    _safeNotify();
    unawaited(_studioPlayer.play());
  }

  Future<void> _configureOfflineTts() async {
    await _offlineTts.awaitSpeakCompletion(false);
    _offlineTts.setProgressHandler((_, start, end, __) {
      if (_book.engine != ReadingEngine.offline || _manualStop) return;
      _currentCharacter = (_spokenBase + end).clamp(0, _text.length).toInt();
      _safeNotify();
    });
    _offlineTts.setCompletionHandler(() {
      if (!_manualStop &&
          _book.engine == ReadingEngine.offline &&
          _status == PlaybackStatus.playing) {
        unawaited(_onChunkCompleted());
      }
    });
    _offlineTts.setErrorHandler((message) {
      _status = PlaybackStatus.error;
      _errorMessage = 'Vocea offline a întâmpinat o problemă: $message';
      _safeNotify();
    });

    try {
      final rawVoices = await _offlineTts.getVoices;
      final parsed = <DeviceVoice>[];
      if (rawVoices is List) {
        for (final item in rawVoices) {
          if (item is! Map) continue;
          final name = item['name']?.toString();
          final locale = item['locale']?.toString();
          if (name == null || locale == null) continue;
          parsed.add(DeviceVoice(
            name: name,
            locale: locale,
            networkRequired: item['network_required'] == true ||
                item['network_required']?.toString() == 'true',
          ));
        }
      }
      parsed.sort((a, b) {
        final aRomanian = a.locale.toLowerCase().startsWith('ro') ? 0 : 1;
        final bRomanian = b.locale.toLowerCase().startsWith('ro') ? 0 : 1;
        final localeCompare = aRomanian.compareTo(bRomanian);
        return localeCompare != 0 ? localeCompare : a.label.compareTo(b.label);
      });
      final offline = parsed.where((voice) => !voice.networkRequired).toList();
      _deviceVoices = offline.isEmpty ? parsed : offline;
    } on Object {
      _deviceVoices = const [];
    }
  }

  void _configureStudioPlayer() {
    _subscriptions.add(
      _studioPlayer.playerStateStream.cast<Object?>().listen((event) {
        final state = event! as PlayerState;
        if (state.processingState == ProcessingState.completed &&
            !_manualStop &&
            _book.engine == ReadingEngine.studio &&
            _status == PlaybackStatus.playing) {
          unawaited(_onChunkCompleted());
        }
      }),
    );
    _subscriptions.add(
      _studioPlayer.positionStream.cast<Object?>().listen((event) {
        if (_book.engine != ReadingEngine.studio || _loadedStudioChunk == null) return;
        final position = event! as Duration;
        final duration = _studioPlayer.duration;
        if (duration == null || duration.inMilliseconds <= 0 || _chunks.isEmpty) return;
        final ratio = position.inMilliseconds / duration.inMilliseconds;
        final chunk = _chunks[_chunkIndex];
        _currentCharacter = (chunk.start + chunk.length * ratio)
            .round()
            .clamp(chunk.start, chunk.end)
            .toInt();
        _safeNotify();
      }),
    );
    _subscriptions.add(
      _studioPlayer.errorStream.cast<Object?>().listen((event) {
        _status = PlaybackStatus.error;
        _errorMessage = 'Fișierul audio nu a putut fi redat: $event';
        _safeNotify();
      }),
    );
  }

  Future<void> _onChunkCompleted() async {
    if (_chunks.isEmpty) return;
    if (_chunkIndex >= _chunks.length - 1) {
      _currentCharacter = _text.length;
      _status = PlaybackStatus.completed;
      await _persistProgress();
      _safeNotify();
      return;
    }
    _chunkIndex++;
    _currentCharacter = _chunks[_chunkIndex].start;
    _loadedStudioChunk = null;
    await _persistProgress();
    await play();
  }

  Future<void> _stopActive() async {
    _manualStop = true;
    await Future.wait([_offlineTts.stop(), _studioPlayer.stop()]);
    _manualStop = false;
  }

  Future<void> _persistProgress() async {
    _book = _book.copyWith(
      progressCharacter: _currentCharacter.clamp(0, _text.length).toInt(),
      lastOpenedAt: DateTime.now(),
    );
    await repository.update(_book);
  }

  static String _detectLocale(String text) {
    final sample = text.substring(0, text.length.clamp(0, 4000).toInt()).toLowerCase();
    if (RegExp('[ăâîșț]').hasMatch(sample) ||
        RegExp(r'\b(și|este|sunt|pentru|care|din|cu|la|un|o)\b')
                .allMatches(sample)
                .length >=
            4) {
      return 'ro-RO';
    }
    return 'en-US';
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_offlineTts.stop());
    unawaited(_studioPlayer.dispose());
    neuralSpeech.dispose();
    if (_initialized) unawaited(_persistProgress());
    super.dispose();
  }
}
