import 'package:flutter/material.dart';
import '../models/product_models.dart';
import '../theme/app_theme.dart';
import '../utils/commerce_strings.dart';
import 'brand_widgets.dart';

class MarketplaceProductCard extends StatelessWidget {
  final BuyerProduct product;
  final VoidCallback onTap;
  const MarketplaceProductCard(
      {super.key, required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AspectRatio(
                aspectRatio: 1.6,
                child: CropImage(product.imageUrl,
                    semanticLabel: S.crop(product.productName))),
            Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.crop(product.productName),
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.location_on_outlined, size: 16),
                            const SizedBox(width: 4),
                            Expanded(
                                child: Text(
                                    [product.farmerName, product.location]
                                        .whereType<String>()
                                        .where((s) => s.trim().isNotEmpty)
                                        .join(' · '),
                                    style:
                                        Theme.of(context).textTheme.bodySmall)),
                          ]),
                      const SizedBox(height: 12),
                      Text(
                          '${product.quantityAvailable} ${S.t(product.quantityUnit)}',
                          style: Theme.of(context).textTheme.bodyMedium),
                      const Divider(height: 24),
                      Row(children: [
                        Expanded(
                            child: Text(
                                '${S.money(product.buyerPricePerUnitPaise)} / ${S.t(product.quantityUnit)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(color: AppTheme.primaryGreen))),
                        const SizedBox(width: 8),
                        const DecoratedBox(
                            decoration: BoxDecoration(
                                color: AppTheme.softGreen,
                                shape: BoxShape.circle),
                            child: Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.arrow_forward_rounded,
                                    size: 20, color: AppTheme.primaryGreen))),
                      ]),
                    ])),
          ])));
}
