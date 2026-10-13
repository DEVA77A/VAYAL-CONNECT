import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vayalconnect_flutter/screens/add_product_screen.dart';
import 'package:vayalconnect_flutter/screens/farmer_application_screen.dart';
import 'package:vayalconnect_flutter/screens/farmer_bank_screen.dart';
import 'package:vayalconnect_flutter/services/api_client.dart';
import 'package:vayalconnect_flutter/services/farmer_service.dart';
import 'package:vayalconnect_flutter/utils/commerce_strings.dart';
import 'package:vayalconnect_flutter/utils/form_examples.dart';
import 'package:vayalconnect_flutter/utils/localization.dart';
import 'package:vayalconnect_flutter/widgets/market_reference_view.dart';

Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == S.t(label));

void main() {
  tearDown(() => VayalStrings.setLanguage(false));
  for (final tamil in [false, true]) {
    testWidgets(
        'crop hints remain empty and cached reference never sets selling price Tamil=$tamil',
        (tester) async {
      VayalStrings.setLanguage(tamil);
      final calls = <http.Request>[];
      final api = ApiClient(client: MockClient((r) async {
        calls.add(r);
        return http.Response(
            jsonEncode({
              'success': true,
              'data': r.url.path.endsWith('filter-options')
                  ? {'categories': []}
                  : {
                      'reference_price_available': true,
                      'reference_verification_status': 'verified',
                      'government_reference_price_paise': 3000,
                      'reference_price_unit': 'kg',
                      'reference_commodity': 'Tomato',
                      'reference_market': 'Tamil Nadu statewide reference',
                      'reference_aggregation_method':
                          'median_distinct_market_range_midpoint',
                      'reference_price_source':
                          'Tamil Nadu Agricultural Marketing Department — Uzhavar Santhai',
                      'reference_price_date': '2026-10-13',
                    }
            }),
            200);
      }));
      await tester.pumpWidget(MaterialApp(home: AddProductScreen(api: api)));
      await tester.pumpAndSettle();
      final selling = tester.widget<TextField>(field('Your selling price'));
      expect(selling.decoration!.hintText, '10');
      expect(selling.controller!.text, isEmpty);
      expect(selling.decoration!.hintStyle!.color, FormExamples.style.color);
      expect(tester.widget<TextField>(field('Quantity')).controller!.text,
          isEmpty);
      await tester.enterText(field('Crop name'), 'Tomato');
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();
      expect(calls.where((r) => r.url.path.endsWith('price-reference')),
          hasLength(1));
      expect(calls.every((r) => r.method == 'GET'), isTrue);
      expect(selling.controller!.text, isEmpty);
      await tester.ensureVisible(field('Your selling price'));
      await tester.enterText(field('Your selling price'), '17');
      await tester.pump();
      expect(selling.controller!.text, '17');
      expect(find.byType(MarketReferenceView), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    });

    testWidgets(
        'farm application and bank fields have bilingual empty hints Tamil=$tamil',
        (tester) async {
      VayalStrings.setLanguage(tamil);
      final service = FarmerService(
          client: MockClient((r) async => http.Response(
              '{"success":true,"data":{"application":{},"approval_status":"PENDING"}}',
              200)));
      await tester.pumpWidget(
          MaterialApp(home: FarmerApplicationScreen(service: service)));
      await tester.pumpAndSettle();
      for (final w in tester.widgetList<TextField>(find.byType(TextField))) {
        expect(w.controller!.text, isEmpty);
        expect(w.decoration!.hintText, isNotEmpty);
      }
      expect(tester.widget<TextField>(field('Farm name')).decoration!.hintText,
          FormExamples.hint('farm_name'));
      await tester.pumpWidget(const MaterialApp(home: FarmerBankScreen()));
      for (final w in tester.widgetList<TextField>(find.byType(TextField))) {
        expect(w.controller!.text, isEmpty);
        expect(w.decoration!.hintText, isNotEmpty);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('background cache failure leaves farmer form usable',
      (tester) async {
    var writes = 0;
    final api = ApiClient(client: MockClient((r) async {
      if (r.method != 'GET') writes++;
      return r.url.path.endsWith('filter-options')
          ? http.Response('{"success":true,"data":{"categories":[]}}', 200)
          : http.Response(
              '{"success":false,"error":{"message":"Unavailable"}}', 503);
    }));
    await tester.pumpWidget(MaterialApp(home: AddProductScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.enterText(field('Crop name'), 'Jasmine');
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(field('Your selling price')).enabled, isTrue);
    expect(
        tester.widget<TextField>(field('Your selling price')).controller!.text,
        isEmpty);
    expect(writes, 0);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
