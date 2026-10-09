/// VayalConnect Dashboard Metrics Models
///
/// Matches app.schemas.farmer (FarmerDashboardResponse)
/// and app.schemas.admin (AdminDashboardResponse)

class FarmerDashboardMetrics {
  final int totalProducts;
  final int activeProducts;
  final int totalOrders;
  final int pendingOrders;
  final int completedOrders;
  final int totalPayoutPaise;
  final String totalPayoutDisplay;
  final int pendingPayoutPaise;
  final String pendingPayoutDisplay;

  FarmerDashboardMetrics({
    this.totalProducts = 0,
    this.activeProducts = 0,
    this.totalOrders = 0,
    this.pendingOrders = 0,
    this.completedOrders = 0,
    this.totalPayoutPaise = 0,
    this.totalPayoutDisplay = '₹0.00',
    this.pendingPayoutPaise = 0,
    this.pendingPayoutDisplay = '₹0.00',
  });

  factory FarmerDashboardMetrics.fromJson(Map<String, dynamic> json) {
    return FarmerDashboardMetrics(
      totalProducts: (json['total_products'] as num?)?.toInt() ?? 0,
      activeProducts: (json['active_products'] as num?)?.toInt() ?? 0,
      totalOrders: (json['total_orders'] as num?)?.toInt() ?? 0,
      pendingOrders: (json['pending_orders'] as num?)?.toInt() ?? 0,
      completedOrders: (json['completed_orders'] as num?)?.toInt() ?? 0,
      totalPayoutPaise: (json['total_payout_paise'] as num?)?.toInt() ?? 0,
      totalPayoutDisplay: json['total_payout_display'] as String? ?? '₹0.00',
      pendingPayoutPaise: (json['pending_payout_paise'] as num?)?.toInt() ?? 0,
      pendingPayoutDisplay: json['pending_payout_display'] as String? ?? '₹0.00',
    );
  }
}

class AdminDashboardMetrics {
  final int totalOrders;
  final int totalSalesPaise;
  final String totalSalesDisplay;
  final int totalQuantitySold;
  final int totalFarmerPayoutPaise;
  final String totalFarmerPayoutDisplay;
  final int totalPlatformCommissionPaise;
  final String totalPlatformCommissionDisplay;
  final int activeFarmers;
  final int activeBuyers;
  final int pendingPayouts;
  final int pendingFarmerApprovals;

  AdminDashboardMetrics({
    this.totalOrders = 0,
    this.totalSalesPaise = 0,
    this.totalSalesDisplay = '₹0.00',
    this.totalQuantitySold = 0,
    this.totalFarmerPayoutPaise = 0,
    this.totalFarmerPayoutDisplay = '₹0.00',
    this.totalPlatformCommissionPaise = 0,
    this.totalPlatformCommissionDisplay = '₹0.00',
    this.activeFarmers = 0,
    this.activeBuyers = 0,
    this.pendingPayouts = 0,
    this.pendingFarmerApprovals = 0,
  });

  factory AdminDashboardMetrics.fromJson(Map<String, dynamic> json) {
    return AdminDashboardMetrics(
      totalOrders: (json['total_orders'] as num?)?.toInt() ?? 0,
      totalSalesPaise: (json['total_sales_paise'] as num?)?.toInt() ?? 0,
      totalSalesDisplay: json['total_sales_display'] as String? ?? '₹0.00',
      totalQuantitySold: (json['total_quantity_sold'] as num?)?.toInt() ?? 0,
      totalFarmerPayoutPaise: (json['total_farmer_payout_paise'] as num?)?.toInt() ?? 0,
      totalFarmerPayoutDisplay: json['total_farmer_payout_display'] as String? ?? '₹0.00',
      totalPlatformCommissionPaise: (json['total_platform_commission_paise'] as num?)?.toInt() ?? 0,
      totalPlatformCommissionDisplay: json['total_platform_commission_display'] as String? ?? '₹0.00',
      activeFarmers: (json['active_farmers'] as num?)?.toInt() ?? 0,
      activeBuyers: (json['active_buyers'] as num?)?.toInt() ?? 0,
      pendingPayouts: (json['pending_payouts'] as num?)?.toInt() ?? 0,
      pendingFarmerApprovals: (json['pending_farmer_approvals'] as num?)?.toInt() ?? 0,
    );
  }
}
