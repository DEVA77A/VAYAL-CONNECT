import 'package:http/http.dart' as http;
import 'api_client.dart';
import '../models/market_price.dart';
import '../utils/commerce_strings.dart';

/// Reads the backend's daily verified cache; never triggers AI discovery.
class MarketPriceService {
  late final ApiClient _api;
  MarketPriceService({http.Client? client}) {
    _api = ApiClient(client: client);
  }
  Future<MarketPriceListResponse> fetchMarketPrices(
      {String? commodity,
      String? state,
      String? district,
      String? market,
      String? category,
      int limit = 20,
      int offset = 0}) async {
    final query = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      'scope': 'market',
      if (commodity?.trim().isNotEmpty == true) 'commodity': commodity!.trim(),
      if (state?.trim().isNotEmpty == true) 'state': state!.trim(),
      if (district?.trim().isNotEmpty == true) 'district': district!.trim(),
      if (market?.trim().isNotEmpty == true) 'market': market!.trim(),
      if (category?.trim().isNotEmpty == true) 'category': category!.trim()
    };
    try {
      final data = await _api.request(
          Uri(path: '/api/v1/market-prices', queryParameters: query)
              .toString());
      return MarketPriceListResponse.fromJson(Map<String, dynamic>.from(data));
    } on ApiException catch (error) {
      if (error.code != 'MARKET_SOURCE_UNAVAILABLE') rethrow;
      return MarketPriceListResponse(
          records: [],
          count: 0,
          isLive: false,
          source: 'Market cache',
          message: S.t('Market price unavailable'));
    }
  }

  Future<FilterOptions> fetchFilterOptions() async {
    final data = await _api.request('/api/v1/market-prices/filter-options');
    return FilterOptions.fromJson(Map<String, dynamic>.from(data));
  }

  void dispose() => _api.dispose();
}
