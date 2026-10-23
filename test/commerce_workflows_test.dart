import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayalconnect_flutter/models/auth_models.dart';
import 'package:vayalconnect_flutter/screens/admin_dashboard_screen.dart';
import 'package:vayalconnect_flutter/screens/buyer_home_screen.dart';
import 'package:vayalconnect_flutter/screens/farmer_home_screen.dart';
import 'package:vayalconnect_flutter/screens/location_gate_screen.dart';
import 'package:vayalconnect_flutter/screens/payment_screen.dart';
import 'package:vayalconnect_flutter/screens/addresses_screen.dart';
import 'package:vayalconnect_flutter/screens/add_product_screen.dart';
import 'package:vayalconnect_flutter/services/api_client.dart';
import 'package:vayalconnect_flutter/services/admin_service.dart';
import 'package:vayalconnect_flutter/services/location_service.dart';
import 'package:vayalconnect_flutter/services/session_manager.dart';
import 'package:geolocator/geolocator.dart';

// Synthetic HTTP/native fixtures only; external verification is recorded separately.
http.Response envelope(dynamic data) =>
    http.Response(jsonEncode({'success': true, 'data': data}), 200);
void session(AppRole role) => SessionManager().setSession(
    token: 'isolated-test-token',
    user: UserProfile(
        id: 'isolated',
        name: 'Test account',
        email: 'test@example.invalid',
        role: role));
