import '../widgets/brand_widgets.dart';
import '../utils/language_rebuild.dart';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/session_manager.dart';
import '../utils/commerce_strings.dart';
import '../widgets/commerce_widgets.dart';
import '../widgets/vayal_app_bar.dart';
import '../widgets/bottom_nav_bar.dart';
import '../utils/presentation_format.dart';
import 'add_product_screen.dart';
import 'farmer_application_screen.dart';
import 'orders_screen.dart';
import '../widgets/vayal_drawer.dart';

class FarmerHomeScreen extends StatefulWidget {
  final ApiClient? api;
  const FarmerHomeScreen({super.key, this.api});
  @override
  State<FarmerHomeScreen> createState() => _FarmerHomeScreenState();
}

class _FarmerHomeScreenState extends State<FarmerHomeScreen>
    with LanguageRebuild<FarmerHomeScreen> {
  late final _api = widget.api ?? ApiClient();
  Map<String, dynamic>? _metrics, _profile;
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
      final values = await Future.wait([
        _api.request('/api/v1/farmers/me/dashboard'),
        _api.request('/api/v1/farmers/me/profile')
      ]);
      if (mounted) {
        setState(() {
          _metrics = Map<String, dynamic>.from(values[0]);
          _profile = Map<String, dynamic>.from(values[1]);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) _load();
  }

  Future<void> _add() async {
    try {
      final p = await _api.request('/api/v1/farmers/me/profile');
      if (p['can_publish'] == true && mounted) {
        await _open(const AddProductScreen());
      } else if (mounted) {
        await _open(const FarmerApplicationScreen());
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0:
        _load();
        break;
      case 1:
        _open(const MyCropsScreen());
        break;
      case 2:
        _open(const OrdersScreen());
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _profile?['can_publish'] == true;
    final m = _metrics;
    return Scaffold(
        appBar: VayalAppBar(
            title: SessionManager().currentUser?.name ?? S.t('Farmer'),
            subtitle: S.t('Dashboard')),
        drawer: const VayalNavigationDrawer(currentSection: 'dashboard'),
        bottomNavigationBar:
            VayalBottomNavBar(currentIndex: 0, onTap: _onBottomNavTap),
        body: PageBody(
            child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  BrandHeading(
                      title: S.t('Dashboard'),
                      subtitle: SessionManager().currentUser?.name,
                      icon: Icons.agriculture_outlined),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null) ErrorPanel(_error!, _load),
                  if (_profile != null)
                    Card(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.35),
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(children: [
                                    Icon(ready
                                        ? Icons.verified
                                        : Icons.lock_outline),
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: Text(
                                            ready
                                                ? S.status('APPROVED')
                                                : S.t('Publishing locked'),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge))
                                  ]),
                                  Text(S.status(_profile!['approval_status'])),
                                  if (!ready)
                                    Text(S.t(
                                        'Complete onboarding and obtain administrator approval.')),
                                  if (_profile!['rejection_reason'] != null)
                                    Text(_profile!['rejection_reason']),
                                  OutlinedButton(
                                      onPressed: () => _open(
                                          const FarmerApplicationScreen()),
                                      child: Text(S.t('Farmer application'))),
                                  ElevatedButton.icon(
                                      onPressed: ready && !_busy ? _add : null,
                                      icon:
                                          Icon(ready ? Icons.add : Icons.lock),
                                      label: Text(S.t('Add crop'))),
                                ]))),
                  const SizedBox(height: 16),
                  if (m != null)
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      MetricCard('Active listings', '${m['active_products']}'),
                      MetricCard('Total orders', '${m['total_orders']}'),
                      MetricCard('Pending orders', '${m['pending_orders']}'),
                      MetricCard('Completed sales', '${m['completed_orders']}'),
                      MetricCard('Paid payouts',
                          m['total_payout_display'] ?? S.money(0)),
                      MetricCard('Pending payouts',
                          m['pending_payout_display'] ?? S.money(0)),
                    ]),
                ]))));
  }
}

