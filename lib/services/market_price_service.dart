import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/market_price.dart';

/// Service responsible for fetching official Government market rates
/// exclusively through the VayalConnect FastAPI backend.
///
/// NOTE: Never connects directly to data.gov.in and holds NO API keys.
class MarketPriceService {
  final http.Client _client;

  MarketPriceService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch list of real mandi market prices with optional filters.
  Future<MarketPriceListResponse> fetchMarketPrices({
    String? commodity,
    String? state,
    String? district,
    String? market,
    int limit = 20,
    int offset = 0,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };

    if (commodity != null && commodity.trim().isNotEmpty) {
      queryParams['commodity'] = commodity.trim();
    }
    if (state != null && state.trim().isNotEmpty) {
      queryParams['state'] = state.trim();
    }
    if (district != null && district.trim().isNotEmpty) {
      queryParams['district'] = district.trim();
    }
    if (market != null && market.trim().isNotEmpty) {
      queryParams['market'] = market.trim();
    }

    final uri = Uri.parse(ApiConfig.marketPricesUrl).replace(queryParameters: queryParams);

    try {
      final response = await _client.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'VayalConnect-Flutter/1.0',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;

        if (decoded['success'] == true && decoded['data'] != null) {
          return MarketPriceListResponse.fromJson(decoded['data'] as Map<String, dynamic>);
        } else {
          final errMsg = decoded['error']?['message'] ?? 'Unable to retrieve market prices.';
          throw Exception(errMsg);
        }
      } else {
        throw Exception('Server returned status code ${response.statusCode}');
      }
    } on SocketException catch (_) {
      throw Exception(
        'Unable to connect to VayalConnect backend server. '
        'Please check your internet connection or ensure the backend is running.',
      );
    } on TimeoutException catch (_) {
      throw Exception('Request timed out while waiting for market prices.');
    } on FormatException catch (_) {
      throw Exception('Received an invalid response format from the server.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Unexpected error: $e');
    }
  }

  /// Fetch available filter options (commodities and districts)
  Future<FilterOptions> fetchFilterOptions() async {
    final uri = Uri.parse(ApiConfig.filterOptionsUrl);

    try {
      final response = await _client.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'VayalConnect-Flutter/1.0',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        if (decoded['success'] == true && decoded['data'] != null) {
          return FilterOptions.fromJson(decoded['data'] as Map<String, dynamic>);
        }
      }
    } catch (_) {
      // Fallback to offline defaults if service unreachable
    }

    return FilterOptions(
      commodities: [
        'Paddy',
        'Tomato',
        'Onion',
        'Potato',
        'Brinjal',
        'Banana',
        'Coconut',
        'Cotton',
        'Turmeric',
        'Maize',
        'Sugarcane',
        'Groundnut',
        'Chilli',
      ],
      districts: [
        'Madurai',
        'Coimbatore',
        'Salem',
        'Tiruchirappalli',
        'Dindigul',
        'Thanjavur',
        'Erode',
        'Tirunelveli',
        'Vellore',
        'Theni',
      ],
      defaultState: 'Tamil Nadu',
    );
  }

  /// Close the HTTP client
  void dispose() {
    _client.close();
  }
}
