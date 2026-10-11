import 'package:flutter/material.dart';
import '../utils/commerce_strings.dart';
import 'commerce_widgets.dart';

class MarketReferenceView extends StatelessWidget {
  final Map<String, dynamic>? reference;
  final int? sellingPricePaise;
  const MarketReferenceView(
      {super.key, this.reference, this.sellingPricePaise});
  @override
  Widget build(BuildContext context) {
    final r = reference;
    if (r == null ||
        r['reference_price_available'] == false ||
        (r['government_reference_price_paise'] as num? ?? 0) <= 0) {
      return Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(S.t('Reference unavailable'))));
    }
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  S.t(r['reference_price_stale'] == true
                      ? 'Historical official reference'
                      : 'Official reference'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${r['reference_commodity']} • ${r['reference_market']}'),
              detailLine('Modal',
                  '${S.money(r['government_reference_price_paise'])} / ${r['reference_price_unit']}'),
              if (r['reference_price_per_listing_unit_paise'] != null)
                detailLine('Comparable reference',
                    '${S.money(r['reference_price_per_listing_unit_paise'])} / ${r['reference_listing_unit']}'),
              if (r['reference_state'] != null)
                detailLine('State', r['reference_state']),
              if (r['reference_min_paise'] != null)
                detailLine('Minimum',
                    '${S.money(r['reference_min_paise'])} / ${r['reference_price_unit']}'),
              if (r['reference_max_paise'] != null)
                detailLine('Maximum',
                    '${S.money(r['reference_max_paise'])} / ${r['reference_price_unit']}'),
              if (sellingPricePaise != null &&
                  (r['reference_price_per_listing_unit_paise'] as num? ?? 0) >
                      0)
                detailLine('Difference from comparable reference',
                    '${S.money(sellingPricePaise! - (r['reference_price_per_listing_unit_paise'] as num).toInt())} / ${r['reference_listing_unit']}'),
              detailLine('Reported date', r['reference_price_date']),
              detailLine('Retrieved at', r['reference_price_retrieved_at']),
              detailLine('Source', r['reference_price_source']),
            ])));
  }
}
