import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/auth_models.dart';
import 'session_manager.dart';

import '../utils/localization.dart';

class AuthService {
  final http.Client _client;

  AuthService({http.Client? client}) : _client = client ?? http.Client();

  /// Login with email and password to the VayalConnect FastAPI backend
  Future<AuthTokenResponse> login(String email, String password) async {
    final uri = Uri.parse(ApiConfig.loginUrl);

    try {
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'VayalConnect-Flutter/1.0',
        },
        body: json.encode({
          'email': email.trim().toLowerCase(),
          'password': password,
        }),
      ).timeout(const Duration(seconds: 15));

      final decoded = _decodeResponse(response);

      if (response.statusCode == 200 && decoded['success'] == true && decoded['data'] != null) {
        final data = decoded['data'] as Map<String, dynamic>;
        if (data['access_token'] is! String || (data['access_token'] as String).isEmpty ||
            data['user'] is! Map<String, dynamic> || data['user']['id'] is! String) {
          throw Exception('Invalid server response. Please try again later.');
        }
        final authData = AuthTokenResponse.fromJson(data);
        SessionManager().setSession(
          token: authData.accessToken,
          user: authData.user,
        );
        return authData;
      } else if (response.statusCode == 401) {
        throw Exception(VayalStrings.errorInvalidCredentials);
      } else {
        final errMsg = decoded['error']?['message'] ?? VayalStrings.errorInvalidCredentials;
        throw Exception(errMsg);
      }
    } on SocketException catch (_) {
      throw Exception(VayalStrings.errorNoNetwork);
    } on http.ClientException catch (_) {
      throw Exception(VayalStrings.errorBackendUnavailable);
    } on TimeoutException catch (_) {
      throw Exception(VayalStrings.errorTimeout);
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception(VayalStrings.errorBackendUnavailable);
    }
  }

  /// Register a new account on the VayalConnect backend
  Future<String> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String address,
    required String areaLocation,
    required String gender,
    required int age,
    String preferredLanguage = 'en',
    double? latitude,
    double? longitude,
  }) async {
    final uri = Uri.parse(ApiConfig.registerUrl);

    try {
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'VayalConnect-Flutter/1.0',
        },
        body: json.encode({
          'name': name.trim(),
          'email': email.trim().toLowerCase(),
          'phone': phone.trim(),
          'password': password,
          'address': address.trim(),
          'area_location': areaLocation.trim(),
          'gender': gender.toLowerCase(),
          'age': age,
          'preferred_language': preferredLanguage,
          if (latitude != null && longitude != null) 'latitude': latitude,
          if (latitude != null && longitude != null) 'longitude': longitude,
        }),
      ).timeout(const Duration(seconds: 15));

      final decoded = _decodeResponse(response);
      if (response.statusCode == 201 && decoded['success'] == true) {
        return decoded['data']?['user_id'] as String? ?? '';
      } else {
        throw Exception(_authenticationError(decoded, 'Registration failed. Please try again.'));
      }
    } on SocketException catch (_) {
      throw Exception('Unable to connect to server at ${ApiConfig.baseUrl}.');
    } on TimeoutException catch (_) {
      throw Exception(
        'Connection timed out. Connect your phone and laptop to the same Wi-Fi '
        'and check that the backend is running at ${ApiConfig.baseUrl}.',
      );
    } on http.ClientException catch (_) {
      throw Exception(
        'Cannot reach ${ApiConfig.baseUrl}. Check the backend and connect '
        'your phone and laptop to the same Wi-Fi.',
      );
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Registration error: $e');
    }
  }

  /// Request OTP for email verification or registration
  Future<String> requestOtp(String email, {String purpose = 'REGISTRATION'}) async {
    final uri = Uri.parse(ApiConfig.requestOtpUrl);

    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: json.encode({
          'email': email.trim().toLowerCase(),
          'purpose': purpose,
        }),
      ).timeout(const Duration(seconds: 12));

      final decoded = _decodeResponse(response);
      if (response.statusCode == 200 && decoded['success'] == true) {
        return decoded['data']?['message'] as String? ?? 'OTP sent to your email.';
      } else {
        throw Exception(_authenticationError(decoded, 'Unable to send OTP. Please try again later.'));
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('OTP request failed: $e');
    }
  }

  /// Verify OTP
  Future<bool> verifyOtp(String email, String otp, {String purpose = 'REGISTRATION'}) async {
    final uri = Uri.parse(ApiConfig.verifyOtpUrl);

    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: json.encode({
          'email': email.trim().toLowerCase(),
          'otp': otp.trim(),
          'purpose': purpose,
        }),
      ).timeout(const Duration(seconds: 12));

      final decoded = _decodeResponse(response);
      if (response.statusCode == 200 && decoded['success'] == true) {
        return decoded['data']?['verified'] == true;
      } else {
        throw Exception(decoded['error']?['message'] ?? 'Invalid OTP entered.');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('OTP verification failed: $e');
    }
  }

  /// Select role (FARMER or BUYER)
  Future<String> selectRole(AppRole role) async {
    final uri = Uri.parse(ApiConfig.selectRoleUrl);
    final token = SessionManager().accessToken;

    try {
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({'role': role.value}),
      ).timeout(const Duration(seconds: 12));

      final decoded = _decodeResponse(response);
      if (response.statusCode == 200 && decoded['success'] == true) {
        SessionManager().switchRole(role);
        return decoded['data']?['message'] as String? ?? 'Role assigned successfully.';
      } else {
        throw Exception(decoded['error']?['message'] ?? 'Failed to update user role.');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Role selection error: $e');
    }
  }

  /// Request password reset OTP
  Future<String> forgotPassword(String email) async {
    final uri = Uri.parse(ApiConfig.forgotPasswordUrl);

    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: json.encode({'email': email.trim().toLowerCase()}),
      ).timeout(const Duration(seconds: 12));

      final decoded = _decodeResponse(response);
      if (response.statusCode == 200 && decoded['success'] == true) {
        return decoded['data']?['message'] as String? ?? 'OTP sent to your email.';
      } else {
        throw Exception(decoded['error']?['message'] ?? 'Failed to send reset OTP.');
      }
    } on SocketException catch (_) {
      throw Exception(VayalStrings.errorNoNetwork);
    } on http.ClientException catch (_) {
      throw Exception(VayalStrings.errorBackendUnavailable);
    } on TimeoutException catch (_) {
      throw Exception(VayalStrings.errorTimeout);
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Forgot password error: $e');
    }
  }

  /// Reset password using OTP
  Future<String> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final uri = Uri.parse(ApiConfig.resetPasswordUrl);

    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: json.encode({
          'email': email.trim().toLowerCase(),
          'otp': otp.trim(),
          'new_password': newPassword,
        }),
      ).timeout(const Duration(seconds: 12));

      final decoded = _decodeResponse(response);
      if (response.statusCode == 200 && decoded['success'] == true) {
        return decoded['data']?['message'] as String? ?? 'Password reset successfully.';
      } else {
        throw Exception(decoded['error']?['message'] ?? 'Failed to reset password.');
      }
    } on SocketException catch (_) {
      throw Exception(VayalStrings.errorNoNetwork);
    } on http.ClientException catch (_) {
      throw Exception(VayalStrings.errorBackendUnavailable);
    } on TimeoutException catch (_) {
      throw Exception(VayalStrings.errorTimeout);
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Reset password error: $e');
    }
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
    final token = SessionManager().accessToken;
    if (token == null) throw Exception('Please sign in again.');
    final response = await _client.put(Uri.parse('${ApiConfig.baseUrl}/api/v1/users/me/password'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'current_password': currentPassword, 'new_password': newPassword}))
      .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('Unable to change password. Check your current password and new password requirements.');
  }

  Future<void> logout() async {
    final token = SessionManager().accessToken;
    if (token == null) return;
    final response = await _client.post(Uri.parse(ApiConfig.logoutUrl),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'})
      .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw Exception('Server sign-out could not be confirmed.');
  }

  String _authenticationError(Map<String, dynamic> decoded, String fallback) {
    final error = decoded['error'];
    final code = error is Map ? error['code'] : null;
    const messages = {
      'EMAIL_ALREADY_EXISTS': 'An account already uses this email. Sign in or complete its email verification.',
      'PHONE_ALREADY_EXISTS': 'An account already uses this phone number. Sign in to that account or use a different number.',
      'EMAIL_DELIVERY_FAILED': 'The OTP email could not be sent. Please try again later; your account is still unverified.',
      'OTP_COOLDOWN': 'Please wait 60 seconds before requesting another OTP.',
    };
    if (messages.containsKey(code)) return messages[code]!;

    // FastAPI validation responses contain user input; expose only static field hints.
    final details = decoded['detail'];
    if (details is List) {
      const hints = {
        'name': 'Enter a name between 2 and 100 characters.',
        'email': 'Enter a valid email address.',
        'phone': 'Enter a valid phone number: 10 digits, or +91 followed by 10 digits. Do not use spaces or hyphens.',
        'password': 'Use 8-128 characters with an uppercase letter and a number.',
        'address': 'Enter an address between 5 and 500 characters.',
        'area_location': 'Enter a location between 2 and 200 characters.',
        'age': 'Enter an age between 18 and 120.',
        'gender': 'Select a valid gender.',
        'preferred_language': 'Select English or Tamil.',
        'purpose': 'Unable to request verification. Please use the registration verification option.',
      };
      final selected = <String>{};
      for (final detail in details) {
        if (detail is! Map) continue;
        final location = detail['loc'];
        if (location is List && location.length == 2 && location[0] == 'body') {
          final hint = hints[location[1]];
          if (hint != null) selected.add(hint);
        }
      }
      if (selected.isNotEmpty) return selected.take(3).join(' ');
    }
    return fallback;
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw Exception('Invalid server response. Please try again later.');
  }

  void dispose() {
    _client.close();
  }
}
