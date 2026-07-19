import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:pdfrx/pdfrx.dart';

import 'core/app_theme.dart';
import 'screens/home_screen.dart';
import 'services/library_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'ro.holban.lectura.audio',
    androidNotificationChannelName: 'Lectură audio',
    androidNotificationOngoing: true,
  );
  runApp(const LecturaApp());
}

class LecturaApp extends StatefulWidget {
  const LecturaApp({super.key});

  @override
  State<LecturaApp> createState() => _LecturaAppState();
}

class _LecturaAppState extends State<LecturaApp> {
  final LibraryRepository _repository = LibraryRepository();
  late final Future<void> _initialization = _repository.initialize();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lectura',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _LaunchScreen();
          }
          if (snapshot.hasError) {
            return _LaunchError(error: snapshot.error.toString());
          }
          return HomeScreen(repository: _repository);
        },
      ),
    );
  }
}

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_rounded, size: 54),
            SizedBox(height: 20),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class _LaunchError extends StatelessWidget {
  const _LaunchError({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 54),
              const SizedBox(height: 18),
              Text('Biblioteca nu a putut fi deschisă',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Text(error, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
