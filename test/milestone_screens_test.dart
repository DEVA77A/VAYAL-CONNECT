import 'package:vayalconnect_flutter/services/api_client.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vayalconnect_flutter/models/auth_models.dart';
import 'package:vayalconnect_flutter/models/product_models.dart';
import 'package:vayalconnect_flutter/services/session_manager.dart';
import 'package:vayalconnect_flutter/services/farmer_service.dart';
import 'package:vayalconnect_flutter/services/order_service.dart';
import 'package:vayalconnect_flutter/screens/farmer_application_screen.dart';
import 'package:vayalconnect_flutter/screens/product_details_screen.dart';

void main() {
  setUp(() => SessionManager().setSession(
      token: 'test-token',
      user: UserProfile(
          id: 'test',
          name: 'Test',
          email: 'test@example.invalid',
          role: AppRole.farmer)));
  tearDown(() => SessionManager().logout());
  testWidgets(
      'farmer can correct a rejected application and submit its current revision',
      (tester) async {
    var submits = 0;
    final application = {
      'farm_name': 'Test farm',
      'farm_address': '10 Test farm road',
      'pickup_address': '10 Pickup farm road',
      'crops': 'Paddy',
      'delivery_available': true,
      'coordinates': {'latitude': 9.92, 'longitude': 78.12}
    };
    final service = FarmerService(client: MockClient((request) async {
      if (request.method == 'PUT') {
        submits++;
        final submitted = jsonDecode(request.body);
        expect(submitted['farm_name'], 'Test farm');
        expect(submitted['application_revision'], 2);
        expect(submitted['delivery_available'], true);
        return http.Response(
            '{"success":true,"data":{"approval_status":"PENDING"}}', 200);
      }
      return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'application': application,
              'application_revision': submits == 0 ? 2 : 3,
              'approval_status': submits == 0 ? 'REJECTED' : 'PENDING',
              'rejection_reason': submits == 0 ? 'Correct farm details' : null,
              'submitted_at': '2026-10-11'
            }
          }),
          200);
    }));
    await tester.pumpWidget(
        MaterialApp(home: FarmerApplicationScreen(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('Review reason: Correct farm details'), findsOneWidget);
    final submit = find.text('Submit for review');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(submits, 1);
    expect(find.text('Pending'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  BuyerProduct product(bool delivery) => BuyerProduct(
      productId: 'product',
      productName: 'Paddy',
      category: 'Grains',
      quantityAvailable: 2,
      quantityUnit: 'KG',
      qualityGrade: 'A',
      location: 'Madurai',
      farmerName: 'Test farmer',
      buyerPricePerUnitPaise: 4969,
      buyerPricePerUnitDisplay: '₹49.69',
      pickupAddress: '10 Pickup farm road',
      deliveryAvailable: delivery);

  testWidgets(
      'checkout shows pickup only when delivery is unavailable and never claims payment success',
      (tester) async {
    final service = OrderService(client: MockClient((request) async {
      expect(jsonDecode(request.body)['fulfillment_method'], 'PICKUP');
      expect(jsonDecode(request.body)['quantity'], 1);
      return http.Response(
          '{"success":true,"data":{"order_id":"test-order","order_number":"TEST-1","order_status":"PENDING_PAYMENT","payment_status":"PENDING"}}',
          201);
    }));
    await tester.pumpWidget(MaterialApp(
        home: ProductDetailsScreen(
            product: product(false),
            orderService: service,
            api: ApiClient(
                client: MockClient((r) async => http.Response(
                    '{"success":true,"data":{"order_id":"test","order_status":"PENDING_PAYMENT","product_name":"Paddy","order_number":"TEST-1","quantity":1,"unit":"KG","buyer_total_paise":4969,"farmer_base_total_paise":4321,"commission_total_paise":648,"payment_status":"PENDING"}}',
                    200))))));
    await tester.pumpAndSettle();
    expect(find.text('Buyer total: ₹49.69'), findsWidgets);
    await tester.ensureVisible(find.text('Place order'));
    final options = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>));
    expect(options.initialValue, 'PICKUP');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Pickup'), findsWidgets);
    expect(find.text('Delivery'),
        findsOneWidget); // Field label only, no delivery option.
    await tester.tap(find.text('Pickup').last);
    await tester.pumpAndSettle();
    expect(find.text('Pickup address: 10 Pickup farm road'), findsOneWidget);
    final orderButton = find.text('Place order');
    await tester.tap(orderButton);
    await tester.pumpAndSettle();
    expect(find.text('Order recorded. Payment pending.'), findsOneWidget);
    expect(find.textContaining('Payment verified'), findsNothing);
    expect(find.textContaining('escrow'), findsNothing);
    expect(find.textContaining('APMC VERIFIED'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'delivery checkout validates a real address before calling the backend',
      (tester) async {
    var calls = 0;
    final service = OrderService(client: MockClient((request) async {
      calls++;
      final submitted = jsonDecode(request.body);
      expect(submitted['fulfillment_method'], 'DELIVERY');
      expect(submitted['delivery_address']['address'], '10 Test buyer road');
      return http.Response(
          '{"success":false,"error":{"message":"Payment service unavailable"}}',
          503);
    }));
    await tester.pumpWidget(MaterialApp(
        home: ProductDetailsScreen(
            product: product(true), orderService: service)));
    await tester.pumpAndSettle();
    final selector = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delivery').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Place order'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.pumpWidget(MaterialApp(
        home: ProductDetailsScreen(
            key: const ValueKey("saved-address"),
            product: product(true),
            orderService: service,
            initialDeliveryAddress: const {
          'recipient_name': 'Test buyer',
          'phone': '9876543210',
          'address': '10 Test buyer road',
          'postal_code': '625001',
          'coordinates': {'latitude': 9.94, 'longitude': 78.14}
        })));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delivery').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Place order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Place order'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.drag(find.byType(ListView), const Offset(0, 1400));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Unable to complete this request. Please retry.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
