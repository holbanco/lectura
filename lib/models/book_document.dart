import 'narration_preset.dart';

enum ReadingEngine { offline, studio }

class BookDocument {
  const BookDocument({
    required this.id,
    required this.title,
    required this.originalFileName,
    required this.format,
    required this.textFileName,
    required this.importedAt,
    required this.lastOpenedAt,
    required this.characterCount,
    this.progressCharacter = 0,
    this.preset = NarrationPreset.neutral,
    this.engine = ReadingEngine.offline,
    this.studioVoice = 'marin',
    this.offlineVoiceName,
    this.offlineVoiceLocale,
    this.colorSeed = 0,
  });

  final String id;
  final String title;
  final String originalFileName;
  final String format;
  final String textFileName;
  final DateTime importedAt;
  final DateTime lastOpenedAt;
  final int characterCount;
  final int progressCharacter;
  final NarrationPreset preset;
  final ReadingEngine engine;
  final String studioVoice;
  final String? offlineVoiceName;
  final String? offlineVoiceLocale;
  final int colorSeed;

  double get progress => characterCount == 0
      ? 0
      : (progressCharacter / characterCount).clamp(0.0, 1.0).toDouble();

  BookDocument copyWith({
    String? title,
    DateTime? lastOpenedAt,
    int? progressCharacter,
    NarrationPreset? preset,
    ReadingEngine? engine,
    String? studioVoice,
    String? offlineVoiceName,
    String? offlineVoiceLocale,
    bool clearOfflineVoice = false,
  }) {
    return BookDocument(
      id: id,
      title: title ?? this.title,
      originalFileName: originalFileName,
      format: format,
      textFileName: textFileName,
      importedAt: importedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      characterCount: characterCount,
      progressCharacter: progressCharacter ?? this.progressCharacter,
      preset: preset ?? this.preset,
      engine: engine ?? this.engine,
      studioVoice: studioVoice ?? this.studioVoice,
      offlineVoiceName:
          clearOfflineVoice ? null : offlineVoiceName ?? this.offlineVoiceName,
      offlineVoiceLocale:
          clearOfflineVoice ? null : offlineVoiceLocale ?? this.offlineVoiceLocale,
      colorSeed: colorSeed,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'originalFileName': originalFileName,
        'format': format,
        'textFileName': textFileName,
        'importedAt': importedAt.toIso8601String(),
        'lastOpenedAt': lastOpenedAt.toIso8601String(),
        'characterCount': characterCount,
        'progressCharacter': progressCharacter,
        'preset': preset.key,
        'engine': engine.name,
        'studioVoice': studioVoice,
        'offlineVoiceName': offlineVoiceName,
        'offlineVoiceLocale': offlineVoiceLocale,
        'colorSeed': colorSeed,
      };

  factory BookDocument.fromJson(Map<String, Object?> json) {
    return BookDocument(
      id: json['id']! as String,
      title: json['title']! as String,
      originalFileName: json['originalFileName']! as String,
      format: json['format']! as String,
      textFileName: json['textFileName']! as String,
      importedAt: DateTime.parse(json['importedAt']! as String),
      lastOpenedAt: DateTime.parse(json['lastOpenedAt']! as String),
      characterCount: (json['characterCount']! as num).toInt(),
      progressCharacter: (json['progressCharacter'] as num?)?.toInt() ?? 0,
      preset: NarrationPresetInfo.fromKey(json['preset'] as String?),
      engine: ReadingEngine.values.where(
        (item) => item.name == json['engine'],
      ).firstOrNull ?? ReadingEngine.offline,
      studioVoice: json['studioVoice'] as String? ?? 'marin',
      offlineVoiceName: json['offlineVoiceName'] as String?,
      offlineVoiceLocale: json['offlineVoiceLocale'] as String?,
      colorSeed: (json['colorSeed'] as num?)?.toInt() ?? 0,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
