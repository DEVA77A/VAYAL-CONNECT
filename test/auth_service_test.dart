import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vayalconnect_flutter/services/auth_service.dart';
import 'package:vayalconnect_flutter/services/session_manager.dart';
import 'package:vayalconnect_flutter/utils/registration_validation.dart';

void main() {
  tearDown(() => SessionManager().logout());
  test('Indian mobile formats are accepted without rewriting', () {
    for (final phone in ['9876543210', '6123456789', '+919876543210', '+916123456789']) {
      expect(validateRegistrationPhone(phone), isNull);
    }
    for (final phone in ['0987654321', '98765 43210', '+91-9876543210', '987654321', '9876543210abc']) {
      expect(validateRegistrationPhone(phone), isNotNull);
    }
  });
  for (final code in ['EMAIL_ALREADY_EXISTS', 'PHONE_ALREADY_EXISTS']) {
    test('duplicate $code gives safe recovery message without OTP request', () async {
      var calls = 0;
      final service = AuthService(client: MockClient((request) async {
        calls++;
        expect(request.url.path, '/api/v1/auth/register');
        return http.Response(jsonEncode({'error': {'code': code, 'message': 'private-provider-diagnostic'}}), 409);
      }));
      await expectLater(service.register(name: 'User', email: 'user@example.invalid', phone: '9876543210',
        password: 'SyntheticTest123!', address: 'Test address', areaLocation: 'Village', gender: 'other', age: 30),
        throwsA(predicate((e) => e.toString().contains('Sign in') && !e.toString().contains('private-provider-diagnostic'))));
      expect(calls, 1);
      service.dispose();
    });
  }
  test('422 phone validation uses field hint and never provider input', () async {
    final service = AuthService(client: MockClient((_) async => http.Response(jsonEncode({
      'detail': [{'loc': ['body', 'phone'], 'msg': 'private-provider-diagnostic', 'input': 'private-value'}]
    }), 422)));
    await expectLater(service.register(name: 'User', email: 'user@example.invalid', phone: 'bad-number',
      password: 'SyntheticTest123!', address: 'Test address', areaLocation: 'Village', gender: 'other', age: 30),
      throwsA(predicate((e) => e.toString().contains('+91') && !e.toString().contains('private-'))));
    service.dispose();
  });
  test('unknown OTP provider error never exposes raw response', () async {
    final service = AuthService(client: MockClient((_) async => http.Response(
      jsonEncode({'error': {'message': 'private-provider-diagnostic'}}), 503)));
    await expectLater(service.requestOtp('user@example.invalid'), throwsA(predicate((e) =>
      e.toString().contains('try again later') && !e.toString().contains('private-provider-diagnostic'))));
    service.dispose();
  });

  testWidgets('registration timeout explains Wi-Fi and backend requirements', (tester) async {
    final service = AuthService(client: MockClient((_) => Completer<http.Response>().future));
    final request = service.register(name: 'User', email: 'user@example.invalid', phone: '9876543210',
      password: 'SyntheticTest123!', address: 'Test address', areaLocation: 'Village', gender: 'other', age: 30);
    final result = expectLater(request, throwsA(predicate((e) =>
      e.toString().contains('same Wi-Fi') && e.toString().contains('backend is running') &&
      !e.toString().contains('TimeoutException'))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    await result;
    service.dispose();
  });
  test('registration client error explains backend connectivity', () async {
    final service = AuthService(client: MockClient((_) async => throw http.ClientException('connection failed')));
    await expectLater(service.register(name: 'User', email: 'user@example.invalid', phone: '9876543210',
      password: 'SyntheticTest123!', address: 'Test address', areaLocation: 'Village', gender: 'other', age: 30),
      throwsA(predicate((e) => e.toString().contains('same Wi-Fi') && e.toString().contains('Cannot reach'))));
    service.dispose();
  });
  test('registration sends actual backend fields', () async {
    final service = AuthService(client: MockClient((request) async {
      expect(request.url.path, '/api/v1/auth/register');
      final body = jsonDecode(request.body);
      expect(body['email'], 'user@example.com');
      expect(body['area_location'], 'Village');
      expect(body.keys.toSet(), {'name', 'email', 'phone', 'password', 'address', 'area_location', 'gender', 'age', 'preferred_language'});
      expect(body['phone'], '9876543210');
      return http.Response(jsonEncode({'success': true, 'data': {'user_id': 'new-user'}}), 201);
    }));
    expect(await service.register(name: 'User', email: ' USER@example.com ', phone: '9876543210',
      password: 'TestPassword123!', address: 'Address', areaLocation: 'Village', gender: 'other', age: 30), 'new-user');
  });
  test('OTP request and resend use existing endpoint', () async {
    var calls = 0;
    final service = AuthService(client: MockClient((request) async {
      calls++;
      expect(request.url.path, '/api/v1/auth/request-otp');
      expect(jsonDecode(request.body)['purpose'], 'REGISTRATION');
      return http.Response(jsonEncode({'success': true, 'data': {'message': 'Provider accepted'}}), 200);
    }));
    await service.requestOtp('user@example.com');
    await service.requestOtp('user@example.com');
    expect(calls, 2);
  });
  test('delivery error is preserved', () async {
    final service = AuthService(client: MockClient((_) async => http.Response(
      jsonEncode({'success': false, 'error': {'code': 'EMAIL_DELIVERY_FAILED', 'message': 'Unable to send OTP email.'}}), 503)));
    await expectLater(service.requestOtp('user@example.com'), throwsA(predicate((e) => e.toString().contains('could not be sent'))));
  });
  test('verification requires explicit backend confirmation', () async {
    final service = AuthService(client: MockClient((request) async {
      expect(request.url.path, '/api/v1/auth/verify-otp');
      return http.Response(jsonEncode({'success': true, 'data': {}}), 200);
    }));
    expect(await service.verifyOtp('user@example.com', '123456'), false);
  });
  test('invalid login response does not establish session', () async {
    final service = AuthService(client: MockClient((_) async => http.Response('<html>failure</html>', 502)));
    await expectLater(service.login('user@example.com', 'password'), throwsA(predicate((e) => e.toString().contains('Invalid server response'))));
    expect(SessionManager().isAuthenticated, false);
  });
  test('login uses backend role and token', () async {
    final service = AuthService(client: MockClient((_) async => http.Response(jsonEncode({
      'success': true, 'data': {'access_token': 'test-token', 'refresh_token': 'refresh',
      'user': {'id': 'buyer', 'email': 'buyer@example.com', 'name': 'Buyer', 'role': 'BUYER'}}}), 200)));
    final result = await service.login('buyer@example.com', 'password');
    expect(result.user.role.name, 'buyer');
    expect(SessionManager().activeRole.name, 'buyer');
  });
}
