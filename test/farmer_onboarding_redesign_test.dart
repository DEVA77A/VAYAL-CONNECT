import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vayalconnect_flutter/models/auth_models.dart';
import 'package:vayalconnect_flutter/screens/farmer_application_screen.dart';
import 'package:vayalconnect_flutter/services/farmer_service.dart';
import 'package:vayalconnect_flutter/services/session_manager.dart';
import 'package:vayalconnect_flutter/utils/commerce_strings.dart';
import 'package:vayalconnect_flutter/utils/localization.dart';

Finder fieldByLabel(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == S.t(label));

void main() {
  setUp(() => SessionManager().setSession(
      token: 'test-token',
      user: UserProfile(
          id: 'test-farmer-id',
          name: 'Farmer Murugan',
          email: 'murugan@vayalconnect.in',
          role: AppRole.farmer)));
  tearDown(() {
    SessionManager().logout();
    VayalStrings.setLanguage(false);
  });

  testWidgets(
      'Farmer onboarding two-step flow: Step 1 farm details, Next, Step 2 bank details, Back preservation, and final submission',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    int bankSavedCount = 0;
    int applicationSubmittedCount = 0;

    final mockClient = MockClient((request) async {
      // 1. Fetch profile
      if (request.method == 'GET' && request.url.path.endsWith('/profile')) {
        return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'user_id': 'test-farmer-id',
                'name': 'Farmer Murugan',
                'approval_status': 'PENDING',
                'bank_details_present': bankSavedCount > 0,
                'application': applicationSubmittedCount > 0
                    ? {
                        'farm_name': 'Murugan Organic Farm',
                        'farm_address': '12 Green Field Road, Madurai',
                        'pickup_address': '12 Green Field Road, Madurai',
                        'crops': 'Paddy, Banana',
                        'farm_details': 'Certified organic farm',
                        'delivery_available': true,
                        'coordinates': {'latitude': 9.9252, 'longitude': 78.1198}
                      }
                    : {},
                'submitted_at': applicationSubmittedCount > 0 ? '2026-10-30T10:00:00Z' : null,
                'application_revision': applicationSubmittedCount,
              }
            }),
            200);
      }

      // 2. Save bank details
      if (request.method == 'PUT' && request.url.path.endsWith('/bank')) {
        bankSavedCount++;
        final body = jsonDecode(request.body);
        expect(body['account_holder_name'], 'Farmer Murugan');
        expect(body['bank_name'], 'State Bank of India');
        expect(body['account_number'], '123456789012');
        expect(body['ifsc'], 'SBIN0001234');
        return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'bank_name': 'State Bank of India',
                'account_number_masked': 'XXXXXXXX9012',
                'ifsc': 'SBIN0001234',
                'bank_details_verified': false,
              }
            }),
            200);
      }

      // 3. Submit application
      if (request.method == 'PUT' && request.url.path.endsWith('/application')) {
        applicationSubmittedCount++;
        final body = jsonDecode(request.body);
        expect(body['farm_name'], 'Murugan Organic Farm');
        expect(body['farm_address'], '12 Green Field Road, Madurai');
        expect(body['pickup_address'], '12 Green Field Road, Madurai');
        expect(body['crops'], 'Paddy, Banana');
        expect(body['delivery_available'], true);
        expect(body['coordinates'], isNotNull);
        return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'approval_status': 'PENDING',
                'application_revision': 1,
              }
            }),
            200);
      }

      return http.Response('{"success":false}', 400);
    });

    final farmerService = FarmerService(client: mockClient);

    // Initial render without coordinates
    await tester.pumpWidget(MaterialApp(
      home: FarmerApplicationScreen(service: farmerService),
    ));
    await tester.pumpAndSettle();

    // Verification 1: Step 1 displays farm details with Step indicator
    expect(find.text('Step 1 of 2: Farm Details'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(fieldByLabel('Farm name'), findsOneWidget);
    expect(fieldByLabel('Farm address'), findsOneWidget);
    expect(fieldByLabel('Pickup address'), findsOneWidget);
    expect(fieldByLabel('Crops grown'), findsOneWidget);
    expect(fieldByLabel('Farm details'), findsOneWidget);
    expect(find.text('Save current farm coordinates'), findsOneWidget);

    // Verification 2: Step 1 contains 'Next' button and NO 'Submit for review' button
    final nextBtn = find.widgetWithText(ElevatedButton, 'Next');
    expect(nextBtn, findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Submit for review'), findsNothing);

    // Verification 3: Required farm fields validation
    await tester.tap(nextBtn);
    await tester.pumpAndSettle();
    expect(find.text('Enter valid details.'), findsWidgets);

    // Fill in valid farm details
    await tester.enterText(fieldByLabel('Farm name'), 'Murugan Organic Farm');
    await tester.enterText(fieldByLabel('Farm address'), '12 Green Field Road, Madurai');
    await tester.enterText(fieldByLabel('Pickup address'), '12 Green Field Road, Madurai');
    await tester.enterText(fieldByLabel('Crops grown'), 'Paddy, Banana');
    await tester.enterText(fieldByLabel('Farm details'), 'Certified organic farm');

    // Attempt Next without coordinates shows error
    await tester.tap(nextBtn);
    await tester.pumpAndSettle();
    expect(find.text('Please save current farm coordinates before proceeding.'), findsOneWidget);

    // Re-render with initialCoordinates
    await tester.pumpWidget(MaterialApp(
      home: FarmerApplicationScreen(
        service: farmerService,
        initialCoordinates: const {'latitude': 9.9252, 'longitude': 78.1198},
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(fieldByLabel('Farm name'), 'Murugan Organic Farm');
    await tester.enterText(fieldByLabel('Farm address'), '12 Green Field Road, Madurai');
    await tester.enterText(fieldByLabel('Pickup address'), '12 Green Field Road, Madurai');
    await tester.enterText(fieldByLabel('Crops grown'), 'Paddy, Banana');
    await tester.enterText(fieldByLabel('Farm details'), 'Certified organic farm');

    // Toggle delivery option
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    // Verification 4: Advance to Step 2
    final nextBtnWithCoords = find.widgetWithText(ElevatedButton, 'Next');
    await tester.tap(nextBtnWithCoords);
    await tester.pumpAndSettle();

    expect(find.text('Step 2 of 2: Bank Details'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(fieldByLabel('Account holder name'), findsOneWidget);
    expect(fieldByLabel('Bank name'), findsOneWidget);
    expect(fieldByLabel('Account number'), findsOneWidget);
    expect(fieldByLabel('IFSC code'), findsOneWidget);
    expect(fieldByLabel('UPI ID'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Back'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Submit for review'), findsOneWidget);

    // Verification 5: Back button returns to Step 1 without losing farm data
    final backBtn = find.widgetWithText(OutlinedButton, 'Back');
    await tester.tap(backBtn);
    await tester.pumpAndSettle();

    expect(find.text('Step 1 of 2: Farm Details'), findsOneWidget);
    expect(tester.widget<TextField>(fieldByLabel('Farm name')).controller!.text, 'Murugan Organic Farm');
    expect(tester.widget<TextField>(fieldByLabel('Farm address')).controller!.text, '12 Green Field Road, Madurai');
    expect(tester.widget<TextField>(fieldByLabel('Crops grown')).controller!.text, 'Paddy, Banana');

    // Go to Step 2 again
    final nextBtnAgain = find.widgetWithText(ElevatedButton, 'Next');
    await tester.tap(nextBtnAgain);
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 2: Bank Details'), findsOneWidget);

    // Verification 6: Invalid bank details produce field-specific errors
    await tester.enterText(fieldByLabel('Account holder name'), 'Farmer Murugan');
    await tester.enterText(fieldByLabel('Bank name'), 'State Bank of India');
    await tester.enterText(fieldByLabel('Account number'), '123'); // Too short (< 8 digits)
    await tester.enterText(fieldByLabel('IFSC code'), 'INVALID_IFSC');

    final submitBtn = find.widgetWithText(ElevatedButton, 'Submit for review');
    await tester.tap(submitBtn);
    await tester.pumpAndSettle();

    expect(find.text('Enter 8–20 digits.'), findsOneWidget);
    expect(find.text('Enter a valid IFSC.'), findsOneWidget);
    expect(bankSavedCount, 0);
    expect(applicationSubmittedCount, 0);

    // Enter valid bank details
    await tester.enterText(fieldByLabel('Account number'), '123456789012');
    await tester.enterText(fieldByLabel('IFSC code'), 'SBIN0001234');

    // Verification 7: Final submission occurs only after both steps are valid
    await tester.tap(submitBtn);
    await tester.pumpAndSettle();

    expect(bankSavedCount, 1);
    expect(applicationSubmittedCount, 1);

    // Success confirmation
    expect(find.text('Application submitted. Awaiting administrator review.'), findsOneWidget);

    farmerService.dispose();
  });

  testWidgets('Approved farmer profile displays approved status without two-step form',
      (tester) async {
    final mockClient = MockClient((request) async {
      return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'user_id': 'approved-farmer-id',
              'name': 'Farmer Raman',
              'approval_status': 'APPROVED',
              'can_publish': true,
              'bank_details_present': true,
              'application': {
                'farm_name': 'Raman Eco Farm',
                'crops': 'Paddy, Groundnut',
                'delivery_available': true,
              },
              'submitted_at': '2026-10-10T00:00:00Z',
              'application_revision': 1,
            }
          }),
          200);
    });

    final farmerService = FarmerService(client: mockClient);

    await tester.pumpWidget(MaterialApp(
      home: FarmerApplicationScreen(service: farmerService),
    ));
    await tester.pumpAndSettle();

    // Verify Approved status view is shown
    expect(find.text('Approved'), findsOneWidget);
    expect(find.textContaining('Raman Eco Farm'), findsOneWidget);
    expect(find.textContaining('Paddy, Groundnut'), findsOneWidget);
    expect(find.text('Bank payout details'), findsOneWidget);

    // The two-step onboarding form should NOT be shown
    expect(find.text('Step 1 of 2: Farm Details'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Next'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Submit for review'), findsNothing);

    farmerService.dispose();
  });
}
