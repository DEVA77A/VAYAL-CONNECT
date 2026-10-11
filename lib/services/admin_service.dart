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
  Future<AdminDashboardMetrics> fetchDashboardMetrics({String? period}) async {
    if (SessionManager().isDemoMode) {
      return DemoFixtures.sampleAdminMetrics();
    }

    final uri = Uri.parse(ApiConfig.adminDashboardUrl).replace(queryParameters: period == null ? null : {'period': period});

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
  Future<void> approveFarmer(String userId, {int applicationRevision = 0}) async {
    if (SessionManager().isDemoMode) return;

    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/admin/farmers/$userId/approve');
    final response = await _client.put(uri, headers: _headers(), body: json.encode({'application_revision': applicationRevision})).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Failed to approve farmer. Status code ${response.statusCode}');
    }
  }

  /// Reject farmer account
  Future<void> rejectFarmer(String userId, String reason, {int applicationRevision = 0}) async {
    if (SessionManager().isDemoMode) return;

    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/admin/farmers/$userId/reject');
    final response = await _client.put(uri, headers: _headers(), body: json.encode({'reason': reason, 'application_revision': applicationRevision})).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Failed to reject farmer. Status code ${response.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> fetchPendingFarmers() =>
      _fetchItems('/api/v1/admin/farmers?status=PENDING&limit=50');

  Future<List<Map<String, dynamic>>> fetchRecentOrders({String? period}) =>
      _fetchItems('/api/v1/reports/orders?limit=10${period == null ? '' : '&period=$period'}');

  Future<List<Map<String, dynamic>>> _fetchItems(String path) async {
    if (SessionManager().isDemoMode) return [];
    final response = await _client.get(Uri.parse('${ApiConfig.baseUrl}$path'), headers: _headers())
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw Exception('Unable to load administrator data. Please retry.');
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['success'] != true || decoded['data'] is! Map || decoded['data']['items'] is! List) {
      throw Exception('Invalid administrator response. Please retry.');
    }
    return (decoded['data']['items'] as List).map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  void dispose() {
    _client.close();
  }
}
