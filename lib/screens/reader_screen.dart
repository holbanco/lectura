import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/book_document.dart';
import '../models/narration_preset.dart';
import '../services/library_repository.dart';
import '../services/local_neural_speech_service.dart';
import '../services/neural_speech_service.dart';
import '../services/reader_session.dart';
import 'settings_screen.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({required this.repository, required this.book, super.key});
  final LibraryRepository repository;
  final BookDocument book;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final ReaderSession _session = ReaderSession(
    repository: widget.repository,
    book: widget.book,
  );
  late final Future<void> _initialization = _session.initialize();
  double? _seekPreview;
  String? _lastShownError;

  @override
  void initState() {
    super.initState();
    _session.addListener(_showNewSessionError);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Text('Documentul nu poate fi deschis: ${snapshot.error}'),
              ),
            ),
          );
        }
        return AnimatedBuilder(
          animation: _session,
          builder: (context, _) => _reader(context),
        );
      },
    );
  }

  Widget _reader(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_session.book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_session.book.chapters.isNotEmpty)
            IconButton(
              tooltip: 'Capitole',
              onPressed: _showChapters,
              icon: const Icon(Icons.format_list_numbered_rounded),
            ),
          IconButton(
            tooltip: 'Temporizator',
            onPressed: _showSleepTimer,
            icon: Icon(
              _session.sleepEndsAt == null
                  ? Icons.bedtime_outlined
                  : Icons.bedtime_rounded,
            ),
          ),
          IconButton(
            tooltip: 'Regie și voce',
            onPressed: _showNarrationSettings,
            icon: const Icon(Icons.record_voice_over_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoPill(icon: Icons.description_outlined, label: _session.book.format),
                      _InfoPill(
                        icon: Icons.theater_comedy_outlined,
                        label: _session.book.preset.shortLabel,
                      ),
                      _InfoPill(
                        icon: _session.isStudio
                            ? Icons.paid_outlined
                            : _session.isLocalNeural
                                ? Icons.offline_bolt_rounded
                                : Icons.phone_android_rounded,
                        label: _engineLabel,
                      ),
                      if (_session.book.usedOcr)
                        const _InfoPill(
                          icon: Icons.document_scanner_outlined,
                          label: 'OCR local',
                        ),
                    ],
                  ),
                  if (_session.errorMessage != null) ...[
                    const SizedBox(height: 22),
                    _ErrorCard(
                      message: _session.errorMessage!,
                      onSettings: _openSettings,
                    ),
                  ],
                  const SizedBox(height: 28),
                  Text(
                    [
                      if (_session.book
                              .chapterAt(_session.currentCharacter) !=
                          null)
                        _session.book
                            .chapterAt(_session.currentCharacter)!
                            .title,
                      'Fragment ${_session.currentChunkIndex + 1} din ${_session.chunks.length}',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 12),
                  _NarratedText(session: _session),
                  if (_session.usesGeneratedAudio) ...[
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 17),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            _session.isLocalNeural
                                ? 'Vocea este generată pe telefon. Următoarele două fragmente se pregătesc în avans pentru lectură fluidă.'
                                : 'OpenAI Premium poate genera costuri. Nu pregătim fragmente contra cost în avans.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          _PlayerPanel(
            session: _session,
            seekValue: _seekPreview ?? _session.progress,
            onSeekChanged: (value) => setState(() => _seekPreview = value),
            onSeekEnd: (value) async {
              setState(() => _seekPreview = null);
              await _session.seekTo(value);
            },
            onNarrationSettings: _showNarrationSettings,
          ),
        ],
      ),
    );
  }

  Future<void> _showNarrationSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => AnimatedBuilder(
        animation: _session,
        builder: (context, _) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              4,
              20,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Regia lecturii', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 18),
                Text('Motor', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ReadingEngine>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: ReadingEngine.offline,
                        icon: Icon(Icons.phone_android_rounded),
                        label: Text('Telefon'),
                      ),
                      ButtonSegment(
                        value: ReadingEngine.localNeural,
                        icon: Icon(Icons.offline_bolt_rounded),
                        label: Text('Neural'),
                      ),
                      ButtonSegment(
                        value: ReadingEngine.openAiPremium,
                        icon: Icon(Icons.paid_outlined),
                        label: Text('Premium'),
                      ),
                    ],
                    selected: {_session.book.engine},
                    onSelectionChanged: (selection) =>
                        _selectEngine(selection.first),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _session.isLocalNeural
                      ? 'Gratuit după descărcarea modelului · rulează pe telefon'
                      : _session.isStudio
                          ? 'OpenAI Fable · cost pe fiecare fragment nou'
                          : 'Motorul instalat în Android · rapid, dar mai robotic',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                Text('Stil și intonație', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                RadioGroup<NarrationPreset>(
                  groupValue: _session.book.preset,
                  onChanged: (value) {
                    if (value != null) _session.setPreset(value);
                  },
                  child: Column(
                    children: [
                      for (final preset in NarrationPreset.values)
                        RadioListTile<NarrationPreset>(
                          value: preset,
                          contentPadding: EdgeInsets.zero,
                          title: Text(preset.label),
                          subtitle: Text(preset.description),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_session.isStudio) ...[
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Premium generează cost. Nu există preîncărcare automată și schimbarea vitezei nu mai regenerează vocea.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Voce OpenAI',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _session.book.studioVoice,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.mic_rounded)),
                    items: [
                      for (final voice in NeuralSpeechService.voices)
                        DropdownMenuItem(
                          value: voice,
                          child: Text(
                            voice == _session.book.preset.recommendedVoice
                                ? '$voice · recomandată'
                                : voice,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) _session.setStudioVoice(value);
                    },
                  ),
                ] else if (_session.isLocalNeural) ...[
                  Text(
                    'Voce neurală locală',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _session.book.localVoice,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.spatial_audio_rounded),
                    ),
                    items: [
                      for (final voice in LocalNeuralSpeechService.voices)
                        DropdownMenuItem(
                          value: voice.id,
                          child: Text(
                            '${voice.label} · ${voice.description}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) _session.setLocalVoice(value);
                    },
                  ),
                  const SizedBox(height: 12),
                  if (_session.isPreparingBook) ...[
                    LinearProgressIndicator(
                      value: _session.preparationProgress,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Carte pregătită ${(100 * _session.preparationProgress).round()}%',
                    ),
                  ] else
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _prepareBook,
                        icon: const Icon(Icons.offline_pin_outlined),
                        label: const Text('Pregătește toată cartea offline'),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _openSettings,
                      child: const Text('Descarcă sau testează modelul local'),
                    ),
                  ),
                ] else ...[
                  Text('Vocea telefonului', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _deviceVoiceKey,
                    isExpanded: true,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.spatial_audio_rounded)),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Automat · limba documentului')),
                      for (final voice in _session.deviceVoices)
                        DropdownMenuItem(
                          value: '${voice.name}|${voice.locale}',
                          child: Text(voice.label, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null || value.isEmpty) {
                        _session.setDeviceVoice(null);
                        return;
                      }
                      final voice = _session.deviceVoices.where(
                        (item) => '${item.name}|${item.locale}' == value,
                      ).firstOrNull;
                      if (voice != null) _session.setDeviceVoice(voice);
                    },
                  ),
                ],
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _session.book.autoDirector,
                  onChanged: _session.setAutoDirector,
                  title: const Text('Regie automată'),
                  subtitle: const Text(
                    'Păstrează stilul potrivit tipului de document și punctuației.',
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Gata'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _engineLabel {
    switch (_session.book.engine) {
      case ReadingEngine.offline:
        return 'Vocea telefonului';
      case ReadingEngine.localNeural:
        return 'Neural local · ${_session.book.localVoice}';
      case ReadingEngine.openAiPremium:
        return 'Premium · ${_session.book.studioVoice}';
    }
  }

  Future<void> _selectEngine(ReadingEngine engine) async {
    if (engine == ReadingEngine.openAiPremium) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Folosești OpenAI Premium?'),
          content: const Text(
            'Fiecare fragment nou consumă credit API. Pentru lectura zilnică recomand Neural local, care nu costă pe minut.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Rămân pe local'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continuă Premium'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await _session.setEngine(engine);
    if (engine == ReadingEngine.localNeural &&
        !await LocalNeuralSpeechService.modelsReady() &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Modelul neural trebuie descărcat o singură dată.',
          ),
          action: SnackBarAction(label: 'Setări', onPressed: _openSettings),
        ),
      );
    }
  }

  Future<void> _prepareBook() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pregătești toată cartea?'),
        content: const Text(
          'Audio neural necomprimat poate ocupa între aproximativ 500 MB și 1,5 GB pentru o carte lungă. Poți asculta fluid și fără această pregătire: aplicația memorează automat fragmentele pe măsură ce citește.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anulează'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Pregătește'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _session.prepareWholeBook();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cartea este pregătită integral pentru ascultare offline.'),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _showChapters() async {
    final chapters = _session.book.chapters;
    if (chapters.isEmpty) return;
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.68,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  'Capitole',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: chapters.length,
                  itemBuilder: (context, index) {
                    final chapter = chapters[index];
                    final active = _session.book
                            .chapterAt(_session.currentCharacter)
                            ?.start ==
                        chapter.start;
                    return ListTile(
                      selected: active,
                      leading: CircleAvatar(child: Text('${index + 1}')),
                      title: Text(chapter.title),
                      trailing: active
                          ? const Icon(Icons.graphic_eq_rounded)
                          : null,
                      onTap: () => Navigator.pop(context, chapter.start),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) await _session.seekToCharacter(selected);
  }

  Future<void> _showSleepTimer() async {
    final duration = await showModalBottomSheet<Duration>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Temporizator de somn',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              for (final minutes in const [15, 30, 45, 60])
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text('$minutes minute'),
                  onTap: () =>
                      Navigator.pop(context, Duration(minutes: minutes)),
                ),
              if (_session.sleepEndsAt != null)
                ListTile(
                  leading: const Icon(Icons.timer_off_outlined),
                  title: const Text('Oprește temporizatorul'),
                  onTap: () => Navigator.pop(context, Duration.zero),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (duration == Duration.zero) {
      await _session.setSleepTimer(null);
    } else if (duration != null) {
      await _session.setSleepTimer(duration);
    }
  }

  String get _deviceVoiceKey {
    final name = _session.book.offlineVoiceName;
    final locale = _session.book.offlineVoiceLocale;
    if (name == null || locale == null) return '';
    final key = '$name|$locale';
    return _session.deviceVoices.any(
      (voice) => '${voice.name}|${voice.locale}' == key,
    )
        ? key
        : '';
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(repository: widget.repository),
    ));
  }

  void _showNewSessionError() {
    final message = _session.errorMessage;
    if (message == null) {
      _lastShownError = null;
      return;
    }
    if (!mounted || message == _lastShownError) return;
    _lastShownError = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _session.errorMessage != message) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 10),
            action: SnackBarAction(label: 'Setări', onPressed: _openSettings),
          ),
        );
    });
  }

  @override
  void dispose() {
    _session.removeListener(_showNewSessionError);
    _session.dispose();
    super.dispose();
  }
}

