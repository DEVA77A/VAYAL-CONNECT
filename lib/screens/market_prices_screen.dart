import 'package:flutter/material.dart';
import '../models/market_price.dart';
import '../services/market_price_service.dart';
import '../theme/app_theme.dart';
import '../utils/commerce_strings.dart';
import '../utils/language_rebuild.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/commerce_widgets.dart';
import '../widgets/vayal_app_bar.dart';

const List<String> _kDefaultCrops = [
  'Tomato',
  'Onion',
  'Potato',
  'Carrot',
  'Brinjal',
  'Paddy',
  'Coconut',
  'Chilli',
  'Garlic',
  'Ginger',
  'Cabbage',
  'Drumstick',
];

const List<String> _kDefaultLocations = [
  'Mettupalayam',
  'Coimbatore',
  'Ooty',
  'Oddanchatram',
  'Madurai',
  'Salem',
  'Dharmapuri',
  'Erode',
  'Tiruchirappalli',
  'Dindigul',
  'Tirunelveli',
  'Theni',
  'Hosur',
  'Panruti',
];

class MarketPricesScreen extends StatefulWidget {
  final MarketPriceService? service;
  const MarketPricesScreen({super.key, this.service});

  @override
  State<MarketPricesScreen> createState() => _MarketPricesScreenState();
}

