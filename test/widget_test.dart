import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vayalconnect_flutter/main.dart';
import 'package:vayalconnect_flutter/screens/market_prices_screen.dart';
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
  testWidgets('MarketPricesScreen renders mandi prices from backend', (WidgetTester tester) async {
    final mockClient = MockHttpClient((request) async {
      if (request.url.path.contains('filter-options')) {
        return http.Response(
          json.encode({
            'success': true,
            'data': {
              'commodities': ['Paddy', 'Tomato'],
              'districts': ['Madurai', 'Salem'],
              'default_state': 'Tamil Nadu',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response(
        json.encode({
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
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final mockService = MarketPriceService(client: mockClient);

    await tester.pumpWidget(
      MaterialApp(
        home: MarketPricesScreen(service: mockService),
      ),
    );

    // Initial loading pump
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify produce item appears from mock backend response
    expect(find.text('Paddy'), findsOneWidget);
    expect(find.text('₹24.00 / kg'), findsOneWidget);
    expect(find.text('data.gov.in AGMARKNET'), findsOneWidget);
  });
}
