import 'package:flutter_test/flutter_test.dart';
import 'package:vayalconnect_flutter/models/product_models.dart';
import 'package:vayalconnect_flutter/models/order_models.dart';
import 'package:vayalconnect_flutter/models/dashboard_models.dart';

void main() {
  group('Product and Order Models Test', () {
    test('FarmerProduct correctly parses payout without leaking buyer price', () {
      final json = {
        'product_id': 'prd_100',
        'product_name': 'Ponni Paddy',
        'category': 'Grains',
        'quantity_available': 25,
        'quantity_unit': 'Quintal',
        'quality_grade': 'Grade A',
        'location': 'Thanjavur',
        'market': 'Thanjavur APMC',
        'farmer_payout_per_unit_paise': 225000,
        'farmer_payout_per_unit_display': '₹2,250 / Quintal',
        'status': 'ACTIVE',
      };

      final product = FarmerProduct.fromJson(json);

      expect(product.productId, 'prd_100');
      expect(product.productName, 'Ponni Paddy');
      expect(product.farmerPayoutPerUnitPaise, 225000);
      expect(product.farmerPayoutPerUnitDisplay, '₹2,250 / Quintal');
      expect(product.status, 'ACTIVE');
    });

    test('BuyerProduct correctly parses buyer price without leaking farmer payout', () {
      final json = {
        'product_id': 'prd_200',
        'product_name': 'Country Tomato',
        'category': 'Vegetables',
        'quantity_available': 400,
        'quantity_unit': 'Kg',
        'quality_grade': 'Grade A',
        'location': 'Madurai',
        'farmer_name': 'Selvaraj',
        'buyer_price_per_unit_paise': 3200,
        'buyer_price_per_unit_display': '₹32.00 / kg',
      };

      final product = BuyerProduct.fromJson(json);

      expect(product.productId, 'prd_200');
      expect(product.farmerName, 'Selvaraj');
      expect(product.buyerPricePerUnitPaise, 3200);
      expect(product.buyerPricePerUnitDisplay, '₹32.00 / kg');
    });

    test('BuyerOrder and FarmerOrder parse accurately', () {
      final buyerJson = {
        'order_id': 'ord_1',
        'order_number': 'VY-8921',
        'product_name': 'Ponni Paddy',
        'quantity': 50,
        'unit': 'Quintal',
        'buyer_unit_price_paise': 245000,
        'buyer_unit_price_display': '₹2,450',
        'buyer_total_paise': 12250000,
        'buyer_total_display': '₹1,22,500',
        'order_status': 'CONFIRMED',
        'payment_status': 'PAID',
      };

      final buyerOrder = BuyerOrder.fromJson(buyerJson);
      expect(buyerOrder.orderNumber, 'VY-8921');
      expect(buyerOrder.buyerTotalDisplay, '₹1,22,500');

      final farmerJson = {
        'order_id': 'ord_2',
        'order_number': 'VY-8921',
        'product_name': 'Ponni Paddy',
        'quantity': 50,
        'unit': 'Quintal',
        'farmer_unit_payout_paise': 225000,
        'farmer_unit_payout_display': '₹2,250',
        'farmer_total_payout_paise': 11250000,
        'farmer_total_payout_display': '₹1,12,500',
        'order_status': 'CONFIRMED',
        'payout_status': 'PENDING_TRANSFER',
      };

      final farmerOrder = FarmerOrder.fromJson(farmerJson);
      expect(farmerOrder.farmerTotalPayoutDisplay, '₹1,12,500');
      expect(farmerOrder.payoutStatus, 'PENDING_TRANSFER');
    });

    test('Dashboard metrics parse accurately', () {
      final farmerDash = FarmerDashboardMetrics.fromJson({
        'total_products': 4,
        'active_products': 2,
        'total_orders': 6,
        'total_payout_display': '₹48,500',
        'pending_payout_display': '₹12,400',
      });

      expect(farmerDash.totalProducts, 4);
      expect(farmerDash.totalPayoutDisplay, '₹48,500');

      final adminDash = AdminDashboardMetrics.fromJson({
        'total_orders': 142,
        'total_sales_display': '₹8,45,000',
        'total_farmer_payout_display': '₹7,80,000',
        'total_platform_commission_display': '₹65,000',
      });

      expect(adminDash.totalOrders, 142);
      expect(adminDash.totalSalesDisplay, '₹8,45,000');
    });
  });
}
