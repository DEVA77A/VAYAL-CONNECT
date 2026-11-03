import 'package:flutter/material.dart';
import '../models/auth_models.dart';
import '../models/market_price.dart';
import '../services/market_price_service.dart';
import '../services/session_manager.dart';
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
  final _searchFocus = FocusNode();

  MarketPriceListResponse? _data;
  MarketPriceSearchResult? _searchResult;
  List<String> _allCropSuggestions = _kDefaultCrops;
  List<String> _suggestions = _kDefaultCrops;
  bool _busy = true;
  String? _error;
  int _request = 0;

  AppRole get _role => SessionManager().activeRole;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commodity.dispose();
    _searchFocus.dispose();
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _suggestions = _allCropSuggestions.take(8).toList();
      } else {
        _suggestions = _allCropSuggestions
            .where((c) => c.toLowerCase().contains(q))
            .take(8)
            .toList();
      }
    });
  }

  void _selectSuggestion(String crop) {
    _commodity.text = crop;
    _commodity.selection =
        TextSelection.fromPosition(TextPosition(offset: crop.length));
    _onQueryChanged(crop);
    _load();
  }

  void _clearSearch() {
    _commodity.clear();
    _onQueryChanged('');
    setState(() {
      _searchResult = null;
    });
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
    });

    final queryText = _commodity.text.trim();

    try {
      if (queryText.isNotEmpty) {
        // Use dedicated unified search endpoint
        final searchRes = await _service.searchMarketPrices(
          queryText,
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
      } else {
        // Browse default statewide market cache
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
            onRefresh: _load,
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
                  S.t('Tamil Nadu Uzhavar Santhai market observations'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 12),
                _buildSearchBar(context),
                const SizedBox(height: 16),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  ErrorPanel(_error!, _load),
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

  Widget _buildSearchBar(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            onChanged: _onQueryChanged,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded,
                  color: AppTheme.primaryDarkGreen),
              suffixIcon: _commodity.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded,
                          color: AppTheme.textSecondary),
                      onPressed: _clearSearch,
                      tooltip: S.t('Clear'),
                    )
                  : null,
              hintText:
                  S.t('Search crop in English or Tamil (e.g. Tomato, தக்காளி)'),
              hintStyle:
                  const TextStyle(color: AppTheme.textMuted, fontSize: 13),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final crop = _suggestions[index];
                final isSelected =
                    _commodity.text.trim().toLowerCase() == crop.toLowerCase();
                return ActionChip(
                  label: Text(crop),
                  labelStyle: TextStyle(
                    fontSize: 12,
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
                      borderRadius: BorderRadius.circular(20)),
                  onPressed: () => _selectSuggestion(crop),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.search_rounded, size: 18),
          label: Text(S.t('Search')),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryGreen,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsContent(BuildContext context) {
    if (_data == null) return const SizedBox.shrink();

    // If searching and we have a best price
    if (_searchResult != null) {
      if (!_searchResult!.found || _searchResult!.bestPrice == null) {
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
                    'No verified price is available for this crop and selection. Enter your own selling price.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _busy ? null : _load,
                child: Text(S.t('Retry')),
              ),
            ],
          ),
        );
      }

      final best = _searchResult!.bestPrice!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            S.t(best.isFresh
                ? 'Retrieved verified market records'
                : 'Cached verified records'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          _buildHeroResultCard(context, best),
          _buildSecondaryObservations(context, _searchResult!.records),
        ],
      );
    }

    // Default browse mode
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
                  onPressed: _busy ? null : _load,
                  child: Text(S.t('Retry')),
                ),
              ],
            ),
          ),
        for (final r in _data!.records) _buildHeroResultCard(context, r),
        if (_data!.records.length >= 50)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              S.t('First 50 matching records. Search by crop for more specific results.'),
              style:
                  const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
      ],
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
          // Title Row: Commodity Name and Fresh/Cached Status Pill
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.commodity,
                      style:
                          Theme.of(context).textTheme.titleLarge?.copyWith(
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

          // Light-green Price Highlight Banner
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
                if (item.minPriceDisplay != 'Unavailable' &&
                    item.maxPriceDisplay != 'Unavailable' &&
                    item.minPriceDisplay != item.maxPriceDisplay) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${S.t('Range')}: ${item.minPriceDisplay} – ${item.maxPriceDisplay}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.primaryDarkGreen,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Mandi observations details
          detailLine('Market', item.market),
          detailLine('District', item.district),
          detailLine('State', item.state),
          detailLine('Source', item.source),
          detailLine('Reported date', item.arrivalDate ?? '—'),
          detailLine('Trade type', S.t(item.priceType)),

          // Role Perspective Banner
          const SizedBox(height: 10),
          _buildRolePerspective(context, item),
        ],
      ),
    );
  }

  Widget _buildRolePerspective(BuildContext context, MarketPriceItem item) {
    final role = _role;
    if (role == AppRole.admin) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.warmCreamSecondary.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.admin_panel_settings_outlined,
                    size: 16, color: AppTheme.earthBrown),
                const SizedBox(width: 6),
                Text(
                  S.t('Verification & Discovery Details'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.darkBrown,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            detailLine('Verification status', item.verificationStatus),
            if (item.verificationMethod.isNotEmpty)
              detailLine('Verification method', S.t(item.verificationMethod)),
            detailLine('Quote type', S.t(item.quoteType)),
            if (item.observationCount != null)
              detailLine(
                  'Eligible observations', item.observationCount.toString()),
            if (item.aggregationMethod != null)
              detailLine('Aggregation method', S.t(item.aggregationMethod!)),
            if (item.sourceUrl != null && item.sourceUrl!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '${S.t('Source URL')}:',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary),
              ),
              SelectableText(
                item.sourceUrl!,
                style: const TextStyle(fontSize: 12, color: AppTheme.infoBlue),
              ),
            ],
          ],
        ),
      );
    } else if (role == AppRole.farmer) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.lightGreenDashboard.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: AppTheme.primaryLightGreen.withOpacity(0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lightbulb_outline_rounded,
                size: 20, color: AppTheme.primaryGreen),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                S.t('Selling price guidance: Verified mandi rates serve as an official baseline. Farmers have full freedom to set their own listing prices based on harvest quality.'),
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
    } else {
      // Buyer perspective
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCream,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 20, color: AppTheme.earthBrown),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                S.t('Fair reference price: Reflects official mandi transactions in ${item.district}. Direct farm orders avoid wholesale middleman costs.'),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }
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
