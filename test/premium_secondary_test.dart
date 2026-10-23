import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vayalconnect_flutter/models/auth_models.dart';
import 'package:vayalconnect_flutter/screens/addresses_screen.dart';
import 'package:vayalconnect_flutter/screens/admin_dashboard_screen.dart';
import 'package:vayalconnect_flutter/screens/farmer_application_screen.dart';
import 'package:vayalconnect_flutter/screens/farmer_bank_screen.dart';
import 'package:vayalconnect_flutter/screens/farmer_home_screen.dart';
import 'package:vayalconnect_flutter/screens/location_gate_screen.dart';
import 'package:vayalconnect_flutter/screens/orders_screen.dart';
import 'package:vayalconnect_flutter/screens/payment_screen.dart';
import 'package:vayalconnect_flutter/services/api_client.dart';
import 'package:vayalconnect_flutter/services/farmer_service.dart';
import 'package:vayalconnect_flutter/services/session_manager.dart';
import 'premium_ui_test.dart' as ui;

Map<String, dynamic> farmer() => {
      'user_id': 'farmer',
      'name': 'Farmer with a long name',
      'phone': '9876543210',
      'email': 'farmer@example.invalid',
      'area_location': 'Pollachi',
      'approval_status': 'PENDING',
      'can_publish': false,
      'submitted_at': '2026-10-15',
      'bank_details_present': true,
      'application': {
        'farm_name': 'Test farm',
        'farm_address': '12 Long agricultural road, Pollachi, Tamil Nadu',
        'pickup_address': '12 Long agricultural road, Pollachi',
        'crops': 'Tomato',
        'farm_details': 'Seasonal vegetables',
        'delivery_available': true,
        'coordinates': {'latitude': 10.65, 'longitude': 77.01},
      },
    };

http.Response response(http.Request request) {
  final path = request.url.path;
  dynamic data = <String, dynamic>{};
  if (path.endsWith('/profile') || path == '/api/v1/admin/farmers/farmer') {
    data = farmer();
  } else if (path.endsWith('/commission')) {
    data = {'commission_percentage_bps': 1800};
  } else if (path.endsWith('/orders/historical')) {
    data = ui.order(AppRole.admin);
  } else if (path.endsWith('/orders/')) {
    data = {
      'items': [ui.order(SessionManager().activeRole)],
      'total': 1
    };
  } else if (path.endsWith('/admin/farmers')) {
    data = {
      'items': [farmer()],
      'total': 1
    };
  } else if (path.endsWith('/sales')) {
    data = {
      'farmer_earnings_paise': 120000,
      'commission_paise': 24000,
      'stock': [
        {'quantity': 120, '_id': 'KG'}
      ],
      'items': [
        {
          '_id': {'crop': 'தக்காளி · Long harvest name', 'unit': 'KG'},
          'quantity': 12,
          'farmer_amount_paise': 120000
        }
      ]
    };
  } else if (path.endsWith('/addresses')) {
    data = {
      'items': [
        {
          'id': 'address',
          'recipient_name': 'Recipient with a long name',
          'building': '12 Farm House',
          'street': 'Agricultural Road',
          'locality': 'Long locality',
          'city': 'Pollachi',
          'state': 'Tamil Nadu',
          'postal_code': '642001',
          'phone': '9876543210',
          'is_default': true
        }
      ]
    };
  }
  return http.Response(jsonEncode({'success': true, 'data': data}), 200,
      headers: {'content-type': 'application/json; charset=utf-8'});
}

void main() {
  tearDown(() => SessionManager().logout());
  for (final tamil in [false, true]) {
    for (final large in [false, true]) {
      testWidgets('secondary pages fit Tamil=$tamil largeText=$large',
          (tester) async {
        tester.view.physicalSize = Size(large ? 320 : 800, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await ui.fonts(tester);
        const channel = MethodChannel('razorpay_flutter');
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => null);
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null));
        final api = ApiClient(client: MockClient((r) async => response(r)));
        addTearDown(api.dispose);
        for (final entry in <(String, AppRole, Widget)>[
          (
            'farmer-application',
            AppRole.farmer,
            FarmerApplicationScreen(
                service:
                    FarmerService(client: MockClient((r) async => response(r))))
          ),
          (
            'farmer-bank',
            AppRole.farmer,
            FarmerBankScreen(
                service:
                    FarmerService(client: MockClient((r) async => response(r))))
          ),
          ('farmer-sales', AppRole.farmer, FarmerSalesScreen(api: api)),
          ('admin-farmers', AppRole.admin, AdminFarmersScreen(api: api)),
          (
            'farmer-review',
            AppRole.admin,
            FarmerReviewScreen(farmer: farmer(), api: api)
          ),
          ('commission', AppRole.admin, CommissionScreen(api: api)),
          (
            'payout-review',
            AppRole.admin,
            PayoutReviewScreen(payout: const {
              'order_id': 'historical',
              'payout_id': 'payout',
              'amount_paise': 120000,
              'status': 'PENDING_APPROVAL'
            }, api: api)
          ),
          ('addresses', AppRole.buyer, AddressesScreen(api: api)),
          (
            'location-gate',
            AppRole.buyer,
            const LocationGateScreen(home: SizedBox())
          ),
          (
            'payment',
            AppRole.buyer,
            PaymentScreen(orderId: 'historical', api: api)
          ),
          ('order-history', AppRole.buyer, OrdersScreen(api: api)),
        ]) {
          ui.setRole(entry.$2, tamil);
          await tester
              .pumpWidget(ui.app(entry.$3, tamil: tamil, scale: large ? 2 : 1));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: entry.$1);
          await ui.capture(tester,
              '${entry.$1}-${tamil ? 'ta' : 'en'}-${large ? '320' : '800'}');
          // Exercise the entire scrollable form/list, including lower actions.
          final scrolls = find.byType(Scrollable);
          if (scrolls.evaluate().isNotEmpty) {
            await tester.drag(scrolls.first, const Offset(0, -550));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull,
                reason: '${entry.$1} scrolled');
          }
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }
}
