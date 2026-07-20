import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../core/app_theme.dart';
import '../models/narration_preset.dart';
import '../services/app_audio_player.dart';
import '../services/library_repository.dart';
import '../services/local_neural_speech_service.dart';
import '../services/neural_speech_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.repository,
    this.beforeAudioPreview,
    super.key,
  });

  final LibraryRepository repository;
  final Future<void> Function()? beforeAudioPreview;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final NeuralSpeechService _speech = NeuralSpeechService(
    cacheDirectory: widget.repository.audioDirectory,
  );
  late final LocalNeuralSpeechService _localSpeech = LocalNeuralSpeechService(
    cacheDirectory: widget.repository.audioDirectory,
  );
  final TextEditingController _keyController = TextEditingController();
  final AudioPlayer _testPlayer = AppAudioPlayer.instance;
  String? _maskedKey;
  String _downloadLabel = '';
  double _downloadProgress = 0;
  int _cacheBytes = 0;
  bool _localReady = false;
  bool _saving = false;
  bool _testingPremium = false;
  bool _testingLocal = false;
  bool _downloadingModel = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<Object?>([
      _speech.readMaskedKey(),
      widget.repository.audioCacheSize(),
      LocalNeuralSpeechService.modelsReady(),
    ]);
    if (!mounted) return;
    setState(() {
      _maskedKey = results[0] as String?;
      _cacheBytes = results[1]! as int;
      _localReady = results[2]! as bool;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setări')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Text(
            'Voce neurală locală',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Varianta recomandată: expresivă, în română și fără cost pe carte. După prima descărcare funcționează fără internet.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          Card(
            color: _localReady
                ? Theme.of(context).colorScheme.secondaryContainer
                : null,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _localReady
                            ? Icons.offline_bolt_rounded
                            : Icons.download_for_offline_outlined,
                        color: _localReady ? AppColors.sage : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _localReady
                              ? 'Vocea locală este instalată'
                              : 'Model local necesar · aprox. 400 MB',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  if (_downloadingModel) ...[
                    const SizedBox(height: 18),
                    LinearProgressIndicator(
                      value: _downloadProgress > 0 ? _downloadProgress : null,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _downloadLabel.isEmpty
                          ? 'Se pregătește descărcarea…'
                          : _downloadLabel,
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: _localReady
                        ? OutlinedButton.icon(
                            onPressed: _testingLocal || _testingPremium
                                ? null
                                : _testLocalVoice,
                            icon: _testingLocal
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.play_circle_outline_rounded),
                            label: Text(
                              _testingLocal
                                  ? 'Se generează…'
                                  : 'Testează vocea Mara',
                            ),
                          )
                        : FilledButton.icon(
                            onPressed: _downloadingModel
                                ? null
                                : _confirmModelDownload,
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('Descarcă vocea locală'),
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 26),
          Text(
            'OpenAI · Premium',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.paid_outlined),
              title: const Text('Fable și vocile OpenAI'),
              subtitle: Text(
                _maskedKey == null
                    ? 'Opțional · neconfigurat · cost pe utilizare'
                    : 'Cheie salvată: $_maskedKey',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                const Text(
                  'Acest motor rămâne disponibil doar la alegerea ta. Aplicația nu mai pregătește fragmente OpenAI în avans și viteza de redare nu mai regenerează audio, pentru a evita consumul inutil.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _keyController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Cheie API OpenAI',
                    hintText: 'sk-…',
                    prefixIcon: Icon(Icons.password_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _saveKey,
                    child: Text(_saving ? 'Se salvează…' : 'Salvează cheia'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _maskedKey == null ||
                            _saving ||
                            _testingPremium ||
                            _testingLocal
                        ? null
                        : _testStudioVoice,
                    icon: _testingPremium
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_circle_outline_rounded),
                    label: Text(
                      _testingPremium
                          ? 'Se testează…'
                          : 'Testează Fable · generează cost',
                    ),
                  ),
                ),
                if (_maskedKey != null)
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _deleteKey,
                      child: const Text('Elimină cheia de pe telefon'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.security_rounded),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Documentele, progresul și vocea neurală locală rămân pe telefon. Cheia OpenAI este criptată în Android Keystore / Apple Keychain.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),
          Text('Stocare', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 8,
              ),
              leading: const Icon(Icons.graphic_eq_rounded),
              title: const Text('Fragmente audio memorate'),
              subtitle: Text(_formatBytes(_cacheBytes)),
              trailing: TextButton(
                onPressed: _cacheBytes == 0 ? null : _clearCache,
                child: const Text('Curăță'),
              ),
            ),
          ),
          const SizedBox(height: 30),
          Text(
            'Confidențialitate',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• Documentele și progresul rămân local pe telefon.'),
                  SizedBox(height: 8),
                  Text(
                    '• În modurile Telefon și Neural local, textul nu este trimis unui serviciu vocal.',
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• În modul OpenAI Premium, numai fragmentul ales pentru citire este trimis pentru generarea audio.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmModelDownload() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descarci vocea locală?'),
        content: const Text(
          'Descărcarea are aproximativ 400 MB. Recomand Wi-Fi și cel puțin 1 GB spațiu liber. Se face o singură dată.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Nu acum'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descarcă'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _downloadLocalModel();
  }

  Future<void> _downloadLocalModel() async {
    setState(() {
      _downloadingModel = true;
      _downloadProgress = 0;
      _downloadLabel = 'Se conectează…';
    });
    try {
      await LocalNeuralSpeechService.downloadModels(
        onProgress: (completed, total, file, progress) {
          if (!mounted) return;
          setState(() {
            _downloadProgress = total == 0
                ? progress
                : ((completed + progress) / total).clamp(0.0, 1.0);
            _downloadLabel =
                'Fișier ${completed + 1} din $total · ${(_downloadProgress * 100).round()}%';
          });
        },
      );
      await _load();
      _show('Vocea neurală locală este instalată și gata de citit.');
    } on Object catch (error) {
      _show('Descărcarea nu a reușit: $error');
    } finally {
      if (mounted) setState(() => _downloadingModel = false);
    }
  }

  Future<void> _testLocalVoice() async {
    setState(() => _testingLocal = true);
    try {
      await widget.beforeAudioPreview?.call();
      final file = await _localSpeech.audioFor(
        bookId: 'local_test',
        text:
            'Salut! Eu sunt Mara. Pot să îți citesc în română, expresiv, direct de pe telefon și fără costuri pe fragmente.',
        voice: 'F2',
        preset: NarrationPreset.fiction,
      );
      await _playPreview(
        filePath: file.path,
        title: 'Test voce Mara',
        artist: 'Lectura · Neural local',
      );
    } on Object catch (error) {
      _show(error.toString());
    } finally {
      if (mounted) setState(() => _testingLocal = false);
    }
  }

  Future<void> _saveKey() async {
    if (_keyController.text.trim().isEmpty) {
      _show('Introdu mai întâi cheia pe care vrei să o salvezi.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _speech.saveApiKey(_keyController.text);
      _keyController.clear();
      await _load();
      _show('Cheia a fost salvată securizat.');
    } on Object catch (error) {
      _show(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteKey() async {
    await _speech.deleteApiKey();
    await _load();
    _show('Cheia a fost eliminată.');
  }

  Future<void> _testStudioVoice() async {
    setState(() => _testingPremium = true);
    try {
      await widget.beforeAudioPreview?.call();
      final file = await _speech.audioFor(
        bookId: 'studio_test',
        text: 'Salut! Acesta este un test scurt pentru vocea Fable.',
        voice: 'fable',
        preset: NarrationPreset.fiction,
        preferredRate: 1,
        forceRefresh: true,
      );
      await _playPreview(
        filePath: file.path,
        title: 'Test voce Fable',
        artist: 'Lectura · OpenAI Premium',
      );
      _show('Test reușit. Fable este disponibilă.');
    } on Object catch (error) {
      _show(error.toString());
    } finally {
      if (mounted) setState(() => _testingPremium = false);
    }
  }

  Future<void> _playPreview({
    required String filePath,
    required String title,
    required String artist,
  }) async {
    await _testPlayer.stop();
    await _testPlayer.setAudioSource(
      AudioSource.file(
        filePath,
        tag: MediaItem(
          id: 'voice-preview:${filePath.hashCode}',
          title: title,
          album: 'Previzualizare voce',
          artist: artist,
        ),
      ),
    );
    await _testPlayer.setSpeed(1);
    await _testPlayer.play();
  }

  Future<void> _clearCache() async {
    final bytes = await widget.repository.clearAudioCache();
    await _load();
    _show('Am eliberat ${_formatBytes(bytes)}.');
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  void dispose() {
    _keyController.dispose();
    unawaited(_testPlayer.stop());
    _speech.dispose();
    _localSpeech.dispose();
    super.dispose();
  }
}
