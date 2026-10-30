import '../utils/presentation_format.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_widgets.dart';
import '../utils/form_examples.dart';
import '../utils/language_rebuild.dart';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/session_manager.dart';
import '../models/auth_models.dart';
import '../utils/commerce_strings.dart';
import '../widgets/commerce_widgets.dart';
import '../widgets/vayal_app_bar.dart';
import 'payment_screen.dart';

class OrdersScreen extends StatefulWidget {
  final ApiClient? api;
  final String initialStatus;
  const OrdersScreen({super.key, this.api, this.initialStatus = ''});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with LanguageRebuild<OrdersScreen> {
  late String _status = widget.initialStatus;
  String _period = '';
  @override
  Widget build(BuildContext context) {
    final query = Uri(queryParameters: {
      if (_status.isNotEmpty) 'status': _status,
      if (_period.isNotEmpty) 'period': _period
    }).query;
    return Scaffold(
        appBar: VayalAppBar(title: S.t('Orders'), showBack: true),
        body: PageBody(
            child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                        isExpanded: true,
                        decoration: InputDecoration(labelText: S.t('Status')),
                        value: _status,
                        items: [
                          '',
                          'PENDING',
                          'PENDING_PAYMENT',
                          'PAID',
                          'CONFIRMED',
                          'PROCESSING',
                          'SHIPPED',
                          'COMPLETED',
                          'CANCELLED'
                        ]
                            .map((v) => DropdownMenuItem(
                                value: v,
                                child: Text(v.isEmpty
                                    ? S.t('All statuses')
                                    : (v == 'PENDING' ? S.t('Pending orders') : S.status(v)))))
                            .toList(),
                        onChanged: (v) => setState(() => _status = v!)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                        isExpanded: true,
                        decoration:
                            InputDecoration(labelText: S.t('All dates')),
                        value: _period,
                        items: {
                          '': 'All dates',
                          'today': 'Day',
                          'month': 'Month',
                          'year': 'Year'
                        }
                            .entries
                            .map((e) => DropdownMenuItem(
                                value: e.key, child: Text(S.t(e.value))))
                            .toList(),
                        onChanged: (v) => setState(() => _period = v!)),
                  ])),
          Expanded(
              child: RecordPage(
                  key: ValueKey(query),
                  title: 'Orders',
                  embedded: true,
                  api: widget.api,
                  path: '/api/v1/orders/?$query',
                  itemBuilder: (ctx, o, reload) => OrderRecordCard(
                      order: o,
                      onTap: () async {
                        await Navigator.push(
                            ctx,
                            MaterialPageRoute(
                                builder: (_) => OrderDetailScreen(
                                    orderId: o['order_id'], api: widget.api)));
                        reload();
                      }))),
        ])));
  }
}

