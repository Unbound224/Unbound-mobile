import 'package:flutter/material.dart';

/// Brand tokens from brand/tokens.json. UI direction is intentionally revisable.
class Brand {
  static const primary = Color(0xFF7537F5);
  static const ink = Color(0xFF10092E);
  static const accent = Color(0xFFAD8AFF);
  static const surface = Color(0xFFFFFFFF);
  static const warning = Color(0xFF8A4B00);
  static const danger = Color(0xFFB00020);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: Brand.primary, primary: Brand.primary, onSurface: Brand.ink, surface: Brand.surface);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: Brand.surface,
    appBarTheme: const AppBarTheme(backgroundColor: Brand.ink, foregroundColor: Colors.white),
    // Large tap targets (>= 48dp) for every button.
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52))),
  );
}
