import '../utils/commerce_strings.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../fixtures/demo_fixtures.dart';
import '../models/order_models.dart';
import 'session_manager.dart';

/// Order Service connecting exclusively to the VayalConnect FastAPI backend.
/// Strictly throws informative errors upon network or API failures.
class OrderService {
  final http.Client _client;
  final Map<String, String> _checkoutKeys = {};

  OrderService({http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> _headers() {
    final token = SessionManager().accessToken;
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': 'VayalConnect-Flutter/1.0',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Create order as Buyer (Backend calculates pricing from snapshot)
  Future<BuyerOrder> createOrder({
    required String productId,
    required int quantity,
    required String fulfillmentMethod,
    int? expectedUnitPricePaise,
    Map<String, dynamic>? deliveryAddress,
  }) async {
    // Isolated Demo Preview Mode
    if (!kReleaseMode && SessionManager().isDemoMode) {
      return BuyerOrder(
        orderId: 'demo-ord-${DateTime.now().millisecondsSinceEpoch}',
        orderNumber:
            'VY-${1000 + (DateTime.now().millisecondsSinceEpoch % 8000)}',
        productName: 'விளைபொருள் (Sample Harvest)',
        quantity: quantity,
        unit: 'QUINTAL',
        buyerUnitPricePaise: 245000,
        buyerUnitPriceDisplay: '₹2,450 / Quintal',
        buyerTotalPaise: quantity * 245000,
        buyerTotalDisplay: '₹${(quantity * 2450).toString()}',
        orderStatus: 'PENDING_PAYMENT',
        paymentStatus: 'PENDING',
        createdAt: '2026-10-09',
      );
    }

    final payload = {
      'product_id': productId,
      'quantity': quantity,
      'fulfillment_method': fulfillmentMethod,
      if (expectedUnitPricePaise != null)
        'expected_unit_price_paise': expectedUnitPricePaise,
      if (deliveryAddress != null) 'delivery_address': deliveryAddress
    };
    final fingerprint = jsonEncode(payload);
    final key = _checkoutKeys.putIfAbsent(
        fingerprint,
        () => List.generate(
            24,
            (_) => Random.secure()
                .nextInt(256)
                .toRadixString(16)
                .padLeft(2, '0')).join());
    payload['idempotency_key'] = key;
    final uri = Uri.parse(ApiConfig.ordersUrl);

    try {
      final response = await _client
          .post(
            uri,
            headers: _headers(),
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 15));

      final decoded = json.decode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 201 &&
          decoded['success'] == true &&
          decoded['data'] != null) {
        return BuyerOrder.fromJson(decoded['data'] as Map<String, dynamic>);
      } else {
        final msg = response.statusCode == 409
            ? S.t('Price changed. Reload before ordering.')
            : S.t('Unable to complete this request. Please retry.');
        throw Exception(msg);
      }
    } on SocketException catch (_) {
      throw Exception(S.t('Cannot reach the server. Check your connection.'));
    } on TimeoutException catch (_) {
      throw Exception(S.t('Request timed out. Please retry.'));
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Create order failed: $e');
    }
  }

  /// Fetch Buyer Orders
  Future<List<BuyerOrder>> fetchBuyerOrders() async {
    if (!kReleaseMode && SessionManager().isDemoMode) {
      return DemoFixtures.sampleBuyerOrders();
    }

    final uri = Uri.parse(ApiConfig.ordersUrl);

    try {
      final response = await _client
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        if (decoded['success'] == true && decoded['data'] != null) {
          final items = decoded['data']['items'] as List<dynamic>? ?? [];
          return items
              .map((i) => BuyerOrder.fromJson(i as Map<String, dynamic>))
              .toList();
        } else {
          throw Exception(
              decoded['error']?['message'] ?? 'Failed to load buyer orders.');
        }
      } else {
        throw Exception('Server returned status ${response.statusCode}');
      }
    } on SocketException catch (_) {
      throw Exception('Unable to reach server at ${ApiConfig.baseUrl}.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Buyer orders error: $e');
    }
  }

  /// Fetch Farmer Orders (payout view)
  Future<List<FarmerOrder>> fetchFarmerOrders() async {
    if (!kReleaseMode && SessionManager().isDemoMode) {
      return DemoFixtures.sampleFarmerOrders();
    }

    final uri = Uri.parse(ApiConfig.ordersUrl);

    try {
      final response = await _client
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        if (decoded['success'] == true && decoded['data'] != null) {
          final items = decoded['data']['items'] as List<dynamic>? ?? [];
          return items
              .map((i) => FarmerOrder.fromJson(i as Map<String, dynamic>))
              .toList();
        } else {
          throw Exception(
              decoded['error']?['message'] ?? 'Failed to load farmer orders.');
        }
      } else {
        throw Exception('Server returned status ${response.statusCode}');
      }
    } on SocketException catch (_) {
      throw Exception('Unable to reach server at ${ApiConfig.baseUrl}.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Farmer orders error: $e');
    }
  }

  void dispose() {
    _client.close();
  }
}
