import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vayalconnect_flutter/models/market_price.dart';
import 'package:vayalconnect_flutter/services/market_price_service.dart';
import 'package:vayalconnect_flutter/screens/market_prices_screen.dart';
import 'package:vayalconnect_flutter/widgets/market_reference_view.dart';
import 'package:vayalconnect_flutter/utils/localization.dart';
import 'package:vayalconnect_flutter/utils/commerce_strings.dart';

const label =
    'Tamil Nadu statewide reference price — calculated from available market observations';

void main() {
  tearDown(() => VayalStrings.setLanguage(false));
  test('statewide provenance is preserved by the model', () {
    final item = MarketPriceItem.fromJson({
      'commodity': 'மல்லிகை',
      'unit': 'bunch',
      'price_paise': 12500,
      'reference_scope': 'statewide',
      'aggregation_method': 'median_distinct_market_modal',
      'observation_count': 3,
      'observation_dates': ['2026-10-13']
    });
    expect(item.referenceScope, 'statewide');
    expect(item.observationCount, 3);
    expect(item.toJson()['observation_dates'], ['2026-10-13']);
    expect(item.unit, 'bunch');
  });
  for (final tamil in [false, true]) {
    testWidgets(
        'statewide reference label, count, unit, date and stale state Tamil=$tamil',
        (tester) async {
      VayalStrings.setLanguage(tamil);
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child:
                      MarketReferenceView(sellingPricePaise: 4321, reference: {
        'reference_scope': 'statewide',
        'reference_price_available': true,
        'reference_verification_status': 'verified',
        'government_reference_price_paise': 12500,
        'reference_price_unit': 'bunch',
        'reference_commodity': 'Jasmine',
        'reference_market': 'Tamil Nadu statewide reference',
        'reference_price_date': '2026-10-13',
        'reference_observation_count': 3,
        'reference_aggregation_method': 'median_distinct_market_modal',
        'reference_price_stale': true,
        'reference_price_source': 'Synthetic fixture only'
      })))));
      expect(find.text(S.t(label)), findsOneWidget);
      expect(find.textContaining('125.00'), findsOneWidget);
      expect(find.textContaining('bunch'), findsOneWidget);
      expect(find.textContaining('2026-10-13'), findsOneWidget);
      expect(find.text(S.t('Stale market reference')), findsOneWidget);
      expect(find.textContaining('${S.t('Eligible observations')}: 3'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('statewide screen asks for no mandi and performs cache GET only',
      (tester) async {
    final requests = <http.Request>[];
    final service = MarketPriceService(client: MockClient((request) async {
      requests.add(request);
      expect(request.method, 'GET');
      expect(request.url.queryParameters.containsKey('market'), false);
      expect(request.url.queryParameters.containsKey('refresh'), false);
      return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'records': [],
              'live': false,
              'count': 0,
              'source': 'Market cache'
            }
          }),
          200);
    }));
    await tester
        .pumpWidget(MaterialApp(home: MarketPricesScreen(service: service)));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text(label), findsOneWidget);
    expect(find.text('Market price unavailable'), findsOneWidget);
    expect(requests, hasLength(1));
    service.dispose();
  });
}
