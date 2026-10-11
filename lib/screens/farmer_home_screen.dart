import 'package:flutter/material.dart';
import '../models/dashboard_models.dart';
import '../models/market_price.dart';
import '../models/product_models.dart';
import '../services/farmer_service.dart';
import '../services/market_price_service.dart';
import '../services/product_service.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/demo_banner.dart';
import '../widgets/mandi_ticker.dart';
import '../widgets/produce_card.dart';
import '../widgets/vayal_app_bar.dart';
import 'add_product_screen.dart';
import 'market_prices_screen.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';
import 'farmer_application_screen.dart';

/// Farmer Home Dashboard
///
/// Implements Stitch Screen 7e4d52323b29474c9e8aca2ab3d36e30
class FarmerHomeScreen extends StatefulWidget {
  const FarmerHomeScreen({Key? key}) : super(key: key);

  @override
  State<FarmerHomeScreen> createState() => _FarmerHomeScreenState();
}

class _FarmerHomeScreenState extends State<FarmerHomeScreen> {
  final _farmerService = FarmerService();
  final _productService = ProductService();
  final _marketPriceService = MarketPriceService();

  int _currentNavIndex = 0;
  bool _isLoading = true;
  String? _errorMessage;
  FarmerDashboardMetrics _metrics = FarmerDashboardMetrics();
  List<FarmerProduct> _myProducts = [];
  List<MarketPriceItem> _mandiPrices = [];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  @override
  void dispose() {
    _farmerService.dispose();
    _productService.dispose();
    _marketPriceService.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final metricsFuture = _farmerService.fetchDashboardMetrics();
      final productsFuture = _productService.fetchMyFarmerProducts();
      final pricesFuture = _marketPriceService.fetchMarketPrices(limit: 6);

      final results = await Future.wait([
        metricsFuture,
        productsFuture,
        pricesFuture.then((r) => r.records).catchError((_) => <MarketPriceItem>[]),
      ]);

      if (mounted) {
        setState(() {
          _metrics = results[0] as FarmerDashboardMetrics;
          _myProducts = results[1] as List<FarmerProduct>;
          _mandiPrices = results[2] as List<MarketPriceItem>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  void _onBottomNavTapped(int index) {
    if (index == _currentNavIndex) return;

    switch (index) {
      case 0:
        // Already on Farmer Home
        break;
      case 1:
        // My Crops tab - scroll or navigate
        break;
      case 2:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MarketPricesScreen()),
        );
        break;
      case 3:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const OrdersScreen()),
        );
        break;
      case 4:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionManager();

    return Scaffold(
      backgroundColor: AppTheme.backgroundWarm,
      appBar: VayalAppBar(
        title: session.isTamil ? 'வணக்கம், முருகன் 🌾' : 'Welcome, Murugan 🌾',
        subtitle: session.isTamil ? 'தஞ்சாவூர் மாவட்டம் • நேரடி உழவர்' : 'Thanjavur • Verified Farmer',
      ),
      body: RefreshIndicator(
        color: AppTheme.primaryGreen,
        onRefresh: _loadDashboardData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DemoModeBanner(),
              if (!session.isDemoMode) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FarmerApplicationScreen())),
                icon: const Icon(Icons.assignment), label: const Text('Complete farmer application / Check approval'))),

              // Error notification banner if backend failed
              if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.errorRed.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off, color: AppTheme.errorRed, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 12, color: AppTheme.errorRed, fontWeight: FontWeight.w500),
                        ),
                      ),
                      TextButton(
                        onPressed: _loadDashboardData,
                        child: const Text('Try Again', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.errorRed)),
                      ),
                    ],
                  ),
                ),

              // Live Weather & Agro Advisory Banner
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.wb_sunny_outlined, color: AppTheme.accentGold, size: 22),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.isTamil ? 'தஞ்சாவூர் வானிலை: 29°C' : 'Thanjavur: 29°C Sunny',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              session.isTamil ? 'அறுவடைக்கு உகந்த சூழல் • ஈரப்பதம் 68%' : 'Optimal harvest weather • 68% Hum',
                              style: const TextStyle(fontSize: 11, color: Colors.white70),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'TN AGRI',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentGold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Farm Overview & Payout Summary Card
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  border: Border.all(color: AppTheme.cardBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTheme.softGreen,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.account_balance_wallet, color: AppTheme.primaryGreen, size: 18),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              session.isTamil ? 'மொத்த பட்டுவாடா (Total Payout)' : 'Total Farmer Payout',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '+14% வளர்ந்து வருகிறது',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.successGreen),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _metrics.totalPayoutDisplay,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryDarkGreen,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.goldLight,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.accentGold.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.hourglass_top, size: 12, color: AppTheme.warningOrange),
                              const SizedBox(width: 4),
                              Text(
                                '${_metrics.pendingPayoutDisplay} வங்கி நிலுவை',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.warningOrange),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: AppTheme.dividerColor),
                    const SizedBox(height: 10),

                    // Quick Mini Stats
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildMiniStat(
                          title: session.isTamil ? 'செயலில் உள்ள பயிர்' : 'Active Crops',
                          value: '${_metrics.activeProducts > 0 ? _metrics.activeProducts : 2}',
                          icon: Icons.grass,
                        ),
                        Container(height: 24, width: 1, color: AppTheme.dividerColor),
                        _buildMiniStat(
                          title: session.isTamil ? 'ஆர்டர்கள்' : 'Orders',
                          value: '${_metrics.totalOrders > 0 ? _metrics.totalOrders : 6}',
                          icon: Icons.receipt_long,
                        ),
                        Container(height: 24, width: 1, color: AppTheme.dividerColor),
                        _buildMiniStat(
                          title: session.isTamil ? 'நிலுவை ஆர்டர்' : 'Pending',
                          value: '${_metrics.pendingOrders > 0 ? _metrics.pendingOrders : 1}',
                          icon: Icons.local_shipping,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Prominent Action CTA: "Add Harvest / பயிர் சேர்"
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AddProductScreen()),
                    );
                  },
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  label: Text(
                    session.isTamil ? 'புதிய அறுவடை சேர் • Add Harvest' : 'List New Harvest',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Live Mandi Ticker
              MandiRatesTicker(
                items: _mandiPrices,
                onViewAll: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MarketPricesScreen()),
                  );
                },
              ),

              const SizedBox(height: 14),

              // Section: My Active Crops
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      session.isTamil ? 'என் செயலில் உள்ள பயிர்கள்' : 'My Active Listings',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      '${_myProducts.length} பட்டியல்கள்',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: AppTheme.primaryGreen),
                  ),
                )
              else if (_myProducts.isEmpty)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.grass, size: 40, color: AppTheme.primaryLightGreen),
                      const SizedBox(height: 10),
                      Text(
                        session.isTamil ? 'தற்போது பட்டியல்கள் இல்லை' : 'No crops listed yet',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        session.isTamil
                            ? 'உங்கள் பயிரை சேர்த்து நேரடி கொள்முதல் பெறவும்'
                            : 'Add your crop to receive direct orders from buyers',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                )
              else
                ..._myProducts.map(
                  (product) => ProduceCard.farmer(
                    farmerItem: product,
                    onAction: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${product.productName} விவரங்கள் புதுப்பிக்கப்பட்டன.'),
                          backgroundColor: AppTheme.primaryGreen,
                        ),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomNavigationBar: VayalBottomNavBar(
        currentIndex: _currentNavIndex,
        onTap: _onBottomNavTapped,
      ),
    );
  }

  Widget _buildMiniStat({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppTheme.primaryGreen),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}
