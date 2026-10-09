import 'package:flutter/material.dart';
import '../models/product_models.dart';
import '../services/order_service.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import 'orders_screen.dart';

/// Product Details & Order Checkout Screen
///
/// Implements Stitch Screen 2d547dab47594885bdb82ee3a63ff7f4
class ProductDetailsScreen extends StatefulWidget {
  final BuyerProduct product;

  const ProductDetailsScreen({
    Key? key,
    required this.product,
  }) : super(key: key);

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  final _orderService = OrderService();
  int _selectedQuantity = 5;
  bool _isOrdering = false;

  @override
  void dispose() {
    _orderService.dispose();
    super.dispose();
  }

  void _confirmOrder() async {
    setState(() => _isOrdering = true);

    try {
      final order = await _orderService.createOrder(
        productId: widget.product.productId,
        quantity: _selectedQuantity,
      );

      if (!mounted) return;
      _showSuccessDialog(order.orderNumber);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ஆர்டர் பிழை: $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isOrdering = false);
    }
  }

  void _showSuccessDialog(String orderNumber) {
    final session = SessionManager();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppTheme.softGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: AppTheme.primaryGreen, size: 48),
            ),
            const SizedBox(height: 16),
            Text(
              session.isTamil ? 'ஆர்டர் வெற்றிகரமாக பதிவு செய்யப்பட்டது!' : 'Order Placed Successfully!',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'ஆர்டர் எண்: $orderNumber',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(
              session.isTamil
                  ? 'விவசாயிக்கு தகவல் அனுப்பப்பட்டது. எஸ்க்ரோ கட்டணம் பாதுகாப்பானது.'
                  : 'Farmer notified. Payment held securely in escrow until delivery inspection.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const OrdersScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              minimumSize: const Size(double.infinity, 44),
            ),
            child: Text(session.isTamil ? 'என் ஆர்டர்களைப் பார்' : 'View My Orders'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionManager();
    final p = widget.product;
    final totalAmount = (_selectedQuantity * (p.buyerPricePerUnitPaise / 100)).toInt();

    return Scaffold(
      backgroundColor: AppTheme.backgroundWarm,
      appBar: AppBar(
        title: Text(session.isTamil ? 'பயிர் விவரம்' : 'Crop Details'),
        backgroundColor: AppTheme.primaryGreen,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('பயிர் விவர இணைப்பு பகிரப்பட்டது.')),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Crop Visual Showcase
            Container(
              height: 180,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.grass_rounded, size: 64, color: AppTheme.accentGold),
                        const SizedBox(height: 8),
                        Text(
                          p.productName,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          p.qualityGrade,
                          style: const TextStyle(fontSize: 13, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified, size: 14, color: AppTheme.primaryGreen),
                          SizedBox(width: 4),
                          Text(
                            'APMC VERIFIED',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Wholesale Price Card & APMC Benchmark Comparison
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.isTamil ? 'நேரடி மொத்த கொள்முதல் விலை' : 'Direct Wholesale Price',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p.buyerPricePerUnitDisplay,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryGreen,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.softGreen,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'கையிருப்பு: ${p.quantityAvailable} ${p.quantityUnit}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Benchmark Comparison Banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceCream,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.accentGold.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.trending_down, size: 16, color: AppTheme.successGreen),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            session.isTamil
                                ? 'சந்தை விலையை விட இடைத்தரகர் கட்டணம் இன்றி சேமிப்பு'
                                : 'Direct from farm savings with zero middleman fee',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primaryDarkGreen),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Verified Farmer Profile Card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppTheme.softGreen,
                    radius: 22,
                    child: const Icon(Icons.person, color: AppTheme.primaryGreen),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              p.farmerName ?? 'முருகன் கே.',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.verified, size: 14, color: AppTheme.primaryGreen),
                          ],
                        ),
                        Text(
                          '${p.location} • ★ 4.9 (128 மதிப்பீடுகள்)',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.phone_in_talk, color: AppTheme.primaryGreen, size: 20),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('விவசாயி அழைப்பு: ${p.farmerName}')),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Quality & Lab Certification Badges
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                session.isTamil ? 'தர உத்தரவாதம் மற்றும் ஆய்வறிக்கை' : 'Quality Assurance & Lab Reports',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
            ),
            const SizedBox(height: 8),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildQualityChip('ஈரப்பதம் <12% (Moisture Safe)'),
                  _buildQualityChip('வேதியியல் சாயம் இல்லை'),
                  _buildQualityChip('100% பூச்சி தாக்குதல் அற்றது'),
                  _buildQualityChip('APMC சான்றிதழ் எண்: TN-8842'),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Wholesale Quantity Selector
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.isTamil ? 'கொள்முதல் அளவு தேர்வு (Quantity)' : 'Select Quantity',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.outlined(
                        icon: const Icon(Icons.remove),
                        onPressed: _selectedQuantity > 1
                            ? () => setState(() => _selectedQuantity--)
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '$_selectedQuantity ${p.quantityUnit}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                      ),
                      const SizedBox(width: 16),
                      IconButton.outlined(
                        icon: const Icon(Icons.add),
                        onPressed: _selectedQuantity < p.quantityAvailable
                            ? () => setState(() => _selectedQuantity++)
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Preset Quick Chips
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [1, 5, 10, 20].map((q) {
                      return ChoiceChip(
                        label: Text('$q ${p.quantityUnit}'),
                        selected: _selectedQuantity == q,
                        onSelected: (_) => setState(() => _selectedQuantity = q),
                        selectedColor: AppTheme.softGreen,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      // Sticky Bottom Order Bar
      bottomSheet: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.cardBorder)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.isTamil ? 'மொத்த மதிப்பு ($_selectedQuantity ${p.quantityUnit})' : 'Total Amount',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
                Text(
                  '₹${totalAmount.toString()}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                ),
              ],
            ),
            ElevatedButton.icon(
              onPressed: _isOrdering ? null : _confirmOrder,
              icon: _isOrdering
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: Text(
                session.isTamil ? 'முன்பதிவு செய் • Confirm Order' : 'Confirm Order',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primaryLightGreen.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check, size: 14, color: AppTheme.primaryGreen),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primaryDarkGreen),
          ),
        ],
      ),
    );
  }
}
