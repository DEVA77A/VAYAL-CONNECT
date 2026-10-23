import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../utils/commerce_strings.dart';
import 'session_manager.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? code, requestId;
  final String method, path;
  ApiException(this.message,
      {this.statusCode,
      this.code,
      this.requestId,
      required this.method,
      required this.path});
  @override
  String toString() => message;
}

class ApiClient {
  final http.Client client;
  ApiClient({http.Client? client}) : client = client ?? http.Client();
  Future<dynamic> request(String path,
      {String method = 'GET',
      Map<String, dynamic>? body,
      Duration timeout = const Duration(seconds: 20)}) async {
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
              .timeout(timeout);
      final decoded = jsonDecode(response.body);
      if (decoded is! Map ||
          response.statusCode >= 400 ||
          decoded['success'] != true) {
        final error = decoded is Map ? decoded['error'] : null;
        final code = error is Map ? error['code'] : null;
        Never fail(String message) => throw ApiException(message,
            statusCode: response.statusCode,
            code: code is String ? code : null,
            requestId: decoded is Map && decoded['request_id'] is String
                ? decoded['request_id'] as String
                : null,
            method: method,
            path: path);
        if (response.statusCode == 401) {
          fail(S.t('Session expired. Sign in again.'));
        }
        if (code == 'FARMER_NOT_APPROVED') {
          fail(S.t('Complete onboarding and obtain administrator approval.'));
        }
        if (code == 'PAYMENT_CREATING') {
          fail(S.t('Payment request in progress. Retry after one minute.'));
        }
        if (code == 'ORDER_RESERVATION_EXPIRED') {
          fail(S.t('Stock reservation expired. Select the crop again.'));
        }
        if (code == 'PRICE_CHANGED') {
          fail(S.t('Price changed. Reload before ordering.'));
        }
        if (code == 'MARKET_SOURCE_UNAVAILABLE') {
          fail(S.t(
              'Verified cached price unavailable. Daily discovery runs at 06:00 IST.'));
        }
        // Domain errors are safe backend messages. Preserve their meaning,
        // especially missing profiles, incomplete payout details and revisions.
        if (response.statusCode < 500 &&
            error is Map &&
            error['message'] is String &&
            (error['message'] as String).isNotEmpty) {
          var message = error['message'] as String;
          final fields = error['fields'];
          if (response.statusCode == 422 && fields is List) {
            final names = fields
                .whereType<Map>()
                .map((f) => f['location'])
                .whereType<List>()
                .map((loc) => loc.skip(1).join('.'))
                .where((name) => name.isNotEmpty)
                .toSet();
            if (names.isNotEmpty) message = '$message (${names.join(', ')})';
          }
          fail(S.t(message));
        }
        if (response.statusCode == 422) {
          fail(S.t('Check the required fields and values.'));
        }
        if (response.statusCode == 403) {
          fail(S.t('This action is unavailable for your account.'));
        }
        if (response.statusCode == 409) {
          fail(S.t('Data changed. Reload before retrying.'));
        }
        if (response.statusCode == 404) {
          fail(S.t(
              'Requested record or service was not found. Refresh and retry.'));
        }
        if (response.statusCode >= 500) {
          fail(S.t('Server is temporarily unavailable. Please retry shortly.'));
        }
        fail(S.t('Unable to complete this request. Please retry.'));
      }
      return decoded['data'];
    } on TimeoutException {
      throw ApiException(
          S.t('Request timed out. Refresh to check whether your changes were saved before retrying.'),
          method: method,
          path: path);
    } on FormatException {
      throw ApiException(S.t('Invalid server response. Please retry.'),
          method: method, path: path);
    } on http.ClientException {
      throw ApiException(S.t('Cannot reach the server. Check your connection.'),
          method: method, path: path);
    }
  }

  void dispose() => client.close();
}
