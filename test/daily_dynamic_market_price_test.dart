import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vayalconnect_flutter/models/auth_models.dart';
import 'package:vayalconnect_flutter/models/product_models.dart';
import 'package:vayalconnect_flutter/screens/admin_dashboard_screen.dart';
import 'package:vayalconnect_flutter/screens/product_details_screen.dart';
import 'package:vayalconnect_flutter/services/admin_service.dart';
import 'package:vayalconnect_flutter/services/api_client.dart';
import 'package:vayalconnect_flutter/services/order_service.dart';
import 'package:vayalconnect_flutter/services/session_manager.dart';
import 'package:vayalconnect_flutter/theme/app_theme.dart';
import 'package:vayalconnect_flutter/widgets/marketplace_product_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BuyerProduct sampleProduct({
    bool stale = false,
    int? marketRefPricePaise = 2500,
    String? marketPriceDate = '2026-10-31',
    String? marketSource = 'AGMARKNET (Dindigul)',
  }) {
    return BuyerProduct(
      productId: 'prod_tomato_1',
      farmerId: 'farmer_1',
      farmerName: 'Farmer Murugan',
      location: 'Dindigul',
      productName: 'Tomato',
      category: 'Vegetables',
      description: 'Farm fresh red tomatoes',
      quantityAvailable: 50,
      quantityUnit: 'KG',
      farmerBasePricePaise: 2500,
      buyerPricePerUnitPaise: 3000,
      commissionPerUnitPaise: 500,
      commissionPercentageBps: 2000,
      deliveryAvailable: true,
      marketReference: {
        'reference_price_available': marketRefPricePaise != null,
        'government_reference_price_paise': marketRefPricePaise,
        'reference_price_unit': 'KG',
        'reference_commodity': 'TOMATO',
        'reference_market': 'DINDIGUL',
        'reference_price_source': marketSource,
        'reference_price_date': marketPriceDate,
        'reference_price_stale': stale,
      },
    );
  }

  tearDown(() {
    SessionManager().logout();
  });

  group('Daily Dynamic Market Price Display Tests', () {
    testWidgets('MarketplaceProductCard displays dynamic price, market reference, and update date',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final product = sampleProduct(stale: false);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: MarketplaceProductCard(
                product: product,
                onTap: () {},
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Buyer price
      expect(find.text('₹30.00 / KG'), findsOneWidget);
      // Market reference
      expect(find.text('Market reference: ₹25.00 / KG'), findsOneWidget);
      // Price updated date
      expect(find.text('Price updated: 2026-10-31'), findsOneWidget);
      // Not stale
      expect(
          find.text('Market price update unavailable. Showing the last available price.'),
          findsNothing);
    });

    testWidgets('MarketplaceProductCard shows stale notice when isMarketPriceStale is true',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final product = sampleProduct(stale: true, marketPriceDate: '2026-10-29');

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: MarketplaceProductCard(
                product: product,
                onTap: () {},
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Stale banner text should be rendered
      expect(
          find.text('Market price update unavailable. Showing the last available price.'),
          findsOneWidget);
      expect(find.text('Price updated: 2026-10-29'), findsOneWidget);
    });

    testWidgets('ProductDetailsScreen displays market reference and date without exposing commission',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      SessionManager().setSession(
        token: 'buyer-token',
        user: UserProfile(
            id: 'b1', name: 'Buyer Anbu', email: 'anbu@vayal.in', role: AppRole.buyer),
      );

      final product = sampleProduct(stale: false);
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'success': true, 'data': {}}), 200);
      });
      final api = ApiClient(client: mockClient);
      final orderService = OrderService(client: mockClient);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ProductDetailsScreen(
          product: product,
          api: api,
          orderService: orderService,
        ),
      ));
      await tester.pumpAndSettle();

      // Buyer total section displays product price, market reference, price updated date
      expect(find.textContaining('Product price: ₹30.00 / KG'), findsOneWidget);
      expect(find.textContaining('Market reference: ₹25.00 / KG'), findsOneWidget);
      expect(find.textContaining('Price updated: 2026-10-31'), findsOneWidget);

      // Verify no commission info exposed to buyer
      expect(find.text('Platform commission'), findsNothing);
      expect(find.textContaining('Commission is added'), findsNothing);
    });

    testWidgets('ProductDetailsScreen shows stale warning badge if market price is stale',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      SessionManager().setSession(
        token: 'buyer-token',
        user: UserProfile(
            id: 'b1', name: 'Buyer Anbu', email: 'anbu@vayal.in', role: AppRole.buyer),
      );

      final product = sampleProduct(stale: true, marketPriceDate: '2026-10-28');
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'success': true, 'data': {}}), 200);
      });
      final api = ApiClient(client: mockClient);
      final orderService = OrderService(client: mockClient);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ProductDetailsScreen(
          product: product,
          api: api,
          orderService: orderService,
        ),
      ));
      await tester.pumpAndSettle();

      expect(
          find.text('Market price update unavailable. Showing the last available price.'),
          findsAtLeastNWidgets(1));
    });

    testWidgets('ProductDetailsScreen alerts buyer with friendly snackbar when order fails with PRICE_CHANGED',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      SessionManager().setSession(
        token: 'buyer-token',
        user: UserProfile(
            id: 'b1', name: 'Buyer Anbu', email: 'anbu@vayal.in', role: AppRole.buyer),
      );

      final product = sampleProduct(stale: false);
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/orders')) {
          return http.Response(
            jsonEncode({
              'success': false,
              'error': {
                'code': 'PRICE_CHANGED',
                'message': 'Product price was updated from daily market data. Expected 3000 but now 3200.'
              }
            }),
            409,
          );
        }
        return http.Response('{"success": true}', 200);
      });
      final api = ApiClient(client: mockClient);
      final orderService = OrderService(client: mockClient);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ProductDetailsScreen(
          product: product,
          api: api,
          orderService: orderService,
        ),
      ));
      await tester.pumpAndSettle();

      // Tap Place order button
      final placeOrderBtn = find.widgetWithText(ElevatedButton, 'Place order');
      expect(placeOrderBtn, findsOneWidget);
      await tester.tap(placeOrderBtn);
      await tester.pump(); // Start async call
      await tester.pumpAndSettle(); // Complete

      // Expect the price changed snackbar to be shown
      expect(
          find.text(
              'Price changed. Please review the updated total before placing your order.'),
          findsOneWidget);
    });

    testWidgets('AdminDashboardScreen includes Daily Market Prices section with functional Refresh button',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      SessionManager().setSession(
        token: 'admin-token',
        user: UserProfile(
            id: 'admin_1', name: 'Admin User', email: 'admin@vayal.in', role: AppRole.admin),
      );

      bool refreshCalled = false;
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/admin/dashboard')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'total_farmers': 15,
                'verified_farmers': 12,
                'pending_farmers': 3,
                'total_buyers': 40,
                'active_products': 25,
                'total_orders': 110,
                'delivered_orders': 95,
                'total_gmv_paise': 25000000,
                'total_platform_commission_paise': 2500000,
                'pending_payouts_paise': 500000,
                'settled_payouts_paise': 22000000,
                'avg_commission_bps': 1000,
                'status': 'OPERATIONAL',
                'service_checks': {},
                'recent_activity': [],
              }
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/market-prices/refresh')) {
          refreshCalled = true;
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'status': 'REFRESHED',
                'records_count': 18,
                'updated_at': '2026-10-31T06:00:00+05:30',
              }
            }),
            200,
          );
        }
        return http.Response('{"success": true}', 200);
      });

      final adminService = AdminService(client: mockClient);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: AdminDashboardScreen(adminService: adminService),
      ));
      await tester.pumpAndSettle();

      // Verify the Daily Market Prices card exists
      expect(find.text('Daily Market Prices'), findsOneWidget);
      expect(find.text('Provider: Government AGMARKNET & Mandi'), findsOneWidget);
      expect(find.text('Schedule: 06:00 IST Daily'), findsOneWidget);

      // Tap Refresh Now
      final refreshBtn = find.widgetWithText(ElevatedButton, 'Refresh Now');
      expect(refreshBtn, findsOneWidget);
      await tester.tap(refreshBtn);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(refreshCalled, isTrue);
      expect(find.textContaining('Market prices refreshed successfully'), findsAtLeastNWidgets(1));
    });
  });
}
