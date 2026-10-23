import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vayalconnect_flutter/screens/add_product_screen.dart';
import 'package:vayalconnect_flutter/services/api_client.dart';
import 'package:vayalconnect_flutter/utils/commerce_strings.dart';
import 'package:vayalconnect_flutter/utils/localization.dart';

Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == S.t(label));

Map<String, dynamic> reference({bool stale = false}) => {
      'reference_price_available': true,
      'reference_verification_status': 'verified',
      'reference_price_stale': stale,
      'reference_price_per_listing_unit_paise': 3250,
      'government_reference_price_paise': 3250,
      'reference_price_unit': 'kg',
      'reference_commodity': 'Tomato',
    };

http.Response response(dynamic data) =>
    http.Response(jsonEncode({'success': true, 'data': data}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  tearDown(() => VayalStrings.setLanguage(false));
  testWidgets(
      'source outage permits publishing a manual price but never the hint',
      (tester) async {
    Map<String, dynamic>? submitted;
    final api = ApiClient(client: MockClient((r) async {
      if (r.url.path.endsWith('filter-options')) {
        return response({'categories': []});
      }
      if (r.url.path.endsWith('price-reference')) {
        return http.Response(
            '{"success":false,"error":{"message":"Unavailable"}}', 503);
      }
      expect(r.method, 'POST');
      submitted = Map<String, dynamic>.from(jsonDecode(r.body));
      return response({'message': 'saved'});
    }));
    await tester.pumpWidget(MaterialApp(
        home: AddProductScreen(
            api: api,
            initialImageUrl:
                'https://vayal-connect.onrender.com/api/v1/media/tomato.jpg')));
    await tester.pumpAndSettle();
    await tester.enterText(field('Crop name'), 'Tomato');
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
    for (final entry in {
      'Quantity': '25',
      'Farm location': 'Pollachi',
      'Nearest mandi': 'Pollachi'
    }.entries) {
      await tester.ensureVisible(field(entry.key));
      await tester.enterText(field(entry.key), entry.value);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Publish'));
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();
    expect(submitted, isNull);
    await tester.ensureVisible(field('Your selling price'));
    await tester.enterText(field('Your selling price'), '43.25');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Publish'));
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();
    expect(submitted?['selling_price_per_unit_paise'], 4325);
    expect(submitted?.containsKey('government_reference_price_paise'), false);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  for (final tamil in [false, true]) {
    testWidgets(
        'current suggestion is editable and unsupported crop clears it Tamil=$tamil',
        (tester) async {
      VayalStrings.setLanguage(tamil);
      final api = ApiClient(client: MockClient((r) async {
        if (r.url.path.endsWith('filter-options')) {
          return response({'categories': []});
        }
        expect(r.url.queryParameters.containsKey('category'), false);
        return response(reference());
      }));
      await tester.pumpWidget(MaterialApp(home: AddProductScreen(api: api)));
      await tester.pumpAndSettle();
      final price =
          tester.widget<TextField>(field('Your selling price')).controller!;
      expect(price.text, isEmpty); // The hint 10 is never a real value.
      await tester.enterText(field('Crop name'), 'Tomato');
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();
      expect(price.text, '32.50');
      await tester.enterText(field('Crop name'), 'Unsupported crop');
      await tester.pumpAndSettle();
      expect(price.text, isEmpty);
      await tester.enterText(field('Crop name'), 'Tomato');
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();
      await tester.ensureVisible(field('Your selling price'));
      await tester.enterText(field('Your selling price'), '47.25');
      await tester.ensureVisible(field('Crop name'));
      await tester.enterText(field('Crop name'), 'Jasmine');
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();
      expect(price.text, '47.25');
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    });
  }

  testWidgets(
      'late response preserves manual entry and stale response stays empty',
      (tester) async {
    final pending = Completer<http.Response>();
    var lookups = 0;
    final api = ApiClient(client: MockClient((r) async {
      if (r.url.path.endsWith('filter-options')) {
        return response({'categories': []});
      }
      lookups++;
      if (lookups == 1) return response(reference(stale: true));
      return pending.future;
    }));
    await tester.pumpWidget(MaterialApp(home: AddProductScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.enterText(field('Crop name'), 'Tomato');
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
    final price =
        tester.widget<TextField>(field('Your selling price')).controller!;
    expect(price.text, isEmpty);
    await tester.enterText(field('Crop name'), 'Jasmine');
    await tester.pump(const Duration(milliseconds: 650));
    await tester.ensureVisible(field('Your selling price'));
    await tester.enterText(field('Your selling price'), '55');
    pending.complete(response(reference()));
    await tester.pumpAndSettle();
    expect(price.text, '55');
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });

  testWidgets(
      'edit fetches reference automatically without replacing existing farmer price',
      (tester) async {
    var calls = 0;
    final api = ApiClient(client: MockClient((r) async {
      if (r.url.path.endsWith('filter-options')) {
        return response({'categories': []});
      }
      calls++;
      return response(reference());
    }));
    await tester.pumpWidget(MaterialApp(
        home: AddProductScreen(api: api, product: const {
      'product_name': 'Tomato',
      'farmer_payout_per_unit_paise': 7100,
      'category': 'Vegetables',
      'quality_grade': 'A',
      'status': 'ACTIVE',
    })));
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(
        tester.widget<TextField>(field('Your selling price')).controller!.text,
        '71.00');
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
