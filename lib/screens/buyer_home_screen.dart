import '../widgets/marketplace_product_card.dart';
import '../widgets/brand_widgets.dart';
import '../utils/language_rebuild.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/product_models.dart';
import '../services/api_client.dart';
import '../services/session_manager.dart';
import '../utils/commerce_strings.dart';
import '../widgets/commerce_widgets.dart';
import '../widgets/vayal_app_bar.dart';
import 'addresses_screen.dart';
import 'market_prices_screen.dart';
import 'orders_screen.dart';
import 'product_details_screen.dart';
import 'profile_screen.dart';

class BuyerHomeScreen extends StatefulWidget {
  final ApiClient? api;
  const BuyerHomeScreen({super.key, this.api});
  @override
  State<BuyerHomeScreen> createState() => _BuyerHomeScreenState();
}

class _BuyerHomeScreenState extends State<BuyerHomeScreen>
    with LanguageRebuild<BuyerHomeScreen> {
  late final _api = widget.api ?? ApiClient();
  final _search = TextEditingController();
  Timer? _debounce;
  int _generation = 0, _page = 1, _total = 0;
  bool _busy = true;
  String? _error;
  String _category = '', _sort = 'newest';
  final _items = <BuyerProduct>[];
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = more ? _page + 1 : 1;
      final query = Uri(queryParameters: {
        'page': '$page',
        'limit': '20',
        'sort': _sort,
        if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
        if (_category.isNotEmpty) 'category': _category
      }).query;
      final data = await _api.request('/api/v1/products/?$query');
      if (!mounted || generation != _generation) return;
      setState(() {
        if (!more) _items.clear();
        _items.addAll((data['items'] as List)
            .map((p) => BuyerProduct.fromJson(Map<String, dynamic>.from(p))));
        _page = page;
        _total = data['total'] as int;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: VayalAppBar(title: S.t('Marketplace')),
      body: PageBody(
          maxWidth: 1120,
          child: RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                        padding: const EdgeInsets.all(16),
                        sliver: SliverToBoxAdapter(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                              BrandHeading(
                                  title:
                                      '${S.t('Welcome')}, ${SessionManager().currentUser?.name ?? ''}',
                                  icon: Icons.storefront_outlined),
                              Wrap(spacing: 8, children: [
                                ActionChip(
                                    label: Text(S.t('Orders')),
                                    avatar: const Icon(Icons.receipt_long),
                                    onPressed: () =>
                                        _open(const OrdersScreen())),
                                ActionChip(
                                    label: Text(S.t('Addresses')),
                                    avatar:
                                        const Icon(Icons.location_on_outlined),
                                    onPressed: () =>
                                        _open(const AddressesScreen())),
                                ActionChip(
                                    label: Text(S.t('Market prices')),
                                    onPressed: () =>
                                        _open(const MarketPricesScreen())),
                                ActionChip(
                                    label: Text(S.t('Profile')),
                                    onPressed: () =>
                                        _open(const ProfileScreen())),
                              ]),
                              const SizedBox(height: 16),
                              TextField(
                                  controller: _search,
                                  decoration: InputDecoration(
                                      labelText: S.t('Search crops'),
                                      prefixIcon: const Icon(Icons.search)),
                                  onChanged: (_) {
                                    _debounce?.cancel();
                                    _debounce = Timer(
                                        const Duration(milliseconds: 400),
                                        () => _load());
                                  }),
                              const SizedBox(height: 12),
                              ResponsivePair(
                                  first: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                          labelText: S.t('Category')),
                                      value: _category,
                                      items: [
                                        '',
                                        'Grains',
                                        'Vegetables',
                                        'Fruits',
                                        'Spices'
                                      ]
                                          .map((v) => DropdownMenuItem(
                                              value: v,
                                              child: Text(S.t(v.isEmpty
                                                  ? 'All crops'
                                                  : v))))
                                          .toList(),
                                      onChanged: (v) {
                                        setState(() => _category = v!);
                                        _load();
                                      }),
                                  second: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                          labelText: S.t('Price')),
                                      value: _sort,
                                      items: {
                                        'newest': 'Newest',
                                        'price_asc': 'Price: low to high',
                                        'price_desc': 'Price: high to low'
                                      }
                                          .entries
                                          .map((e) => DropdownMenuItem(
                                              value: e.key,
                                              child: Text(S.t(e.value),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis)))
                                          .toList(),
                                      onChanged: (v) {
                                        setState(() => _sort = v!);
                                        _load();
                                      })),
                              const SizedBox(height: 20),
                              if (_busy) const LinearProgressIndicator(),
                              if (_error != null)
                                ErrorPanel(_error!, () => _load()),
                              if (!_busy && _error == null && _items.isEmpty)
                                const EmptyPanel(
                                    'No available crops match your search.'),
                            ]))),
                    SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverLayoutBuilder(
                            builder: (context, constraints) {
                          final largeText =
                              MediaQuery.textScalerOf(context).scale(14) > 21;
                          final columns = largeText
                              ? 1
                              : constraints.crossAxisExtent >= 1000
                                  ? 3
                                  : constraints.crossAxisExtent >= 640
                                      ? 2
                                      : 1;
                          return SliverList(
                              delegate: SliverChildBuilderDelegate(
                                  (context, row) => Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            for (var col = 0;
                                                col < columns;
                                                col++) ...[
                                              if (col > 0)
                                                const SizedBox(width: 16),
                                              Expanded(
                                                  child: row * columns + col <
                                                          _items.length
                                                      ? MarketplaceProductCard(
                                                          key: ValueKey(
                                                              _items[row * columns + col]
                                                                  .productId),
                                                          product: _items[
                                                              row * columns +
                                                                  col],
                                                          onTap: () => _open(
                                                              ProductDetailsScreen(
                                                                  product: _items[
                                                                      row * columns +
                                                                          col])))
                                                      : const SizedBox()),
                                            ]
                                          ]),
                                  childCount:
                                      (_items.length / columns).ceil()));
                        })),
                    SliverPadding(
                        padding: const EdgeInsets.all(16),
                        sliver: SliverToBoxAdapter(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                              if (_items.length < _total)
                                OutlinedButton(
                                    onPressed:
                                        _busy ? null : () => _load(more: true),
                                    child: Text(S.t('Load more'))),
                            ]))),
                  ]))));
}
