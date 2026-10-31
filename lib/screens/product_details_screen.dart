import '../theme/app_theme.dart';
import '../widgets/brand_widgets.dart';
import '../utils/language_rebuild.dart';
import 'package:flutter/material.dart';
import '../models/product_models.dart';
import '../services/order_service.dart';
import '../services/api_client.dart';
import '../utils/commerce_strings.dart';
import '../widgets/commerce_widgets.dart';
import '../widgets/market_reference_view.dart';
import '../widgets/vayal_app_bar.dart';
import 'addresses_screen.dart';
import 'orders_screen.dart';
import '../models/auth_models.dart';
import '../services/session_manager.dart';

class ProductDetailsScreen extends StatefulWidget {
  final BuyerProduct product;
  final OrderService? orderService;
  final ApiClient? api;
  final Map<String, dynamic>? initialDeliveryAddress;
  const ProductDetailsScreen(
      {super.key,
      required this.product,
      this.orderService,
      this.api,
      this.initialDeliveryAddress});
  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen>
    with LanguageRebuild<ProductDetailsScreen> {
  late final _orders = widget.orderService ?? OrderService();
  late final _api = widget.api ?? ApiClient();
  int _quantity = 1;
  String _method = 'PICKUP';
  Map<String, dynamic>? _address;
  Map<String, dynamic>? _estimate;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _address = widget.initialDeliveryAddress;
  }

