import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../utils/commerce_strings.dart';
import 'session_manager.dart';

class ApiClient {
  final http.Client client;
  ApiClient({http.Client? client}) : client = client ?? http.Client();
  Future<dynamic> request(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    final request =
        http.Request(method, Uri.parse('${ApiConfig.baseUrl}$path'));
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (SessionManager().accessToken != null)
        'Authorization': 'Bearer ${SessionManager().accessToken}'
    });
    if (body != null) request.body = jsonEncode(body);
    try {
      final response =
          await http.Response.fromStream(await client.send(request))
              .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map ||
          response.statusCode >= 400 ||
          decoded['success'] != true) {
        final error = decoded is Map ? decoded['error'] : null;
        final code = error is Map ? error['code'] : null;
        if (response.statusCode == 401) {
          throw Exception(S.t('Session expired. Sign in again.'));
        }
        if (code == 'FARMER_NOT_APPROVED') {
          throw Exception(
              S.t('Complete onboarding and obtain administrator approval.'));
        }
        if (code == 'PAYMENT_CREATING') {
          throw Exception(
              S.t('Payment request in progress. Retry after one minute.'));
        }
        if (code == 'ORDER_RESERVATION_EXPIRED') {
          throw Exception(
              S.t('Stock reservation expired. Select the crop again.'));
        }
        if (code == 'PRICE_CHANGED') {
          throw Exception(S.t('Price changed. Reload before ordering.'));
        }
        if (code == 'MARKET_SOURCE_UNAVAILABLE') {
          throw Exception(
              S.t('Official market source unavailable. Please retry later.'));
        }
        if (response.statusCode == 422) {
          throw Exception(S.t('Check the required fields and values.'));
        }
        if (response.statusCode == 403) {
          throw Exception(S.t('This action is unavailable for your account.'));
        }
        if (response.statusCode == 409) {
          throw Exception(S.t('Data changed. Reload before retrying.'));
        }
        throw Exception(S.t('Unable to complete this request. Please retry.'));
      }
      return decoded['data'];
    } on TimeoutException {
      throw Exception(S.t('Request timed out. Please retry.'));
    } on FormatException {
      throw Exception(S.t('Invalid server response. Please retry.'));
    } on http.ClientException {
      throw Exception(S.t('Cannot reach the server. Check your connection.'));
    }
  }

  void dispose() => client.close();
}
