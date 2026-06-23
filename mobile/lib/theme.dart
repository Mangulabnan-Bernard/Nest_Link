import 'package:flutter/material.dart';

/// Nest Link brand palette — deep charcoal canvas, glowing emerald for
/// safety/connection, teal for normal messaging.
class Brand {
  static const charcoal = Color(0xFF101316);
  static const charcoalHi = Color(0xFF161A1E);
  static const surface = Color(0xFF1E2227);
  static const surfaceHi = Color(0xFF262B31);
  static const emerald = Color(0xFF2ECC71);
  static const emeraldDim = Color(0xFF1E7E4F);
  static const teal = Color(0xFF1ABC9C);
  static const amber = Color(0xFFF1C40F);
  static const coral = Color(0xFFFF6B6B);
  static const text = Color(0xFFEAF0F2);
  static const textDim = Color(0xFF8A949E);
  static const line = Color(0xFF2C3238);

  static const meshGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1FA968), Color(0xFF15805A)],
  );
}

ThemeData buildNestLinkTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Brand.charcoal,
    colorScheme: const ColorScheme.dark(
      primary: Brand.emerald,
      secondary: Brand.teal,
      surface: Brand.surface,
      onPrimary: Brand.charcoal,
      onSurface: Brand.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.charcoal,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Brand.text,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: Brand.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Brand.charcoalHi,
      indicatorColor: Brand.emerald.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Brand.textDim),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? Brand.emerald : Brand.textDim,
        ),
      ),
    ),
    dividerColor: Brand.line,
  );
}
