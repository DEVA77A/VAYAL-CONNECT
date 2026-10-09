import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/auth_models.dart';
import 'session_manager.dart';

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

      final decoded = json.decode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && decoded['success'] == true && decoded['data'] != null) {
        final authData = AuthTokenResponse.fromJson(decoded['data'] as Map<String, dynamic>);
        SessionManager().setSession(
          token: authData.accessToken,
          user: authData.user,
        );
        return authData;
      } else {
        final errMsg = decoded['error']?['message'] ?? 'Login failed. Please check your credentials.';
        throw Exception(errMsg);
      }
    } on SocketException catch (_) {
      throw Exception('Unable to connect to VayalConnect server at ${ApiConfig.baseUrl}. Please verify backend is running.');
    } on TimeoutException catch (_) {
      throw Exception('Login request timed out.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Login error: $e');
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
        }),
      ).timeout(const Duration(seconds: 15));

      final decoded = json.decode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 201 && decoded['success'] == true) {
        return decoded['data']?['user_id'] as String? ?? '';
      } else {
        throw Exception(decoded['error']?['message'] ?? 'Registration failed.');
      }
    } on SocketException catch (_) {
      throw Exception('Unable to connect to server at ${ApiConfig.baseUrl}.');
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

      final decoded = json.decode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && decoded['success'] == true) {
        return decoded['data']?['message'] as String? ?? 'OTP sent to your email.';
      } else {
        throw Exception(decoded['error']?['message'] ?? 'Unable to send OTP.');
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

      final decoded = json.decode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && decoded['success'] == true) {
        return decoded['data']?['verified'] as bool? ?? true;
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

      final decoded = json.decode(response.body) as Map<String, dynamic>;
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

  void dispose() {
    _client.close();
  }
}
