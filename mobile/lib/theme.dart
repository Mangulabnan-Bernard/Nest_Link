import 'package:flutter/material.dart';

/// Nest Link design system — a friendly, light, accessible look for a community
/// safety platform. (Member names kept stable so existing screens re-skin
/// automatically; they get proper per-screen redesigns in the redesign sprints.)
class Brand {
  // Surfaces (light, soft — not stark white)
  static const charcoal = Color(0xFFEFF3F8); // app background
  static const charcoalHi = Color(0xFFF6F9FC); // subtle raised background
  static const surface = Color(0xFFFFFFFF); // cards
  static const surfaceHi = Color(0xFFEDF2F7); // chips / insets

  // Brand accents
  static const emerald = Color(0xFF12B76A); // primary — safety / go
  static const emeraldDim = Color(0xFF9BE7C4);
  static const teal = Color(0xFF0EA5A5);
  static const amber = Color(0xFFF59E0B);
  static const coral = Color(0xFFF04438); // emergency / SOS

  // Text
  static const text = Color(0xFF10202E); // primary ink
  static const textDim = Color(0xFF667487); // secondary ink
  static const line = Color(0xFFE1E8F0); // hairlines / borders

  static const meshGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF12B76A), Color(0xFF0E9E7E)],
  );
}

ThemeData buildNestLinkTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Brand.charcoal,
    colorScheme: const ColorScheme.light(
      primary: Brand.emerald,
      secondary: Brand.teal,
      surface: Brand.surface,
      onPrimary: Colors.white,
      onSurface: Brand.text,
      error: Brand.coral,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.charcoal,
      foregroundColor: Brand.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Brand.text,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: Brand.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Brand.line),
      ),
    ),
    dividerColor: Brand.line,
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Brand.surfaceHi,
      side: const BorderSide(color: Brand.line),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.line),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Brand.surface,
      elevation: 3,
      indicatorColor: Brand.emerald.withValues(alpha: 0.14),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Brand.textDim),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? Brand.emerald : Brand.textDim,
        ),
      ),
    ),
  );
}
