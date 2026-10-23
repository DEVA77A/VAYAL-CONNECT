import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vayalconnect_flutter/models/auth_models.dart';
import 'package:vayalconnect_flutter/models/product_models.dart';
import 'package:vayalconnect_flutter/screens/product_details_screen.dart';
import 'package:vayalconnect_flutter/screens/orders_screen.dart';
import 'package:vayalconnect_flutter/screens/profile_screen.dart';
import 'package:vayalconnect_flutter/screens/addresses_screen.dart';
import 'package:vayalconnect_flutter/screens/add_product_screen.dart';
import 'package:vayalconnect_flutter/screens/admin_dashboard_screen.dart';
import 'package:vayalconnect_flutter/screens/auth_gateway_screen.dart';
import 'package:vayalconnect_flutter/screens/buyer_home_screen.dart';
import 'package:vayalconnect_flutter/screens/farmer_home_screen.dart';
import 'package:vayalconnect_flutter/screens/splash_screen.dart';
import 'package:vayalconnect_flutter/services/admin_service.dart';
import 'package:vayalconnect_flutter/services/api_client.dart';
import 'package:vayalconnect_flutter/services/session_manager.dart';
import 'package:vayalconnect_flutter/theme/app_theme.dart';

// Test-only HTTP fixtures. Production screens continue using their real services.
http.Response fixture(http.Request request) {
  dynamic data = <String, dynamic>{};
  final path = request.url.path;
  if (path.endsWith('/products/')) {
    data = {
      'total': 1,
      'items': [
        {
          'product_id': 'test-crop',
          'product_name': 'Tomato · தக்காளி',
          'category': 'Vegetables',
          'quantity_available': 120,
          'quantity_unit': 'KG',
          'quality_grade': 'A',
          'location': 'Pollachi',
          'farmer_name': 'Test farmer',
          'buyer_price_per_unit_paise': 4200,
        }
      ]
    };
  } else if (path.endsWith('/profile')) {
    data = {'can_publish': true, 'approval_status': 'APPROVED'};
  } else if (path.endsWith('/dashboard')) {
    data = {
      'active_products': 12,
      'total_orders': 24,
      'pending_orders': 3,
      'completed_orders': 21,
      'total_farmers': 14,
      'total_buyers': 32
    };
  } else if (path.contains('/orders/') || path.endsWith('/addresses')) {
    data = {'items': [], 'total': 0};
  } else if (path.endsWith('/filter-options')) {
    data = {'categories': <String>[]};
  }
  return http.Response(jsonEncode({'success': true, 'data': data}), 200,
      headers: {'content-type': 'application/json; charset=utf-8'});
}

