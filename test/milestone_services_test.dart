import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vayalconnect_flutter/models/auth_models.dart';
import 'package:vayalconnect_flutter/models/product_models.dart';
import 'package:vayalconnect_flutter/services/session_manager.dart';
import 'package:vayalconnect_flutter/services/order_service.dart';
import 'package:vayalconnect_flutter/services/farmer_service.dart';
import 'package:vayalconnect_flutter/services/product_service.dart';
import 'package:vayalconnect_flutter/services/admin_service.dart';
import 'package:vayalconnect_flutter/utils/money_input.dart';

void main() {
  setUp(() => SessionManager().setSession(
      token: 'synthetic-test-token',
      user: UserProfile(
          id: 'test-user',
          name: 'Test',
          email: 'test@example.invalid',
          role: AppRole.farmer)));
  tearDown(() => SessionManager().logout());
  test('price input uses exact paise and rejects invalid amounts', () {
    expect(parseSellingPricePaise('43.21'), 4321);
    expect(parseSellingPricePaise('0.01'), 1);
    expect(parseSellingPricePaise('1000000'), 100000000);
    for (final value in [
      '0',
      '-1',
      '1.999',
      'NaN',
      'Infinity',
      '1000000.01',
      '1e2',
      ''
    ]) {
      expect(parseSellingPricePaise(value), isNull);
    }
  });
  test('listing sends chosen payout in paise without client buyer price', () {
    final payload = CreateProductPayload(
            productName: 'Paddy',
            category: 'Grains',
            quantity: 3,
            quantityUnit: 'KG',
            qualityGrade: 'A',
            location: 'Madurai',
            market: 'Madurai',
            sellingPricePerUnitPaise: 4321)
        .toJson();
    expect(payload['selling_price_per_unit_paise'], 4321);
    expect(payload.containsKey('buyer_price_per_unit_paise'), false);
    expect(payload.containsKey('commission_percentage_bps'), false);
  });
  test('application and revision are submitted through authenticated API',
      () async {
    final service = FarmerService(client: MockClient((request) async {
      expect(request.method, 'PUT');
      expect(request.url.path, '/api/v1/farmers/me/application');
      expect(request.headers['Authorization'], 'Bearer synthetic-test-token');
      expect(jsonDecode(request.body)['application_revision'], 2);
      return http.Response(
          '{"success":true,"data":{"approval_status":"PENDING","application_revision":3}}',
          200);
    }));
    expect(
        (await service
            .submitApplication({'application_revision': 2}))['approval_status'],
        'PENDING');
    service.dispose();
  });
  test('admin decision includes the revision actually reviewed', () async {
    final service = AdminService(client: MockClient((request) async {
      expect(jsonDecode(request.body)['application_revision'], 3);
      return http.Response('{"success":true}', 200);
    }));
    await service.approveFarmer('farmer', applicationRevision: 3);
    service.dispose();
  });
  test('reference failures remain explicit and never substitute sample prices',
      () async {
    final service = ProductService(client: MockClient((request) async {
      expect(request.url.path, '/api/v1/products/price-reference');
      expect(request.url.queryParameters,
          {'commodity': 'Paddy', 'market': 'Madurai', 'unit': 'QUINTAL'});
      return http.Response(
          '{"success":false,"error":{"message":"Reference unavailable"}}', 503);
    }));
    await expectLater(
        service.fetchPriceReference(
            commodity: 'Paddy', market: 'Madurai', unit: 'QUINTAL'),
        throwsException);
    service.dispose();
  });
  test(
      'checkout retries retain a key and send fulfillment without money fields',
      () async {
    final keys = <String>[];
    final service = OrderService(client: MockClient((request) async {
      final payload = jsonDecode(request.body) as Map;
      expect(payload['fulfillment_method'], 'DELIVERY');
      expect(payload['delivery_address']['postal_code'], '625001');
      expect(payload.containsKey('buyer_total_paise'), false);
      keys.add(payload['idempotency_key'] as String);
      return http.Response(
          '{"success":false,"error":{"message":"Payment service unavailable"}}',
          503);
    }));
    for (var attempt = 0; attempt < 2; attempt++) {
      await expectLater(
          service.createOrder(
              productId: 'product',
              quantity: 2,
              fulfillmentMethod: 'DELIVERY',
              deliveryAddress: {'postal_code': '625001'}),
          throwsException);
    }
    expect(keys[0], keys[1]);
    service.dispose();
  });
}