class MyCropsScreen extends StatelessWidget {
  const MyCropsScreen({super.key});
  @override
  Widget build(BuildContext context) => RecordPage(
      title: 'My crops',
      path: '/api/v1/products/my',
      itemBuilder: (ctx, p, reload) => Card(
          child: ListTile(
              leading: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                      width: 56,
                      height: 56,
                      child: CropImage(p['image_url'] as String?,
                          semanticLabel: p['product_name']))),
              title: Text(S.crop(p['product_name'] as String?)),
              subtitle: Text(
                  '${p['quantity_available']} ${S.t((p['quantity_unit'] as String? ?? 'KG').toUpperCase())} • ${S.status(p['status'])}\n${p['farmer_payout_per_unit_display']}'),
              trailing: const Icon(Icons.edit),
              onTap: () async {
                await Navigator.push(
                    ctx,
                    MaterialPageRoute(
                        builder: (_) => AddProductScreen(product: p)));
                reload();
              })));
}

class FarmerPayoutsScreen extends StatelessWidget {
  const FarmerPayoutsScreen({super.key});
  @override
  Widget build(BuildContext context) => RecordPage(
      title: 'Payouts',
      path: '/api/v1/farmers/me/payouts',
      itemBuilder: (ctx, p, reload) => Card(
          child: ListTile(
              leading: const Icon(Icons.account_balance),
              title: Text(p['amount_display']),
              subtitle: Text(
                  '${S.status(p['status'])}\n${displayDate(ctx, p['created_at'])}'))));
}

class FarmerSalesScreen extends StatefulWidget {
  final ApiClient? api;
  const FarmerSalesScreen({super.key, this.api});
  @override
  State<FarmerSalesScreen> createState() => _FarmerSalesScreenState();
}

class _FarmerSalesScreenState extends State<FarmerSalesScreen>
    with LanguageRebuild<FarmerSalesScreen> {
  late final _api = widget.api ?? ApiClient();
  String _period = 'month';
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = true;
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
      final d = await _api.request('/api/v1/farmers/me/sales?period=$_period');
      if (mounted) setState(() => _data = Map<String, dynamic>.from(d));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _data?['items'] as List? ?? [];
    final maxAmount = items.fold<num>(1,
        (a, r) => r['farmer_amount_paise'] > a ? r['farmer_amount_paise'] : a);
    return Scaffold(
        appBar: VayalAppBar(title: S.t('Sales'), showBack: true),
        body: PageBody(
            child: ListView(padding: const EdgeInsets.all(16), children: [
          Wrap(spacing: 8, children: [
            for (final p
                in {'today': 'Day', 'month': 'Month', 'year': 'Year'}.entries)
              ChoiceChip(
                  label: Text(S.t(p.value)),
                  selected: _period == p.key,
                  onSelected: _busy
                      ? null
                      : (_) {
                          setState(() => _period = p.key);
                          _load();
                        })
          ]),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ErrorPanel(_error!, _load),
          if (_data != null) ...[
            Wrap(spacing: 12, runSpacing: 12, children: [
              MetricCard(
                  'Farmer earnings', S.money(_data!['farmer_earnings_paise'])),
              MetricCard(
                  'Platform commission', S.money(_data!['commission_paise']))
            ]),
            const SizedBox(height: 16),
            Text(S.t(
                'Farmer receives the full base price. Commission is added for buyers.')),
            for (final stock in _data!['stock'])
              detailLine(
                  'Available stock', '${stock['quantity']} ${S.t((stock['_id'] as String? ?? 'KG').toUpperCase())}'),
            if (items.isEmpty)
              Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(S.t('No orders in this period.'))),
            for (final r in items)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Card(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${S.crop(r['_id']['crop'] as String?)} • ${r['quantity']} ${S.t((r['_id']['unit'] as String? ?? 'KG').toUpperCase())}'),
                                Text(S.money(r['farmer_amount_paise'])),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                    value: (r['farmer_amount_paise'] as num) /
                                        maxAmount,
                                    minHeight: 8),
                              ])))),
          ]
        ])));
  }
}
