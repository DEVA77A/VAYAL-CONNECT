import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../fixtures/demo_fixtures.dart';
import '../models/dashboard_models.dart';
import 'session_manager.dart';

class FarmerService {
  final http.Client _client;

  FarmerService({http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> _headers() {
    final token = SessionManager().accessToken;
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': 'VayalConnect-Flutter/1.0',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Fetch Farmer Dashboard Metrics
  Future<FarmerDashboardMetrics> fetchDashboardMetrics() async {
    if (SessionManager().isDemoMode) {
      return DemoFixtures.sampleFarmerMetrics();
    }

    final uri = Uri.parse(ApiConfig.farmerDashboardUrl);

    try {
      final response = await _client.get(uri, headers: _headers()).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        if (decoded['success'] == true && decoded['data'] != null) {
          return FarmerDashboardMetrics.fromJson(decoded['data'] as Map<String, dynamic>);
        } else {
          throw Exception(decoded['error']?['message'] ?? 'Failed to load farmer metrics.');
        }
      } else {
        throw Exception('Server returned status ${response.statusCode}');
      }
    } on SocketException catch (_) {
      throw Exception('Unable to reach server at ${ApiConfig.baseUrl}.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Farmer dashboard error: $e');
    }
  }

  Future<Map<String, dynamic>> fetchBankDetails() async {
    final response = await _client.get(Uri.parse('${ApiConfig.baseUrl}/api/v1/farmers/me/bank'), headers: _headers())
      .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw Exception('Unable to load bank details.');
    final data = jsonDecode(response.body);
    if (data is! Map || data['success'] != true || data['data'] is! Map) throw Exception('Invalid bank response.');
    return Map<String, dynamic>.from(data['data']);
  }

  void dispose() {
    _client.close();
  }
}
