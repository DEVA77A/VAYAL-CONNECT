import 'package:flutter/material.dart';
import '../models/market_price.dart';
import '../theme/app_theme.dart';

/// Horizontal Live APMC Mandi Rates Ticker matching Stitch Design
class MandiRatesTicker extends StatelessWidget {
  final List<MarketPriceItem> items;
  final VoidCallback? onViewAll;

  const MandiRatesTicker({
    Key? key,
    required this.items,
    this.onViewAll,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppTheme.successGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'நேரலை மண்டி நிலவரம் • Live Mandi',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              if (onViewAll != null)
                TextButton(
                  onPressed: onViewAll,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'அனைத்தும் பார் • View All',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryGreen,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 84,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: items.isNotEmpty ? items.length : 3,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (items.isEmpty) {
                // Fallback realistic APMC items for preview
                return _buildSampleCard(index);
              }
              final item = items[index];
              return _buildMandiPill(
                commodity: item.commodity,
                market: item.market,
                pricePerKg: item.pricePerKgDisplay,
                modalQuintal: '${item.modalPriceDisplay}/${item.unit}',
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSampleCard(int index) {
    final samples = [
      {'name': 'தக்காளி (Tomato)', 'mkt': 'Madurai APMC', 'kg': '₹28/kg', 'q': '₹2,800/Q'},
      {'name': 'பொன்னி நெல் (Paddy)', 'mkt': 'Thanjavur APMC', 'kg': '₹22.50/kg', 'q': '₹2,250/Q'},
      {'name': 'சின்ன வெங்காயம்', 'mkt': 'Coimbatore APMC', 'kg': '₹46/kg', 'q': '₹4,600/Q'},
    ];
    final s = samples[index % samples.length];
    return _buildMandiPill(
      commodity: s['name']!,
      market: s['mkt']!,
      pricePerKg: s['kg']!,
      modalQuintal: s['q']!,
    );
  }

  Widget _buildMandiPill({
    required String commodity,
    required String market,
    required String pricePerKg,
    required String modalQuintal,
  }) {
    return Container(
      width: 190,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCream,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  commodity,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.softGreen,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  pricePerKg,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryGreen,
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  market,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              Text(
                modalQuintal,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
