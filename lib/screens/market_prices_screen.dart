import 'package:flutter/material.dart';
import '../models/market_price.dart';
import '../services/market_price_service.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/market_price_card.dart';
import '../widgets/state_views.dart';
import '../widgets/vayal_app_bar.dart';
import 'add_product_screen.dart';

/// Government Mandi Market Prices Explorer
///
/// Implements Stitch Screen 7dbcb8bf32524c758864a5bf42d9c278
class MarketPricesScreen extends StatefulWidget {
  final MarketPriceService? service;

  const MarketPricesScreen({Key? key, this.service}) : super(key: key);

  @override
  State<MarketPricesScreen> createState() => _MarketPricesScreenState();
}

class _MarketPricesScreenState extends State<MarketPricesScreen> {
  late final MarketPriceService _service;
  final _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  List<MarketPriceItem> _prices = [];
  bool _isLive = false;
  String _dataSource = 'data.gov.in AGMARKNET';
  String? _statusMessage;

  String _selectedDistrict = 'அனைத்தும்';
  String _selectedSort = 'இயல்பு';

  final List<String> _districts = [
    'அனைத்தும்',
    'Madurai',
    'Thanjavur',
    'Coimbatore',
    'Salem',
    'Tiruchirappalli',
    'Dindigul',
    'Erode',
  ];

  final List<String> _sortOptions = [
    'இயல்பு (Default)',
    'அதிக விலை (High)',
    'குறைந்த விலை (Low)',
  ];

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? MarketPriceService();
    _fetchPrices();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _fetchPrices({String? query}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final districtFilter = _selectedDistrict == 'அனைத்தும்' ? null : _selectedDistrict;
      final commodityFilter = query ?? (_searchController.text.trim().isNotEmpty ? _searchController.text.trim() : null);

      final response = await _service.fetchMarketPrices(
        commodity: commodityFilter,
        district: districtFilter,
        state: 'Tamil Nadu',
      );

      if (mounted) {
        setState(() {
          _prices = response.records;
          _isLive = response.isLive;
          _dataSource = response.source;
          _statusMessage = response.message;
          _applySorting();
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

  void _applySorting() {
    if (_sortOptions.indexOf(_selectedSort) == 1) {
      _prices.sort((a, b) => b.modalPricePaise.compareTo(a.modalPricePaise));
    } else if (_sortOptions.indexOf(_selectedSort) == 2) {
      _prices.sort((a, b) => a.modalPricePaise.compareTo(b.modalPricePaise));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionManager();

    return Scaffold(
      backgroundColor: AppTheme.backgroundWarm,
      appBar: VayalAppBar(
        showBack: true,
        title: session.isTamil ? 'மண்டி நிலவரம்' : 'Mandi Market Rates',
        subtitle: session.isTamil ? 'அரசு AGMARKNET நேரடி விலைகள்' : 'Official AGMARKNET Rates',
      ),
      body: Column(
        children: [
          // Official Attribution & Live Indicator Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _isLive ? AppTheme.softGreen : AppTheme.goldLight,
              border: Border(
                bottom: BorderSide(
                  color: _isLive ? AppTheme.cardBorder : AppTheme.accentGold.withOpacity(0.3),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _isLive ? AppTheme.successGreen : AppTheme.warningOrange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isLive
                          ? (session.isTamil ? 'நேரலை APMC விலைகள்' : 'LIVE AGMARKNET RATES')
                          : (session.isTamil ? 'சேமிக்கப்பட்ட விலைகள்' : 'Cached Mandi Rates'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _isLive ? AppTheme.primaryGreen : AppTheme.warningOrange,
                      ),
                    ),
                  ],
                ),
                Text(
                  _dataSource,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Search Input
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: TextField(
              controller: _searchController,
              onSubmitted: (val) => _fetchPrices(query: val),
              decoration: InputDecoration(
                hintText: session.isTamil
                    ? 'பயிர் அல்லது மண்டி தேடுக (எ.கா: Tomato, Paddy)...'
                    : 'Search crop or mandi (e.g. Tomato, Paddy)...',
                prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _fetchPrices();
                        },
                      )
                    : IconButton(
                        icon: const Icon(Icons.search, color: AppTheme.primaryGreen),
                        onPressed: () => _fetchPrices(),
                      ),
              ),
            ),
          ),

          // District Filter Chips
          Container(
            color: Colors.white,
            height: 42,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              scrollDirection: Axis.horizontal,
              itemCount: _districts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final d = _districts[index];
                final isSelected = _selectedDistrict == d;
                return ChoiceChip(
                  label: Text(d),
                  selected: isSelected,
                  selectedColor: AppTheme.primaryGreen,
                  backgroundColor: AppTheme.backgroundWarm,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                  ),
                  onSelected: (_) {
                    setState(() {
                      _selectedDistrict = d;
                    });
                    _fetchPrices();
                  },
                );
              },
            ),
          ),

          const Divider(height: 1, color: AppTheme.dividerColor),

          // Commodity Price Cards List
          Expanded(
            child: RefreshIndicator(
              color: AppTheme.primaryGreen,
              onRefresh: () => _fetchPrices(),
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const LoadingView(message: 'அரசு மண்டி விலை விவரங்களை ஏற்றுகிறது...');
    }

    if (_errorMessage != null) {
      return ErrorView(
        message: _errorMessage!,
        onRetry: () => _fetchPrices(),
      );
    }

    if (_prices.isEmpty) {
      return EmptyView(
        message: 'தேர்ந்தெடுக்கப்பட்ட வடிகட்டிகளுக்கு மண்டி விலைகள் கிடைக்கவில்லை.',
        onClearFilters: () {
          _searchController.clear();
          setState(() {
            _selectedDistrict = 'அனைத்தும்';
          });
          _fetchPrices();
        },
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _prices.length,
      itemBuilder: (context, index) {
        final item = _prices[index];
        return Column(
          children: [
            MarketPriceCard(item: item),
            // Quick action to sell crop directly at these rates
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AddProductScreen()),
                      );
                    },
                    icon: const Icon(Icons.add_shopping_cart, size: 14),
                    label: const Text(
                      'இந்த விலைக்கு விற்பனை செய் • Sell at this rate',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
