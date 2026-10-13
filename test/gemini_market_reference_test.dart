import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayalconnect_flutter/models/market_price.dart';
import 'package:vayalconnect_flutter/widgets/market_reference_view.dart';

void main() {
  test('missing flower modal and range stay unavailable', () {
    final item = MarketPriceItem.fromJson({
      'commodity': 'Jasmine',
      'unit': 'bunch',
      'price_paise': 50000,
      'price_display': '₹500.00',
      'modal_price_paise': null,
      'price_type': 'wholesale',
      'verification_status': 'verified',
      'source_url': 'https://example.org/flower-bulletin',
      'stale': true,
    });
    expect(item.unit, 'bunch');
    expect(item.modalPriceDisplay, 'Unavailable');
    expect(item.minPriceDisplay, 'Unavailable');
    expect(item.priceDisplay, '₹500.00');
    expect(item.toJson()['source_url'], 'https://example.org/flower-bulletin');
    expect(item.stale, isTrue);
  });

  testWidgets('flower reference preserves units and multiple market records',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: MarketReferenceView(reference: {
        'reference_price_available': true,
        'government_reference_price_paise': 50000,
        'reference_price_unit': 'bunch',
        'reference_price_per_listing_unit_paise': null,
        'reference_commodity': 'Jasmine',
        'reference_market': 'Coimbatore',
        'reference_price_source': 'example.org',
        'reference_price_type': 'wholesale',
        'reference_verification_status': 'verified',
        'reference_source_url': 'https://example.org/flowers',
        'reference_price_stale': true,
        'reference_records': [
          {},
          {
            'commodity': 'Jasmine',
            'market': 'Flower market',
            'variety': 'Local',
            'price_display': '₹600.00',
            'unit': 'bundle',
            'price_type': 'retail',
            'arrival_date': '2026-10-12',
            'verification_status': 'verified',
            'source_url': 'https://example.org/second-market'
          },
        ],
      }),
    ))));
    expect(find.textContaining('/ bunch'), findsOneWidget);
    expect(find.textContaining('/ bundle'), findsOneWidget);
    expect(find.text('Historical verified reference'), findsOneWidget);
    expect(
        find.text(
            'Original unit preserved. No valid conversion to your listing unit.'),
        findsOneWidget);
    expect(find.text('https://example.org/second-market'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable lookup displays its reason without a price',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: MarketReferenceView(
      reference: {
        'reference_price_available': false,
        'reference_price_message': 'No current verified flower price found.'
      },
    ))));
    expect(
        find.text('No current verified flower price found.'), findsOneWidget);
    expect(find.textContaining('₹'), findsNothing);
  });
}
