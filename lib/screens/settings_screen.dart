import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../services/library_repository.dart';
import '../services/neural_speech_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.repository, super.key});
  final LibraryRepository repository;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final NeuralSpeechService _speech = NeuralSpeechService(
    cacheDirectory: widget.repository.audioDirectory,
  );
  final TextEditingController _keyController = TextEditingController();
  String? _maskedKey;
  int _cacheBytes = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<Object?>([
      _speech.readMaskedKey(),
      widget.repository.audioCacheSize(),
    ]);
    if (!mounted) return;
    setState(() {
      _maskedKey = results[0] as String?;
      _cacheBytes = results[1]! as int;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setări')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Text('Voce Studio', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Pentru intonație de audiobook și interpretare expresivă. Necesită internet, o cheie API și poate genera costuri de utilizare. Modul offline nu are nevoie de cheie sau internet.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _maskedKey == null ? Icons.key_off_rounded : Icons.verified_user_rounded,
                        color: _maskedKey == null ? null : AppColors.sage,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _maskedKey == null
                              ? 'Vocea Studio nu este configurată'
                              : 'Cheie salvată: $_maskedKey',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
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
                      'Cheia este criptată în Android Keystore / Apple Keychain. Această opțiune este potrivită pentru aplicația ta personală. Pentru publicarea către alți utilizatori, cheia trebuie mutată pe un server securizat.',
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              leading: const Icon(Icons.graphic_eq_rounded),
              title: const Text('Audio Studio memorat'),
              subtitle: Text(_formatBytes(_cacheBytes)),
              trailing: TextButton(
                onPressed: _cacheBytes == 0 ? null : _clearCache,
                child: const Text('Curăță'),
              ),
            ),
          ),
          const SizedBox(height: 30),
          Text('Confidențialitate', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• Documentele și progresul rămân local pe telefon.'),
                  SizedBox(height: 8),
                  Text('• În modul offline, textul nu părăsește dispozitivul.'),
                  SizedBox(height: 8),
                  Text('• În modul Studio, numai fragmentul citit este trimis serviciului vocal pentru a genera audio.'),
                  SizedBox(height: 8),
                  Text('• Vocile Studio sunt generate de inteligență artificială, nu sunt înregistrări umane.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
    _speech.dispose();
    super.dispose();
  }
}
