import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayalconnect_flutter/models/auth_models.dart';
import 'package:vayalconnect_flutter/screens/farmer_home_screen.dart';
import 'package:vayalconnect_flutter/screens/buyer_home_screen.dart';
import 'package:vayalconnect_flutter/screens/admin_dashboard_screen.dart';
import 'package:vayalconnect_flutter/screens/add_product_screen.dart';
import 'package:vayalconnect_flutter/services/api_client.dart';
import 'package:vayalconnect_flutter/services/session_manager.dart';
import 'package:vayalconnect_flutter/theme/app_theme.dart';
import 'package:vayalconnect_flutter/widgets/bottom_nav_bar.dart';
import 'package:vayalconnect_flutter/widgets/vayal_drawer.dart';
import 'package:vayalconnect_flutter/widgets/vayal_app_bar.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MockHomeScreenApi extends ApiClient {
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (path.contains('/api/v1/farmers/me/dashboard')) {
      return {
        'active_products': 5,
        'total_orders': 10,
        'pending_orders': 2,
        'completed_orders': 8,
        'total_payout_display': '₹5,000.00',
        'pending_payout_display': '₹1,200.00',
      };
    }
    if (path.contains('/api/v1/farmers/me/profile')) {
      return {
        'can_publish': true,
        'approval_status': 'APPROVED',
      };
    }
    if (path.contains('/api/v1/products/')) {
      return {'items': [], 'total': 0};
    }
    if (path.contains('/api/v1/admin/dashboard')) {
      return {
        'total_farmers': 12,
        'approved_farmers': 10,
        'pending_farmer_approvals': 2,
        'gross_order_value_paise': 1500000,
        'total_platform_commission_paise': 75000,
        'captured_payments_paise': 1500000,
        'paid_payouts_paise': 1200000,
        'pending_payouts_paise': 225000,
      };
    }
    if (path.contains('/api/v1/market-prices/filter-options')) {
      return {'categories': ['Grains', 'Vegetables']};
    }
    return {};
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SessionManager().resetForTests();
  });

  group('Top-Left Menu and Navigation Drawer Tests', () {
    testWidgets('FarmerHomeScreen renders top-left menu icon and opens drawer with farmer destinations',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final session = SessionManager();
      await session.setSession(
        token: 'test_token',
        refreshToken: 'test_refresh_token',
        user: UserProfile(
          id: 'f_123',
          role: AppRole.farmer,
          name: 'Selvam Farmer',
          phone: '+919876543210',
          email: 'selvam@example.com',
          preferredLanguage: 'en',
        ),
      );

      final api = MockHomeScreenApi();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: FarmerHomeScreen(api: api),
        ),
      );
      await tester.pumpAndSettle();

      // Top-left menu icon button exists
      final menuButton = find.byTooltip('Menu');
      expect(menuButton, findsOneWidget);

      // Bottom nav has 3 items and no More item
      expect(find.byType(VayalBottomNavBar), findsOneWidget);
      expect(find.text('Dashboard'), findsWidgets);
      expect(find.text('My Crops'), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('More'), findsNothing);

      // Tap menu button to open drawer
      await tester.tap(menuButton);
      await tester.pumpAndSettle();

      // Drawer is open
      expect(find.byType(VayalNavigationDrawer), findsOneWidget);
      expect(find.text('Selvam Farmer'), findsWidgets);
      expect(find.text('+919876543210'), findsOneWidget);

      // Check farmer drawer destinations
      expect(find.text('Add Crop'), findsOneWidget);
      expect(find.text('Market Prices'), findsOneWidget);
      expect(find.text('Sales & Earnings'), findsOneWidget);
      expect(find.text('Payouts'), findsOneWidget);
      expect(find.text('Bank Details'), findsOneWidget);
      expect(find.text('Farmer Application'), findsOneWidget);
      expect(find.text('Delivery Addresses'), findsOneWidget);
      expect(find.text('Profile & Settings'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);
    });

    testWidgets('BuyerHomeScreen renders top-left menu icon and opens buyer drawer',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final session = SessionManager();
      await session.setSession(
        token: 'test_buyer_token',
        refreshToken: 'test_buyer_refresh',
        user: UserProfile(
          id: 'b_123',
          role: AppRole.buyer,
          name: 'Kavitha Buyer',
          phone: '+919876543211',
          email: 'kavitha@example.com',
          preferredLanguage: 'en',
        ),
      );

      final api = MockHomeScreenApi();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: BuyerHomeScreen(api: api),
        ),
      );
      await tester.pumpAndSettle();

      final menuButton = find.byTooltip('Menu');
      expect(menuButton, findsOneWidget);

      // Bottom nav has 3 items and no More item
      expect(find.text('Market'), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('More'), findsNothing);

      // Open drawer
      await tester.tap(menuButton);
      await tester.pumpAndSettle();

      expect(find.byType(VayalNavigationDrawer), findsOneWidget);
      expect(find.text('Kavitha Buyer'), findsOneWidget);
      expect(find.text('Browse Products'), findsOneWidget);
      expect(find.text('Delivery Addresses'), findsOneWidget);
      expect(find.text('Market Prices'), findsOneWidget);
      expect(find.text('Profile & Settings'), findsOneWidget);
    });

    testWidgets('AdminDashboardScreen renders top-left menu icon and opens admin drawer',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final session = SessionManager();
      await session.setSession(
        token: 'test_admin_token',
        refreshToken: 'test_admin_refresh',
        user: UserProfile(
          id: 'a_123',
          role: AppRole.admin,
          name: 'Admin User',
          phone: '+919876543212',
          email: 'admin@vayalconnect.com',
          preferredLanguage: 'en',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const AdminDashboardScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final menuButton = find.byTooltip('Menu');
      expect(menuButton, findsOneWidget);

      // Bottom nav has 3 items and no More item
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Farmers'), findsWidgets);
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('More'), findsNothing);

      // Open drawer
      await tester.tap(menuButton);
      await tester.pumpAndSettle();

      expect(find.byType(VayalNavigationDrawer), findsOneWidget);
      expect(find.text('Admin User'), findsOneWidget);
      expect(find.text('Farmer Applications'), findsOneWidget);
      expect(find.text('Buyers'), findsOneWidget);
      expect(find.text('Products & Listings'), findsOneWidget);
      expect(find.text('Commission Management'), findsOneWidget);
      expect(find.text('Payouts'), findsOneWidget);
    });
  });

  group('Session Preservation and Camera Lifecycle Regression Tests', () {
    test('SessionManager stores, restores, and updates refresh tokens properly', () async {
      final session = SessionManager();

      await session.setSession(
        token: 'access_123',
        refreshToken: 'refresh_456',
        user: UserProfile(
          id: 'f_456',
          role: AppRole.farmer,
          name: 'Ramu Farmer',
          phone: '+919876543213',
          email: 'ramu@example.com',
          preferredLanguage: 'en',
        ),
      );

      expect(session.accessToken, 'access_123');
      expect(session.refreshToken, 'refresh_456');
      expect(session.isAuthenticated, isTrue);

      // Simulate app restart by creating a new SessionManager instance
      // (or testing restoreSession on SharedPreferences)
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('vayal_access_token'), 'access_123');
      expect(prefs.getString('vayal_refresh_token'), 'refresh_456');

      // Update tokens (as after silent refresh)
      await session.updateTokens(
        accessToken: 'access_new_789',
        refreshToken: 'refresh_new_999',
      );

      expect(session.accessToken, 'access_new_789');
      expect(session.refreshToken, 'refresh_new_999');
      expect(prefs.getString('vayal_access_token'), 'access_new_789');
      expect(prefs.getString('vayal_refresh_token'), 'refresh_new_999');
    });

    testWidgets('AddProductScreen restores form draft and accepts image without AI verification',
        (tester) async {
      // Pre-seed a draft that was saved before camera capture
      final prefs = await SharedPreferences.getInstance();
      final draft = {
        'product_name': 'Organic Tomato',
        'category': 'Vegetables',
        'quantity': '150',
        'quantity_unit': 'KG',
        'selling_price': '42.50',
        'location': 'Dindigul',
        'market': 'Ottanchathiram',
        'state': 'Tamil Nadu',
        'district': 'Dindigul',
        'variety': 'Naatu Thakkali',
        'description': 'Fresh morning harvest without chemical sprays',
        'quality_grade': 'A',
        'image_url': '/api/v1/media/demo-tomato',
        'image_verified': true,
      };
      await prefs.setString('vayal_add_product_draft', jsonEncode(draft));

      final mockApi = MockHomeScreenApi();
      await tester.pumpWidget(
        MaterialApp(
          home: AddProductScreen(api: mockApi),
        ),
      );
      await tester.pumpAndSettle();

      // Verify draft inputs are restored
      expect(find.text('Organic Tomato'), findsOneWidget);
      expect(find.text('150'), findsOneWidget);
      expect(find.text('42.50'), findsOneWidget);
      expect(find.text('Dindigul'), findsWidgets);
      expect(find.text('Ottanchathiram'), findsOneWidget);

      // Verify image is accepted without any AI verification requirement or warning cards
      expect(find.text('✓ Image Accepted'), findsOneWidget);
      expect(find.textContaining('AI verification'), findsNothing);
      expect(find.textContaining('GEMINI_API_KEY'), findsNothing);
    });

    test('ApiClient retries request silently upon 401 when refresh token is valid', () async {
      final session = SessionManager();
      await session.setSession(
        token: 'expired_token',
        refreshToken: 'valid_refresh',
        user: UserProfile(
          id: 'f_789',
          role: AppRole.farmer,
          name: 'Farmer',
          phone: '+919876543214',
          email: 'farmer@example.com',
          preferredLanguage: 'en',
        ),
      );

      int attempts = 0;
      final mockHttp = MockClient((req) async {
        attempts++;
        if (req.url.path.contains('/api/v1/auth/refresh')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'access_token': 'new_valid_token',
                'refresh_token': 'new_refresh_token',
              }
            }),
            200,
          );
        }
        if (req.headers['Authorization'] == 'Bearer expired_token') {
          return http.Response(
            jsonEncode({'detail': 'Token expired'}),
            401,
          );
        }
        if (req.headers['Authorization'] == 'Bearer new_valid_token') {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'crops': ['Tomato', 'Chilli']
              }
            }),
            200,
          );
        }
        return http.Response('Forbidden', 403);
      });

      final client = ApiClient(client: mockHttp);
      final result = await client.request('/api/v1/products/my');

      expect(result['crops'], contains('Tomato'));
      expect(session.accessToken, 'new_valid_token');
      expect(session.isAuthenticated, isTrue);
      client.dispose();
    });
  });
}
