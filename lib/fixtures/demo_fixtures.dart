import '../models/dashboard_models.dart';
import '../models/order_models.dart';
import '../models/product_models.dart';

/// Isolated Demo & Testing Fixtures
///
/// NOTE: These fixtures are strictly isolated and only active when the user
/// explicitly enables DEMO PREVIEW mode in the application.
/// They are NEVER silently returned during production failures.
class DemoFixtures {
  DemoFixtures._();

  static List<BuyerProduct> sampleBuyerProducts() {
    return [
      BuyerProduct(
        productId: 'demo-prod-001',
        productName: 'பொன்னி நெல் (Ponni Paddy)',
        category: 'தானியங்கள் (Grains)',
        quantityAvailable: 25,
        quantityUnit: 'QUINTAL',
        qualityGrade: 'A',
        location: 'தஞ்சாவூர் (Thanjavur)',
        farmerName: 'முருகன் கே. (Murugan)',
        buyerPricePerUnitPaise: 245000,
        buyerPricePerUnitDisplay: '₹2,450 / Quintal',
        harvestDate: '2026-10-08',
      ),
      BuyerProduct(
        productId: 'demo-prod-002',
        productName: 'நாட்டுத் தக்காளி (Country Tomato)',
        category: 'காய்கறிகள் (Vegetables)',
        quantityAvailable: 400,
        quantityUnit: 'KG',
        qualityGrade: 'A',
        location: 'மதுரை (Madurai APMC)',
        farmerName: 'செல்வராஜ் (Selvaraj)',
        buyerPricePerUnitPaise: 3200,
        buyerPricePerUnitDisplay: '₹32.00 / kg',
        harvestDate: '2026-10-09',
      ),
      BuyerProduct(
        productId: 'demo-prod-003',
        productName: 'சேலம் விரலி மஞ்சள் (Salem Turmeric)',
        category: 'மசாலா (Spices)',
        quantityAvailable: 50,
        quantityUnit: 'QUINTAL',
        qualityGrade: 'PREMIUM',
        location: 'சேலம் / ஈரோடு (Salem)',
        farmerName: 'கந்தசாமி (Kandasamy)',
        buyerPricePerUnitPaise: 14500,
        buyerPricePerUnitDisplay: '₹145.00 / kg',
        harvestDate: '2026-10-05',
      ),
      BuyerProduct(
        productId: 'demo-prod-004',
        productName: 'சின்ன வெங்காயம் (Shallots)',
        category: 'காய்கறிகள் (Vegetables)',
        quantityAvailable: 800,
        quantityUnit: 'KG',
        qualityGrade: 'B',
        location: 'திண்டுக்கல் (Dindigul)',
        farmerName: 'பழனிவேல் (Palanivel)',
        buyerPricePerUnitPaise: 4800,
        buyerPricePerUnitDisplay: '₹48.00 / kg',
        harvestDate: '2026-10-07',
      ),
    ];
  }

  static List<FarmerProduct> sampleFarmerProducts() {
    return [
      FarmerProduct(
        productId: 'demo-farm-001',
        productName: 'பொன்னி நெல் (Ponni Paddy)',
        category: 'தானியங்கள் (Grains)',
        quantityAvailable: 25,
        quantityUnit: 'QUINTAL',
        qualityGrade: 'A',
        location: 'பாபநாசம், தஞ்சாவூர்',
        market: 'தஞ்சாவூர் ஒழுங்குமுறை விற்பனைக்கூடம்',
        harvestDate: '2026-10-08',
        farmerPayoutPerUnitPaise: 225000,
        farmerPayoutPerUnitDisplay: '₹2,250 / Quintal',
        status: 'ACTIVE',
      ),
      FarmerProduct(
        productId: 'demo-farm-002',
        productName: 'நாட்டுத் தக்காளி (Country Tomato)',
        category: 'காய்கறிகள் (Vegetables)',
        quantityAvailable: 400,
        quantityUnit: 'KG',
        qualityGrade: 'A',
        location: 'உசிலம்பட்டி, மதுரை',
        market: 'மதுரை மத்திய APMC மண்டி',
        harvestDate: '2026-10-09',
        farmerPayoutPerUnitPaise: 2800,
        farmerPayoutPerUnitDisplay: '₹28.00 / kg',
        status: 'ACTIVE',
      ),
    ];
  }

