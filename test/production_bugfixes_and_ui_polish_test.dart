import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayalconnect_flutter/models/auth_models.dart';
import 'package:vayalconnect_flutter/services/session_manager.dart';
import 'package:vayalconnect_flutter/theme/app_theme.dart';
import 'package:vayalconnect_flutter/utils/localization.dart';
import 'package:vayalconnect_flutter/widgets/bottom_nav_bar.dart';
import 'package:vayalconnect_flutter/screens/auth_gateway_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionManager Persistence & Camera Logout Regression Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SessionManager().resetForTests();
    });

    test('Session is persisted to SharedPreferences and restored safely', () async {
      final session = SessionManager();
      final user = UserProfile(
        id: 'farmer_123',
        name: 'Murugan',
        phone: '9876543210',
        email: 'murugan@vayal.in',
        role: AppRole.farmer,
      );

      await session.setSession(
        token: 'secure_jwt_token_abc123',
        user: user,
      );

      expect(session.isAuthenticated, isTrue);
      expect(session.accessToken, equals('secure_jwt_token_abc123'));
      expect(session.currentUser?.name, equals('Murugan'));

      // Simulate Android LMK killing process and recreating SessionManager
      SessionManager().resetForTests();
      expect(SessionManager().isAuthenticated, isFalse);

      // Startup session restore
      await SessionManager().restoreSession();
      expect(SessionManager().isAuthenticated, isTrue);
      expect(SessionManager().accessToken, equals('secure_jwt_token_abc123'));
      expect(SessionManager().currentUser?.id, equals('farmer_123'));
      expect(SessionManager().currentUser?.name, equals('Murugan'));
      expect(SessionManager().activeRole, equals(AppRole.farmer));
    });

    test('Logout clears all persisted credentials from SharedPreferences', () async {
      final session = SessionManager();
      await session.setSession(
        token: 'temp_token',
        user: UserProfile(
          id: 'u1',
          name: 'Farmer Test',
          phone: '9999999999',
          email: 'farmer@vayal.in',
          role: AppRole.farmer,
        ),
      );
      expect(session.isAuthenticated, isTrue);

      await session.logout();
      expect(session.isAuthenticated, isFalse);
      expect(session.accessToken, isNull);

      SessionManager().resetForTests();
      await SessionManager().restoreSession();
      expect(SessionManager().isAuthenticated, isFalse);
    });
  });

  group('Signup Confirm Password Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SessionManager().resetForTests();
    });

    testWidgets('Registration sheet renders Password and Confirm Password with visibility toggle',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const AuthGatewayScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Open registration sheet via RichText link
      final registerLink = find.textContaining('Register', findRichText: true);
      expect(registerLink, findsOneWidget);
      await tester.tap(registerLink);
      await tester.pumpAndSettle();

      // Verify Confirm Password field exists
      expect(find.text('Confirm Password'), findsOneWidget);
      final sheetIcons = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byIcon(Icons.visibility_off_outlined),
      );
      expect(sheetIcons, findsNWidgets(2));

      // Tap visibility toggle on confirm password
      await tester.tap(sheetIcons.last);
      await tester.pumpAndSettle();

      final sheetVisibleIcons = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byIcon(Icons.visibility_outlined),
      );
      expect(sheetVisibleIcons, findsOneWidget);
    });

    testWidgets('Mismatched confirm password shows validation error', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const AuthGatewayScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Open registration sheet
      final registerLink = find.textContaining('Register', findRichText: true);
      await tester.tap(registerLink);
      await tester.pumpAndSettle();

      // Enter mismatched passwords directly into the designated fields
      final passwordField = find.widgetWithText(TextFormField, 'Password');
      final confirmPasswordField = find.widgetWithText(TextFormField, 'Confirm Password');

      await tester.enterText(passwordField, 'Pass1234');
      await tester.enterText(confirmPasswordField, 'Mismatch1234');

      // Tap Submit/Create Account button
      final submitButton = find.widgetWithText(ElevatedButton, VayalStrings.register);
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(find.text('Passwords do not match'), findsOneWidget);
    });
  });

  group('Navigation & Bottom Nav Bar Tests', () {
    testWidgets('Farmer bottom nav bar displays 4 primary destinations and opens More menu',
        (tester) async {
      SessionManager().switchRole(AppRole.farmer);

      int tappedIndex = -1;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: const Text('Farmer Body'),
            bottomNavigationBar: VayalBottomNavBar(
              currentIndex: 0,
              onTap: (index) => tappedIndex = index,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('My Crops'), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('More'), findsNothing);

      await tester.tap(find.text('My Crops'));
      expect(tappedIndex, equals(1));
    });

    testWidgets('Buyer bottom nav bar displays Market, Orders, Profile and no More item', (tester) async {
      SessionManager().switchRole(AppRole.buyer);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: const Text('Buyer Body'),
            bottomNavigationBar: VayalBottomNavBar(
              currentIndex: 0,
              onTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Market'), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('More'), findsNothing);
    });

    testWidgets('Admin bottom nav bar displays Overview, Farmers, Orders and no More item', (tester) async {
      SessionManager().switchRole(AppRole.admin);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: const Text('Admin Body'),
            bottomNavigationBar: VayalBottomNavBar(
              currentIndex: 0,
              onTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Farmers'), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('More'), findsNothing);
    });
  });

  group('AppTheme Palette Consistency Tests', () {
    test('ThemeData uses the authoritative green, cream, white, and brown palette', () {
      final theme = AppTheme.lightTheme;

      expect(AppTheme.primaryGreen.value, equals(0xFF5B9030));
      expect(AppTheme.primaryDarkGreen.value, equals(0xFF264E22));
      expect(AppTheme.deepGreen.value, equals(0xFF1E3F1C));
      expect(AppTheme.primaryLightGreen.value, equals(0xFF88BD38));
      expect(AppTheme.softGreen.value, equals(0xFFEBF4DB));
      expect(AppTheme.surfaceCream.value, equals(0xFFF7F2EA));
      expect(AppTheme.backgroundWarm.value, equals(0xFFFAF8F5));
      expect(AppTheme.earthBrown.value, equals(0xFF7A471F));
      expect(AppTheme.darkBrown.value, equals(0xFF482710));
      expect(AppTheme.cardBorder.value, equals(0xFFE2E7DB));
      expect(AppTheme.textPrimary.value, equals(0xFF1B211A));

      // ColorScheme check
      expect(theme.colorScheme.primary, equals(AppTheme.primaryGreen));
      expect(theme.colorScheme.primaryContainer, equals(AppTheme.softGreen));
      expect(theme.colorScheme.secondary, equals(AppTheme.earthBrown));
      expect(theme.scaffoldBackgroundColor, equals(AppTheme.backgroundWarm));
    });
  });
}
