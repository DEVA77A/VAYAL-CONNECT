import 'package:flutter/material.dart';

/// VayalConnect Design System Tokens & Brand Theme
///
/// Designed with Stitch MCP (Project: 8393298150002994477, Asset: assets/8321542949480181807)
/// Theme: Deep Agricultural Forest Green (#1B5E20), Warm Canvas (#FAFAF7),
/// Earth Brown (#795548), Harvest Gold (#F57F17), and crisp Material 3 tokens.
class AppTheme {
  AppTheme._();

  // Core Brand Palette
  static const Color primaryGreen = Color(0xFF1B5E20);      // Deep forest emerald
  static const Color primaryDarkGreen = Color(0xFF123D25);  // Deep forest header
  static const Color deepGreen = Color(0xFF123D25);         // Header & elevation green
  static const Color primaryLightGreen = Color(0xFF2E7D32); // Fresh foliage green
  static const Color softGreen = Color(0xFFE8F5E9);         // Status pill & badge tint
  static const Color surfaceCream = Color(0xFFF9FBE7);      // Warm agricultural highlight
  static const Color backgroundWarm = Color(0xFFFAFAF7);    // Premium canvas background
  static const Color backgroundLight = Color(0xFFF1F8E9);   // Soft tinted surface
  static const Color earthBrown = Color(0xFF795548);        // Natural soil accent
  static const Color darkBrown = Color(0xFF4E342E);         // Earthy contrast
  static const Color accentGold = Color(0xFFF57F17);        // Harvest amber / gold
  static const Color goldLight = Color(0xFFFFF8E1);         // Warning / pending tint

  // Neutral Tokens
  static const Color textPrimary = Color(0xFF1B1F1B);       // High-contrast readable dark
  static const Color textSecondary = Color(0xFF566573);     // Subtle secondary text
  static const Color textMuted = Color(0xFF8C98A4);         // Helper text
  static const Color cardBorder = Color(0xFFE2E8E0);        // Crisp card outline
  static const Color dividerColor = Color(0xFFEBEFEA);      // Subtle line divider

  // Semantic Status Tokens
  static const Color successGreen = Color(0xFF2E7D32);
  static const Color errorRed = Color(0xFFC62828);
  static const Color warningOrange = Color(0xFFE65100);
  static const Color infoBlue = Color(0xFF1565C0);

  // Border Radius Constants
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 24.0;

  // Material 3 ThemeData
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: backgroundWarm,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryGreen,
        primary: primaryGreen,
        secondary: accentGold,
        tertiary: earthBrown,
        surface: Colors.white,
        error: errorRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: 0.1,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1.0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          side: const BorderSide(color: cardBorder, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryGreen,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          side: const BorderSide(color: primaryGreen, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryGreen,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: const BorderSide(color: cardBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: const BorderSide(color: cardBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: const BorderSide(color: primaryGreen, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: const BorderSide(color: errorRed, width: 1.5),
        ),
        hintStyle: const TextStyle(
          color: textMuted,
          fontSize: 14,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryGreen,
        unselectedItemColor: textSecondary,
        selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }
}
