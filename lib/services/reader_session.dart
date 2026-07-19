import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import '../models/book_document.dart';
import '../models/narration_preset.dart';
import '../models/text_chunk.dart';
import 'library_repository.dart';
import 'local_neural_speech_service.dart';
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
        ),
        localSpeech = LocalNeuralSpeechService(
          cacheDirectory: repository.audioDirectory,
        );

  final LibraryRepository repository;
  final NeuralSpeechService neuralSpeech;
  final LocalNeuralSpeechService localSpeech;
  final FlutterTts _offlineTts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final List<int> _queuedChunks = [];
  final Map<int, Future<File>> _audioFutures = {};

  BookDocument _book;
  String _text = '';
  List<TextChunk> _chunks = const [];
  List<DeviceVoice> _deviceVoices = const [];
  PlaybackStatus _status = PlaybackStatus.idle;
  int _chunkIndex = 0;
  int _currentCharacter = 0;
  int _spokenBase = 0;
  int _generationEpoch = 0;
  double _playbackRate = 1.0;
  double _preparationProgress = 0;
  String? _errorMessage;
  bool _initialized = false;
  bool _disposed = false;
  bool _manualStop = false;
  bool _fillingBuffer = false;
  bool _preparingBook = false;
  Timer? _sleepTimer;
  DateTime? _sleepEndsAt;

  BookDocument get book => _book;
  String get text => _text;
  List<TextChunk> get chunks => _chunks;
  List<DeviceVoice> get deviceVoices => _deviceVoices;
  PlaybackStatus get status => _status;
  bool get isPlaying => _status == PlaybackStatus.playing;
  bool get isLoading => _status == PlaybackStatus.loading;
  bool get isStudio => _book.engine == ReadingEngine.openAiPremium;
  bool get isLocalNeural => _book.engine == ReadingEngine.localNeural;
  bool get usesGeneratedAudio => _book.engine != ReadingEngine.offline;
  bool get isPreparingBook => _preparingBook;
  double get preparationProgress => _preparationProgress;
  DateTime? get sleepEndsAt => _sleepEndsAt;
  int get currentCharacter => _currentCharacter;
  int get currentChunkIndex => _chunkIndex;
  double get playbackRate => _playbackRate;
  String? get errorMessage => _errorMessage;

  double get progress => _text.isEmpty
      ? 0
      : (_currentCharacter / _text.length).clamp(0.0, 1.0).toDouble();

  TextChunk? get currentChunk => _chunks.isEmpty
      ? null
      : _chunks[_chunkIndex.clamp(0, _chunks.length - 1).toInt()];

  int get remainingMinutes {
    final remaining =
        (_text.length - _currentCharacter).clamp(0, _text.length).toInt();
    final charactersPerMinute = (930 * _playbackRate).round();
    return charactersPerMinute == 0
        ? 0
        : (remaining / charactersPerMinute).ceil();
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
    final audioSession = await AudioSession.instance;
    await audioSession.configure(AudioSessionConfiguration.speech());
    _configureAudioPlayer();
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
        await _playGenerated();
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
      await _player.pause();
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
    _status = PlaybackStatus.paused;
    await _persistProgress();
    _safeNotify();
    if (resume) await play();
  }

  Future<void> seekTo(double normalized) async {
    await seekToCharacter(
      (_text.length * normalized.clamp(0.0, 1.0)).round(),
    );
  }

  Future<void> seekToCharacter(int character) async {
    if (_chunks.isEmpty) return;
    final resume = isPlaying || isLoading;
    await _stopActive();
    _currentCharacter = character.clamp(0, _text.length).toInt();
    _chunkIndex = TextChunker.chunkIndexForOffset(_chunks, _currentCharacter);
    _currentCharacter = _currentCharacter.clamp(
      _chunks[_chunkIndex].start,
      _chunks[_chunkIndex].end - 1,
    ).toInt();
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
    await repository.update(_book);
    _status = PlaybackStatus.paused;
    _safeNotify();
    if (resume) await play();
  }

  Future<void> setStudioVoice(String voice) async {
    if (_book.studioVoice == voice ||
        !NeuralSpeechService.voices.contains(voice)) {
      return;
    }
    final resume = isPlaying || isLoading;
    await _stopActive();
    _book = _book.copyWith(studioVoice: voice, lastOpenedAt: DateTime.now());
    await repository.update(_book);
    _status = PlaybackStatus.paused;
    _safeNotify();
    if (resume) await play();
  }

  Future<void> setLocalVoice(String voice) async {
    if (_book.localVoice == voice ||
        !LocalNeuralSpeechService.voices.any((item) => item.id == voice)) {
      return;
    }
    final resume = isPlaying || isLoading;
    await _stopActive();
    _book = _book.copyWith(localVoice: voice, lastOpenedAt: DateTime.now());
    await repository.update(_book);
    _status = PlaybackStatus.paused;
    _safeNotify();
    if (resume) await play();
  }

  Future<void> setAutoDirector(bool enabled) async {
    _book = _book.copyWith(autoDirector: enabled, lastOpenedAt: DateTime.now());
    await repository.update(_book);
    _safeNotify();
  }

  Future<void> setDeviceVoice(DeviceVoice? voice) async {
    final resume = isPlaying || isLoading;
    await _stopActive();
    if (voice == null) {
      _book = _book.copyWith(
        clearOfflineVoice: true,
        lastOpenedAt: DateTime.now(),
      );
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
    if (usesGeneratedAudio) {
      await _player.setSpeed(safe);
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

  Future<void> setSleepTimer(Duration? duration) async {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepEndsAt = null;
    if (duration != null) {
      _sleepEndsAt = DateTime.now().add(duration);
      _sleepTimer = Timer(duration, () {
        unawaited(pause());
        _sleepEndsAt = null;
        _sleepTimer = null;
        _safeNotify();
      });
    }
    _safeNotify();
  }

  Future<void> prepareWholeBook() async {
    if (_preparingBook || _chunks.isEmpty) return;
    if (_book.engine != ReadingEngine.localNeural) {
      throw const LocalNeuralSpeechException(
        'Pregătirea integrală este disponibilă doar pentru vocea neurală locală, fără cost.',
      );
    }
    if (!await LocalNeuralSpeechService.modelsReady()) {
      throw const LocalModelMissingException();
    }
    _preparingBook = true;
    _preparationProgress = 0;
    final preparationEpoch = _generationEpoch;
    final voice = _book.localVoice;
    _safeNotify();
    try {
      for (var index = 0; index < _chunks.length; index++) {
        if (_book.engine != ReadingEngine.localNeural ||
            preparationEpoch != _generationEpoch) {
          throw const LocalNeuralSpeechException(
            'Pregătirea cărții a fost oprită.',
          );
        }
        final chunk = _chunks[index];
        await localSpeech.audioFor(
          bookId: _book.id,
          text: chunk.text,
          voice: voice,
          preset: _directedPreset(chunk),
        );
        _preparationProgress = (index + 1) / _chunks.length;
        _safeNotify();
      }
    } finally {
      _preparingBook = false;
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
        if (voice.locale
            .toLowerCase()
            .startsWith(locale.substring(0, 2).toLowerCase())) {
          await _offlineTts.setVoice({
            'name': voice.name,
            'locale': voice.locale,
          });
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

  Future<void> _playGenerated() async {
    final queuedIndex = _queuedChunks.indexOf(_chunkIndex);
    if (queuedIndex >= 0 &&
        _player.processingState != ProcessingState.completed) {
      if (_player.currentIndex != queuedIndex) {
        await _player.seek(Duration.zero, index: queuedIndex);
      }
      await _player.setSpeed(_playbackRate);
      _status = PlaybackStatus.playing;
      _safeNotify();
      unawaited(_player.play());
      unawaited(_fillBuffer(_generationEpoch));
      return;
    }

    final epoch = ++_generationEpoch;
    _queuedChunks.clear();
    _status = PlaybackStatus.loading;
    _safeNotify();
    final file = await _audioForChunk(_chunkIndex);
    if (epoch != _generationEpoch || _disposed) return;
    _queuedChunks.add(_chunkIndex);
    await _player.setAudioSources([_sourceFor(_chunkIndex, file)]);
    await _player.setSpeed(_playbackRate);
    _status = PlaybackStatus.playing;
    _safeNotify();
    unawaited(_player.play());
    unawaited(_fillBuffer(epoch));
  }

  Future<void> _fillBuffer(int epoch) async {
    if (_fillingBuffer || _book.engine != ReadingEngine.localNeural) return;
    _fillingBuffer = true;
    try {
      while (epoch == _generationEpoch && !_disposed) {
        final last = _queuedChunks.isEmpty ? _chunkIndex : _queuedChunks.last;
        final ahead = last - _chunkIndex;
        if (ahead >= 2 || last >= _chunks.length - 1) break;
        final next = last + 1;
        final file = await _audioForChunk(next);
        if (epoch != _generationEpoch || _disposed) return;
        if (_queuedChunks.contains(next)) continue;
        _queuedChunks.add(next);
        await _player.addAudioSource(_sourceFor(next, file));
        if (_player.processingState == ProcessingState.completed &&
            (_status == PlaybackStatus.playing ||
                _status == PlaybackStatus.loading)) {
          final queueIndex = _queuedChunks.indexOf(next);
          await _player.seek(Duration.zero, index: queueIndex);
          _status = PlaybackStatus.playing;
          _safeNotify();
          unawaited(_player.play());
        }
      }
    } on Object catch (error) {
      if (epoch == _generationEpoch && !_disposed) {
        _errorMessage = 'Bufferul următor nu a putut fi pregătit: $error';
        _safeNotify();
      }
    } finally {
      _fillingBuffer = false;
    }
  }

  Future<File> _audioForChunk(int index) {
    return _audioFutures.putIfAbsent(index, () {
      final chunk = _chunks[index];
      final directedPreset = _directedPreset(chunk);
      if (_book.engine == ReadingEngine.localNeural) {
        return localSpeech.audioFor(
          bookId: _book.id,
          text: chunk.text,
          voice: _book.localVoice,
          preset: directedPreset,
        );
      }
      return neuralSpeech.audioFor(
        bookId: _book.id,
        text: chunk.text,
        voice: _book.studioVoice,
        preset: directedPreset,
        preferredRate: 1,
      );
    });
  }

  NarrationPreset _directedPreset(TextChunk chunk) {
    if (!_book.autoDirector ||
        _book.preset == NarrationPreset.technical ||
        _book.preset == NarrationPreset.evening) {
      return _book.preset;
    }
    final dialogueMarks = RegExp('[„”«»"]|(^|\n)\\s*[—–-]\\s+')
        .allMatches(chunk.text)
        .length;
    final emotionalMarks = RegExp('[!?…]').allMatches(chunk.text).length;
    if (dialogueMarks >= 4 || emotionalMarks >= 5) {
      return NarrationPreset.dramatic;
    }
    return _book.preset;
  }

  AudioSource _sourceFor(int chunkIndex, File file) {
    final cover = repository.coverFile(_book);
    return AudioSource.file(
      file.path,
      tag: MediaItem(
        id: '${_book.id}:$chunkIndex',
        title: _book.title,
        album: 'Fragment ${chunkIndex + 1} din ${_chunks.length}',
        artist: _book.engine == ReadingEngine.localNeural
            ? 'Lectura · Neural local'
            : 'Lectura · OpenAI Premium',
        artUri: cover == null ? null : Uri.file(cover.path),
      ),
    );
  }

  Future<void> _configureOfflineTts() async {
    await _offlineTts.awaitSpeakCompletion(false);
    _offlineTts.setProgressHandler((_, _, end, _) {
      if (_book.engine != ReadingEngine.offline || _manualStop) return;
      _currentCharacter = (_spokenBase + end).clamp(0, _text.length).toInt();
      _safeNotify();
    });
    _offlineTts.setCompletionHandler(() {
      if (!_manualStop &&
          _book.engine == ReadingEngine.offline &&
          _status == PlaybackStatus.playing) {
        unawaited(_onOfflineChunkCompleted());
      }
    });
    _offlineTts.setErrorHandler((message) {
      _status = PlaybackStatus.error;
      _errorMessage = 'Vocea telefonului a întâmpinat o problemă: $message';
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
        return localeCompare != 0
            ? localeCompare
            : a.label.compareTo(b.label);
      });
      final offline = parsed.where((voice) => !voice.networkRequired).toList();
      _deviceVoices = offline.isEmpty ? parsed : offline;
    } on Object {
      _deviceVoices = const [];
    }
  }

  void _configureAudioPlayer() {
    _subscriptions.add(
      _player.currentIndexStream.cast<Object?>().listen((event) {
        final queueIndex = event as int?;
        if (queueIndex == null ||
            queueIndex < 0 ||
            queueIndex >= _queuedChunks.length ||
            !usesGeneratedAudio) {
          return;
        }
        final newChunk = _queuedChunks[queueIndex];
        if (newChunk != _chunkIndex) {
          _chunkIndex = newChunk;
          _currentCharacter = _chunks[newChunk].start;
          unawaited(_persistProgress());
        }
        if (_status == PlaybackStatus.loading) _status = PlaybackStatus.playing;
        _safeNotify();
        unawaited(_fillBuffer(_generationEpoch));
      }),
    );
    _subscriptions.add(
      _player.processingStateStream.cast<Object?>().listen((event) {
        final state = event! as ProcessingState;
        if (state == ProcessingState.completed &&
            !_manualStop &&
            usesGeneratedAudio &&
            (_status == PlaybackStatus.playing ||
                _status == PlaybackStatus.loading)) {
          unawaited(_onGeneratedQueueCompleted());
        }
      }),
    );
    _subscriptions.add(
      _player.positionStream.cast<Object?>().listen((event) {
        if (!usesGeneratedAudio || _queuedChunks.isEmpty) return;
        final queueIndex = _player.currentIndex;
        if (queueIndex == null || queueIndex >= _queuedChunks.length) return;
        final position = event! as Duration;
        final duration = _player.duration;
        if (duration == null || duration.inMilliseconds <= 0) return;
        final chunkIndex = _queuedChunks[queueIndex];
        final chunk = _chunks[chunkIndex];
        final ratio = position.inMilliseconds / duration.inMilliseconds;
        _currentCharacter = (chunk.start + chunk.length * ratio)
            .round()
            .clamp(chunk.start, chunk.end)
            .toInt();
        _safeNotify();
      }),
    );
    _subscriptions.add(
      _player.errorStream.cast<Object?>().listen((event) {
        _status = PlaybackStatus.error;
        _errorMessage = 'Fișierul audio nu a putut fi redat: $event';
        _safeNotify();
      }),
    );
  }

  Future<void> _onOfflineChunkCompleted() async {
    if (_chunks.isEmpty) return;
    if (_chunkIndex >= _chunks.length - 1) {
      await _completeBook();
      return;
    }
    _chunkIndex++;
    _currentCharacter = _chunks[_chunkIndex].start;
    await _persistProgress();
    await play();
  }

  Future<void> _onGeneratedQueueCompleted() async {
    if (_chunks.isEmpty) return;
    final lastPlayed = _queuedChunks.isEmpty ? _chunkIndex : _queuedChunks.last;
    if (lastPlayed >= _chunks.length - 1) {
      await _completeBook();
      return;
    }
    _chunkIndex = lastPlayed + 1;
    _currentCharacter = _chunks[_chunkIndex].start;
    await _persistProgress();
    // OpenAI deliberately generates only after the user reaches the boundary;
    // local neural audio is normally already queued two fragments ahead.
    await _playGenerated();
  }

  Future<void> _completeBook() async {
    _currentCharacter = _text.length;
    _status = PlaybackStatus.completed;
    await _persistProgress();
    _safeNotify();
  }

  Future<void> _stopActive() async {
    _generationEpoch++;
    _manualStop = true;
    await Future.wait([_offlineTts.stop(), _player.stop()]);
    _manualStop = false;
    _queuedChunks.clear();
    _audioFutures.clear();
    _fillingBuffer = false;
  }

  Future<void> _persistProgress() async {
    _book = _book.copyWith(
      progressCharacter: _currentCharacter.clamp(0, _text.length).toInt(),
      lastOpenedAt: DateTime.now(),
    );
    await repository.update(_book);
  }

  static String _detectLocale(String text) {
    final sample = text
        .substring(0, text.length.clamp(0, 4000).toInt())
        .toLowerCase();
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
    _sleepTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_offlineTts.stop());
    unawaited(_player.dispose());
    neuralSpeech.dispose();
    localSpeech.dispose();
    if (_initialized) unawaited(_persistProgress());
    super.dispose();
  }
}
