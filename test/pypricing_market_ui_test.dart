// Synthetic backend fixtures only; no provider or production requests.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vayalconnect_flutter/models/market_price.dart';
import 'package:vayalconnect_flutter/screens/market_prices_screen.dart';
import 'package:vayalconnect_flutter/screens/add_product_screen.dart';
import 'package:vayalconnect_flutter/services/api_client.dart';
import 'package:vayalconnect_flutter/services/market_price_service.dart';
import 'package:vayalconnect_flutter/utils/localization.dart';
import 'package:vayalconnect_flutter/widgets/market_reference_view.dart';

http.Response envelope(dynamic data) =>
    http.Response(jsonEncode({'success': true, 'data': data}), 200);

Map<String, dynamic> reference({bool stale = true, int price = 12345}) => {
      'reference_price_available': true,
      'government_reference_price_paise': price,
      'reference_price_per_listing_unit_paise': null,
      'reference_price_unit': 'Qui',
      'reference_listing_unit': 'KG',
      'reference_commodity': 'TOMATO',
      'reference_market': 'MADURAI',
      'reference_state': 'Tamil Nadu',
      'reference_price_source': 'pyPricingAPI (Chitta)',
      'reference_price_date': '2022-02-11',
      'reference_verification_method': 'provider_reported_quote',
      'reference_price_stale': stale,
      'reference_quote_type': 'unknown',
      'reference_currency': 'INR',
    };

void main() {
  tearDown(() => VayalStrings.setLanguage(false));

  test('quote model distinguishes zero from missing and keeps new metadata',
      () {
    final missing = MarketPriceItem.fromJson({'commodity': 'Tomato'});
    final zero = MarketPriceItem.fromJson({
      'commodity': 'Tomato',
      'price_paise': 0,
      'unit': 'Qui',
      'currency': 'INR',
      'commodity_id': 'synthetic-id',
      'verification_method': 'provider_reported_quote',
      'freshness_status': 'stale',
    });
    expect(missing.pricePaise, isNull);
    expect(zero.pricePaise, 0);
    expect(zero.unit, 'Qui');
    expect(zero.toJson()['commodity_id'], 'synthetic-id');
    expect(zero.toJson()['freshness_status'], 'stale');
  });

  testWidgets('loading waits for cache response without extra requests',
      (tester) async {
    final pending = Completer<http.Response>();
    var calls = 0;
    final service = MarketPriceService(client: MockClient((request) async {
      calls++;
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/market-prices');
      return pending.future;
    }));
    await tester
        .pumpWidget(MaterialApp(home: MarketPricesScreen(service: service)));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(calls, 1);
    pending.complete(envelope({'records': [], 'live': false, 'count': 0}));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets('unavailable response and user retry only reload cached GET',
      (tester) async {
    var calls = 0;
    final service = MarketPriceService(client: MockClient((request) async {
      calls++;
      expect(request.method, 'GET');
      expect(request.url.queryParameters.containsKey('refresh'), false);
      expect(request.body, isEmpty);
      return http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'MARKET_SOURCE_UNAVAILABLE',
              'message': 'Synthetic unavailable'
            }
          }),
          503);
    }));
    await tester
        .pumpWidget(MaterialApp(home: MarketPricesScreen(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('Market price unavailable'), findsWidgets);
    expect(find.textContaining('₹'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Search'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets(
      'stale reference shows observation date, source and original unit',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: MarketReferenceView(
                    reference: reference(), sellingPricePaise: 900)))));
    expect(find.text('Stale market reference'), findsOneWidget);
    expect(find.textContaining('2022-02-11'), findsOneWidget);
    expect(find.textContaining('pyPricingAPI (Chitta)'), findsOneWidget);
    expect(find.textContaining('/ Qui'), findsOneWidget);
    expect(find.textContaining('INR'), findsOneWidget);
    expect(find.textContaining('Difference from comparable'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'zero legacy quote is unavailable under the validated price contract',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: MarketReferenceView(
                    reference: reference(stale: false, price: 0))))));
    expect(find.text('Source-reported market reference'), findsNothing);
    expect(find.textContaining('₹0.00 / Qui'), findsNothing);
    expect(find.text('Market price unavailable'), findsOneWidget);
  });

  testWidgets('unavailable market state has a Tamil translation',
      (tester) async {
    VayalStrings.setLanguage(true);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: MarketReferenceView(
                reference: {'reference_price_available': false}))));
    expect(find.text('சந்தை விலை கிடைக்கவில்லை'), findsOneWidget);
  });

  testWidgets(
      'fetching a reference leaves the farmer selling-price field unchanged',
      (tester) async {
    var referenceCalls = 0;
    final api = ApiClient(client: MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/products/price-reference');
      referenceCalls++;
      return envelope(reference());
    }));
    final product = {
      'id': 'synthetic-product',
      'revision': 1,
      'product_name': 'Tomato',
      'category': 'Vegetables',
      'quantity_unit': 'KG',
      'quality_grade': 'A',
      'farmer_payout_per_unit_paise': 900,
      'quantity': 10,
      'market': 'Madurai',
      'location': 'Madurai',
      'status': 'ACTIVE',
    };
    await tester.pumpWidget(
        MaterialApp(home: AddProductScreen(product: product, api: api)));
    await tester.pumpAndSettle();
    final selling = find.widgetWithText(TextFormField, 'Your selling price');
    await tester.ensureVisible(selling);
    await tester.enterText(selling, '9.99');
    await tester.ensureVisible(find.text('Verified market reference'));
    await tester.tap(find.text('Verified market reference'));
    await tester.pumpAndSettle();
    expect(referenceCalls, 1);
    expect(tester.widget<TextFormField>(selling).controller!.text, '9.99');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
