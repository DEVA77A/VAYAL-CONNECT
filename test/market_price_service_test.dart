import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vayalconnect_flutter/services/market_price_service.dart';

class MockHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.BaseRequest request) _handler;

  MockHttpClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

void main() {
  group('MarketPriceService Tests', () {
    test('Successfully fetches and parses market prices from backend', () async {
      final mockClient = MockHttpClient((request) async {
        expect(request.url.path, '/api/v1/market-prices');
        expect(request.url.queryParameters['commodity'], 'Paddy');

        final responseBody = json.encode({
          'success': true,
          'data': {
            'count': 1,
            'live': true,
            'source': 'data.gov.in AGMARKNET',
            'message': 'Live government mandi rates retrieved successfully.',
            'records': [
              {
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
              }
            ],
          },
          'error': null,
          'request_id': 'req-test-123',
        });

        return http.Response(responseBody, 200, headers: {
          'content-type': 'application/json',
        });
      });

      final service = MarketPriceService(client: mockClient);
      final result = await service.fetchMarketPrices(commodity: 'Paddy');

      expect(result.count, 1);
      expect(result.isLive, true);
      expect(result.records.first.commodity, 'Paddy');
      expect(result.records.first.modalPriceDisplay, '₹2,400.00');
      expect(result.records.first.pricePerKgDisplay, '₹24.00 / kg');
    });

    test('Throws informative exception when backend returns error', () async {
      final mockClient = MockHttpClient((request) async {
        final responseBody = json.encode({
          'success': false,
          'data': null,
          'error': {
            'code': 'SERVICE_UNAVAILABLE',
            'message': 'Government mandi service temporarily unreachable.',
          },
          'request_id': 'req-err-456',
        });

        return http.Response(responseBody, 200, headers: {
          'content-type': 'application/json',
        });
      });

      final service = MarketPriceService(client: mockClient);

      expect(
        () => service.fetchMarketPrices(commodity: 'NonExistent'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