  @override
  void dispose() {
    if (widget.orderService == null) _orders.dispose();
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  Future<void> _selectAddress() async {
    final result = await Navigator.push<Map<String, dynamic>>(context,
        MaterialPageRoute(builder: (_) => const AddressesScreen(select: true)));
    if (result == null || !mounted) return;
    setState(() => _address = result);
    try {
      final estimate =
          await _api.request('/api/v1/orders/estimate', method: 'POST', body: {
        'product_id': widget.product.productId,
        'fulfillment_method': 'DELIVERY',
        'destination': result['coordinates']
      });
      if (mounted) {
        setState(() => _estimate = Map<String, dynamic>.from(estimate));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _order() async {
    if (_busy) return;
    if (_method == 'DELIVERY' &&
        (_address == null || _address!['coordinates'] == null)) {
      setState(
          () => _error = S.t('Coordinates required for delivery estimate.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final o = await _orders.createOrder(
          productId: widget.product.productId,
          quantity: _quantity,
          fulfillmentMethod: _method,
          expectedUnitPricePaise: widget.product.buyerPricePerUnitPaise,
          deliveryAddress: _method == 'DELIVERY' ? _address : null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('Order recorded. Payment pending.'))));
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  OrderDetailScreen(orderId: o.orderId, api: widget.api)));
    } catch (e) {
      if (mounted) {
        final errStr = e.toString();
        setState(() => _error = errStr);
        if (errStr.contains('PRICE_CHANGED') || errStr.toLowerCase().contains('price changed')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.t('Price changed. Please review the updated total before placing your order.')),
              backgroundColor: AppTheme.warningOrange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return Scaffold(
        appBar: VayalAppBar(title: S.t('Checkout'), showBack: true),
        body: PageBody(
            child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ErrorPanel(_error!, _order),
          ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                  aspectRatio: 1.6,
                  child: CropImage(p.imageUrl, semanticLabel: S.crop(p.productName)))),
          const SizedBox(height: 16),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(S.crop(p.productName),
                            style: Theme.of(context).textTheme.headlineSmall),
                        Text(p.description),
                        detailLine('Farmer', p.farmerName),
                        detailLine('Farm location', p.location),
                        detailLine('Harvest date', p.harvestDate),
                        detailLine('Available stock',
                            '${p.quantityAvailable} ${S.t(p.quantityUnit)}'),
                        const FormSection('Quantity',
                            icon: Icons.inventory_2_outlined),
                        TextFormField(
                            initialValue: '1',
                            keyboardType: TextInputType.number,
                            decoration:
                                InputDecoration(labelText: S.t('Quantity')),
                            onChanged: (value) {
                              final n = int.tryParse(value);
                              setState(() => _quantity = n ?? 0);
                            },
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            validator: (v) {
                              final n = int.tryParse(v ?? '');
                              return n == null ||
                                      n <= 0 ||
                                      n > p.quantityAvailable
                                  ? S.t('Enter a valid quantity.')
                                  : null;
                            }),
                        const FormSection('Buyer total',
                            icon: Icons.receipt_long_outlined),
                        detailLine('Product price',
                            '${S.money(p.buyerPricePerUnitPaise)} / ${S.t(p.quantityUnit)}'),
                        detailLine('Quantity',
                            '$_quantity ${S.t(p.quantityUnit)}'),
                        detailLine('Delivery charge', S.money(0)),
                        detailLine('Buyer total',
                            S.money(p.buyerPricePerUnitPaise * _quantity)),
                        if (p.marketReferencePricePaise != null)
                          detailLine('Market reference',
                              '${S.money(p.marketReferencePricePaise)} / ${S.t(p.quantityUnit)}'),
                        if (p.marketPriceDate != null && p.marketPriceDate!.isNotEmpty)
                          detailLine('Price updated', p.marketPriceDate!),
                        if (p.isMarketPriceStale)
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.sandBeige.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              S.t('Market price update unavailable. Showing the last available price.'),
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.earthBrown,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        if (SessionManager().activeRole == AppRole.admin) ...[
                          detailLine('Farmer base price',
                              '${S.money(p.farmerBasePricePaise * _quantity)} / $_quantity ${S.t(p.quantityUnit)}'),
                          detailLine('Platform commission',
                              '${S.money(p.commissionPerUnitPaise * _quantity)} (${p.commissionPercentageBps / 100}%)'),
                          Text(S.t(
                              'Buyer total = farmer base + platform commission + delivery charge.')),
                          Text(S.t(
                              'Farmer receives the full base price. Commission is added for buyers.')),
                        ],
                        const SizedBox(height: 20),
                        DropdownButtonFormField<String>(
                            isExpanded: true,
                            itemHeight: null,
                            value: _method,
                            decoration:
                                InputDecoration(labelText: S.t('Delivery')),
                            items: [
                              DropdownMenuItem(
                                  value: 'PICKUP', child: Text(S.t('Pickup'))),
                              if (p.deliveryAvailable)
                                DropdownMenuItem(
                                    value: 'DELIVERY',
                                    child: Text(S.t('Delivery')))
                            ],
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _method = v!)),
                        if (_method == 'PICKUP')
                          detailLine(
                              'Pickup address', p.pickupAddress ?? p.location),
                        if (_method == 'DELIVERY') ...[
                          OutlinedButton.icon(
                              onPressed: _busy ? null : _selectAddress,
                              icon: const Icon(Icons.location_on),
                              label: Text(S.t('Select address'))),
                          if (_address != null)
                            Text(
                                '${_address!['recipient_name']}\n${_address!['address']} ${_address!['postal_code']}'),
                          if (_estimate?['available'] == true) ...[
                            detailLine('Straight-line distance',
                                '${_estimate!['distance_km']} km'),
                            detailLine('Estimated arrival window',
                                '${_estimate!['arrival_from']} – ${_estimate!['arrival_to']}'),
                            Text(S.t(
                                'Farmer confirmation required. Road distance and exact arrival are unavailable.')),
                          ],
                        ],
                        const SizedBox(height: 16),
                        ElevatedButton(
                            onPressed: _busy ||
                                    _quantity <= 0 ||
                                    _quantity > p.quantityAvailable
                                ? null
                                : _order,
                            child: Text(S.t('Place order'))),
                      ]))),
          const SizedBox(height: 12),
          MarketReferenceView(
              reference: p.marketReference,
              sellingPricePaise: p.farmerBasePricePaise),
        ])));
  }
}