void main() {
  tearDown(() => SessionManager().logout());
  testWidgets('admin period filters call backend and locale rebuild persists',
      (tester) async {
    session(AppRole.admin);
    final periods = <String>[];
    final service = AdminService(client: MockClient((r) async {
      periods.add(r.url.queryParameters['period']!);
      return envelope({'total_orders': periods.length, 'total_farmers': 7});
    }));
    await tester.pumpWidget(
        MaterialApp(home: AdminDashboardScreen(adminService: service)));
    await tester.pumpAndSettle();
    expect(find.text('7'), findsOneWidget);
    expect(periods, ['today']);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year').last);
    await tester.pumpAndSettle();
    expect(periods.last, 'year');
    SessionManager().setLanguage(true);
    await tester.pumpAndSettle();
    expect(find.text('நிர்வாகப் பலகை'), findsOneWidget);
    expect(find.text('ஆண்டு'), findsOneWidget);
    expect(
        (await SharedPreferences.getInstance()).getBool('vayal_language_tamil'),
        isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });
  testWidgets('pending farmer stays locked despite dashboard metrics',
      (tester) async {
    session(AppRole.farmer);
    final api = ApiClient(
        client: MockClient((r) async => envelope(r.url.path.endsWith('profile')
            ? {'approval_status': 'PENDING', 'can_publish': false}
            : {
                'active_products': 0,
                'total_orders': 0,
                'pending_orders': 0,
                'completed_orders': 0
              })));
    await tester.pumpWidget(MaterialApp(home: FarmerHomeScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Publishing locked'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Add crop'));
    expect(button.onPressed, isNull);
    SessionManager().setLanguage(true);
    await tester.pumpAndSettle();
    expect(find.text('பயிர் சேர்'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets('buyer empty marketplace and debounced query stay genuine',
      (tester) async {
    session(AppRole.buyer);
    final queries = <String?>[];
    final api = ApiClient(client: MockClient((r) async {
      queries.add(r.url.queryParameters['search']);
      return envelope({'items': [], 'total': 0});
    }));
    await tester.pumpWidget(MaterialApp(home: BuyerHomeScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('No available crops match your search.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Wheat');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(queries.last, 'Wheat');
    SessionManager().setLanguage(true);
    await tester.pumpAndSettle();
    expect(find.text('சந்தை'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'location denial stays at gate and never persists invented coordinates',
      (tester) async {
    session(AppRole.buyer);
    var writes = 0, reads = 0;
    final api = ApiClient(client: MockClient((r) async {
      writes++;
      return envelope({});
    }));
    final gps = LocationService(
        enabled: () async => true,
        checkPermission: () async => LocationPermission.deniedForever,
        readPosition: () async {
          reads++;
          return const LocationResult(LocationState.unavailable);
        });
    await tester.pumpWidget(MaterialApp(
        home: LocationGateScreen(
            home: const Text('Home'), api: api, locationService: gps)));
    await tester.tap(find.text('Allow location'));
    await tester.pumpAndSettle();
    expect(reads, 0);
    expect(writes, 0);
    expect(find.text('Home'), findsNothing);
    expect(find.text('Open settings'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  for (final verified in [false, true]) {
    testWidgets('native success requires backend verification: $verified',
        (tester) async {
      session(AppRole.buyer);
      var verifies = 0;
      const channel = MethodChannel('razorpay_flutter');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        if (call.method == 'resync') return null;
        expect(call.method, 'open');
        expect((call.arguments as Map)['key'], 'rzp_test_isolated');
        return {
          'type': 0,
          'data': {
            'razorpay_payment_id': 'pay_fixture',
            'razorpay_order_id': 'order_fixture',
            'razorpay_signature': 'fixture_signature'
          }
        };
      });
      final api = ApiClient(client: MockClient((r) async {
        if (r.url.path.endsWith('checkout')) {
          return envelope({
            'key_id': 'rzp_test_isolated',
            'test_mode': true,
            'amount_paise': 1151,
            'currency': 'INR',
            'razorpay_order_id': 'order_fixture'
          });
        }
        verifies++;
        expect(jsonDecode(r.body)['razorpay_order_id'], 'order_fixture');
        return verified
            ? envelope({'payment_verified': true, 'order_status': 'PAID'})
            : http.Response('{"success":false}', 503);
      }));
      await tester.pumpWidget(
          MaterialApp(home: PaymentScreen(orderId: 'isolated', api: api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pay in test mode'));
      await tester.pumpAndSettle();
      expect(verifies, 1);
      expect(find.text('Verified test payment.'),
          verified ? findsOneWidget : findsNothing);
      if (!verified) {
        expect(find.textContaining('Payment awaiting server verification.'),
            findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  }
  testWidgets('address form rejects empty fields without backend writes',
      (tester) async {
    session(AppRole.buyer);
    var writes = 0;
    final api = ApiClient(client: MockClient((r) async {
      writes++;
      return envelope({});
    }));
    await tester.pumpWidget(MaterialApp(home: AddressEditorScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('Required'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets('editing a listing submits price and signed stock adjustment',
      (tester) async {
    session(AppRole.farmer);
    Map<String, dynamic>? submitted;
    final api = ApiClient(client: MockClient((r) async {
      if (r.url.path.endsWith('filter-options')) {
        return envelope({'categories': []});
      }
      expect(r.method, 'PUT');
      expect(r.url.path, '/api/v1/products/isolated-crop');
      submitted = Map<String, dynamic>.from(jsonDecode(r.body));
      return envelope({'message': 'saved'});
    }));
    final product = {
      'product_id': 'isolated-crop',
      'product_name': 'Wheat',
      'description': 'Actual fixture description',
      'location': 'Test town',
      'market': 'Test mandi',
      'quantity_unit': 'KG',
      'category': 'Grains',
      'quality_grade': 'A',
      'farmer_payout_per_unit_paise': 1001,
      'status': 'ACTIVE',
      'harvest_date': '2026-10-11',
      'image_url': 'https://vayal-connect.onrender.com/api/v1/media/wheat.jpg'
    };
    await tester.pumpWidget(
        MaterialApp(home: AddProductScreen(product: product, api: api)));
    await tester.pumpAndSettle();
    final stock = find.widgetWithText(TextFormField, 'Stock adjustment');
    final price = find.widgetWithText(TextFormField, 'Your selling price');
    await tester.enterText(stock, '-2');
    await tester.enterText(price, '12.34');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(submitted, isNotNull,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .join(' | '));
    expect(submitted?['stock_adjustment'], -2);
    expect(submitted?['selling_price_per_unit_paise'], 1234);
    expect(submitted!.containsKey('quantity'), isFalse);
    expect(submitted!.containsKey('commission'), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'saved address edit invalidates coordinates when postal details change',
      (tester) async {
    session(AppRole.buyer);
    final address = {
      'id': 'isolated-address',
      'recipient_name': 'Test buyer',
      'phone': '9876543210',
      'building': '10 Test house',
      'street': 'Test street',
      'locality': 'Test locality',
      'city': 'Test city',
      'state': 'Tamil Nadu',
      'postal_code': '625001',
      'instructions': '',
      'is_default': true,
      'coordinates': {'latitude': 9.94, 'longitude': 78.14}
    };
    Map<String, dynamic>? submitted;
    final api = ApiClient(client: MockClient((r) async {
      expect(r.method, 'PUT');
      submitted = Map<String, dynamic>.from(jsonDecode(r.body));
      return envelope(address);
    }));
    await tester.pumpWidget(
        MaterialApp(home: AddressEditorScreen(address: address, api: api)));
    await tester.pumpAndSettle();
    final street = find.widgetWithText(TextFormField, 'Street');
    await tester.enterText(street, 'Another street');
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(submitted?['street'], 'Another street');
    expect(submitted?['coordinates'], isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  for (final role in AppRole.values) {
    testWidgets('Tamil ${role.name} dashboard fits a narrow phone',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      session(role);
      SessionManager().setLanguage(true);
      final client = MockClient((r) async => envelope(
          r.url.path.endsWith('profile')
              ? {'approval_status': 'APPROVED', 'can_publish': true}
              : r.url.path.contains('products')
                  ? {'items': [], 'total': 0}
                  : {
                      'total_farmers': 14,
                      'total_orders': 0,
                      'active_products': 0
                    }));
      final api = ApiClient(client: client);
      final admin = AdminService(client: client);
      final Widget screen = role == AppRole.admin
          ? AdminDashboardScreen(adminService: admin)
          : role == AppRole.farmer
              ? FarmerHomeScreen(api: api)
              : BuyerHomeScreen(api: api);
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    });
  }
}
