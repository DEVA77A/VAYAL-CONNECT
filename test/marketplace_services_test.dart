import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vayalconnect_flutter/services/location_service.dart';
import 'package:vayalconnect_flutter/services/admin_service.dart';
import 'package:vayalconnect_flutter/services/session_manager.dart';
import 'package:vayalconnect_flutter/models/auth_models.dart';
import 'package:vayalconnect_flutter/utils/localization.dart';

void main() {
  tearDown(() { SessionManager().logout(); SessionManager().setLanguage(false); });
  for (final state in [LocationPermission.denied, LocationPermission.deniedForever]) {
    test('denied location never reads GPS $state', () async {
      var reads = 0;
      final service = LocationService(enabled: () async => true,
        checkPermission: () async => state, requestPermission: () async => state,
        readPosition: () async { reads++; return const LocationResult(LocationState.available); });
      expect((await service.request()).state, state == LocationPermission.denied ? LocationState.denied : LocationState.permanentlyDenied);
      expect(reads, 0);
    });
  }
  test('disabled services do not request OS permission', () async {
    var permissions = 0;
    final service = LocationService(enabled: () async => false, checkPermission: () async {
      permissions++; return LocationPermission.whileInUse;
    });
    expect((await service.request()).state, LocationState.disabled);
    expect(permissions, 0);
  });
  test('granted location returns usable coordinates; timeout remains safe', () async {
    final success = LocationService(enabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      readPosition: () async => const LocationResult(LocationState.available, latitude: 13, longitude: 80));
    expect((await success.request()).latitude, 13);
    final failure = LocationService(enabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      readPosition: () async => throw Exception('private diagnostic'));
    expect((await failure.request()).state, LocationState.unavailable);
  });
  test('admin decisions use PUT and authenticated real identifiers', () async {
    SessionManager().setSession(token: 'test-token', user: UserProfile(id: 'admin', name: 'Test', email: 'admin@example.invalid', role: AppRole.admin));
    final calls = <String>[];
    final service = AdminService(client: MockClient((request) async {
      calls.add(request.url.path);
      expect(request.method, 'PUT');
      expect(request.headers['Authorization'], 'Bearer test-token');
      if (request.url.path.endsWith('reject')) expect(jsonDecode(request.body)['reason'], 'Incomplete profile');
      return http.Response('{"success":true}', 200);
    }));
    await service.approveFarmer('stored-farmer');
    await service.rejectFarmer('stored-farmer', 'Incomplete profile');
    expect(calls.length, 2);
    service.dispose();
  });
  test('admin pending list preserves actual API records and empty state', () async {
    final service = AdminService(client: MockClient((request) async {
      expect(request.url.queryParameters['status'], 'PENDING');
      return http.Response('{"success":true,"data":{"items":[]}}', 200);
    }));
    expect(await service.fetchPendingFarmers(), isEmpty);
    service.dispose();
  });
  test('language preference is restored from backend and saved through protected API', () async {
    final session = SessionManager();
    session.setSession(token: 'test-token', user: UserProfile(id: 'buyer', name: 'Test', email: 'buyer@example.invalid', role: AppRole.buyer, preferredLanguage: 'ta'));
    expect(VayalStrings.isTamil, true);
    final client = MockClient((request) async {
      expect(request.method, 'PUT');
      expect(request.url.path, '/api/v1/users/me/language');
      expect(jsonDecode(request.body)['preferred_language'], 'en');
      return http.Response('{"success":true}', 200);
    });
    await session.toggleLanguagePersisted(client: client);
    expect(VayalStrings.isTamil, false);
    client.close();
  });
  test('failed preference save keeps previous language', () async {
    final session = SessionManager();
    session.setSession(token: 'test-token', user: UserProfile(id: 'buyer', name: 'Test', email: 'buyer@example.invalid', role: AppRole.buyer));
    final client = MockClient((_) async => http.Response('{"success":false}', 503));
    await expectLater(session.toggleLanguagePersisted(client: client), throwsException);
    expect(session.isTamil, false);
    client.close();
  });
}
