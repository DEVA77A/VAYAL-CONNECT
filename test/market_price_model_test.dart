import 'package:flutter_test/flutter_test.dart';
import 'package:vayalconnect_flutter/models/market_price.dart';

void main() {
  group('MarketPriceItem Model Tests', () {
    test('Correctly parses valid JSON from FastAPI backend', () {
      final json = {
        'price_id': 'mp_paddy_madurai_2026-10-09',
        'commodity': 'Paddy',
        'market': 'Madurai',
        'state': 'Tamil Nadu',
        'district': 'Madurai',
        'variety': 'Ponni',
        'grade': 'FAQ',
        'min_price_paise': 220000,
        'max_price_paise': 260000,
        'modal_price_paise': 240000,
        'min_price_display': '₹2,200.00',
        'max_price_display': '₹2,600.00',
        'modal_price_display': '₹2,400.00',
        'price_per_kg_paise': 2400,
        'price_per_kg_display': '₹24.00 / kg',
        'unit': 'Quintal',
        'arrival_date': '2026-10-09',
        'source': 'data.gov.in AGMARKNET',
      };

      final item = MarketPriceItem.fromJson(json);

      expect(item.commodity, 'Paddy');
      expect(item.market, 'Madurai');
      expect(item.district, 'Madurai');
      expect(item.state, 'Tamil Nadu');
      expect(item.variety, 'Ponni');
      expect(item.modalPricePaise, 240000);
      expect(item.modalPriceDisplay, '₹2,400.00');
      expect(item.pricePerKgPaise, 2400);
      expect(item.pricePerKgDisplay, '₹24.00 / kg');
      expect(item.unit, 'Quintal');
      expect(item.arrivalDate, '2026-10-09');
      expect(item.source, 'data.gov.in AGMARKNET');
    });

    test('Handles missing / null fields gracefully', () {
      final json = <String, dynamic>{
        'commodity': 'Tomato',
      };

      final item = MarketPriceItem.fromJson(json);

      expect(item.commodity, 'Tomato');
      expect(item.variety, 'Unknown');
      expect(item.grade, 'Unknown');
      expect(item.modalPricePaise, 0);
      expect(item.modalPriceDisplay, 'Unavailable');
      expect(item.unit, 'Unknown');
    });
  });

  group('MarketPriceListResponse Model Tests', () {
    test('Parses list response with metadata and records', () {
      final json = {
        'count': 1,
        'live': true,
        'source': 'data.gov.in AGMARKNET',
        'message': 'Live government mandi rates retrieved successfully.',
        'records': [
          {
            'price_id': 'mp_tomato_madurai_2026-10-09',
            'commodity': 'Tomato',
            'market': 'Madurai',
            'state': 'Tamil Nadu',
            'district': 'Madurai',
            'variety': 'Hybrid',
            'grade': 'FAQ',
            'min_price_paise': 180000,
            'max_price_paise': 220000,
            'modal_price_paise': 200000,
            'min_price_display': '₹1,800.00',
            'max_price_display': '₹2,200.00',
            'modal_price_display': '₹2,000.00',
            'price_per_kg_paise': 2000,
            'price_per_kg_display': '₹20.00 / kg',
            'unit': 'Quintal',
            'arrival_date': '2026-10-09',
            'source': 'data.gov.in AGMARKNET',
          }
        ],
      };

      final response = MarketPriceListResponse.fromJson(json);

      expect(response.count, 1);
      expect(response.isLive, true);
      expect(response.records.length, 1);
      expect(response.records.first.commodity, 'Tomato');
      expect(response.records.first.modalPriceDisplay, '₹2,000.00');
    });
  });
}