void main() {
  tearDown(() => SessionManager().logout());
  for (final role in <AppRole?>[null, ...AppRole.values]) {
    testWidgets('splash retains destination for ${role?.name ?? 'signed out'}',
        (tester) async {
      SessionManager().logout();
      if (role != null) {
        SessionManager().setSession(
            token: 'test-only',
            user: UserProfile(
                id: 'test-only',
                name: 'Test account',
                email: 'test@example.invalid',
                role: role));
      }
      await tester.pumpWidget(
          MaterialApp(theme: AppTheme.lightTheme, home: const SplashScreen()));
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byType(SplashScreen), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      final destination = switch (role) {
        null => AuthGatewayScreen,
        AppRole.buyer => BuyerHomeScreen,
        AppRole.farmer => FarmerHomeScreen,
        AppRole.admin => AdminDashboardScreen,
      };
      expect(find.byType(destination), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final tamil in [false, true]) {
    for (final large in [false, true]) {
      testWidgets(
          'role screens and forms fit ${tamil ? 'Tamil' : 'English'} ${large ? '320px 2x' : '390px'}',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(large ? 320 : 390, 844);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        if (const bool.fromEnvironment('UI_PREVIEWS')) {
          await tester.runAsync(() async {
            for (final pair in [
              [
                'Roboto',
                'C:/src/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf'
              ],
              [
                'MaterialIcons',
                'C:/src/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf'
              ],
              ['Nirmala UI', 'C:/Windows/Fonts/Nirmala.ttc'],
              ['Ahem', 'C:/Windows/Fonts/Nirmala.ttc'],
            ]) {
              final file = File(pair[1]);
              if (await file.exists()) {
                final loader = FontLoader(pair[0]);
                loader.addFont(Future.value(
                    ByteData.sublistView(await file.readAsBytes())));
                await loader.load();
              }
            }
          });
        }
        final client = MockClient((r) async => fixture(r));
        final api = ApiClient(client: client);
        final admin = AdminService(client: MockClient((r) async => fixture(r)));
        addTearDown(api.dispose);
        addTearDown(admin.dispose);
        for (final entry in <(String, AppRole, Widget)>[
          ('buyer', AppRole.buyer, BuyerHomeScreen(api: api)),
          ('farmer', AppRole.farmer, FarmerHomeScreen(api: api)),
          ('admin', AppRole.admin, AdminDashboardScreen(adminService: admin)),
          ('crop-form', AppRole.farmer, AddProductScreen(api: api)),
          (
            'checkout',
            AppRole.buyer,
            ProductDetailsScreen(
                api: api,
                product: BuyerProduct.fromJson({
                  'product_id': 'test',
                  'product_name': 'Tomato · தக்காளி',
                  'quantity_available': 120,
                  'quantity_unit': 'KG',
                  'buyer_price_per_unit_paise': 4200,
                  'location': 'Pollachi',
                  'farmer_name': 'Test farmer',
                  'delivery_available': true,
                }))
          ),
          ('orders', AppRole.buyer, OrdersScreen(api: api)),
          ('profile', AppRole.buyer, ProfileScreen(api: api)),
          ('address-form', AppRole.buyer, AddressEditorScreen(api: api)),
          ('auth', AppRole.buyer, const AuthGatewayScreen()),
          ('splash', AppRole.buyer, const SplashScreen()),
        ]) {
          SessionManager().setSession(
              token: 'test-only',
              user: UserProfile(
                  id: 'test-only',
                  name: 'Test account',
                  email: 'test@example.invalid',
                  role: entry.$2,
                  preferredLanguage: tamil ? 'ta' : 'en'));
          final key = GlobalKey();
          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.lightTheme.copyWith(
                textTheme: AppTheme.lightTheme.textTheme.apply(
                    fontFamily: 'Roboto',
                    fontFamilyFallback: const ['Nirmala UI'])),
            locale: Locale(tamil ? 'ta' : 'en'),
            supportedLocales: const [Locale('en'), Locale('ta')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
                child: child!),
            home: RepaintBoundary(key: key, child: entry.$3),
          ));
          if (const bool.fromEnvironment('UI_PREVIEWS')) {
            await tester.runAsync(() => precacheImage(
                const AssetImage('assets/branding/vayalconnect-logo.jpeg'),
                key.currentContext!));
          }
          if (entry.$1 == 'splash') {
            await tester.pump(const Duration(milliseconds: 650));
          } else {
            await tester.pumpAndSettle();
          }
          final issue = tester.takeException();
          expect(issue, isNull,
              reason:
                  '${entry.$1}: ${issue is FlutterError ? issue.toStringDeep() : issue}');
          if (!large && const bool.fromEnvironment('UI_PREVIEWS')) {
            final boundary = key.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final img = await boundary.toImage(pixelRatio: 1);
              final bytes =
                  await img.toByteData(format: ui.ImageByteFormat.png);
              final dir = Directory(const String.fromEnvironment(
                  'UI_PREVIEW_DIR',
                  defaultValue: '../artifacts/ui-redesign-20261015-previews'));
              await dir.create(recursive: true);
              await File('${dir.path}/${entry.$1}-${tamil ? 'ta' : 'en'}.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              img.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        }
      });
    }
  }
}
