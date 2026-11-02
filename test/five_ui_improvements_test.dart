import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vayalconnect_flutter/models/auth_models.dart';
import 'package:vayalconnect_flutter/models/product_models.dart';
import 'package:vayalconnect_flutter/screens/add_product_screen.dart';
import 'package:vayalconnect_flutter/screens/location_gate_screen.dart';
import 'package:vayalconnect_flutter/screens/product_details_screen.dart';
import 'package:vayalconnect_flutter/screens/profile_screen.dart';
import 'package:vayalconnect_flutter/screens/splash_screen.dart';
import 'package:vayalconnect_flutter/services/api_client.dart';
import 'package:vayalconnect_flutter/services/location_service.dart';
import 'package:vayalconnect_flutter/services/session_manager.dart';
import 'package:vayalconnect_flutter/theme/app_theme.dart';
import 'package:vayalconnect_flutter/utils/localization.dart';
import 'package:vayalconnect_flutter/widgets/logout_dialog.dart';
import 'package:vayalconnect_flutter/widgets/market_reference_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VayalStrings.setLanguage(false);
  });

  group('FIVE UI Improvements Tests', () {
    // -------------------------------------------------------------
    // CHANGE 1: Location Required Page UI Redesign
    // -------------------------------------------------------------
    testWidgets(
        'Change 1: LocationGateScreen renders redesigned UI and retains permission logic',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final gps = LocationService(
        enabled: () async => true,
        checkPermission: () async => LocationPermission.denied,
        requestPermission: () async => LocationPermission.deniedForever,
        readPosition: () async =>
            const LocationResult(LocationState.unavailable),
      );

      final api = ApiClient(
          client:
              MockClient((r) async => http.Response('{"success": true}', 200)));

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: LocationGateScreen(
          home: const Text('Home Screen Target'),
          api: api,
          locationService: gps,
        ),
      ));
      await tester.pumpAndSettle();

      // Verify typography and headings
      expect(find.text('Location required'), findsWidgets);
      expect(
          find.text('Enable location for a better experience'), findsOneWidget);

      // Verify Information Feature Card rows
      expect(find.text('Nearby Farm Discovery'), findsOneWidget);
      expect(find.text('Accurate Distance'), findsOneWidget);
      expect(find.text('Transparent Pricing'), findsOneWidget);

      // Verify Allow location button
      final allowBtn = find.text('Allow location');
      expect(allowBtn, findsOneWidget);

      // Ensure button is visible before tap
      await tester.ensureVisible(allowBtn);
      await tester.tap(allowBtn);
      await tester.pumpAndSettle();

      expect(find.text('Open settings'), findsOneWidget);
      expect(find.text('Enable location permission in app settings.'),
          findsOneWidget);
      api.dispose();
    });

    // -------------------------------------------------------------
    // CHANGE 2: Logout Confirmation Dialog Redesign
    // -------------------------------------------------------------
    testWidgets(
        'Change 2: LogoutConfirmationDialog renders modern dialog with Cancel and Logout actions',
        (tester) async {
      bool loggedOut = false;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                LogoutConfirmationDialog.show(
                  context,
                  onConfirm: () async {
                    loggedOut = true;
                  },
                );
              },
              child: const Text('Trigger Logout'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Open dialog
      await tester.tap(find.text('Trigger Logout'));
      await tester.pumpAndSettle();

      // Verify dialog structure and typography
      expect(find.text('Confirm Logout'), findsOneWidget);
      expect(find.text('Are you sure you want to log out of your account?'),
          findsOneWidget);
      expect(find.byIcon(Icons.logout_rounded), findsOneWidget);

      // Verify Cancel button closes dialog without logging out
      final cancelBtn = find.text('Cancel');
      expect(cancelBtn, findsOneWidget);
      await tester.tap(cancelBtn);
      await tester.pumpAndSettle();

      expect(loggedOut, isFalse);
      expect(find.text('Confirm Logout'), findsNothing);

      // Open dialog again and confirm logout
      await tester.tap(find.text('Trigger Logout'));
      await tester.pumpAndSettle();

      final logoutBtn = find.text('Logout');
      expect(logoutBtn, findsOneWidget);
      await tester.tap(logoutBtn);
      await tester.pumpAndSettle();

      expect(loggedOut, isTrue);
    });

    // -------------------------------------------------------------
    // CHANGE 3: Profile Page Complete UI Enhancement
    // -------------------------------------------------------------
    testWidgets(
        'Change 3: ProfileScreen renders unified header hero, info card, and action tiles',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mockProfileData = {
        'id': 'user_1',
        'name': 'Deva Farmer',
        'email': 'deva@example.com',
        'phone': '9876543210',
        'address': '123 Green Valley Farm',
        'area_location': 'Madurai South',
        'role': 'FARMER',
        'is_active': true,
      };

      final api = ApiClient(client: MockClient((request) async {
        if (request.url.path.endsWith('/users/me')) {
          return http.Response(
            '{"success": true, "data": ${'''{
              "id": "user_1",
              "name": "Deva Farmer",
              "email": "deva@example.com",
              "phone": "9876543210",
              "address": "123 Green Valley Farm",
              "area_location": "Madurai South",
              "role": "FARMER",
              "is_active": true
            }'''}}',
            200,
          );
        }
        if (request.url.path.endsWith('/farmers/me/bank')) {
          return http.Response(
            '{"success": true, "data": {"bank_name": "State Bank of India", "account_number_masked": "XXXX1234", "bank_details_verified": true}}',
            200,
          );
        }
        return http.Response('{"success": true, "data": {}}', 200);
      }));

      await SessionManager().setSession(
        token: 'test-token',
        user: UserProfile.fromJson(mockProfileData),
      );

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ProfileScreen(api: api),
      ));
      await tester.pumpAndSettle();

      // Verify Profile Header & Hero
      expect(find.text('Deva Farmer'), findsWidgets);
      expect(find.text('Farmer'), findsWidgets);

      // Verify Personal Information section
      expect(find.text('Personal Information'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('deva@example.com'), findsOneWidget);
      expect(find.text('Contact number'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('Address'), findsOneWidget);
      expect(find.text('123 Green Valley Farm'), findsOneWidget);
      expect(find.text('Area / locality'), findsOneWidget);
      expect(find.text('Madurai South'), findsOneWidget);

      // Verify Account Actions section
      expect(find.text('Account Actions'), findsOneWidget);
      expect(find.text('Edit profile'), findsOneWidget);
      expect(find.text('Farmer application'), findsOneWidget);
      expect(find.text('Bank payout details'), findsWidgets);
      expect(find.text('Check for updates'), findsOneWidget);
      expect(find.text('Change password'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);

      // Tapping Logout opens LogoutConfirmationDialog
      await tester.ensureVisible(find.text('Logout'));
      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Logout'), findsOneWidget);
      expect(find.text('Are you sure you want to log out of your account?'),
          findsOneWidget);

      // Close dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      api.dispose();
      await SessionManager().logout();
    });

    // -------------------------------------------------------------
    // CHANGE 4: App Intro / Splash Screen Color Redesign
    // -------------------------------------------------------------
    testWidgets(
        'Change 4: SplashScreen renders with light-green background and primary dark green typography',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: SplashScreen(),
      ));
      await tester.pump();

      // Verify Scaffold has the soft light-green background color (#DCEBCB)
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, const Color(0xFFDCEBCB));

      // Verify App name and Tagline text exist
      final appNameFinder = find.text('VayalConnect');
      final taglineFinder = find.text('Direct Farmer-to-Buyer Marketplace');

      expect(appNameFinder, findsOneWidget);
      expect(taglineFinder, findsOneWidget);

      final appNameText = tester.widget<Text>(appNameFinder);
      expect(appNameText.style?.color, const Color(0xFF174B2A));

      final taglineText = tester.widget<Text>(taglineFinder);
      expect(taglineText.style?.color, const Color(0xFF4B8F20));

      // Settle pending animation timers before test teardown
      await tester.pump(const Duration(seconds: 2));
    });

    // -------------------------------------------------------------
    // CHANGE 5: Remove Technical Market Price Fetch Details
    // -------------------------------------------------------------
    testWidgets(
        'Change 5: Technical MarketReferenceView is removed from AddCrop and ProductDetails for Farmers/Buyers',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = ApiClient(client: MockClient((request) async {
        if (request.url.path.contains('price-reference')) {
          return http.Response(
            '{"success": true, "data": {"reference_price_available": true, "reference_price_per_listing_unit_paise": 3500}}',
            200,
          );
        }
        return http.Response('{"success": true, "data": []}', 200);
      }));

      // Test AddProductScreen (Farmer side)
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: AddProductScreen(api: api),
      ));
      await tester.pumpAndSettle();

      // Technical card and button MUST NOT be present
      expect(find.byType(MarketReferenceView), findsNothing);
      expect(find.text('Verified market reference'), findsNothing);

      // Test ProductDetailsScreen as Buyer
      await SessionManager().setSession(
        token: 'test-buyer-token',
        user: UserProfile(
          id: 'buyer_1',
          name: 'Test Buyer',
          email: 'buyer@example.com',
          role: AppRole.buyer,
        ),
      );

      final product = BuyerProduct(
        productId: 'prod_123',
        farmerId: 'farmer_1',
        farmerName: 'Farmer Murugan',
        productName: 'Fresh Tomato',
        category: 'Vegetables',
        quantityAvailable: 100,
        quantityUnit: 'KG',
        qualityGrade: 'FAQ',
        buyerPricePerUnitPaise: 4000,
        buyerPricePerUnitDisplay: '₹40.00 / KG',
        farmerBasePricePaise: 3800,
        commissionPerUnitPaise: 200,
        commissionPercentageBps: 500,
        description: 'Fresh farm tomatoes',
        marketReference: {
          'reference_commodity': 'Tomato',
          'reference_market': 'Madurai Mandi',
          'reference_price_per_listing_unit_paise': 3600,
          'reference_aggregation_method': 'median_distinct_market_modal',
        },
        location: 'Madurai',
        deliveryAvailable: true,
      );

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ProductDetailsScreen(
            key: const ValueKey('buyer-details'), product: product, api: api),
      ));
      await tester.pumpAndSettle();

      // For Buyer: MarketReferenceView MUST NOT be displayed
      expect(find.byType(MarketReferenceView), findsNothing);

      // Test ProductDetailsScreen as Admin
      await SessionManager().setSession(
        token: 'test-admin-token',
        user: UserProfile(
          id: 'admin_1',
          name: 'Test Admin',
          email: 'admin@example.com',
          role: AppRole.admin,
        ),
      );

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ProductDetailsScreen(
            key: const ValueKey('admin-details'), product: product, api: api),
      ));
      await tester.pumpAndSettle();

      // For Admin: MarketReferenceView IS retained for administrative verification
      expect(find.byType(MarketReferenceView), findsOneWidget);

      api.dispose();
      await SessionManager().logout();
    });
  });
}
