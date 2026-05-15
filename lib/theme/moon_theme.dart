import 'package:flutter/material.dart';

class MoonColors {
  static const bg = Color(0xFFFAFAFA);
  static const panel = Colors.white;
  static const panel2 = Color(0xFFF3F4F6);
  static const edge = Color(0xFFE0E0E0);
  static const text = Color(0xFF202124);
  static const muted = Color(0xFF5F6368);
  static const moon = Color(0xFF202124);
  static const accent = Color(0xFF6750A4);
  static const purple = Color(0xFF6750A4);
  static const danger = Color(0xFFBA1A1A);
  static const ok = Color(0xFF146C2E);
  static const warn = Color(0xFF7D5700);
}

class MoonTheme {
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: MoonColors.accent),
      );
}