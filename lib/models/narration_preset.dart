enum NarrationPreset {
  fiction,
  business,
  technical,
  dramatic,
  evening,
  neutral,
}

extension NarrationPresetInfo on NarrationPreset {
  String get key => name;

  String get label {
    switch (this) {
      case NarrationPreset.fiction:
        return 'Roman / ficțiune';
      case NarrationPreset.business:
        return 'Business';
      case NarrationPreset.technical:
        return 'Tehnic și clar';
      case NarrationPreset.dramatic:
        return 'Dramatic';
      case NarrationPreset.evening:
        return 'Calm, de seară';
      case NarrationPreset.neutral:
        return 'Natural';
    }
  }

  String get shortLabel {
    switch (this) {
      case NarrationPreset.fiction:
        return 'Ficțiune';
      case NarrationPreset.business:
        return 'Business';
      case NarrationPreset.technical:
        return 'Tehnic';
      case NarrationPreset.dramatic:
        return 'Dramatic';
      case NarrationPreset.evening:
        return 'Seară';
      case NarrationPreset.neutral:
        return 'Natural';
    }
  }

  String get description {
    switch (this) {
      case NarrationPreset.fiction:
        return 'Cald, cinematografic, cu dialog natural';
      case NarrationPreset.business:
        return 'Sigur, energic și ușor de urmărit';
      case NarrationPreset.technical:
        return 'Precis, rar și fără teatralitate inutilă';
      case NarrationPreset.dramatic:
        return 'Expresiv, tensionat și cu pauze controlate';
      case NarrationPreset.evening:
        return 'Moale, lent și liniștitor';
      case NarrationPreset.neutral:
        return 'Echilibrat și conversațional';
    }
  }

  String get recommendedVoice {
    switch (this) {
      case NarrationPreset.fiction:
        return 'fable';
      case NarrationPreset.business:
        return 'cedar';
      case NarrationPreset.technical:
        return 'marin';
      case NarrationPreset.dramatic:
        return 'onyx';
      case NarrationPreset.evening:
        return 'shimmer';
      case NarrationPreset.neutral:
        return 'marin';
    }
  }

  double get offlineRate {
    switch (this) {
      case NarrationPreset.technical:
        return 0.43;
      case NarrationPreset.dramatic:
        return 0.42;
      case NarrationPreset.evening:
        return 0.37;
      case NarrationPreset.business:
        return 0.48;
      case NarrationPreset.fiction:
      case NarrationPreset.neutral:
        return 0.44;
    }
  }

  double get offlinePitch {
    switch (this) {
      case NarrationPreset.evening:
        return 0.92;
      case NarrationPreset.dramatic:
        return 0.95;
      case NarrationPreset.business:
        return 1.02;
      case NarrationPreset.fiction:
      case NarrationPreset.technical:
      case NarrationPreset.neutral:
        return 1.0;
    }
  }

  String get studioInstructions {
    switch (this) {
      case NarrationPreset.fiction:
        return 'Perform as a professional audiobook narrator. Use warm cinematic storytelling, natural emotional variation, measured pauses, and subtly distinct dialogue delivery without caricature.';
      case NarrationPreset.business:
        return 'Read like a confident, engaging business audiobook narrator. Sound clear, energetic and intelligent. Emphasize conclusions and key contrasts, without sounding like an advertisement.';
      case NarrationPreset.technical:
        return 'Read with exceptional clarity and precision. Keep a steady measured cadence, articulate numbers and terminology carefully, and avoid unnecessary drama.';
      case NarrationPreset.dramatic:
        return 'Give a restrained professional dramatic performance. Build tension through cadence and pauses, vary emotional intensity naturally, and never become melodramatic.';
      case NarrationPreset.evening:
        return 'Read in a soft, intimate and reassuring bedtime-audiobook style. Use an unhurried cadence, gentle emotion and comfortable pauses. Never whisper so quietly that words become unclear.';
      case NarrationPreset.neutral:
        return 'Read naturally like an excellent professional narrator: warm, clear, conversational and expressive, with balanced pacing.';
    }
  }

  static NarrationPreset fromKey(String? value) {
    return NarrationPreset.values.where((item) => item.key == value).firstOrNull ??
        NarrationPreset.neutral;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
