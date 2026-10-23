import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vayalconnect_flutter/models/auth_models.dart';
import 'package:vayalconnect_flutter/screens/farmer_application_screen.dart';
import 'package:vayalconnect_flutter/screens/admin_dashboard_screen.dart';
import 'package:vayalconnect_flutter/services/api_client.dart';
import 'package:vayalconnect_flutter/services/farmer_service.dart';
import 'package:vayalconnect_flutter/services/admin_service.dart';
import 'package:vayalconnect_flutter/services/session_manager.dart';

void main() {
  setUp(() => SessionManager().setSession(
      token: 'test-token',
      user: UserProfile(
          id: 'test-user',
          name: 'Test',
          email: 'test@example.invalid',
          role: AppRole.farmer)));
  tearDown(() => SessionManager().logout());

  for (final failure in [
    (404, 'NOT_FOUND', 'Farmer profile not found.'),
    (
      409,
      'APPLICATION_CHANGED',
      'Application changed. Reload before submitting.'
    ),
    (403, 'FORBIDDEN', 'Verify your email before submitting an application.'),
    (
      422,
      'VALIDATION_ERROR',
      'Approval requires farm coordinates and complete bank payout details.'
    ),
  ]) {
    test('onboarding preserves ${failure.$1} message and request diagnostics',
        () async {
      final service = FarmerService(
          client: MockClient((r) async => http.Response(
              jsonEncode({
                'success': false,
                'request_id': 'test-request',
                'error': {'code': failure.$2, 'message': failure.$3}
              }),
              failure.$1)));
      await expectLater(
          service.submitApplication({}),
          throwsA(isA<ApiException>()
              .having((e) => e.message, 'message', failure.$3)
              .having((e) => e.statusCode, 'status', failure.$1)
              .having((e) => e.requestId, 'request ID', 'test-request')
              .having((e) => e.path, 'path', '/api/v1/farmers/me/application')
              .having((e) => e.method, 'method', 'PUT')
              .having((e) => e.toString(), 'display', failure.$3)));
      service.dispose();
    });
  }
  test('field validation identifies fields without submitted sensitive values',
      () async {
    final api = ApiClient(
        client: MockClient((r) async => http.Response(
            '{"success":false,"error":{"code":"VALIDATION_ERROR","message":"Check required fields and values.","fields":[{"location":["body","account_number"],"type":"string_pattern_mismatch"}]}}',
            422)));
    await expectLater(
        api.request('/api/v1/farmers/me/bank', method: 'PUT'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'field', contains('account_number'))));
    api.dispose();
  });
  test('admin never treats an error envelope with HTTP 200 as approval',
      () async {
    final service = AdminService(
        client: MockClient((r) async => http.Response(
            '{"success":false,"error":{"code":"APPLICATION_CHANGED","message":"Application changed. Reload before deciding."}}',
            200)));
    await expectLater(service.approveFarmer('farmer', applicationRevision: 2),
        throwsA(isA<ApiException>()));
    service.dispose();
  });
  test('admin rejection targets user ID with reviewed revision and reason',
      () async {
    final service = AdminService(client: MockClient((r) async {
      expect(r.url.path, '/api/v1/admin/farmers/farmer-user/reject');
      expect(r.method, 'PUT');
      expect(r.headers['Authorization'], 'Bearer test-token');
      expect(jsonDecode(r.body),
          {'reason': 'Correct details', 'application_revision': 4});
      return http.Response(
          '{"success":true,"data":{"message":"Farmer rejected."}}', 200);
    }));
    await service.rejectFarmer('farmer-user', 'Correct details',
        applicationRevision: 4);
    service.dispose();
  });
  test('unexpected server details stay hidden', () async {
    final api = ApiClient(
        client: MockClient((r) async => http.Response(
            '{"success":false,"error":{"message":"private exception internals"}}',
            500)));
    await expectLater(
        api.request('/api/v1/farmers/me/profile'),
        throwsA(isA<ApiException>().having((e) => e.message, 'safe error',
            'Server is temporarily unavailable. Please retry shortly.')));
    api.dispose();
  });

  testWidgets('profile loading has progress and failure never claims Pending',
      (tester) async {
    final response = Completer<http.Response>();
    final service = FarmerService(client: MockClient((r) => response.future));
    await tester.pumpWidget(
        MaterialApp(home: FarmerApplicationScreen(service: service)));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Pending'), findsNothing);
    response.complete(http.Response(
        '{"success":false,"error":{"code":"NOT_FOUND","message":"Farmer profile not found."}}',
        404));
    await tester.pumpAndSettle();
    expect(find.text('Farmer profile not found.'), findsOneWidget);
    expect(find.textContaining('Exception:'), findsNothing);
    expect(find.text('Pending'), findsNothing);
    expect(find.text('Submit for review'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('admin disables review after detail refresh fails',
      (tester) async {
    final api = ApiClient(
        client: MockClient((r) async => http.Response(
            '{"success":false,"error":{"code":"NOT_FOUND","message":"Farmer not found."}}',
            404)));
    await tester.pumpWidget(MaterialApp(
        home: FarmerReviewScreen(api: api, farmer: const {
      'user_id': 'farmer-user',
      'approval_status': 'PENDING',
      'submitted_at': '2026-10-12',
      'application_revision': 2,
    })));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Approve'))
            .onPressed,
        isNull);
    await tester.ensureVisible(find.text('Farmer not found.'));
    expect(find.text('Farmer not found.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
