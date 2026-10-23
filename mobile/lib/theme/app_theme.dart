import 'package:flutter/material.dart';

/// CookTogether design tokens: "a recipe card on the counter".
///
/// Warm paper, dark ink, one accent. Terracotta is only for the primary
/// action, green only means done or selected, amber only means timer or
/// attention. See `.claude/skills/cookalong-flutter-ui/SKILL.md`.
class CookTogetherTheme {
  CookTogetherTheme._();

  // Surfaces & text
  static const Color background = Color(0xFFFAF7EF);
  static const Color surface = Color(0xFFFFFDF8);
  static const Color line = Color(0xFFE8E3D6);
  static const Color ink = Color(0xFF28332A);
  static const Color inkMuted = Color(0xFF646B62);

  // Primary action
  static const Color accent = Color(0xFFC44A3A);
  static const Color onAccent = Colors.white;

  // Done / selected
  static const Color success = Color(0xFF4A7A36);
  static const Color successSoft = Color(0xFFE6F0DC);

  // Timer / attention
  static const Color warning = Color(0xFF9E5A1C);
  static const Color warningSoft = Color(0xFFFBE9D2);

  // Soft fills behind recipe emoji
  static Color toneBackground(String tone) {
    return switch (tone) {
      'green' => const Color(0xFFE2EFD8),
      'orange' => const Color(0xFFFBE6CE),
      'red' => const Color(0xFFF8DFD4),
      'yellow' => const Color(0xFFFFF0BF),
      _ => const Color(0xFFE2EFD8),
    };
  }

  // The app is a phone-width column; on wide screens it is centred.
  static const double maxContentWidth = 460;

  // Spacing
  static const double gutter = 20;
  static const double radiusControl = 12;
  static const double radiusCard = 16;

  // Emoji are drawn by the platform emoji font; naming it keeps them in
  // colour wherever the primary font lacks the glyph.
  static const List<String> _fallback = ['Noto Color Emoji'];

  static ThemeData buildTheme() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        primary: accent,
        onPrimary: onAccent,
        secondary: success,
        surface: surface,
        onSurface: ink,
        onSurfaceVariant: inkMuted,
        outline: line,
        outlineVariant: line,
      ),
    );

    TextStyle? style(
      TextStyle? s,
      double size,
      FontWeight weight, {
      double height = 1.3,
      double spacing = 0,
      Color color = ink,
    }) {
      return s?.copyWith(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: spacing,
        color: color,
        fontFamilyFallback: _fallback,
      );
    }

    final t = base.textTheme;
    final textTheme = t.copyWith(
      displaySmall: style(
        t.displaySmall,
        30,
        FontWeight.w800,
        height: 1.15,
        spacing: -0.6,
      ),
      headlineSmall: style(
        t.headlineSmall,
        24,
        FontWeight.w800,
        height: 1.2,
        spacing: -0.4,
      ),
      titleLarge: style(t.titleLarge, 20, FontWeight.w600, height: 1.35),
      titleMedium: style(t.titleMedium, 17, FontWeight.w700),
      titleSmall: style(t.titleSmall, 15, FontWeight.w700),
      bodyLarge: style(t.bodyLarge, 16, FontWeight.w400, height: 1.45),
      bodyMedium: style(
        t.bodyMedium,
        14,
        FontWeight.w400,
        height: 1.4,
        color: inkMuted,
      ),
      bodySmall: style(
        t.bodySmall,
        13,
        FontWeight.w400,
        height: 1.35,
        color: inkMuted,
      ),
      labelLarge: style(t.labelLarge, 15, FontWeight.w700),
      labelMedium: style(t.labelMedium, 13, FontWeight.w600),
    );

    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusControl),
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      dividerTheme: const DividerThemeData(color: line, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          disabledBackgroundColor: const Color(0xFFE9DDD6),
          disabledForegroundColor: inkMuted,
          minimumSize: const Size(64, 56),
          textStyle: textTheme.labelLarge,
          shape: controlShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(48, 48),
          textStyle: textTheme.labelLarge,
          shape: controlShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: line),
          textStyle: textTheme.labelLarge,
          shape: controlShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(48, 48),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: surface,
          foregroundColor: ink,
          selectedBackgroundColor: successSoft,
          selectedForegroundColor: success,
          side: const BorderSide(color: line),
          minimumSize: const Size(48, 48),
          textStyle: textTheme.labelMedium,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : inkMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? success : line,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? success : inkMuted,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: textTheme.bodyMedium,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: ink, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: const Color(0xFFF6DED8),
        height: 68,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => textTheme.labelMedium?.copyWith(
            color: s.contains(WidgetState.selected) ? accent : inkMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? accent : inkMuted,
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        // Match the app column instead of the whole browser window.
        constraints: BoxConstraints(maxWidth: maxContentWidth),
        dragHandleColor: line,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}
