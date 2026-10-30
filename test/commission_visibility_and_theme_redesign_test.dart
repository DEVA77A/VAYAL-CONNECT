import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vayalconnect_flutter/models/auth_models.dart';
import 'package:vayalconnect_flutter/models/product_models.dart';
import 'package:vayalconnect_flutter/screens/farmer_home_screen.dart';
import 'package:vayalconnect_flutter/screens/orders_screen.dart';
import 'package:vayalconnect_flutter/screens/product_details_screen.dart';
import 'package:vayalconnect_flutter/screens/admin_dashboard_screen.dart';
import 'package:vayalconnect_flutter/screens/add_product_screen.dart';
import 'package:vayalconnect_flutter/services/api_client.dart';
import 'package:vayalconnect_flutter/services/order_service.dart';
import 'package:vayalconnect_flutter/services/session_manager.dart';
import 'package:vayalconnect_flutter/theme/app_theme.dart';
import 'package:vayalconnect_flutter/widgets/brand_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BuyerProduct sampleProduct() => BuyerProduct(
        productId: 'prod_1',
        farmerId: 'farmer_1',
        farmerName: 'Farmer Murugan',
        location: 'Madurai',
        productName: 'Paddy',
        category: 'Grains',
        description: 'Fresh organic paddy',
        quantityAvailable: 100,
        quantityUnit: 'KG',
        farmerBasePricePaise: 4000,
        buyerPricePerUnitPaise: 4800,
        commissionPerUnitPaise: 800,
        commissionPercentageBps: 2000,
        deliveryAvailable: true,
      );

  tearDown(() {
    SessionManager().logout();
  });

  group('Priority 1: Commission Visibility Tests', () {
    testWidgets('Farmer on Sales screen does NOT see commission metric or formula',
        (tester) async {
      SessionManager().setSession(
        token: 'farmer-token',
        user: UserProfile(
            id: 'f1', name: 'Farmer Murugan', email: 'f@vayal.in', role: AppRole.farmer),
      );

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/sales')) {
          return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'farmer_earnings_paise': 450000,
                  'stock': [
                    {'quantity': 80, '_id': 'KG'}
                  ],
                  'items': [
                    {
                      '_id': {'crop': 'Paddy', 'unit': 'KG'},
                      'quantity': 50,
                      'farmer_amount_paise': 450000,
                    }
                  ],
                }
              }),
              200);
        }
        return http.Response('{"success":false}', 404);
      });

      final api = ApiClient(client: mockClient);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: FarmerSalesScreen(api: api),
      ));
      await tester.pumpAndSettle();

      // Farmer sees their own earnings
      expect(find.text('Farmer earnings'), findsOneWidget);
      expect(find.text('₹4,500.00'), findsOneWidget);

      // Farmer DOES NOT see platform commission
      expect(find.text('Platform commission'), findsNothing);
      expect(find.textContaining('Commission is added for buyers'), findsNothing);
      expect(find.textContaining('platform commission'), findsNothing);
    });

    testWidgets('Farmer on Add Crop screen does NOT see commission text',
        (tester) async {
      SessionManager().setSession(
        token: 'farmer-token',
        user: UserProfile(
            id: 'f1', name: 'Farmer Murugan', email: 'f@vayal.in', role: AppRole.farmer),
      );

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'success': true, 'data': {}}), 200);
      });

      final api = ApiClient(client: mockClient);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: AddProductScreen(api: api),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Commission is added for buyers'), findsNothing);
    });

    testWidgets('Buyer on Product Details screen does NOT see commission or farmer base price',
        (tester) async {
      SessionManager().setSession(
        token: 'buyer-token',
        user: UserProfile(
            id: 'b1', name: 'Buyer Anbu', email: 'b@vayal.in', role: AppRole.buyer),
      );

      final p = sampleProduct();
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'success': true, 'data': {}}), 200);
      });
      final api = ApiClient(client: mockClient);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ProductDetailsScreen(
          product: p,
          orderService: OrderService(client: mockClient),
          api: api,
        ),
      ));
      await tester.pumpAndSettle();

      // Buyer sees product price, quantity, and buyer total
      expect(find.text('Product price: ₹48.00 / KG'), findsOneWidget);
      expect(find.text('Quantity: 1 KG'), findsOneWidget);
      expect(find.text('Buyer total: ₹48.00'), findsOneWidget);

      // Buyer does NOT see commission, farmer base price, or commission formulas
      expect(find.textContaining('Platform commission'), findsNothing);
      expect(find.textContaining('Farmer base price'), findsNothing);
      expect(find.textContaining('Commission is added for buyers'), findsNothing);
      expect(find.textContaining('Buyer total = farmer base'), findsNothing);
    });

    testWidgets('Buyer on Orders screen does NOT see platform commission or farmer base price',
        (tester) async {
      SessionManager().setSession(
        token: 'buyer-token',
        user: UserProfile(
            id: 'b1', name: 'Buyer Anbu', email: 'b@vayal.in', role: AppRole.buyer),
      );

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/orders/')) {
          return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'items': [
                    {
                      'order_id': 'ord_123',
                      'order_number': 'VC-ORD-123',
                      'product_name': 'Paddy',
                      'quantity': 2,
                      'unit': 'KG',
                      'order_status': 'COMPLETED',
                      'payment_status': 'CAPTURED',
                      'created_at': '2026-10-30T10:00:00Z',
                      'farmer_base_total_paise': 8000,
                      'commission_total_paise': 1600,
                      'delivery_fee_paise': 0,
                      'buyer_total_paise': 9600,
                      'fulfillment_method': 'DELIVERY',
                    }
                  ],
                  'total': 1
                }
              }),
              200);
        }
        return http.Response('{"success":false}', 404);
      });

      final api = ApiClient(client: mockClient);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: OrdersScreen(api: api),
      ));
      await tester.pumpAndSettle();

      // Buyer sees Buyer total
      expect(find.text('Buyer total'), findsOneWidget);
      expect(find.text('₹96.00'), findsOneWidget);

      // Buyer DOES NOT see Platform commission or Farmer base price
      expect(find.text('Platform commission'), findsNothing);
      expect(find.text('Farmer base price'), findsNothing);
      expect(find.textContaining('Commission is added for buyers'), findsNothing);
    });

    testWidgets('Admin on Orders screen CAN see platform commission',
        (tester) async {
      SessionManager().setSession(
        token: 'admin-token',
        user: UserProfile(
            id: 'a1', name: 'Admin Prabhu', email: 'a@vayal.in', role: AppRole.admin),
      );

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/orders/')) {
          return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'items': [
                    {
                      'order_id': 'ord_123',
                      'order_number': 'VC-ORD-123',
                      'product_name': 'Paddy',
                      'quantity': 2,
                      'unit': 'KG',
                      'order_status': 'COMPLETED',
                      'payment_status': 'CAPTURED',
                      'created_at': '2026-10-30T10:00:00Z',
                      'farmer_base_total_paise': 8000,
                      'commission_total_paise': 1600,
                      'delivery_fee_paise': 0,
                      'buyer_total_paise': 9600,
                      'fulfillment_method': 'DELIVERY',
                    }
                  ],
                  'total': 1
                }
              }),
              200);
        }
        return http.Response('{"success":false}', 404);
      });

      final api = ApiClient(client: mockClient);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: OrdersScreen(api: api),
      ));
      await tester.pumpAndSettle();

      // Admin sees platform commission
      expect(find.text('Platform commission'), findsOneWidget);
      expect(find.text('₹16.00'), findsOneWidget);
    });
  });

  group('Priority 2 & 3: Theme and Light Green Dashboard Tests', () {
    testWidgets('BrandHeading hero uses light-green background and dark green text',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: BrandHeading(
            title: 'Dashboard',
            subtitle: 'Farmer Murugan',
            icon: Icons.agriculture_outlined,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Find Container decoration of BrandHeading
      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;

      expect(decoration.color, equals(const Color(0xFFDCEBCB))); // Light green dashboard
      expect(decoration.borderRadius, equals(BorderRadius.circular(24)));

      // Verify title uses dark green text
      final titleText = tester.widget<Text>(find.text('Dashboard'));
      expect(titleText.style?.color, equals(const Color(0xFF174B2A))); // Dark green text

      // Verify subtitle uses secondary text color
      final subtitleText = tester.widget<Text>(find.text('Farmer Murugan'));
      expect(subtitleText.style?.color, equals(AppTheme.textSecondary));
    });

    test('AppTheme ThemeData uses warm cream palette tokens', () {
      final theme = AppTheme.lightTheme;

      expect(theme.scaffoldBackgroundColor, equals(const Color(0xFFF4EEE5)));
      expect(theme.cardTheme.color, equals(const Color(0xFFFAF6EF)));
      expect(theme.dialogTheme.backgroundColor, equals(const Color(0xFFFAF6EF)));
      expect(theme.bottomSheetTheme.backgroundColor, equals(const Color(0xFFFAF6EF)));
      expect(theme.colorScheme.surface, equals(const Color(0xFFFAF6EF)));
      expect(theme.inputDecorationTheme.fillColor, equals(const Color(0xFFFAF6EF)));
      expect(AppTheme.primaryGreen, equals(const Color(0xFF4B8F20)));
      expect(AppTheme.darkGreenText, equals(const Color(0xFF174B2A)));
      expect(AppTheme.lightGreenDashboard, equals(const Color(0xFFDCEBCB)));
      expect(AppTheme.earthBrown, equals(const Color(0xFF805638)));
    });
  });
}