class _MarketPricesScreenState extends State<MarketPricesScreen>
    with LanguageRebuild<MarketPricesScreen> {
  late final _service = widget.service ?? MarketPriceService();
  final _commodity = TextEditingController();
  final _location = TextEditingController();
  final _searchFocus = FocusNode();
  final _locationFocus = FocusNode();

  MarketPriceListResponse? _data;
  MarketPriceSearchResult? _searchResult;
  List<String> _allCropSuggestions = _kDefaultCrops;
  List<String> _cropSuggestions = _kDefaultCrops;
  List<String> _locationSuggestions = _kDefaultLocations;
  bool _busy = true;
  String? _error;
  String? _locationError;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _loadBrowse();
  }

  @override
  void dispose() {
    _commodity.dispose();
    _location.dispose();
    _searchFocus.dispose();
    _locationFocus.dispose();
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  void _onCropChanged(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _cropSuggestions = _allCropSuggestions.take(8).toList();
      } else {
        _cropSuggestions = _allCropSuggestions
            .where((c) => c.toLowerCase().contains(q))
            .take(8)
            .toList();
      }
    });
  }

  void _onLocationChanged(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _locationError = null;
      if (q.isEmpty) {
        _locationSuggestions = _kDefaultLocations.take(8).toList();
      } else {
        _locationSuggestions = _kDefaultLocations
            .where((l) => l.toLowerCase().contains(q))
            .take(8)
            .toList();
      }
    });
  }

  void _selectCropSuggestion(String crop) {
    _commodity.text = crop;
    _commodity.selection =
        TextSelection.fromPosition(TextPosition(offset: crop.length));
    _onCropChanged(crop);
    if (_location.text.trim().isNotEmpty) {
      _performSearch();
    } else {
      _locationFocus.requestFocus();
    }
  }

  void _selectLocationSuggestion(String loc) {
    _location.text = loc;
    _location.selection =
        TextSelection.fromPosition(TextPosition(offset: loc.length));
    _onLocationChanged(loc);
    if (_commodity.text.trim().isNotEmpty) {
      _performSearch();
    }
  }

  void _clearSearch() {
    _commodity.clear();
    _location.clear();
    _onCropChanged('');
    _onLocationChanged('');
    setState(() {
      _locationError = null;
      _searchResult = null;
    });
    _loadBrowse();
  }

  Future<void> _loadBrowse() async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
      _locationError = null;
    });

    try {
      final d = await _service.fetchMarketPrices(
        commodity: '',
        state: 'Tamil Nadu',
        limit: 50,
      );
      if (mounted && request == _request) {
        setState(() {
          _searchResult = null;
          _data = d;
          if (d.records.isNotEmpty) {
            final newCrops =
                d.records.map((r) => r.commodity).where((c) => c.isNotEmpty);
            _allCropSuggestions = {..._kDefaultCrops, ...newCrops}.toList();
          }
        });
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(() => _error =
            S.t('Unable to load verified market prices. Please retry.'));
      }
    } finally {
      if (mounted && request == _request) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _performSearch() async {
    final cropText = _commodity.text.trim();
    final locationText = _location.text.trim();

    // 1. Validate Crop Name
    if (cropText.isEmpty) {
      setState(() {
        _error = S.t('Enter crop name.');
      });
      _searchFocus.requestFocus();
      return;
    }

    // 2. Strict Requirement: Location cannot be empty for farmer search
    if (locationText.isEmpty) {
      setState(() {
        _locationError =
            S.t('Please select or enter your farm or market location.');
        _busy = false;
      });
      _locationFocus.requestFocus();
      return;
    }

    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
      _locationError = null;
    });

    try {
      final searchRes = await _service.searchMarketPrices(
        cropText,
        location: locationText,
        state: 'Tamil Nadu',
      );
      if (mounted && request == _request) {
        setState(() {
          _searchResult = searchRes;
          _data = MarketPriceListResponse(
            records: searchRes.records,
            count: searchRes.count,
            isLive: searchRes.bestPrice?.isFresh ?? false,
            source: searchRes.bestPrice?.source ?? 'Market cache',
            message: searchRes.message,
          );
          if (searchRes.records.isNotEmpty) {
            final newCrops = searchRes.records
                .map((r) => r.commodity)
                .where((c) => c.isNotEmpty);
            _allCropSuggestions =
                {..._kDefaultCrops, ...newCrops, ...searchRes.suggestions}
                    .toList();
          }
        });
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(() => _error =
            S.t('Unable to load verified market prices. Please retry.'));
      }
    } finally {
      if (mounted && request == _request) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: VayalAppBar(title: S.t('Market prices'), showBack: true),
        body: PageBody(
          child: RefreshIndicator(
            onRefresh: () async {
              if (_commodity.text.trim().isNotEmpty &&
                  _location.text.trim().isNotEmpty) {
                await _performSearch();
              } else {
                await _loadBrowse();
              }
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                BrandHeading(
                  title: S.t('Market prices'),
                  subtitle: S.t(
                      'Verified market prices are references. Farmers set their own selling price.'),
                  icon: Icons.analytics_outlined,
                ),
                Text(
                  S.t('Tamil Nadu agricultural market observations & recommendations'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 12),
                _buildSearchForm(context),
                const SizedBox(height: 16),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  ErrorPanel(_error!, _performSearch),
                ],
                if (_error == null && !_busy) ...[
                  const SizedBox(height: 8),
                  _buildResultsContent(context),
                ],
              ],
            ),
          ),
        ),
      );

  Widget _buildSearchForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Crop Name Input
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.cardBorder, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: AppTheme.darkBrown.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: _commodity,
            focusNode: _searchFocus,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _locationFocus.requestFocus(),
            onChanged: _onCropChanged,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.eco_rounded,
                  color: AppTheme.primaryDarkGreen),
              suffixIcon: _commodity.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded,
                          color: AppTheme.textSecondary),
                      onPressed: () {
                        _commodity.clear();
                        _onCropChanged('');
                      },
                      tooltip: S.t('Clear'),
                    )
                  : null,
              hintText:
                  S.t('Crop name (e.g. Tomato, தக்காளி, Onion)'),
              hintStyle:
                  const TextStyle(color: AppTheme.textMuted, fontSize: 13),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        if (_cropSuggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _cropSuggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final crop = _cropSuggestions[index];
                final isSelected =
                    _commodity.text.trim().toLowerCase() == crop.toLowerCase();
                return ActionChip(
                  label: Text(crop),
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color:
                        isSelected ? Colors.white : AppTheme.primaryDarkGreen,
                  ),
                  backgroundColor:
                      isSelected ? AppTheme.primaryGreen : AppTheme.softGreen,
                  side: BorderSide(
                    color: isSelected
                        ? AppTheme.primaryGreen
                        : AppTheme.primaryGreen.withOpacity(0.3),
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  onPressed: () => _selectCropSuggestion(crop),
                );
              },
            ),
          ),
        ],

        const SizedBox(height: 12),

        // 2. Location Input (District, Town, or Mandi)
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _locationError != null ? Colors.red : AppTheme.cardBorder,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.darkBrown.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: _location,
            focusNode: _locationFocus,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _performSearch(),
            onChanged: _onLocationChanged,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.location_on_rounded,
                  color: AppTheme.primaryDarkGreen),
              suffixIcon: _location.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded,
                          color: AppTheme.textSecondary),
                      onPressed: () {
                        _location.clear();
                        _onLocationChanged('');
                      },
                      tooltip: S.t('Clear'),
                    )
                  : null,
              hintText: S.t('Farm / Market Location (e.g. Mettupalayam, Coimbatore)'),
              hintStyle:
                  const TextStyle(color: AppTheme.textMuted, fontSize: 13),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        if (_locationError != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              _locationError!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        if (_locationSuggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _locationSuggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final loc = _locationSuggestions[index];
                final isSelected =
                    _location.text.trim().toLowerCase() == loc.toLowerCase();
                return ActionChip(
                  label: Text(loc),
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.white : AppTheme.darkBrown,
                  ),
                  backgroundColor:
                      isSelected ? AppTheme.darkBrown : AppTheme.warmCreamSecondary,
                  side: BorderSide(
                    color: isSelected
                        ? AppTheme.darkBrown
                        : AppTheme.cardBorder,
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  onPressed: () => _selectLocationSuggestion(loc),
                );
              },
            ),
          ),
        ],

        const SizedBox(height: 14),

        // Action Buttons Row
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _performSearch,
                icon: const Icon(Icons.search_rounded, size: 18),
                label: Text(S.t('Search Market Price')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            if (_commodity.text.isNotEmpty || _location.text.isNotEmpty) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _busy ? null : _clearSearch,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(S.t('Clear')),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildResultsContent(BuildContext context) {
    if (_data == null && _searchResult == null) return const SizedBox.shrink();

    // 1. Search Result Mode (Location-specific recommendation)
    if (_searchResult != null) {
      if (!_searchResult!.found) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                S.t('Market price unavailable'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                S.t(_searchResult!.message ??
                    'No verified price is available for this crop and location. Enter your own selling price.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _busy ? null : _performSearch,
                child: Text(S.t('Retry')),
              ),
            ],
          ),
        );
      }

      final res = _searchResult!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                S.t(res.freshnessStatus == 'FRESH'
                    ? 'Retrieved verified market records'
                    : 'Preserved verified cache'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              if (res.isFallback && res.fallbackReason != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade400),
                  ),
                  child: Text(
                    res.fallbackReason == 'STATEWIDE_FALLBACK'
                        ? S.t('Statewide Reference')
                        : S.t('District Reference'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildSearchHeroCard(context, res),
          _buildSecondaryObservations(context, res.records),
        ],
      );
    }

    // 2. Default Browse Mode
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.t(_data!.isLive
              ? 'Retrieved verified market records'
              : 'Cached verified records'),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        if (_data!.message != null) ...[
          const SizedBox(height: 4),
          Text(
            S.t(_data!.message!),
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
        const SizedBox(height: 8),
        if (_data!.records.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(
                  S.t('Market price unavailable'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  S.t('No verified price is available for this crop and selection. Enter your own selling price.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _busy ? null : _loadBrowse,
                  child: Text(S.t('Retry')),
                ),
              ],
            ),
          ),
        for (final r in _data!.records) _buildHeroResultCard(context, r),
      ],
    );
  }

  Widget _buildSearchHeroCard(BuildContext context, MarketPriceSearchResult res) {
    final isFresh = res.freshnessStatus == 'FRESH';
    final refPriceDisplay = res.referencePricePerKgDisplay ??
        (res.referencePricePerKgPaise != null && res.referencePricePerKgPaise! > 0
            ? '₹${(res.referencePricePerKgPaise! / 100).toStringAsFixed(2)} / KG'
            : 'Unavailable');

    final recPriceDisplay = res.recommendedFarmerPriceDisplay ??
        (res.recommendedFarmerPricePaise != null && res.recommendedFarmerPricePaise! > 0
            ? '₹${(res.recommendedFarmerPricePaise! / 100).toStringAsFixed(2)} / KG'
            : refPriceDisplay);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCream,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.darkBrown.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title & Status
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      res.commodity,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppTheme.primaryDarkGreen,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    if (res.location != null && res.location!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              size: 14, color: AppTheme.primaryGreen),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${S.t('Farm location')}: ${res.location}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppTheme.darkBrown,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isFresh ? AppTheme.softGreen : AppTheme.sandBeige,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isFresh
                        ? AppTheme.primaryGreen.withOpacity(0.4)
                        : AppTheme.earthBrown.withOpacity(0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isFresh
                          ? Icons.check_circle_outline_rounded
                          : Icons.history_rounded,
                      size: 14,
                      color: isFresh
                          ? AppTheme.primaryDarkGreen
                          : AppTheme.darkBrown,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isFresh ? S.t('Fresh') : S.t('Cached'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isFresh
                            ? AppTheme.primaryDarkGreen
                            : AppTheme.darkBrown,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Recommended Farmer Selling Price (Hero Banner)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.t('Recommended farmer selling price'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryDarkGreen,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  recPriceDisplay,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryDarkGreen,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  S.t('Includes harvesting, sorting, packaging, transport and farmer margin.'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Market Reference Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCream,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                detailLine('Market reference', refPriceDisplay),
                detailLine('Reference market', res.market ?? 'Tamil Nadu'),
                detailLine('Reference district', res.district ?? 'Tamil Nadu'),
                detailLine('Reference date', res.sourceDate ?? '—'),
                detailLine('Source provider', res.sourceProvider ?? 'AGMARKNET'),
              ],
            ),
          ),

          const SizedBox(height: 10),
          _buildFarmerPerspectiveNote(context),
        ],
      ),
    );
  }

  Widget _buildFarmerPerspectiveNote(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.lightGreenDashboard.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryLightGreen.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline_rounded,
              size: 20, color: AppTheme.primaryGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              S.t('Verified mandi rates serve as an official baseline. Farmers have full freedom to set their own selling prices in the marketplace.'),
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.primaryDarkGreen,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroResultCard(BuildContext context, MarketPriceItem item) {
    final isFresh = item.isFresh;
    final displayPrice = item.pricePerKgDisplay != 'Unavailable'
        ? item.pricePerKgDisplay
        : (item.pricePerKgPaise > 0
            ? '₹${(item.pricePerKgPaise / 100).toStringAsFixed(2)} / KG'
            : '${item.priceDisplay} / ${item.unit}');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCream,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.darkBrown.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.commodity,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppTheme.primaryDarkGreen,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    if (item.variety.isNotEmpty &&
                        item.variety != 'Unknown') ...[
                      const SizedBox(height: 2),
                      Text(
                        '${S.t('Variety')}: ${item.variety}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isFresh ? AppTheme.softGreen : AppTheme.sandBeige,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isFresh
                        ? AppTheme.primaryGreen.withOpacity(0.4)
                        : AppTheme.earthBrown.withOpacity(0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isFresh
                          ? Icons.check_circle_outline_rounded
                          : Icons.history_rounded,
                      size: 14,
                      color: isFresh
                          ? AppTheme.primaryDarkGreen
                          : AppTheme.darkBrown,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isFresh ? S.t('Fresh') : S.t('Cached'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isFresh
                            ? AppTheme.primaryDarkGreen
                            : AppTheme.darkBrown,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.lightGreenDashboard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.t('Standardized price per KG'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryDarkGreen,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayPrice,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryDarkGreen,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          detailLine('Market', item.market),
          detailLine('District', item.district),
          detailLine('State', item.state),
          detailLine('Source', item.source),
          detailLine('Reported date', item.arrivalDate ?? '—'),
          detailLine('Trade type', S.t(item.priceType)),
        ],
      ),
    );
  }

  Widget _buildSecondaryObservations(
      BuildContext context, List<MarketPriceItem> records) {
    final secondaries =
        records.length > 1 ? records.sublist(1) : <MarketPriceItem>[];
    if (secondaries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '${S.t('Other Mandi Observations')} (${secondaries.length})',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.primaryDarkGreen,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        for (final r in secondaries)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${r.market} · ${r.district}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        r.pricePerKgDisplay != 'Unavailable'
                            ? r.pricePerKgDisplay
                            : '${r.priceDisplay} / ${r.unit}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryDarkGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${S.t('Source')}: ${r.source} · ${S.t('Reported')}: ${r.arrivalDate ?? '—'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
