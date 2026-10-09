import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../fixtures/demo_fixtures.dart';
import '../models/dashboard_models.dart';
import 'session_manager.dart';

class AdminService {
  final http.Client _client;

  AdminService({http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> _headers() {
    final token = SessionManager().accessToken;
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': 'VayalConnect-Flutter/1.0',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Fetch Admin Dashboard Aggregate Metrics
  Future<AdminDashboardMetrics> fetchDashboardMetrics() async {
    if (SessionManager().isDemoMode) {
      return DemoFixtures.sampleAdminMetrics();
    }

    final uri = Uri.parse(ApiConfig.adminDashboardUrl);

    try {
      final response = await _client.get(uri, headers: _headers()).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        if (decoded['success'] == true && decoded['data'] != null) {
          return AdminDashboardMetrics.fromJson(decoded['data'] as Map<String, dynamic>);
        } else {
          throw Exception(decoded['error']?['message'] ?? 'Failed to load admin metrics.');
        }
      } else {
        throw Exception('Server returned status ${response.statusCode}');
      }
    } on SocketException catch (_) {
      throw Exception('Unable to reach server at ${ApiConfig.baseUrl}.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Admin dashboard error: $e');
    }
  }

  /// Approve farmer account
  Future<void> approveFarmer(String userId) async {
    if (SessionManager().isDemoMode) return;

    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/admin/farmers/$userId/approve');
    final response = await _client.post(uri, headers: _headers(), body: json.encode({}));
    if (response.statusCode != 200) {
      throw Exception('Failed to approve farmer. Status code ${response.statusCode}');
    }
  }

  /// Reject farmer account
  Future<void> rejectFarmer(String userId, String reason) async {
    if (SessionManager().isDemoMode) return;

    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/admin/farmers/$userId/reject');
    final response = await _client.post(uri, headers: _headers(), body: json.encode({'reason': reason}));
    if (response.statusCode != 200) {
      throw Exception('Failed to reject farmer. Status code ${response.statusCode}');
    }
  }

  void dispose() {
    _client.close();
  }
}
