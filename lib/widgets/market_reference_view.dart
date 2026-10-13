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
    final amount = r?['government_reference_price_paise'];
    if (r == null ||
        (r['reference_verification_status'] != null &&
            r['reference_verification_status'] != 'verified') ||
        r['reference_price_available'] == false ||
        amount is! num ||
        !amount.isFinite ||
        amount <= 0) {
      return Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.t('Market price unavailable')),
                    if (r?['reference_price_message'] != null)
                      Text(S.t(r!['reference_price_message'] as String))
                  ])));
    }
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  S.t(r['reference_aggregation_method'] ==
                          'median_distinct_market_range_midpoint'
                      ? 'Tamil Nadu Uzhavar Santhai reference — median of available market range midpoints'
                      : r['reference_scope'] == 'statewide'
                          ? 'Tamil Nadu statewide reference price — calculated from available market observations'
                          : r['reference_verification_method'] ==
                                  'provider_reported_quote'
                              ? (r['reference_price_stale'] == true
                                  ? 'Stale market reference'
                                  : 'Source-reported market reference')
                              : r['reference_price_stale'] == true
                                  ? 'Historical verified reference'
                                  : 'Verified market reference'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${r['reference_commodity']} • ${r['reference_market']}'),
              detailLine('Quoted price',
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
              if (r['reference_scope'] == 'statewide') ...[
                detailLine(
                    'Eligible observations', r['reference_observation_count']),
                detailLine(
                    'Aggregation method',
                    S.t(r['reference_aggregation_method']?.toString() ??
                        'median_distinct_market_modal')),
                if (r['reference_price_stale'] == true)
                  Text(S.t('Stale market reference')),
              ],
              if (r['reference_currency'] != null)
                detailLine('Currency', r['reference_currency']),
              if (r['reference_quote_type'] != null)
                detailLine(
                    'Price type', S.t(r['reference_quote_type'].toString())),
              detailLine('Retrieved at', r['reference_price_retrieved_at']),
              detailLine('Source', r['reference_price_source']),
              if (r['reference_price_type'] != null)
                detailLine('Trade type', r['reference_price_type']),
              if (r['reference_verification_status'] != null)
                detailLine('Verification', r['reference_verification_status']),
              if (r['reference_source_url'] != null)
                SelectableText(r['reference_source_url'].toString()),
              if (r['reference_price_per_listing_unit_paise'] == null)
                Text(S.t(
                    'Original unit preserved. No valid conversion to your listing unit.')),
              if (r['reference_records'] is List &&
                  (r['reference_records'] as List).length > 1) ...[
                for (final record in (r['reference_records'] as List).skip(1))
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${record['commodity']} · ${record['market']} · ${record['variety'] ?? ""}'),
                          Text(
                              '${record['price_display']} / ${record['unit']} · ${record['price_type']}'),
                          Text(
                              '${record['arrival_date']} · ${record['verification_status']}'),
                          if (record['stale'] == true)
                            Text(S.t('Stale market reference')),
                          SelectableText(
                              record['source_url']?.toString() ?? ''),
                        ],
                      )),
              ],
            ])));
  }
}
