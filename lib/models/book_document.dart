import 'document_chapter.dart';
import 'narration_preset.dart';

enum ReadingEngine { offline, localNeural, openAiPremium }

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
    this.engine = ReadingEngine.localNeural,
    this.studioVoice = 'marin',
    this.localVoice = 'F2',
    this.offlineVoiceName,
    this.offlineVoiceLocale,
    this.colorSeed = 0,
    this.chapters = const [],
    this.coverFileName,
    this.usedOcr = false,
    this.autoDirector = true,
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
  final String localVoice;
  final String? offlineVoiceName;
  final String? offlineVoiceLocale;
  final int colorSeed;
  final List<DocumentChapter> chapters;
  final String? coverFileName;
  final bool usedOcr;
  final bool autoDirector;

  double get progress => characterCount == 0
      ? 0
      : (progressCharacter / characterCount).clamp(0.0, 1.0).toDouble();

  DocumentChapter? chapterAt(int character) {
    if (chapters.isEmpty) return null;
    var result = chapters.first;
    for (final chapter in chapters) {
      if (chapter.start > character) break;
      result = chapter;
    }
    return result;
  }

  BookDocument copyWith({
    String? title,
    DateTime? lastOpenedAt,
    int? progressCharacter,
    NarrationPreset? preset,
    ReadingEngine? engine,
    String? studioVoice,
    String? localVoice,
    String? offlineVoiceName,
    String? offlineVoiceLocale,
    bool clearOfflineVoice = false,
    bool? autoDirector,
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
      localVoice: localVoice ?? this.localVoice,
      offlineVoiceName:
          clearOfflineVoice ? null : offlineVoiceName ?? this.offlineVoiceName,
      offlineVoiceLocale:
          clearOfflineVoice ? null : offlineVoiceLocale ?? this.offlineVoiceLocale,
      colorSeed: colorSeed,
      chapters: chapters,
      coverFileName: coverFileName,
      usedOcr: usedOcr,
      autoDirector: autoDirector ?? this.autoDirector,
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
        'localVoice': localVoice,
        'offlineVoiceName': offlineVoiceName,
        'offlineVoiceLocale': offlineVoiceLocale,
        'colorSeed': colorSeed,
        'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
        'coverFileName': coverFileName,
        'usedOcr': usedOcr,
        'autoDirector': autoDirector,
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
      // v0.x stored OpenAI as "studio". Migrate it to the free local engine so
      // upgrading the app can never spend API credit merely by pressing Play.
      engine: json['engine'] == 'studio'
          ? ReadingEngine.localNeural
          : ReadingEngine.values.where(
                  (item) => item.name == json['engine'],
                ).firstOrNull ??
              ReadingEngine.localNeural,
      studioVoice: json['studioVoice'] as String? ?? 'marin',
      localVoice: json['localVoice'] as String? ?? 'F2',
      offlineVoiceName: json['offlineVoiceName'] as String?,
      offlineVoiceLocale: json['offlineVoiceLocale'] as String?,
      colorSeed: (json['colorSeed'] as num?)?.toInt() ?? 0,
      chapters: (json['chapters'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((item) => DocumentChapter.fromJson(
                    item.cast<String, Object?>(),
                  ))
              .toList() ??
          const [],
      coverFileName: json['coverFileName'] as String?,
      usedOcr: json['usedOcr'] as bool? ?? false,
      autoDirector: json['autoDirector'] as bool? ?? true,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
