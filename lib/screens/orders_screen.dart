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
  const OrdersScreen({super.key, this.api});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with LanguageRebuild<OrdersScreen> {
  String _status = '', _period = '';
  @override
  Widget build(BuildContext context) {
    final query = Uri(queryParameters: {
      if (_status.isNotEmpty) 'status': _status,
      if (_period.isNotEmpty) 'period': _period
    }).query;
    return Scaffold(
        appBar: VayalAppBar(title: S.t('Orders'), showBack: true),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButton<String>(
                        isExpanded: true,
                        value: _status,
                        items: [
                          '',
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
                                    : S.status(v))))
                            .toList(),
                        onChanged: (v) => setState(() => _status = v!)),
                    DropdownButton<String>(
                        isExpanded: true,
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
                  itemBuilder: (ctx, o, reload) => Card(
                      child: ListTile(
                          leading: const Icon(Icons.receipt_long),
                          title: Text(o['product_name'] ?? ''),
                          subtitle: Text(
                              '${o['order_number']}\n${o['quantity']} ${o['unit']} · ${S.status(o['order_status'])}\n${S.t('Payment')}: ${S.status(o['payment_status'] ?? 'PENDING')}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.push(
                                ctx,
                                MaterialPageRoute(
                                    builder: (_) => OrderDetailScreen(
                                        orderId: o['order_id'],
                                        api: widget.api)));
                            reload();
                          })))),
        ]));
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
                    decoration:
                        InputDecoration(labelText: S.t('Cancellation reason'))),
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
        body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) ErrorPanel(_error!, _load),
              if (o != null)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(o['product_name'],
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall),
                              Text(o['order_number']),
                              detailLine(
                                  'Quantity', '${o['quantity']} ${o['unit']}'),
                              detailLine('Order date', o['created_at']),
                              if (status == 'PENDING_PAYMENT' &&
                                  o['reservation_expires_at'] != null)
                                detailLine('Stock reserved until',
                                    o['reservation_expires_at']),
                              detailLine('Orders', S.status(status)),
                              detailLine('Payment',
                                  S.status(o['payment_status'] ?? 'PENDING')),
                              if (o['buyer_name'] != null)
                                detailLine('Buyers', o['buyer_name']),
                              detailLine(
                                  'Farmer earnings',
                                  S.money(o['farmer_base_total_paise'] ??
                                      o['farmer_total_payout_paise'])),
                              detailLine('Platform commission',
                                  S.money(o['commission_total_paise'])),
                              detailLine('Delivery charge',
                                  S.money(o['delivery_fee_paise'])),
                              if (buyer)
                                detailLine(
                                    'Buyer total', o['buyer_total_display']),
                              Text(S.t(
                                  'Farmer receives the full base price. Commission is added for buyers.')),
                              detailLine('Delivery',
                                  S.status(o['fulfillment_method'] ?? '')),
                              if (o['pickup_address'] != null)
                                detailLine(
                                    'Pickup address', o['pickup_address']),
                              if (o['delivery_address'] != null)
                                Text(
                                    '${o['delivery_address']['recipient_name']}\n${o['delivery_address']['phone']}\n${o['delivery_address']['address']} ${o['delivery_address']['postal_code']}'),
                              if (o['delivery_estimate']?['available'] ==
                                  true) ...[
                                detailLine('Straight-line distance',
                                    '${o['delivery_estimate']['distance_km']} km'),
                                detailLine('Estimated arrival window',
                                    '${o['delivery_estimate']['arrival_from']} – ${o['delivery_estimate']['arrival_to']}'),
                                Text(S.t(
                                    'Farmer confirmation required. Road distance and exact arrival are unavailable.')),
                              ],
                              if (o['cancellation_reason'] != null)
                                detailLine('Cancellation reason',
                                    o['cancellation_reason']),
                              const SizedBox(height: 16),
                              if (buyer && status == 'PENDING_PAYMENT')
                                ElevatedButton(
                                    onPressed: _busy
                                        ? null
                                        : () async {
                                            await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                    builder: (_) =>
                                                        PaymentScreen(
                                                            orderId: widget
                                                                .orderId)));
                                            if (mounted) _load();
                                          },
                                    child: Text(S.t('Pay in test mode'))),
                              if (status == 'PENDING_PAYMENT')
                                OutlinedButton(
                                    onPressed: _busy ? null : _cancel,
                                    child: Text(S.t('Cancel unpaid order'))),
                              if (!buyer && status == 'PAID')
                                ElevatedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _transition('CONFIRMED'),
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
                                    onPressed: _busy
                                        ? null
                                        : () => _transition('SHIPPED'),
                                    child: Text(S.t('Mark shipped'))),
                              if (!buyer &&
                                  (status == 'SHIPPED' ||
                                      status == 'PROCESSING' &&
                                          o['fulfillment_method'] == 'PICKUP'))
                                ElevatedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _transition('COMPLETED'),
                                    child: Text(S.t('Complete order'))),
                            ]))),
            ])));
  }
}
