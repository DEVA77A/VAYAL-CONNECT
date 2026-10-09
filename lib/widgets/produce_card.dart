import 'package:flutter/material.dart';
import '../models/product_models.dart';
import '../theme/app_theme.dart';

/// Reusable Produce Card matching Stitch Design System
class ProduceCard extends StatelessWidget {
  final BuyerProduct? buyerItem;
  final FarmerProduct? farmerItem;
  final VoidCallback? onAction;
  final VoidCallback? onTap;

  const ProduceCard.buyer({
    Key? key,
    required this.buyerItem,
    this.onAction,
    this.onTap,
  })  : farmerItem = null,
        super(key: key);

  const ProduceCard.farmer({
    Key? key,
    required this.farmerItem,
    this.onAction,
    this.onTap,
  })  : buyerItem = null,
        super(key: key);

  @override
  Widget build(BuildContext context) {
    final isBuyer = buyerItem != null;
    final title = isBuyer ? buyerItem!.productName : farmerItem!.productName;
    final location = isBuyer ? buyerItem!.location : farmerItem!.location;
    final grade = isBuyer ? buyerItem!.qualityGrade : farmerItem!.qualityGrade;
    final qty = isBuyer
        ? '${buyerItem!.quantityAvailable} ${buyerItem!.quantityUnit}'
        : '${farmerItem!.quantityAvailable} ${farmerItem!.quantityUnit}';
    final priceDisplay = isBuyer
        ? buyerItem!.buyerPricePerUnitDisplay
        : farmerItem!.farmerPayoutPerUnitDisplay;
    final priceLabel = isBuyer ? 'நேரடி விலை (Price)' : 'பட்டுவாடா (Payout)';
    final harvestDate = isBuyer ? buyerItem!.harvestDate : farmerItem!.harvestDate;
    final secondaryInfo = isBuyer
        ? 'விவசாயி: ${buyerItem!.farmerName ?? "சரிபார்க்கப்பட்டது"}'
        : 'சந்தை: ${farmerItem!.market}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: BorderSide(color: AppTheme.cardBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header: Title, Category, Quality Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: AppTheme.softGreen,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.grass_rounded,
                    color: AppTheme.primaryGreen,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.backgroundLight,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              grade,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryGreen,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'கையிருப்பு: $qty',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Status Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.softGreen,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified, size: 12, color: AppTheme.primaryGreen),
                      SizedBox(width: 3),
                      Text(
                        'VERIFIED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1, color: AppTheme.dividerColor),
            const SizedBox(height: 10),

            // Metadata: Location & Secondary Info
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 15, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ),
                if (harvestDate != null) ...[
                  const Icon(Icons.event_available_outlined, size: 15, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    harvestDate,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              secondaryInfo,
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),

            const SizedBox(height: 10),

            // Bottom Bar: Price Highlight & CTA
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      priceLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      priceDisplay,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryGreen,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: onAction,
                  icon: Icon(
                    isBuyer ? Icons.shopping_cart_checkout : Icons.edit_note,
                    size: 16,
                  ),
                  label: Text(isBuyer ? 'முன்பதிவு செய் • Order' : 'திருத்து • Edit'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isBuyer ? AppTheme.primaryGreen : Colors.white,
                    foregroundColor: isBuyer ? Colors.white : AppTheme.primaryGreen,
                    side: isBuyer ? null : const BorderSide(color: AppTheme.primaryGreen),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
