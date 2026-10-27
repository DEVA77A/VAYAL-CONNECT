import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vayalconnect_flutter/models/auth_models.dart';
import 'package:vayalconnect_flutter/screens/admin_dashboard_screen.dart';
import 'package:vayalconnect_flutter/services/admin_service.dart';
import 'package:vayalconnect_flutter/services/api_client.dart';
import 'package:vayalconnect_flutter/services/session_manager.dart';
import 'package:vayalconnect_flutter/services/update_service.dart';
import 'package:vayalconnect_flutter/widgets/commerce_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UpdateService & AppReleaseInfo Tests', () {
    test('AppReleaseInfo deserializes correctly and selects localized notes', () {
      final json = {
        'app_id': 'com.vayalconnect.app',
        'version_name': '1.1.0',
        'version_code': 11,
        'min_supported_version_code': 1,
        'apk_url': 'https://vayal-connect.onrender.com/releases/app.apk',
        'sha256': 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855',
        'release_notes_en': 'Bug fixes and performance improvements.',
        'release_notes_ta': 'பிழை திருத்தங்கள் மற்றும் மேம்பாடுகள்.',
        'mandatory': false,
        'release_date': '2026-10-26T14:00:00Z',
      };

      final info = AppReleaseInfo.fromJson(json);

      expect(info.appId, 'com.vayalconnect.app');
      expect(info.versionName, '1.1.0');
      expect(info.versionCode, 11);
      expect(info.sha256, 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855');
      expect(info.localizedReleaseNotes(false), 'Bug fixes and performance improvements.');
      expect(info.localizedReleaseNotes(true), 'பிழை திருத்தங்கள் மற்றும் மேம்பாடுகள்.');
    });

    test('UpdateService.checkForUpdate returns release when newer version exists', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/settings/app-release');
        return http.Response(
            '{"success":true,"data":{"app_id":"com.vayalconnect.app","version_name":"1.1.0","version_code":99,"apk_url":"https://example.com/app.apk","sha256":"abc123","release_notes_en":"New update","mandatory":false}}',
            200);
      });

      final apiClient = ApiClient(client: client);
      final updateService = UpdateService(api: apiClient);

      final release = await updateService.checkForUpdate();
      expect(release, isNotNull);
      expect(release!.versionCode, 99);
      expect(release.versionName, '1.1.0');
      expect(release.apkUrl, 'https://example.com/app.apk');
    });

    test('UpdateService.checkForUpdate returns null when installed is up to date or older backend response', () async {
      final client = MockClient((request) async {
        return http.Response(
            '{"success":true,"data":{"app_id":"com.vayalconnect.app","version_name":"1.0.0","version_code":1,"apk_url":"https://example.com/app.apk","sha256":"","mandatory":false}}',
            200);
      });

      final apiClient = ApiClient(client: client);
      final updateService = UpdateService(api: apiClient);

      final release = await updateService.checkForUpdate();
      expect(release, isNull);
    });

    test('UpdateService.checkForUpdate returns null on server failure', () async {
      final client = MockClient((request) async {
        return http.Response('{"detail":"Internal error"}', 500);
      });

      final apiClient = ApiClient(client: client);
      final updateService = UpdateService(api: apiClient);

      final release = await updateService.checkForUpdate();
      expect(release, isNull);
    });
  });

  group('MetricCard & Admin Dashboard Tests', () {
    testWidgets('MetricCard invokes onTap callback and displays values', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MetricCard(
            'Approved Farmers',
            '42',
            icon: Icons.verified_user_outlined,
            color: Colors.green,
            onTap: () {
              tapped = true;
            },
          ),
        ),
      ));

      expect(find.text('Approved Farmers'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.byIcon(Icons.verified_user_outlined), findsOneWidget);

      await tester.tap(find.byType(MetricCard));
      expect(tapped, isTrue);
    });

    testWidgets('AdminDashboardScreen renders all 10 operational metric cards with real data counts', (tester) async {
      SessionManager().setSession(
          token: 'test-admin-token',
          user: UserProfile(
              id: 'admin1',
              name: 'Super Admin',
              email: 'admin@vayalconnect.invalid',
              role: AppRole.admin));

      final adminService = AdminService(client: MockClient((request) async {
        if (request.url.path.endsWith('/dashboard')) {
          return http.Response('''
          {
            "success": true,
            "data": {
              "total_farmers": 20,
              "approved_farmers": 14,
              "pending_farmer_approvals": 4,
              "rejected_farmers": 2,
              "total_buyers": 50,
              "active_products": 35,
              "total_orders": 85,
              "pending_orders": 12,
              "completed_orders": 68,
              "cancelled_orders": 5,
              "total_gmv": 150000.0,
              "total_commission": 7500.0,
              "farmer_payouts_due": 142500.0
            }
          }
          ''', 200);
        }
        return http.Response('{"success":true,"data":{"items":[]}}', 200);
      }));

      await tester.pumpWidget(MaterialApp(
        home: AdminDashboardScreen(adminService: adminService),
      ));
      await tester.pumpAndSettle();

      // Verify the 10 operational metric cards are present
      expect(find.text('Registered farmers'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);

      expect(find.text('Approved farmers'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);

      expect(find.text('Pending applications'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);

      expect(find.text('Rejected applications'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      expect(find.text('Registered buyers'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);

      expect(find.text('Active listings'), findsOneWidget);
      expect(find.text('35'), findsOneWidget);

      expect(find.text('Total orders'), findsOneWidget);
      expect(find.text('85'), findsOneWidget);

      expect(find.text('Pending orders'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);

      expect(find.text('Completed orders'), findsOneWidget);
      expect(find.text('68'), findsOneWidget);

      expect(find.text('Cancelled orders'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      SessionManager().logout();
    });
  });
}