  static List<BuyerOrder> sampleBuyerOrders() {
    return [
      BuyerOrder(
        orderId: 'demo-ord-101',
        orderNumber: 'VY-8921',
        productName: 'பொன்னி நெல் (Ponni Paddy)',
        quantity: 50,
        unit: 'QUINTAL',
        buyerUnitPricePaise: 225000,
        buyerUnitPriceDisplay: '₹2,250',
        buyerTotalPaise: 11250000,
        buyerTotalDisplay: '₹1,12,500',
        orderStatus: 'CONFIRMED',
        paymentStatus: 'PAID',
        createdAt: '2026-10-08',
      ),
      BuyerOrder(
        orderId: 'demo-ord-102',
        orderNumber: 'VY-8920',
        productName: 'நாட்டுத் தக்காளி (Country Tomato)',
        quantity: 800,
        unit: 'KG',
        buyerUnitPricePaise: 2800,
        buyerUnitPriceDisplay: '₹28.00 / kg',
        buyerTotalPaise: 2240000,
        buyerTotalDisplay: '₹22,400',
        orderStatus: 'PROCESSING',
        paymentStatus: 'PAID',
        createdAt: '2026-10-09',
      ),
    ];
  }

  static List<FarmerOrder> sampleFarmerOrders() {
    return [
      FarmerOrder(
        orderId: 'demo-farm-ord-1',
        orderNumber: 'VY-8921',
        productName: 'பொன்னி நெல் (Ponni Paddy)',
        quantity: 50,
        unit: 'QUINTAL',
        farmerUnitPayoutPaise: 225000,
        farmerUnitPayoutDisplay: '₹2,250 / Q',
        farmerTotalPayoutPaise: 11250000,
        farmerTotalPayoutDisplay: '₹1,12,500',
        orderStatus: 'DELIVERED',
        payoutStatus: 'PAID',
        buyerName: 'சென்னை ஆர்கானிக்ஸ் (Chennai Organics)',
        createdAt: '2026-10-08',
      ),
      FarmerOrder(
        orderId: 'demo-farm-ord-2',
        orderNumber: 'VY-8920',
        productName: 'நாட்டுத் தக்காளி (Country Tomato)',
        quantity: 400,
        unit: 'KG',
        farmerUnitPayoutPaise: 2800,
        farmerUnitPayoutDisplay: '₹28.00 / kg',
        farmerTotalPayoutPaise: 1120000,
        farmerTotalPayoutDisplay: '₹11,200',
        orderStatus: 'PROCESSING',
        payoutStatus: 'PENDING_TRANSFER',
        buyerName: 'மதுரை மொத்த வர்த்தகர் (Madurai Traders)',
        createdAt: '2026-10-09',
      ),
    ];
  }

  static FarmerDashboardMetrics sampleFarmerMetrics() {
    return FarmerDashboardMetrics(
      totalProducts: 4,
      activeProducts: 2,
      totalOrders: 6,
      pendingOrders: 1,
      completedOrders: 5,
      totalPayoutPaise: 4850000,
      totalPayoutDisplay: '₹48,500',
      pendingPayoutPaise: 1240000,
      pendingPayoutDisplay: '₹12,400',
    );
  }

  static AdminDashboardMetrics sampleAdminMetrics() {
    return AdminDashboardMetrics(
      totalOrders: 142,
      totalSalesPaise: 84500000,
      totalSalesDisplay: '₹8,45,000',
      totalQuantitySold: 420,
      totalFarmerPayoutPaise: 78000000,
      totalFarmerPayoutDisplay: '₹7,80,000',
      totalPlatformCommissionPaise: 6500000,
      totalPlatformCommissionDisplay: '₹65,000',
      activeFarmers: 64,
      activeBuyers: 38,
      pendingPayouts: 3,
      pendingFarmerApprovals: 4,
    );
  }
}
