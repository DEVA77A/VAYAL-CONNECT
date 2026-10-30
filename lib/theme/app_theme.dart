import 'package:flutter/material.dart';

/// VayalConnect Design System Tokens & Brand Theme
///
/// Shared agricultural brand palette and accessible Material 3 controls.
class AppTheme {
  AppTheme._();

  // Core Brand Palette from Reference Image (Warm Cream & Light Green)
  static const Color primaryGreen =
      Color(0xFF4B8F20); // Primary agricultural green (#4B8F20)
  static const Color primaryDarkGreen =
      Color(0xFF174B2A); // Deep organic canopy green / text (#174B2A)
  static const Color darkGreenText =
      Color(0xFF174B2A); // High-contrast text on light green dashboard (#174B2A)
  static const Color deepGreen =
      Color(0xFF1E3F1C); // Header & elevation green
  static const Color primaryLightGreen =
      Color(0xFF88BD38); // Fresh spring lime green wave
  static const Color softGreen =
      Color(0xFFDCEBCB); // Botanical pill & badge tint (#DCEBCB)
  static const Color lightGreenDashboard =
      Color(0xFFDCEBCB); // Light green dashboard hero (#DCEBCB)
  static const Color surfaceCream =
      Color(0xFFFAF6EF); // Card & surface background (#FAF6EF)
  static const Color backgroundWarm =
      Color(0xFFF4EEE5); // Main application canvas background (#F4EEE5)
  static const Color warmCreamSecondary =
      Color(0xFFEEE4D6); // Secondary warm cream surface (#EEE4D6)
  static const Color backgroundLight =
      Color(0xFFFAF6EF); // Soft cream surface
  static const Color earthBrown =
      Color(0xFF805638); // Natural warm soil accent (#805638)
  static const Color darkBrown =
      Color(0xFF482710); // Rich earthy soil contrast
  static const Color lightBrown =
      Color(0xFFBA8754); // Warm caramel/amber wave
  static const Color sandBeige =
      Color(0xFFE5D5C2); // Soft sand divider & badge tint
  static const Color accentGold =
      Color(0xFF805638); // Legacy token mapped to brown accent
  static const Color goldLight =
      Color(0xFFFAF6EF); // Warning / pending tint

  // Neutral Tokens
  static const Color textPrimary =
      Color(0xFF25291F); // High-contrast readable botanical charcoal (#25291F)
  static const Color darkBackground = Color(0xFF121512);
  static const Color textSecondary = Color(0xFF68665D); // Subtle secondary text (#68665D)
  static const Color textMuted = Color(0xFF758172); // Helper text
  static const Color cardBorder =
      Color(0xFFE3D9CB); // Subtle borders (#E3D9CB)
  static const Color dividerColor =
      Color(0xFFE3D9CB); // Subtle line divider (#E3D9CB)

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
        onPrimary: Colors.white,
        primaryContainer: softGreen,
        onPrimaryContainer: deepGreen,
        secondary: earthBrown,
        onSecondary: Colors.white,
        secondaryContainer: surfaceCream,
        onSecondaryContainer: darkBrown,
        tertiary: primaryLightGreen,
        onTertiary: deepGreen,
        surface: surfaceCream,
        onSurface: textPrimary,
        surfaceContainer: surfaceCream,
        surfaceContainerLow: backgroundWarm,
        surfaceContainerHigh: surfaceCream,
        surfaceContainerHighest: surfaceCream,
        outline: cardBorder,
        outlineVariant: dividerColor,
        error: errorRed,
        onError: Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceCream,
        indicatorColor: softGreen,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primaryGreen);
          }
          return const IconThemeData(color: textSecondary);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
                fontFamily: 'Roboto',
                fontFamilyFallback: ['Noto Sans Tamil', 'Nirmala UI'],
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: primaryGreen);
          }
          return const TextStyle(
              fontFamily: 'Roboto',
              fontFamilyFallback: ['Noto Sans Tamil', 'Nirmala UI'],
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: textSecondary);
        }),
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
        backgroundColor: surfaceCream,
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
          backgroundColor: surfaceCream,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusXLarge))),
      bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: surfaceCream,
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
        backgroundColor: primaryGreen,
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
        color: surfaceCream,
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
        fillColor: surfaceCream,
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
        backgroundColor: surfaceCream,
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
