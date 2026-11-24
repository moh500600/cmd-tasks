import 'package:flutter/material.dart';

class AppTheme {
  static const seed = Color(0xFF5B5BD6);

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: b);
    final dark = b == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Tajawal',
      scaffoldBackgroundColor: dark ? const Color(0xFF111218) : const Color(0xFFF6F6FB),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: dark ? const Color(0xFF111218) : const Color(0xFFF6F6FB),
        titleTextStyle: TextStyle(
            fontFamily: 'Tajawal', fontSize: 20, fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xFF1C1D26) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF1C1D26) : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }

  static const priorityColors = [
    Color(0xFF64748B), // low
    Color(0xFF0EA5E9), // medium
    Color(0xFFF59E0B), // high
    Color(0xFFEF4444), // urgent
  ];

  static const statusColors = {
    'todo': Color(0xFF94A3B8),
    'inProgress': Color(0xFF3B82F6),
    'completed': Color(0xFF16A34A),
    'postponed': Color(0xFFA855F7),
  };

  static const palette = [
    0xFF5B5BD6, 0xFF0EA5E9, 0xFF16A34A, 0xFFF59E0B,
    0xFFEF4444, 0xFFEC4899, 0xFF8B5CF6, 0xFF14B8A6, 0xFF64748B, 0xFFF97316,
  ];
}
