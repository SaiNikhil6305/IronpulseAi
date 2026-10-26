import 'package:flutter/material.dart';

/// IronPulse design tokens: deep black, charcoal, electric orange used sparingly.
class IP {
  static const bg = Color(0xFF0A0A0A);
  static const surface = Color(0xFF151515);
  static const surface2 = Color(0xFF1F1F1F);
  static const border = Color(0xFF2A2A2A);
  static const accent = Color(0xFFFF6A00);
  static const text = Colors.white;
  static const muted = Color(0xFF9A9A9A);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
}

ThemeData buildTheme() {
  final radius = BorderRadius.circular(14);
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: IP.accent,
      onPrimary: Colors.black,
      secondary: IP.accent,
      surface: IP.surface,
      onSurface: IP.text,
      error: IP.error,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: IP.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: IP.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: IP.text),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: IP.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: IP.accent.withOpacity(0.18),
      height: 68,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: IP.surface2,
      hintStyle: const TextStyle(color: IP.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: IP.accent, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: IP.accent,
        foregroundColor: Colors.black,
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: IP.text,
        minimumSize: const Size(48, 52),
        side: const BorderSide(color: IP.border),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: IP.surface2,
      selectedColor: IP.accent.withOpacity(0.22),
      side: const BorderSide(color: IP.border),
      labelStyle: const TextStyle(color: IP.text, fontWeight: FontWeight.w600),
    ),
    dividerColor: IP.border,
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: IP.surface, surfaceTintColor: Colors.transparent),
  );
}