class _NarratedText extends StatelessWidget {
  const _NarratedText({required this.session});
  final ReaderSession session;

  @override
  Widget build(BuildContext context) {
    final chunk = session.currentChunk;
    if (chunk == null) return const Text('Nu există text de citit.');
    final localOffset = (session.currentCharacter - chunk.start)
        .clamp(0, chunk.text.length)
        .toInt();
    final read = chunk.text.substring(0, localOffset);
    final remaining = chunk.text.substring(localOffset);
    final base = Theme.of(context).textTheme.bodyLarge!.copyWith(
          fontSize: 20,
          height: 1.72,
        );
    return SelectionArea(
      child: RichText(
        text: TextSpan(
          style: base.copyWith(color: Theme.of(context).colorScheme.onSurface),
          children: [
            TextSpan(
              text: read,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
              ),
            ),
            TextSpan(text: remaining),
          ],
        ),
      ),
    );
  }
}

class _PlayerPanel extends StatelessWidget {
  const _PlayerPanel({
    required this.session,
    required this.seekValue,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.onNarrationSettings,
  });

  final ReaderSession session;
  final double seekValue;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final VoidCallback onNarrationSettings;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 14,
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: seekValue.clamp(0.0, 1.0).toDouble(),
                onChanged: onSeekChanged,
                onChangeEnd: onSeekEnd,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Text('${(seekValue * 100).round()}%'),
                    const Spacer(),
                    Text('aprox. ${session.remainingMinutes} min rămase'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => _chooseSpeed(context),
                    child: Text('${session.playbackRate.toStringAsFixed(2)}×'),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Fragmentul anterior',
                    onPressed: session.previous,
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  SizedBox.square(
                    dimension: 66,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.ink,
                      ),
                      onPressed: session.playPause,
                      child: session.isLoading
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : Icon(
                              session.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              size: 36,
                            ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Fragmentul următor',
                    onPressed: session.next,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                  IconButton(
                    tooltip: 'Regie și voce',
                    onPressed: onNarrationSettings,
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseSpeed(BuildContext context) async {
    final value = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Viteza lecturii', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final speed in const [0.75, 0.9, 1.0, 1.1, 1.25, 1.5])
                    ChoiceChip(
                      label: Text('${speed.toStringAsFixed(2)}×'),
                      selected: (session.playbackRate - speed).abs() < 0.01,
                      onSelected: (_) => Navigator.pop(context, speed),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (value != null) await session.setPlaybackRate(value);
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onSettings});
  final String message;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
            TextButton(onPressed: onSettings, child: const Text('Setări')),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
