import 'package:flutter/material.dart';
import '../models/product_models.dart';
import '../services/product_service.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/demo_banner.dart';
import '../widgets/produce_card.dart';
import '../widgets/vayal_app_bar.dart';
import 'market_prices_screen.dart';
import 'orders_screen.dart';
import 'product_details_screen.dart';
import 'profile_screen.dart';

/// Buyer Marketplace & Product Discovery Screen
///
/// Implements Stitch Screen d3d8ba1466884db38886934787122590
class BuyerHomeScreen extends StatefulWidget {
  const BuyerHomeScreen({Key? key}) : super(key: key);

  @override
  State<BuyerHomeScreen> createState() => _BuyerHomeScreenState();
}

class _BuyerHomeScreenState extends State<BuyerHomeScreen> {
  final _productService = ProductService();
  final _searchController = TextEditingController();

  int _currentNavIndex = 0;
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedCategory = 'அனைத்தும்';
  List<BuyerProduct> _allProducts = [];
  List<BuyerProduct> _filteredProducts = [];

  final List<String> _categories = [
    'அனைத்தும்',
    'தானியங்கள்',
    'காய்கறிகள்',
    'பழங்கள்',
    'மசாலா',
  ];

  @override
  void initState() {
    super.initState();
    _loadProduce();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _productService.dispose();
    super.dispose();
  }

  Future<void> _loadProduce() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final items = await _productService.fetchBuyerProducts();
      if (mounted) {
        setState(() {
          _allProducts = items;
          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredProducts = _allProducts.where((p) {
        final matchesQuery = query.isEmpty ||
            p.productName.toLowerCase().contains(query) ||
            p.location.toLowerCase().contains(query) ||
            (p.farmerName != null && p.farmerName!.toLowerCase().contains(query));

        final matchesCategory = _selectedCategory == 'அனைத்தும்' ||
            p.category.toLowerCase().contains(_selectedCategory.toLowerCase());

        return matchesQuery && matchesCategory;
      }).toList();
    });
  }

  void _onBottomNavTapped(int index) {
    if (index == _currentNavIndex) return;

    switch (index) {
      case 0:
        // Already on Marketplace
        break;
      case 1:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MarketPricesScreen()),
        );
        break;
      case 2:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const OrdersScreen()),
        );
        break;
      case 3:
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
        title: session.isTamil ? 'விளைபொருட்கள் சந்தை' : 'Farm Marketplace',
        subtitle: session.isTamil ? 'நேரடி உழவர் கொள்முதல்' : 'Direct Farmer Sourcing',
      ),
      body: RefreshIndicator(
        color: AppTheme.primaryGreen,
        onRefresh: _loadProduce,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Demo Banner
              if (session.isDemoMode) const DemoModeBanner(),

              // Delivery Location Banner
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 16, color: AppTheme.primaryGreen),
                        const SizedBox(width: 4),
                        Text(
                          session.isTamil ? 'விநியோகம்: மதுரை (Madurai, TN)' : 'Deliver to: Madurai, TN',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.softGreen,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        session.isTamil ? '24 மணி நேர டெலிவரி' : '24h Delivery',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => _applyFilters(),
                  decoration: InputDecoration(
                    hintText: session.isTamil ? 'பயிர் அல்லது விவசாயி தேடுக...' : 'Search crop or farmer...',
                    prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _applyFilters();
                            },
                          )
                        : const Icon(Icons.mic, color: AppTheme.primaryGreen),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Horizontal Category Filter Pills
              SizedBox(
                height: 38,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final isSelected = _selectedCategory == cat;
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedCategory = cat;
                          _applyFilters();
                        });
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primaryGreen : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? AppTheme.primaryGreen : AppTheme.cardBorder,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // Direct Farmer Sourcing Trust Banner
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCream,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accentGold.withOpacity(0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 22, color: AppTheme.accentGold),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.isTamil
                                ? 'நேரடி உழவர் கொள்முதல் • 0% கமிஷன்'
                                : 'Direct Farm Sourcing • 0% Middleman',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            session.isTamil
                                ? 'எடைச் சீட்டு சரிபார்க்கப்பட்டு பாதுகாப்பான பணம்'
                                : 'Digital weighbridge slips with escrow protection',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Produce Listing Count
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      session.isTamil ? 'கிடைக்கும் புதிய அறுவடைகள்' : 'Available Farm Harvests',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    Text(
                      '${_filteredProducts.length} பயிர்கள்',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 6),

              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: CircularProgressIndicator(color: AppTheme.primaryGreen),
                  ),
                )
              else if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.wifi_off_rounded, color: AppTheme.errorRed, size: 36),
                      const SizedBox(height: 8),
                      Text(
                        session.isTamil ? 'இணைப்புப் பிழை ஏற்பட்டது' : 'Connection Error',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.errorRed),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _loadProduce,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: Text(session.isTamil ? 'மீண்டும் முயற்சிக்கவும்' : 'Retry'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen),
                      ),
                    ],
                  ),
                )
              else if (_filteredProducts.isEmpty)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Icons.search_off, size: 40, color: AppTheme.textSecondary),
                        const SizedBox(height: 8),
                        Text(
                          session.isTamil ? 'பயிர்கள் எதுவும் கிடைக்கவில்லை' : 'No harvests found',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ..._filteredProducts.map(
                  (product) => ProduceCard.buyer(
                    buyerItem: product,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProductDetailsScreen(product: product),
                        ),
                      );
                    },
                    onAction: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProductDetailsScreen(product: product),
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
}
