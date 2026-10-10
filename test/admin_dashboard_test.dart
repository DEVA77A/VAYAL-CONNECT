import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vayalconnect_flutter/screens/admin_dashboard_screen.dart';
import 'package:vayalconnect_flutter/services/admin_service.dart';
import 'package:vayalconnect_flutter/services/session_manager.dart';
import 'package:vayalconnect_flutter/models/auth_models.dart';

void main() {
  testWidgets('admin dashboard renders real empty responses without sample identities', (tester) async {
    SessionManager().setSession(token: 'unit-test-token', user: UserProfile(id: 'admin', name: 'Test', email: 'admin@example.invalid', role: AppRole.admin));
    final paths = <String>{};
    final service = AdminService(client: MockClient((request) async {
      paths.add(request.url.path);
      expect(request.headers['Authorization'], 'Bearer unit-test-token');
      if (request.url.path.endsWith('dashboard')) return http.Response('{"success":true,"data":{"total_orders":0}}', 200);
      return http.Response('{"success":true,"data":{"items":[]}}', 200);
    }));
    await tester.pumpWidget(MaterialApp(home: AdminDashboardScreen(adminService: service)));
    await tester.pumpAndSettle();
    expect(paths, {'/api/v1/admin/dashboard', '/api/v1/admin/farmers', '/api/v1/reports/orders'});
    expect(find.text('No farmers awaiting review.'), findsOneWidget);
    expect(find.text('No orders in this period.'), findsOneWidget);
    expect(find.textContaining('VY-8921'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    SessionManager().logout();
  });
}