class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  final ApiClient? api;
  const OrderDetailScreen({super.key, required this.orderId, this.api});
  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen>
    with LanguageRebuild<OrderDetailScreen> {
  late final _api = widget.api ?? ApiClient();
  Map<String, dynamic>? _order;
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final o = await _api.request('/api/v1/orders/${widget.orderId}');
      if (mounted) setState(() => _order = Map<String, dynamic>.from(o));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _transition(String next) async {
    setState(() => _busy = true);
    try {
      await _api.request('/api/v1/orders/${widget.orderId}/status',
          method: 'PUT', body: {'order_status': next});
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(S.t('Cancel unpaid order')),
                content: TextField(
                    controller: controller,
                    maxLength: 500,
                    decoration: InputDecoration(
                        labelText: S.t('Cancellation reason'),
                        hintText: FormExamples.hint('cancellation'),
                        hintStyle: FormExamples.style)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(S.t('Close'))),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(S.t('Cancel')))
                ]));
    if (confirmed != true) {
      controller.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      await _api.request('/api/v1/orders/${widget.orderId}/cancel',
          method: 'PUT', body: {'reason': controller.text.trim()});
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      controller.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    final buyer = SessionManager().activeRole == AppRole.buyer;
    final status = o?['order_status'];
    return Scaffold(
        appBar: VayalAppBar(title: S.t('Order details'), showBack: true),
        body: PageBody(
            child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_busy) const LinearProgressIndicator(),
                      if (_error != null) ErrorPanel(_error!, _load),
                      if (o != null) ...[
                        SectionCard(
                            title: 'Order summary',
                            icon: Icons.receipt_long_outlined,
                            children: [
                              CropSummary(
                                  name: S.crop(o['product_name'] ?? ''),
                                  imageUrl: o['image_url'] as String?),
                              const SizedBox(height: 12),
                              InfoRow('Order ID',
                                  o['order_number'] ?? widget.orderId),
                              InfoRow('Quantity',
                                  '${o['quantity'] ?? '—'} ${S.t(o['unit'] ?? '')}'),
                              if (o['created_at'] != null)
                                InfoRow('Order date',
                                    displayDate(context, o['created_at'])),
                              if (status == 'PENDING_PAYMENT' &&
                                  o['reservation_expires_at'] != null)
                                InfoRow(
                                    'Stock reserved until',
                                    displayDate(
                                        context, o['reservation_expires_at'])),
                              const Divider(),
                              Text(S.t('Order status'),
                                  style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 8),
                              Align(
                                  alignment: Alignment.centerLeft,
                                  child: StatusPill(status ?? 'PENDING')),
                              const SizedBox(height: 16),
                              Text(S.t('Payment status'),
                                  style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 8),
                              Align(
                                  alignment: Alignment.centerLeft,
                                  child: StatusPill(
                                      o['payment_status'] ?? 'PENDING')),
                              if (o['payout_status'] != null) ...[
                                const SizedBox(height: 16),
                                Text(S.t('Payouts'),
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                                const SizedBox(height: 8),
                                Align(
                                    alignment: Alignment.centerLeft,
                                    child: StatusPill(o['payout_status'])),
                              ],
                              if (o['buyer_name'] != null)
                                InfoRow('Buyers', o['buyer_name']),
                              if (o['farmer_name'] != null)
                                InfoRow('Farmer', o['farmer_name']),
                            ]),
                        SectionCard(
                            title: 'Payment breakdown',
                            icon: Icons.payments_outlined,
                            children: [
                              if (!buyer &&
                                  (o['farmer_base_total_paise'] is num ||
                                      o['farmer_total_payout_paise'] is num))
                                InfoRow(
                                    'Farmer earnings',
                                    S.money(o['farmer_base_total_paise'] ??
                                        o['farmer_total_payout_paise'])),
                              if (SessionManager().activeRole == AppRole.admin &&
                                  o['commission_total_paise'] is num)
                                InfoRow('Platform commission',
                                    S.money(o['commission_total_paise'])),
                              if (o['delivery_fee_paise'] is num)
                                InfoRow('Delivery charge',
                                    S.money(o['delivery_fee_paise'])),
                              if (SessionManager().activeRole !=
                                      AppRole.farmer &&
                                  (o['buyer_total_paise'] is num ||
                                      o['buyer_total_display'] != null)) ...[
                                const Divider(),
                                InfoRow(
                                    'Buyer total',
                                    o['buyer_total_display'] ??
                                        S.money(o['buyer_total_paise']),
                                    emphasize: true),
                              ],
                              if (SessionManager().activeRole == AppRole.admin) ...[
                                const SizedBox(height: 12),
                                Text(
                                    S.t('Farmer receives the full base price. Commission is added for buyers.'),
                                    style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ]),
                        SectionCard(
                            title: 'Delivery information',
                            icon: Icons.local_shipping_outlined,
                            children: [
                              InfoRow('Delivery',
                                  S.status(o['fulfillment_method'] ?? '')),
                              if (o['pickup_address'] != null)
                                InfoRow('Pickup address', o['pickup_address']),
                              if (o['delivery_address'] is Map) ...[
                                if (o['delivery_address']['recipient_name'] !=
                                    null)
                                  InfoRow('Recipient name',
                                      o['delivery_address']['recipient_name']),
                                if (o['delivery_address']['phone'] != null)
                                  InfoRow('Contact number',
                                      o['delivery_address']['phone']),
                                InfoRow(
                                    'Address',
                                    [
                                      o['delivery_address']['address'],
                                      o['delivery_address']['postal_code']
                                    ]
                                        .where((v) =>
                                            v != null &&
                                            v.toString().trim().isNotEmpty)
                                        .join(', ')),
                              ],
                              if (o['delivery_estimate']?['available'] ==
                                  true) ...[
                                InfoRow('Straight-line distance',
                                    '${o['delivery_estimate']['distance_km']} km'),
                                InfoRow('Estimated arrival window',
                                    '${o['delivery_estimate']['arrival_from']} – ${o['delivery_estimate']['arrival_to']}'),
                                Text(
                                    S.t(
                                        'Farmer confirmation required. Road distance and exact arrival are unavailable.'),
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ],
                              if (o['cancellation_reason'] != null)
                                InfoRow('Cancellation reason',
                                    o['cancellation_reason']),
                            ]),
                        if (buyer && status == 'PENDING_PAYMENT')
                          ElevatedButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (_) => PaymentScreen(
                                                  orderId: widget.orderId)));
                                      if (mounted) _load();
                                    },
                              child: Text(S.t('Pay in test mode'))),
                        if (status == 'PENDING_PAYMENT')
                          OutlinedButton(
                              onPressed: _busy ? null : _cancel,
                              child: Text(S.t('Cancel unpaid order'))),
                        if (!buyer && status == 'PAID')
                          ElevatedButton(
                              onPressed:
                                  _busy ? null : () => _transition('CONFIRMED'),
                              child: Text(S.t('Accept order'))),
                        if (!buyer && status == 'CONFIRMED')
                          ElevatedButton(
                              onPressed: _busy
                                  ? null
                                  : () => _transition('PROCESSING'),
                              child: Text(S.t('Start preparing'))),
                        if (!buyer &&
                            status == 'PROCESSING' &&
                            o['fulfillment_method'] == 'DELIVERY')
                          ElevatedButton(
                              onPressed:
                                  _busy ? null : () => _transition('SHIPPED'),
                              child: Text(S.t('Mark shipped'))),
                        if (!buyer &&
                            (status == 'SHIPPED' ||
                                status == 'PROCESSING' &&
                                    o['fulfillment_method'] == 'PICKUP'))
                          ElevatedButton(
                              onPressed:
                                  _busy ? null : () => _transition('COMPLETED'),
                              child: Text(S.t('Complete order'))),
                      ],
                    ]))));
  }
}

