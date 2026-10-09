/// VayalConnect Order Models
///
/// Matches backend role separation in app.schemas.order

class BuyerOrder {
  final String orderId;
  final String orderNumber;
  final String productName;
  final int quantity;
  final String unit;
  final int buyerUnitPricePaise;
  final String buyerUnitPriceDisplay;
  final int buyerTotalPaise;
  final String buyerTotalDisplay;
  final String orderStatus;
  final String paymentStatus;
  final String? razorpayOrderId;
  final String? createdAt;

  BuyerOrder({
    required this.orderId,
    required this.orderNumber,
    required this.productName,
    required this.quantity,
    required this.unit,
    required this.buyerUnitPricePaise,
    required this.buyerUnitPriceDisplay,
    required this.buyerTotalPaise,
    required this.buyerTotalDisplay,
    required this.orderStatus,
    required this.paymentStatus,
    this.razorpayOrderId,
    this.createdAt,
  });

  factory BuyerOrder.fromJson(Map<String, dynamic> json) {
    return BuyerOrder(
      orderId: json['order_id'] as String? ?? json['id'] as String? ?? '',
      orderNumber: json['order_number'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unit: json['unit'] as String? ?? 'Quintal',
      buyerUnitPricePaise: (json['buyer_unit_price_paise'] as num?)?.toInt() ?? 0,
      buyerUnitPriceDisplay: json['buyer_unit_price_display'] as String? ?? '₹0.00',
      buyerTotalPaise: (json['buyer_total_paise'] as num?)?.toInt() ?? 0,
      buyerTotalDisplay: json['buyer_total_display'] as String? ?? '₹0.00',
      orderStatus: json['order_status'] as String? ?? 'PENDING',
      paymentStatus: json['payment_status'] as String? ?? 'PENDING',
      razorpayOrderId: json['razorpay_order_id'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }
}

class FarmerOrder {
  final String orderId;
  final String orderNumber;
  final String productName;
  final int quantity;
  final String unit;
  final int farmerUnitPayoutPaise;
  final String farmerUnitPayoutDisplay;
  final int farmerTotalPayoutPaise;
  final String farmerTotalPayoutDisplay;
  final String orderStatus;
  final String payoutStatus;
  final String? buyerName;
  final String? createdAt;

  FarmerOrder({
    required this.orderId,
    required this.orderNumber,
    required this.productName,
    required this.quantity,
    required this.unit,
    required this.farmerUnitPayoutPaise,
    required this.farmerUnitPayoutDisplay,
    required this.farmerTotalPayoutPaise,
    required this.farmerTotalPayoutDisplay,
    required this.orderStatus,
    required this.payoutStatus,
    this.buyerName,
    this.createdAt,
  });

  factory FarmerOrder.fromJson(Map<String, dynamic> json) {
    return FarmerOrder(
      orderId: json['order_id'] as String? ?? json['id'] as String? ?? '',
      orderNumber: json['order_number'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unit: json['unit'] as String? ?? 'Quintal',
      farmerUnitPayoutPaise: (json['farmer_unit_payout_paise'] as num?)?.toInt() ?? 0,
      farmerUnitPayoutDisplay: json['farmer_unit_payout_display'] as String? ?? '₹0.00',
      farmerTotalPayoutPaise: (json['farmer_total_payout_paise'] as num?)?.toInt() ?? 0,
      farmerTotalPayoutDisplay: json['farmer_total_payout_display'] as String? ?? '₹0.00',
      orderStatus: json['order_status'] as String? ?? 'PENDING',
      payoutStatus: json['payout_status'] as String? ?? 'PENDING',
      buyerName: json['buyer_name'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }
}
