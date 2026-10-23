import 'package:flutter/material.dart';

/// VayalConnect Design System Tokens & Brand Theme
///
/// Shared agricultural brand palette and accessible Material 3 controls.
class AppTheme {
  AppTheme._();

  // Core Brand Palette from Reference Image (Panels 1, 2, and 3)
  static const Color primaryGreen =
      Color(0xFF5B9030); // Fresh leaf & foliage green from Panel 1 & 3
  static const Color primaryDarkGreen =
      Color(0xFF264E22); // Deep organic canopy green from Panel 3
  static const Color deepGreen =
      Color(0xFF1E3F1C); // Header & elevation green (replaces harsh #163D2B)
  static const Color primaryLightGreen =
      Color(0xFF88BD38); // Fresh spring lime green wave from Panel 1
  static const Color softGreen =
      Color(0xFFEBF4DB); // Botanical pill & badge tint from Panel 1
  static const Color surfaceCream =
      Color(0xFFF7F2EA); // Warm ivory/earth tone from Panel 2 & 3
  static const Color backgroundWarm =
      Color(0xFFFAF8F5); // Premium light canvas background from reference
  static const Color backgroundLight =
      Color(0xFFF1F6E8); // Soft botanical surface
  static const Color earthBrown =
      Color(0xFF7A471F); // Natural warm soil accent from Panel 2 & 3
  static const Color darkBrown =
      Color(0xFF482710); // Rich earthy soil contrast from Panel 2
  static const Color lightBrown =
      Color(0xFFBA8754); // Warm caramel/amber wave from Panel 2
  static const Color sandBeige =
      Color(0xFFE5D5C2); // Soft sand divider & badge tint
  static const Color accentGold =
      Color(0xFF7A471F); // Legacy token mapped to logo earth brown
  static const Color goldLight =
      Color(0xFFF7F2EA); // Warning / pending tint

  // Neutral Tokens
  static const Color textPrimary =
      Color(0xFF1B211A); // High-contrast readable botanical charcoal
  static const Color darkBackground = Color(0xFF121512);
  static const Color textSecondary = Color(0xFF556052); // Subtle secondary text
  static const Color textMuted = Color(0xFF758172); // Helper text
  static const Color cardBorder =
      Color(0xFFE2E7DB); // Crisp card outline with soft organic tint
  static const Color dividerColor =
      Color(0xFFEAEFE4); // Subtle line divider

  // Semantic Status Tokens
  static const Color successGreen = Color(0xFF43701E);
  static const Color errorRed = Color(0xFFC62828);
  static const Color warningOrange = Color(0xFFE65100);
  static const Color infoBlue = Color(0xFF1565C0);

  // Border Radius Constants
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 24.0;
  static const Duration motionFast = Duration(milliseconds: 180);
  static const Duration motionStandard = Duration(milliseconds: 240);

  // Material 3 ThemeData
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      fontFamilyFallback: const ['Noto Sans Tamil', 'Nirmala UI'],
      scaffoldBackgroundColor: backgroundWarm,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: VayalPageTransitions(),
        TargetPlatform.windows: VayalPageTransitions(),
        TargetPlatform.linux: VayalPageTransitions(),
      }),
      iconTheme: const IconThemeData(color: earthBrown, size: 24),
      expansionTileTheme: const ExpansionTileThemeData(
          iconColor: earthBrown,
          textColor: textPrimary,
          collapsedIconColor: earthBrown,
          tilePadding: EdgeInsets.symmetric(horizontal: 16)),
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryGreen,
        primary: primaryGreen,
        secondary: earthBrown,
        tertiary: earthBrown,
        surface: Colors.white,
        error: errorRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['Noto Sans Tamil', 'Nirmala UI'],
            fontSize: 26,
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: textPrimary,
            letterSpacing: -0.5),
        titleLarge: TextStyle(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['Noto Sans Tamil', 'Nirmala UI'],
            fontSize: 22,
            height: 1.3,
            fontWeight: FontWeight.w700,
            color: textPrimary),
        titleMedium: TextStyle(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['Noto Sans Tamil', 'Nirmala UI'],
            fontSize: 16,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: textPrimary),
        bodyLarge: TextStyle(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['Noto Sans Tamil', 'Nirmala UI'],
            fontSize: 16,
            height: 1.5,
            color: textPrimary),
        bodyMedium: TextStyle(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['Noto Sans Tamil', 'Nirmala UI'],
            fontSize: 14,
            height: 1.5,
            color: textPrimary),
        bodySmall: TextStyle(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['Noto Sans Tamil', 'Nirmala UI'],
            fontSize: 12,
            height: 1.45,
            color: textSecondary),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium)),
        textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['Noto Sans Tamil', 'Nirmala UI'],
            fontSize: 15,
            fontWeight: FontWeight.w600),
      )),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        iconColor: earthBrown,
        titleTextStyle: TextStyle(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['Noto Sans Tamil', 'Nirmala UI'],
            fontSize: 16,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: textPrimary),
        subtitleTextStyle: TextStyle(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['Noto Sans Tamil', 'Nirmala UI'],
            fontSize: 14,
            height: 1.5,
            color: textSecondary),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: softGreen,
        side: const BorderSide(color: cardBorder),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        labelStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['Noto Sans Tamil', 'Nirmala UI'],
            color: deepGreen,
            fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium)),
      ),
      dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusXLarge))),
      bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          showDragHandle: true,
          shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(radiusXLarge)))),
      snackBarTheme: SnackBarThemeData(
          backgroundColor: deepGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMedium))),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: primaryGreen,
          linearTrackColor: softGreen,
          linearMinHeight: 3,
          borderRadius: BorderRadius.all(Radius.circular(8))),
      dividerTheme: const DividerThemeData(color: dividerColor, space: 24),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          elevation: 2),
      appBarTheme: const AppBarTheme(
        backgroundColor: deepGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          fontFamilyFallback: ['Noto Sans Tamil', 'Nirmala UI'],
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: 0.1,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          side: const BorderSide(color: cardBorder, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['Noto Sans Tamil', 'Nirmala UI'],
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: earthBrown,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          side: const BorderSide(color: cardBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['Noto Sans Tamil', 'Nirmala UI'],
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryGreen,
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['Noto Sans Tamil', 'Nirmala UI'],
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        errorMaxLines: 4,
        helperMaxLines: 4,
        hintMaxLines: 3,
        floatingLabelStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['Noto Sans Tamil', 'Nirmala UI'],
            color: primaryGreen,
            fontWeight: FontWeight.w600),
        hintStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontFamilyFallback: ['Noto Sans Tamil', 'Nirmala UI'],
          color: textMuted,
          fontSize: 14,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryGreen,
        unselectedItemColor: textSecondary,
        selectedLabelStyle: TextStyle(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['Noto Sans Tamil', 'Nirmala UI'],
            fontSize: 12,
            fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['Noto Sans Tamil', 'Nirmala UI'],
            fontSize: 11,
            fontWeight: FontWeight.w500),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}

/// Shares Navigator's existing animation; no extra controllers or route changes.
class VayalPageTransitions extends PageTransitionsBuilder {
  const VayalPageTransitions();

  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final progress = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(
        opacity: progress,
        child: SlideTransition(
            position: progress
                .drive(Tween(begin: const Offset(0, 0.025), end: Offset.zero)),
            child: child));
  }
}
