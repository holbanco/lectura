import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/book_document.dart';
import '../models/narration_preset.dart';
import '../services/library_repository.dart';
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
                        icon: _session.isStudio ? Icons.auto_awesome_rounded : Icons.phone_android_rounded,
                        label: _session.isStudio ? 'Studio · ${_session.book.studioVoice}' : 'Offline',
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Fragment ${_session.currentChunkIndex + 1} din ${_session.chunks.length}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 12),
                  _NarratedText(session: _session),
                  if (_session.errorMessage != null) ...[
                    const SizedBox(height: 24),
                    _ErrorCard(
                      message: _session.errorMessage!,
                      onSettings: _openSettings,
                    ),
                  ],
                  if (_session.isStudio) ...[
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 17),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'Voce generată cu AI. Fragmentul este memorat local după prima redare.',
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
                    segments: const [
                      ButtonSegment(
                        value: ReadingEngine.offline,
                        icon: Icon(Icons.phone_android_rounded),
                        label: Text('Offline'),
                      ),
                      ButtonSegment(
                        value: ReadingEngine.studio,
                        icon: Icon(Icons.auto_awesome_rounded),
                        label: Text('Studio'),
                      ),
                    ],
                    selected: {_session.book.engine},
                    onSelectionChanged: (selection) => _session.setEngine(selection.first),
                  ),
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
                  Text('Voce Studio', style: Theme.of(context).textTheme.titleMedium),
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

  @override
  void dispose() {
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
