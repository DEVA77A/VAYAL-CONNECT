import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vayalconnect_flutter/config/api_config.dart';
import 'package:vayalconnect_flutter/services/market_price_service.dart';
import 'package:vayalconnect_flutter/services/product_service.dart';

void main() {
  test('market and crop reference reads use backend GETs without AI or refresh',
      () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      expect(request.url.host, Uri.parse(ApiConfig.baseUrl).host);
      expect(request.method, 'GET');
      expect(request.body, isEmpty);
      expect(request.url.queryParameters.containsKey('refresh'), isFalse);
      expect(request.headers.containsKey('x-goog-api-key'), isFalse);
      expect(request.url.queryParameters.containsKey('key'), isFalse);
      final isReference = request.url.path.endsWith('price-reference');
      expect(
          request.url.path,
          isReference
              ? '/api/v1/products/price-reference'
              : '/api/v1/market-prices');
      return http.Response(
          jsonEncode({
            'success': true,
            'data': isReference
                ? {
                    'reference_price_available': false,
                    'reference_price_message':
                        'Verified cached price unavailable.'
                  }
                : {
                    'records': [],
                    'count': 0,
                    'live': false,
                    'source': 'Gemini grounded discovery (Cached)',
                    'message': 'Verified cached price unavailable.'
                  }
          }),
          200);
    });
    final markets = MarketPriceService(client: client);
    final products = ProductService(client: client);
    for (final crop in [
      'Jasmine',
      'Tomato',
      'Mango',
      'Novel aromatic seedling'
    ]) {
      final result = await markets.fetchMarketPrices(commodity: crop);
      expect(result.isLive, isFalse);
      expect(result.records, isEmpty);
      final reference = await products.fetchPriceReference(
          commodity: crop, market: 'Coimbatore', unit: 'KG');
      expect(reference['reference_price_available'], isFalse);
    }
    expect(requests, hasLength(8));
    expect(requests.map((r) => r.url.queryParameters['commodity']).toSet(),
        {'Jasmine', 'Tomato', 'Mango', 'Novel aromatic seedling'});
    markets.dispose();
  });
}
