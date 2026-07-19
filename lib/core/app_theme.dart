import 'package:flutter/material.dart';

abstract class AppColors {
  static const ink = Color(0xFF172019);
  static const forest = Color(0xFF1F3A2E);
  static const sage = Color(0xFF75937E);
  static const gold = Color(0xFFC89549);
  static const parchment = Color(0xFFF5F0E5);
  static const paper = Color(0xFFFFFCF5);
  static const night = Color(0xFF0E1511);
  static const nightSurface = Color(0xFF17211B);
}

abstract class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.forest,
      brightness: Brightness.light,
      surface: AppColors.paper,
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: AppColors.parchment,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
      ),
    );
  }

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.sage,
      brightness: Brightness.dark,
      surface: AppColors.nightSurface,
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: AppColors.night,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.parchment,
        elevation: 0,
      ),
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'serif',
      textTheme: const TextTheme(
        displaySmall: TextStyle(fontWeight: FontWeight.w700, height: 1.05),
        headlineSmall: TextStyle(fontWeight: FontWeight.w700, height: 1.15),
        titleLarge: TextStyle(fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(height: 1.55),
        bodyMedium: TextStyle(height: 1.45),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
        activeTrackColor: AppColors.gold,
        thumbColor: AppColors.gold,
      ),
    );
  }
}
