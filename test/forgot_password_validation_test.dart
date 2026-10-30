import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vayalconnect_flutter/screens/auth_gateway_screen.dart';
import 'package:vayalconnect_flutter/services/auth_service.dart';
import 'package:vayalconnect_flutter/utils/commerce_strings.dart';
import 'package:vayalconnect_flutter/utils/localization.dart';

void main() {
  tearDown(() => VayalStrings.setLanguage(false));

  testWidgets('forgot password sheet validates password policy and confirmation',
      (tester) async {
    final mockAuth = AuthService(
      client: MockClient((r) async {
        if (r.url.path.endsWith('/forgot-password')) {
          return http.Response(
              jsonEncode({'success': true, 'data': {'message': 'OTP sent.'}}),
              200);
        }
        if (r.url.path.endsWith('/reset-password')) {
          final body = jsonDecode(r.body);
          if (body['new_password'] == 'mypassword') {
            return http.Response(
                jsonEncode({
                  'success': false,
                  'error': {
                    'code': 'VALIDATION_ERROR',
                    'message':
                        'Your password must contain at least one uppercase letter and one number.',
                    'fields': [
                      {
                        'location': ['body', 'new_password'],
                        'type': 'value_error',
                        'message':
                            'Your password must contain at least one uppercase letter and one number.'
                      }
                    ]
                  }
                }),
                422);
          }
          return http.Response(
              jsonEncode({
                'success': true,
                'data': {'message': 'Password reset successfully.'}
              }),
              200);
        }
        return http.Response('{"success":false}', 400);
      }),
    );

    await tester.pumpWidget(MaterialApp(
      home: AuthGatewayScreen(authService: mockAuth),
    ));
    await tester.pumpAndSettle();

    // 1. Open Forgot Password sheet
    final forgotBtn = find.text('Forgot Password?');
    expect(forgotBtn, findsOneWidget);
    await tester.tap(forgotBtn);
    await tester.pumpAndSettle();

    expect(find.text('Reset Password'), findsOneWidget);

    // 2. Request OTP
    final emailField = find.widgetWithText(TextField, 'Phone or Email');
    await tester.enterText(emailField, 'farmer@example.com');
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();

    // 3. OTP and Password fields should now appear
    expect(find.text('Enter OTP'), findsOneWidget);
    expect(find.text('New Password'), findsOneWidget);
    expect(find.text('Confirm Password'), findsOneWidget);

    final otpField = find.widgetWithText(TextField, 'Enter OTP');
    final newPassField = find.widgetWithText(TextField, 'New Password');
    final confirmPassField = find.widgetWithText(TextField, 'Confirm Password');

    // 4. Test invalid OTP (< 6 digits)
    await tester.enterText(otpField, '123');
    await tester.enterText(newPassField, 'ValidPass1');
    await tester.enterText(confirmPassField, 'ValidPass1');
    await tester.tap(find.text('Confirm Reset'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid 6-digit OTP.'), findsOneWidget);

    // 5. Test lowercase-only password ('mypassword')
    await tester.enterText(otpField, '123456');
    await tester.enterText(newPassField, 'mypassword');
    await tester.enterText(confirmPassField, 'mypassword');
    await tester.tap(find.text('Confirm Reset'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Your password must contain at least one uppercase letter and one number.'),
        findsOneWidget);

    // 6. Test password too short (< 8 chars)
    await tester.enterText(newPassField, 'Pass1');
    await tester.enterText(confirmPassField, 'Pass1');
    await tester.tap(find.text('Confirm Reset'));
    await tester.pumpAndSettle();
    expect(find.text('Password must be at least 8 characters long.'),
        findsOneWidget);

    // 7. Test missing number
    await tester.enterText(newPassField, 'Password');
    await tester.enterText(confirmPassField, 'Password');
    await tester.tap(find.text('Confirm Reset'));
    await tester.pumpAndSettle();
    expect(find.text('Your password must contain at least one number.'),
        findsOneWidget);

    // 8. Test missing uppercase
    await tester.enterText(newPassField, 'password1');
    await tester.enterText(confirmPassField, 'password1');
    await tester.tap(find.text('Confirm Reset'));
    await tester.pumpAndSettle();
    expect(
        find.text('Your password must contain at least one uppercase letter.'),
        findsOneWidget);

    // 9. Test password confirmation mismatch
    await tester.enterText(newPassField, 'ValidPass1');
    await tester.enterText(confirmPassField, 'DifferentPass1');
    await tester.tap(find.text('Confirm Reset'));
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsOneWidget);

    // 10. Test valid password and confirmation submission
    await tester.enterText(confirmPassField, 'ValidPass1');
    await tester.tap(find.text('Confirm Reset'));
    await tester.pumpAndSettle();

    // Sheet should close and success snackbar should show
    expect(find.text('Reset Password'), findsNothing);
    expect(find.text('Password reset successfully! Please login.'),
        findsOneWidget);

    mockAuth.dispose();
  });
}

