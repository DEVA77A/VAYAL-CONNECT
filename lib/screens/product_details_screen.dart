import 'package:flutter/material.dart';
import '../models/product_models.dart';
import '../models/order_models.dart';
import '../services/order_service.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import 'orders_screen.dart';

/// Product Details & Order Checkout Screen
///
/// Implements Stitch Screen 2d547dab47594885bdb82ee3a63ff7f4
class ProductDetailsScreen extends StatefulWidget {
  final BuyerProduct product;
  final OrderService? orderService;

  const ProductDetailsScreen({
    Key? key,
    required this.product,
    this.orderService,
  }) : super(key: key);

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  late final _orderService = widget.orderService ?? OrderService();
  int _selectedQuantity = 1;
  String _fulfillment = 'PICKUP';
  final _deliveryForm = GlobalKey<FormState>();
  final _addressFields = {'recipient_name': TextEditingController(), 'phone': TextEditingController(), 'address': TextEditingController(), 'postal_code': TextEditingController()};
  bool _isOrdering = false;

  @override
  void dispose() {
    for (final field in _addressFields.values) { field.dispose(); }
    _orderService.dispose();
    super.dispose();
  }

  void _confirmOrder() async {
    if (_isOrdering || (_fulfillment == 'DELIVERY' && !_deliveryForm.currentState!.validate())) return;
    setState(() => _isOrdering = true);

    try {
      final order = await _orderService.createOrder(
        productId: widget.product.productId,
        quantity: _selectedQuantity,
        fulfillmentMethod: _fulfillment,
        expectedUnitPricePaise: widget.product.buyerPricePerUnitPaise,
        deliveryAddress: _fulfillment == 'DELIVERY' ? {for (final e in _addressFields.entries) e.key: e.value.text.trim()} : null,
      );

      if (!mounted) return;
      _showOrderDialog(order);
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

  void _showOrderDialog(BuyerOrder order) {
    final session = SessionManager();
    final orderNumber = order.orderNumber;

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
              session.isDemoMode ? 'Demo order preview' : 'Order recorded • Payment pending',
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
              'Status: ' + order.orderStatus + '\nPayment: ' + order.paymentStatus + '\nNo payment has been confirmed by this checkout. Gateway checkout is not yet available in the app.',
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
    final totalAmount = (_selectedQuantity * p.buyerPricePerUnitPaise / 100).toStringAsFixed(2);

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
                            'Farmer listing',
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
                            'Buyer price includes platform commission. No savings claim is guaranteed.',
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
                              p.farmerName ?? 'Farmer',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.verified, size: 14, color: AppTheme.primaryGreen),
                          ],
                        ),
                        Text(
                          p.location,
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

            Padding(padding: const EdgeInsets.all(16), child: Form(key: _deliveryForm, child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Pickup or delivery / பெறுதல் அல்லது விநியோகம்', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButtonFormField<String>(value: _fulfillment,
                  items: [const DropdownMenuItem(value: 'PICKUP', child: Text('Pickup / நேரில் பெறுதல்')),
                    if (p.deliveryAvailable) const DropdownMenuItem(value: 'DELIVERY', child: Text('Delivery / விநியோகம்'))],
                  onChanged: _isOrdering ? null : (value) => setState(() => _fulfillment = value!)),
                if (_fulfillment == 'PICKUP') Text('Pickup: ' + (p.pickupAddress ?? p.location)),
                if (!p.deliveryAvailable) const Text('This farmer offers pickup only.'),
                if (_fulfillment == 'DELIVERY') ...[
                  const Text('Delivery is included. Timing must be arranged with the farmer; no ETA is promised.'),
                  for (final field in _addressFields.entries) TextFormField(
                    controller: field.value, enabled: !_isOrdering,
                    decoration: InputDecoration(labelText: field.key.replaceAll('_', ' ')),
                    keyboardType: field.key == 'phone' || field.key == 'postal_code' ? TextInputType.number : TextInputType.streetAddress,
                    validator: (v) {
                      final value = v?.trim() ?? '';
                      if (field.key == 'phone') return RegExp(r'^[6-9][0-9]{9}$').hasMatch(value) ? null : 'Enter a valid 10-digit mobile number.';
                      if (field.key == 'postal_code') return RegExp(r'^[1-9][0-9]{5}$').hasMatch(value) ? null : 'Enter a valid 6-digit postal code.';
                      return value.length >= (field.key == 'address' ? 10 : 2) ? null : 'Complete this field.';
                    },
                  ),
                ],
              ],
            ))),

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
                        onPressed: !_isOrdering && _selectedQuantity > 1
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
                        onPressed: !_isOrdering && _selectedQuantity < p.quantityAvailable
                            ? () => setState(() => _selectedQuantity++)
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Preset Quick Chips
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [1, 5, 10, 20].where((q) => q <= p.quantityAvailable).map((q) {
                      return ChoiceChip(
                        label: Text('$q ${p.quantityUnit}'),
                        selected: _selectedQuantity == q,
                        onSelected: _isOrdering ? null : (_) => setState(() => _selectedQuantity = q),
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
              onPressed: _isOrdering || p.quantityAvailable < 1 ? null : _confirmOrder,
              icon: _isOrdering
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: Text(
                session.isTamil ? 'ஆர்டர் பதிவு செய்' : 'Create pending order',
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

}
