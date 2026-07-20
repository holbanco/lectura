import 'package:just_audio/just_audio.dart';

/// The background-audio integration supports exactly one [AudioPlayer].
///
/// Reader sessions and voice previews therefore share this process-wide
/// instance. It intentionally lives until Android terminates the app process.
abstract final class AppAudioPlayer {
  static final AudioPlayer instance = AudioPlayer();
}
