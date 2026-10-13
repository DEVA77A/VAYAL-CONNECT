import '../utils/form_examples.dart';
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
  final _commodity = TextEditingController();
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
          commodity: _commodity.text, state: 'Tamil Nadu', limit: 50);
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
                'Verified market prices are references. Farmers set their own selling price.')),
            Text(S.t(
                'Tamil Nadu statewide reference price — calculated from available market observations')),
            const SizedBox(height: 12),
            TextField(
                controller: _commodity,
                decoration: InputDecoration(
                    labelText: S.t('Commodity'),
                    hintText: FormExamples.hint('product_name'),
                    hintStyle: FormExamples.style)),
            FilledButton(
                onPressed: _busy ? null : _load, child: Text(S.t('Search'))),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) ErrorPanel(_error!, _load),
            if (_data != null && _error == null) ...[
              Text(S.t(_data!.isLive
                  ? 'Retrieved verified market records'
                  : 'Cached verified records')),
              if (_data!.message != null) Text(_data!.message!),
              if (_data!.records.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(S.t('Market price unavailable'))),
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
                                  '${r.minPriceDisplay} / ${r.unit}'),
                              detailLine('Maximum',
                                  '${r.maxPriceDisplay} / ${r.unit}'),
                              detailLine('Quoted price',
                                  '${r.priceDisplay} / ${r.unit}'),
                              detailLine('Currency', r.currency),
                              detailLine('Price type', S.t(r.quoteType)),
                              if (r.verificationMethod ==
                                  'provider_reported_quote')
                                Text(S.t('Source-reported market reference')),
                              detailLine('Reported date', r.arrivalDate),
                              detailLine('Retrieved at', r.retrievedAt),
                              detailLine('Source', r.source),
                              detailLine('Trade type', r.priceType),
                              detailLine('Verification', r.verificationStatus),
                              detailLine('Variety', r.variety),
                              if (r.observationCount != null)
                                detailLine('Eligible observations',
                                    r.observationCount.toString()),
                              if (r.aggregationMethod != null)
                                detailLine('Aggregation method',
                                    S.t(r.aggregationMethod!)),
                              if (r.sourceUrl != null)
                                SelectableText(r.sourceUrl!),
                              if (r.stale) Text(S.t('Stale market reference')),
                            ]))),
              if (_data!.records.length == 50)
                Text(S.t(
                    'First 50 matching records. Search by crop for more specific results.')),
            ],
          ])));
}
