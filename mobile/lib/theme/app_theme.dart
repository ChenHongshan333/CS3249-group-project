import 'package:flutter/material.dart';

/// CookTogether warm kitchen color palette and typography tokens,
/// inspired by the original web prototype's ColorHunt palette.
class CookTogetherTheme {
  CookTogetherTheme._();

  // Core surfaces & text
  static const Color cream = Color(0xFFFAF7EF);
  static const Color surface = Color(0xFFFFFDF8);
  static const Color surfaceWarm = Color(0xFFFFFCF3);
  static const Color border = Color(0xFFEAE7DC);
  static const Color ink = Color(0xFF28332A);
  static const Color muted = Color(0xFF7D847B);

  // Primary four-color palette
  static const Color terracottaRed = Color(0xFFC44A3A);
  static const Color warmOrange = Color(0xFFD97A2B);
  static const Color butterYellow = Color(0xFFF2D479);
  static const Color herbGreen = Color(0xFF6FAF4F);
  static const Color deepHerbGreen = Color(0xFF456D31);

  // Soft tone fills for recipe art & status cards
  static const Color toneGreenBg = Color(0xFFE2EFD8);
  static const Color toneOrangeBg = Color(0xFFFBE6CE);
  static const Color toneRedBg = Color(0xFFF8DFD4);
  static const Color toneYellowBg = Color(0xFFFFF0BF);
  static const Color gentleNoteBg = Color(0xFFEDF3E7);
  static const Color gentleNoteFg = Color(0xFF536C4B);

  static Color toneBackground(String tone) {
    return switch (tone) {
      'green' => toneGreenBg,
      'orange' => toneOrangeBg,
      'red' => toneRedBg,
      'yellow' => toneYellowBg,
      _ => toneGreenBg,
    };
  }

  static Color toneAccent(String tone) {
    return switch (tone) {
      'green' => herbGreen,
      'orange' => warmOrange,
      'red' => terracottaRed,
      'yellow' => const Color(0xFFB98D22),
      _ => herbGreen,
    };
  }

  static TextStyle headingStyle({
    double fontSize = 24,
    FontWeight fontWeight = FontWeight.w800,
    Color color = ink,
    double height = 1.12,
    double letterSpacing = -0.6,
  }) {
    return TextStyle(
      fontFamily: '.SF UI Rounded',
      fontFamilyFallback: const [
        'Avenir Next',
        '.SF Pro Display',
        'Roboto',
        'sans-serif',
      ],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle bodyStyle({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w500,
    Color color = ink,
    double height = 1.45,
    double letterSpacing = 0,
  }) {
    return TextStyle(
      fontFamily: '.SF Pro Text',
      fontFamilyFallback: const [
        'Avenir Next',
        'Roboto',
        'sans-serif',
      ],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static ThemeData buildTheme() {
    final baseText = ThemeData.light().textTheme;
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: cream,
      colorScheme: ColorScheme.fromSeed(
        seedColor: terracottaRed,
        primary: terracottaRed,
        secondary: herbGreen,
        tertiary: warmOrange,
        surface: surface,
        onSurface: ink,
      ),
      textTheme: baseText.copyWith(
        displayLarge: headingStyle(fontSize: 32),
        headlineMedium: headingStyle(fontSize: 24),
        titleLarge: headingStyle(fontSize: 19),
        titleMedium: headingStyle(fontSize: 16, fontWeight: FontWeight.w700),
        bodyLarge: bodyStyle(fontSize: 15),
        bodyMedium: bodyStyle(fontSize: 13),
        bodySmall: bodyStyle(fontSize: 11, color: muted),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: border),
        ),
      ),
      dividerColor: border,
    );
  }
}
