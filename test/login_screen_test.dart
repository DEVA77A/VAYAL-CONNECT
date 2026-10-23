import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayalconnect_flutter/screens/auth_gateway_screen.dart';
import 'package:vayalconnect_flutter/services/session_manager.dart';
import 'package:vayalconnect_flutter/utils/localization.dart';

void main() {
  setUp(() {
    // Ensure English default before each test
    SessionManager().setLanguage(false);
  });

  testWidgets('Login screen opens directly in English by default',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthGatewayScreen(),
      ),
    );
    await tester.pump();

    // Verify English text by default
    expect(find.text('VayalConnect'), findsOneWidget);
    expect(find.text('Direct Farmer-to-Buyer Marketplace'), findsOneWidget);
    expect(find.text('Phone or Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.text('தமிழ்'), findsOneWidget); // Toggle shows Tamil option
  });

  testWidgets('Language switcher toggles between English and Tamil',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthGatewayScreen(),
      ),
    );
    await tester.pump();

    // Tap Tamil toggle button
    await tester.tap(find.text('தமிழ்'));
    await tester.pump();

    // Verify Tamil labels are rendered
    expect(SessionManager().isTamil, isTrue);
    expect(find.text('வயல் Connect'), findsOneWidget);
    expect(find.text('கைபேசி அல்லது மின்னஞ்சல்'), findsOneWidget);
    expect(find.text('கடவுச்சொல்'), findsOneWidget);
    expect(find.text('உள்நுழைக'), findsOneWidget);
    expect(find.text('English'), findsOneWidget); // Toggle shows English option

    // Toggle back to English
    await tester.tap(find.text('English'));
    await tester.pump();

    expect(SessionManager().isTamil, isFalse);
    expect(find.text('VayalConnect'), findsOneWidget);
    expect(find.text('Phone or Email'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });

  testWidgets('Form validation fails when credentials are empty',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthGatewayScreen(),
      ),
    );
    await tester.pump();

    // Scroll to the redesigned form action before validating empty fields.
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login'));
    await tester.pump();

    // Verify validation errors
    expect(find.text(VayalStrings.emailRequired), findsOneWidget);
  });

  testWidgets('Password visibility toggle toggles obscureText',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthGatewayScreen(),
      ),
    );
    await tester.pump();

    // Initially obscureText is true, so visibility_off_outlined icon is shown
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

    // Tap the visibility toggle
    await tester.tap(find.byKey(const Key('password_visibility_toggle')));
    await tester.pump();

    // Now obscureText is false, so visibility_outlined icon is shown
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
  });
}
