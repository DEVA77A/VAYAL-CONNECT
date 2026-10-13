import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../fixtures/demo_fixtures.dart';
import '../models/product_models.dart';
import 'session_manager.dart';

/// Product Service connecting exclusively to the VayalConnect FastAPI backend.
/// In production mode, network and backend errors are raised honestly.
/// Sample fixtures are isolated and returned ONLY when isDemoMode is active.
class ProductService {
  final http.Client _client;

  ProductService({http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> _headers() {
    final token = SessionManager().accessToken;
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': 'VayalConnect-Flutter/1.0',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Fetch active marketplace products for buyers
  Future<List<BuyerProduct>> fetchBuyerProducts({
    String? category,
    String? location,
    int page = 1,
    int limit = 20,
  }) async {
    // Isolated Demo Preview Mode
    if (!kReleaseMode && SessionManager().isDemoMode) {
      final samples = DemoFixtures.sampleBuyerProducts();
      if (category != null &&
          category.isNotEmpty &&
          category != 'All' &&
          category != 'அனைத்தும்') {
        return samples
            .where((p) =>
                p.category.toLowerCase().contains(category.toLowerCase()))
            .toList();
      }
      return samples;
    }

    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (category != null &&
        category.isNotEmpty &&
        category != 'All' &&
        category != 'அனைத்தும்') {
      queryParams['category'] = category;
    }
    if (location != null && location.isNotEmpty) {
      queryParams['location'] = location;
    }

    final uri =
        Uri.parse(ApiConfig.productsUrl).replace(queryParameters: queryParams);

    try {
      final response = await _client
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        if (decoded['success'] == true && decoded['data'] != null) {
          final items = decoded['data']['items'] as List<dynamic>? ?? [];
          return items
              .map((i) => BuyerProduct.fromJson(i as Map<String, dynamic>))
              .toList();
        } else {
          final msg = decoded['error']?['message'] ??
              'Unable to retrieve marketplace products.';
          throw Exception(msg);
        }
      } else {
        throw Exception(
            'Server returned status ${response.statusCode} while fetching products.');
      }
    } on SocketException catch (_) {
      throw Exception(
        'Unable to connect to VayalConnect backend at ${ApiConfig.baseUrl}. '
        'Please ensure the FastAPI backend is running.',
      );
    } on TimeoutException catch (_) {
      throw Exception(
          'Request timed out while connecting to VayalConnect server.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Product service error: $e');
    }
  }

  /// Fetch farmer's own product listings
  Future<List<FarmerProduct>> fetchMyFarmerProducts({
    int page = 1,
    int limit = 20,
  }) async {
    // Isolated Demo Preview Mode
    if (!kReleaseMode && SessionManager().isDemoMode) {
      return DemoFixtures.sampleFarmerProducts();
    }

    final uri = Uri.parse(ApiConfig.myProductsUrl).replace(queryParameters: {
      'page': page.toString(),
      'limit': limit.toString(),
    });

    try {
      final response = await _client
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        if (decoded['success'] == true && decoded['data'] != null) {
          final items = decoded['data']['items'] as List<dynamic>? ?? [];
          return items
              .map((i) => FarmerProduct.fromJson(i as Map<String, dynamic>))
              .toList();
        } else {
          final msg = decoded['error']?['message'] ??
              'Failed to retrieve your listings.';
          throw Exception(msg);
        }
      } else if (response.statusCode == 401) {
        throw Exception(
            'Session expired or unauthorized. Please log in again.');
      } else {
        throw Exception('Server returned status ${response.statusCode}');
      }
    } on SocketException catch (_) {
      throw Exception(
        'Unable to connect to backend at ${ApiConfig.baseUrl}. Please check server connection.',
      );
    } on TimeoutException catch (_) {
      throw Exception('Request timed out while fetching farmer products.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Farmer products error: $e');
    }
  }

  /// Create a new crop listing as farmer
  Future<FarmerProduct> createProduct(CreateProductPayload payload) async {
    if (!kReleaseMode && SessionManager().isDemoMode) {
      // In isolated demo mode, return simulated response based on user input
      return FarmerProduct(
        productId: 'demo-created-${DateTime.now().millisecondsSinceEpoch}',
        productName: payload.productName,
        category: payload.category,
        quantityAvailable: payload.quantity,
        quantityUnit: payload.quantityUnit,
        qualityGrade: payload.qualityGrade,
        location: payload.location,
        market: payload.market,
        harvestDate: payload.harvestDate,
        farmerPayoutPerUnitPaise: payload.sellingPricePerUnitPaise,
        farmerPayoutPerUnitDisplay:
            '₹${(payload.sellingPricePerUnitPaise / 100).toStringAsFixed(2)} / ${payload.quantityUnit}',
        status: 'ACTIVE',
      );
    }

    final uri = Uri.parse(ApiConfig.productsUrl);

    try {
      final response = await _client
          .post(
            uri,
            headers: _headers(),
            body: json.encode(payload.toJson()),
          )
          .timeout(const Duration(seconds: 15));

      final decoded = json.decode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 201 &&
          decoded['success'] == true &&
          decoded['data'] != null) {
        return FarmerProduct.fromJson(decoded['data'] as Map<String, dynamic>);
      } else {
        throw Exception(decoded['error']?['message'] ??
            'Failed to list product on server.');
      }
    } on SocketException catch (_) {
      throw Exception(
          'Cannot connect to backend server at ${ApiConfig.baseUrl}.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Create crop failed: $e');
    }
  }

  Future<Map<String, dynamic>> fetchPriceReference(
      {required String commodity, String? market, required String unit}) async {
    if (!kReleaseMode && SessionManager().isDemoMode) {
      throw Exception('Sign in to look up a verified reference.');
    }
    final uri = Uri.parse('${ApiConfig.productsUrl}price-reference')
        .replace(queryParameters: {'commodity': commodity, 'unit': unit});
    final response = await _client
        .get(uri, headers: _headers())
        .timeout(const Duration(seconds: 20));
    final decoded = jsonDecode(response.body);
    if (response.statusCode != 200 ||
        decoded is! Map ||
        decoded['success'] != true ||
        decoded['data'] is! Map) {
      throw Exception(decoded is Map
          ? (decoded['error']?['message'] ?? 'Reference unavailable.')
          : 'Reference unavailable.');
    }
    return Map<String, dynamic>.from(decoded['data']);
  }

  void dispose() {
    _client.close();
  }
}
