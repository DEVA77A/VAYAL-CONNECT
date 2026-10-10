import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vayalconnect_flutter/screens/auth_gateway_screen.dart';
import 'package:vayalconnect_flutter/services/auth_service.dart';
import 'package:vayalconnect_flutter/services/session_manager.dart';

void main() {
  testWidgets('login prevents duplicate requests while loading and recovers from failure', (tester) async {
    SessionManager().logout();
    SessionManager().setLanguage(false);
    final response = Completer<http.Response>();
    var requests = 0;
    final service = AuthService(client: MockClient((_) { requests++; return response.future; }));
    await tester.pumpWidget(MaterialApp(home: AuthGatewayScreen(authService: service)));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'user@example.com');
    await tester.enterText(fields.at(1), 'TestPassword123!');
    await tester.ensureVisible(find.text('Login'));
    await tester.tap(find.text('Login'));
    await tester.pump();
    expect(requests, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton).first);
    expect(button.onPressed, isNull);
    response.complete(http.Response('{"success":false}', 401));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(SessionManager().isAuthenticated, false);
  });
}
