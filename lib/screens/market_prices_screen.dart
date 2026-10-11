import 'package:flutter/material.dart';
import '../models/market_price.dart';
import '../services/market_price_service.dart';
import '../utils/commerce_strings.dart';
import '../utils/language_rebuild.dart';
import '../widgets/commerce_widgets.dart';
import '../widgets/vayal_app_bar.dart';

class MarketPricesScreen extends StatefulWidget {
  final MarketPriceService? service;
  const MarketPricesScreen({super.key, this.service});
  @override
  State<MarketPricesScreen> createState() => _MarketPricesScreenState();
}

class _MarketPricesScreenState extends State<MarketPricesScreen>
    with LanguageRebuild<MarketPricesScreen> {
  late final _service = widget.service ?? MarketPriceService();
  final _commodity = TextEditingController(),
      _state = TextEditingController(text: 'Tamil Nadu'),
      _market = TextEditingController();
  MarketPriceListResponse? _data;
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commodity.dispose();
    _state.dispose();
    _market.dispose();
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await _service.fetchMarketPrices(
          commodity: _commodity.text,
          state: _state.text,
          market: _market.text,
          limit: 50);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: VayalAppBar(title: S.t('Market prices'), showBack: true),
      body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(S.t(
                'Government prices are references. Farmers set their own selling price.')),
            const SizedBox(height: 12),
            TextField(
                controller: _commodity,
                decoration: InputDecoration(labelText: S.t('Commodity'))),
            TextField(
                controller: _state,
                decoration: InputDecoration(labelText: S.t('State'))),
            TextField(
                controller: _market,
                decoration: InputDecoration(labelText: S.t('Market'))),
            FilledButton(
                onPressed: _busy ? null : _load, child: Text(S.t('Search'))),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) ErrorPanel(_error!, _load),
            if (_data != null && _error == null) ...[
              Text(S.t(_data!.isLive
                  ? 'Retrieved from official source'
                  : 'Cached official records')),
              if (_data!.records.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(24),
                    child:
                        Text(S.t('No matching official market prices found.'))),
              for (final r in _data!.records)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.commodity,
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              Text('${r.market} · ${r.district} · ${r.state}'),
                              detailLine('Minimum',
                                  '${S.money(r.minPricePaise)} / ${r.unit}'),
                              detailLine('Maximum',
                                  '${S.money(r.maxPricePaise)} / ${r.unit}'),
                              detailLine('Modal',
                                  '${S.money(r.modalPricePaise)} / ${r.unit}'),
                              detailLine('Reported date', r.arrivalDate),
                              detailLine('Retrieved at', r.retrievedAt),
                              detailLine('Source', r.source),
                              if (!_data!.isLive ||
                                  (DateTime.tryParse(r.arrivalDate ?? '')
                                          ?.isBefore(DateTime.now().subtract(
                                              const Duration(days: 1))) ??
                                      true))
                                Text(S.t('Historical official reference')),
                            ]))),
              if (_data!.records.length == 50)
                Text(S.t(
                    'First 50 matching records. Narrow the filters for a specific market.')),
            ],
          ])));
}
