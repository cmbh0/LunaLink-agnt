import 'package:flutter/material.dart';

class MoonColors {
  static const bg = Color(0xFFFAFAFA);
  static const panel = Colors.white;
  static const panel2 = Color(0xFFF3F4F6);
  static const edge = Color(0xFFE6E6E6);
  static const text = Color(0xFF111111);
  static const muted = Color(0xFF8A8A8A);
  static const moon = Color(0xFF111111);
  static const accent = Color(0xFF5B2CCB);
  static const purple = Color(0xFF5B2CCB);
  static const danger = Color(0xFFD32F2F);
  static const ok = Color(0xFF2E7D32);
  static const warn = Color(0xFFF57C00);
}

class MoonTheme {
  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(seedColor: MoonColors.accent);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: MoonColors.bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: MoonColors.bg,
        foregroundColor: MoonColors.text,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardTheme(
        color: MoonColors.panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: MoonColors.edge),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MoonColors.panel2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: MoonColors.accent),
        ),
      ),
    );
  }
}
