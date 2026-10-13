// Backend-only market reads and UI trust checks; no live providers.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vayalconnect_flutter/services/market_price_service.dart';
import 'package:vayalconnect_flutter/widgets/market_reference_view.dart';

void main() {
  test('arbitrary new categories and Tamil crop names use backend GET only',
      () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      expect(request.method, 'GET');
      expect(request.url.host, isNot('api.groq.com'));
      expect(request.headers.containsKey('x-api-key'), isFalse);
      return http.Response(
          jsonEncode({
            'success': true,
            'data': request.url.path.endsWith('filter-options')
                ? {
                    'commodities': ['மல்லிகை', 'Novel flower'],
                    'categories': ['New flower category'],
                    'districts': ['Madurai']
                  }
                : {
                    'records': [],
                    'count': 0,
                    'live': false,
                    'source': 'Market cache'
                  }
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final service = MarketPriceService(client: client);
    final options = await service.fetchFilterOptions();
    expect(options.categories, ['New flower category']);
    expect(options.commodities, contains('மல்லிகை'));
    await service.fetchMarketPrices(
        commodity: 'மல்லிகை', category: 'New flower category');
    expect(
        requests.last.url.queryParameters['category'], 'New flower category');
    expect(requests.last.url.queryParameters['commodity'], 'மல்லிகை');
    service.dispose();
  });

  testWidgets('unverified numeric estimates remain unavailable',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: MarketReferenceView(reference: {
      'reference_price_available': true,
      'government_reference_price_paise': 12345,
      'reference_verification_status': 'unverified',
      'reference_price_unit': 'bunch',
    }))));
    expect(find.text('Market price unavailable'), findsOneWidget);
    expect(find.textContaining('123.45'), findsNothing);
  });

  test('Flutter source contains no Groq endpoint, key or API configuration',
      () {
    for (final file
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      expect(source.contains('api.groq.com'), isFalse, reason: file.path);
      expect(source.contains('GROQ_API_KEY'), isFalse, reason: file.path);
      expect(source.contains('gsk_'), isFalse, reason: file.path);
    }
  });
}