/// Uses only the order snapshot. Old orders do not need a product lookup.
class OrderRecordCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onTap;
  const OrderRecordCard({super.key, required this.order, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final o = order;
    final amount = SessionManager().activeRole == AppRole.farmer
        ? o['farmer_total_payout_display'] ??
            (o['farmer_total_payout_paise'] is num
                ? S.money(o['farmer_total_payout_paise'])
                : null)
        : o['buyer_total_display'] ??
            (o['buyer_total_paise'] is num
                ? S.money(o['buyer_total_paise'])
                : null);
    return Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                    width: 64,
                                    height: 64,
                                    child: CropImage(o['image_url'] as String?,
                                        semanticLabel:
                                            S.crop(o['product_name'] as String?)))),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(S.crop(o['product_name'] ?? ''),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 4),
                                  Text(o['order_number'] ?? '',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                  const SizedBox(height: 4),
                                  Text(
                                      '${o['quantity'] ?? '—'} ${S.t(o['unit'] ?? '')}'),
                                ])),
                            const Icon(Icons.chevron_right,
                                color: AppTheme.earthBrown, size: 20),
                          ]),
                      const SizedBox(height: 16),
                      Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(S.t('Order status'),
                                style: Theme.of(context).textTheme.bodySmall),
                            StatusPill(o['order_status'] ?? 'PENDING'),
                          ]),
                      const SizedBox(height: 8),
                      Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(S.t('Payment status'),
                                style: Theme.of(context).textTheme.bodySmall),
                            StatusPill(o['payment_status'] ?? 'PENDING'),
                          ]),
                      if (amount != null || o['created_at'] != null) ...[
                        const Divider(),
                        if (o['created_at'] != null)
                          Text(displayDate(context, o['created_at']),
                              style: Theme.of(context).textTheme.bodySmall),
                        if (amount != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(amount.toString(),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(color: AppTheme.deepGreen))),
                      ],
                    ]))));
  }
}
