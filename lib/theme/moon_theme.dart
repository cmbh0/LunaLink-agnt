import 'package:flutter/material.dart';

class MoonColors {
  static const bg = Color(0xFF090B14);
  static const panel = Color(0xFF111827);
  static const panel2 = Color(0xFF172033);
  static const edge = Color(0xFF2B3654);
  static const text = Color(0xFFE9ECF8);
  static const muted = Color(0xFF9AA4BF);
  static const moon = Color(0xFFDDE7FF);
  static const accent = Color(0xFF8AB4FF);
  static const purple = Color(0xFFB69CFF);
  static const danger = Color(0xFFFF6B8A);
  static const ok = Color(0xFF7CE7B2);
  static const warn = Color(0xFFFFD166);
}

class MoonTheme {
  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: MoonColors.accent,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        primary: MoonColors.accent,
        secondary: MoonColors.purple,
        surface: MoonColors.panel,
        background: MoonColors.bg,
        error: MoonColors.danger,
      ),
      scaffoldBackgroundColor: MoonColors.bg,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: MoonColors.text,
        centerTitle: false,
      ),
      cardTheme: CardTheme(
        color: MoonColors.panel.withOpacity(.92),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: MoonColors.edge),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MoonColors.panel2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: MoonColors.edge),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: MoonColors.edge),
        ),
      ),
    );
  }
}
