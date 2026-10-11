import '../utils/language_rebuild.dart';
import 'package:flutter/material.dart';
import '../services/admin_service.dart';
import '../services/api_client.dart';
import '../utils/commerce_strings.dart';
import '../widgets/commerce_widgets.dart';
import '../widgets/vayal_app_bar.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  final AdminService? adminService;
  const AdminDashboardScreen({super.key, this.adminService});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with LanguageRebuild<AdminDashboardScreen> {
  late final _service = widget.adminService ?? AdminService();
  late final _api = _service.api;
  String _period = 'today';
  Map<String, dynamic>? _data;
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.adminService == null) _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data =
          await _api.request('/api/v1/admin/dashboard?period=$_period');
      if (mounted) setState(() => _data = Map<String, dynamic>.from(data));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: VayalAppBar(title: S.t('Admin dashboard')),
      body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(S.t('Manage VayalConnect'),
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ActionChip(
                  label: Text(S.t('Farmers')),
                  onPressed: () => _open(AdminFarmersScreen(api: _api))),
              ActionChip(
                  label: Text(S.t('Buyers')),
                  onPressed: () => _open(const AdminBuyersScreen())),
              ActionChip(
                  label: Text(S.t('Commission')),
                  onPressed: () => _open(CommissionScreen(api: _api))),
              ActionChip(
                  label: Text(S.t('Payouts')),
                  onPressed: () => _open(AdminPayoutsScreen(api: _api))),
              ActionChip(
                  label: Text(S.t('Orders')),
                  onPressed: () => _open(const OrdersScreen())),
              ActionChip(
                  label: Text(S.t('Profile')),
                  onPressed: () => _open(const ProfileScreen())),
            ]),
            const SizedBox(height: 16),
            DropdownButton<String>(
                value: _period,
                items: {'today': 'Day', 'month': 'Month', 'year': 'Year'}
                    .entries
                    .map((e) => DropdownMenuItem(
                        value: e.key, child: Text(S.t(e.value))))
                    .toList(),
                onChanged: _busy
                    ? null
                    : (v) {
                        setState(() => _period = v!);
                        _load();
                      }),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) ErrorPanel(_error!, _load),
            if (_data != null) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in {
                  'total_farmers': 'Registered farmers',
                  'approved_farmers': 'Approved farmers',
                  'pending_farmer_approvals': 'Pending applications',
                  'rejected_farmers': 'Rejected applications',
                  'total_buyers': 'Registered buyers',
                  'active_products': 'Active listings',
                  'total_orders': 'Total orders',
                  'pending_orders': 'Pending orders',
                  'completed_orders': 'Completed orders',
                  'cancelled_orders': 'Cancelled orders'
                }.entries)
                  MetricCard(e.value, '${_data![e.key] ?? 0}'),
                for (final e in {
                  'gross_order_value_paise': 'Gross order value',
                  'total_platform_commission_paise': 'Earned commission',
                  'captured_payments_paise': 'Captured payments',
                  'paid_payouts_paise': 'Paid payouts',
                  'pending_payouts_paise': 'Pending payouts'
                }.entries)
                  MetricCard(e.value, S.money(_data![e.key] ?? 0)),
              ]),
              const SizedBox(height: 16),
              Text(S.t(
                  'Financial periods use UTC order creation dates. Earned commission requires completed and captured orders.')),
            ],
          ])));
}

class AdminFarmersScreen extends StatefulWidget {
  final ApiClient api;
  const AdminFarmersScreen({super.key, required this.api});
  @override
  State<AdminFarmersScreen> createState() => _AdminFarmersScreenState();
}

class _AdminFarmersScreenState extends State<AdminFarmersScreen>
    with LanguageRebuild<AdminFarmersScreen> {
  String _status = '';
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: VayalAppBar(title: S.t('Farmers'), showBack: true),
      body: Column(children: [
        DropdownButton<String>(
            value: _status,
            items: ['', 'PENDING', 'APPROVED', 'REJECTED']
                .map((v) => DropdownMenuItem(
                    value: v,
                    child: Text(v.isEmpty ? S.t('All farmers') : S.status(v))))
                .toList(),
            onChanged: (v) => setState(() => _status = v!)),
        Expanded(
            child: RecordPage(
                key: ValueKey(_status),
                title: 'Farmers',
                embedded: true,
                api: widget.api,
                path:
                    '/api/v1/admin/farmers${_status.isEmpty ? '' : '?status=$_status'}',
                itemBuilder: (ctx, f, reload) => Card(
                    child: ListTile(
                        title: Text(f['name'] ?? ''),
                        subtitle: Text(
                            '${S.status(f['approval_status'])}\n${f['area_location'] ?? ''}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.push(
                              ctx,
                              MaterialPageRoute(
                                  builder: (_) => FarmerReviewScreen(
                                      farmer: f, api: widget.api)));
                          reload();
                        })))),
      ]));
}

class FarmerReviewScreen extends StatefulWidget {
  final Map<String, dynamic> farmer;
  final ApiClient api;
  const FarmerReviewScreen(
      {super.key, required this.farmer, required this.api});
  @override
  State<FarmerReviewScreen> createState() => _FarmerReviewScreenState();
}

class _FarmerReviewScreenState extends State<FarmerReviewScreen>
    with LanguageRebuild<FarmerReviewScreen> {
  late Map<String, dynamic> _farmer = widget.farmer;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final f = await widget.api
          .request("/api/v1/admin/farmers/${widget.farmer['user_id']}");
      if (mounted) setState(() => _farmer = Map<String, dynamic>.from(f));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _error;
  Future<void> _decide(bool approve) async {
    String? reason;
    if (!approve) {
      final controller = TextEditingController();
      reason = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: Text(S.t('Rejection reason')),
                  content: TextField(controller: controller, maxLength: 500),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(S.t('Cancel'))),
                    TextButton(
                        onPressed: () =>
                            Navigator.pop(ctx, controller.text.trim()),
                        child: Text(S.t('Reject')))
                  ]));
      controller.dispose();
      if (reason == null || reason.isEmpty || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.request(
          '/api/v1/admin/farmers/${widget.farmer['user_id']}/${approve ? 'approve' : 'reject'}',
          method: 'PUT',
          body: {
            'application_revision': _farmer['application_revision'] ?? 0,
            if (!approve) 'reason': reason
          });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _farmer, a = Map<String, dynamic>.from(f['application'] ?? {});
    return Scaffold(
        appBar: VayalAppBar(title: S.t('Farmer application'), showBack: true),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          detailLine('Name', f['name']),
          detailLine('Email', f['email']),
          detailLine('Contact number', f['phone']),
          detailLine('Status', S.status(f['approval_status'])),
          detailLine('Farm name', a['farm_name']),
          detailLine('Farm address', a['farm_address']),
          detailLine('Farm details', a['farm_details']),
          detailLine('Crops', a['crops']),
          detailLine('Farm coordinates', a['coordinates']),
          detailLine('Rejection reason', f['rejection_reason']),
          detailLine('Bank details submitted',
              S.t(f['bank_details_present'] == true ? 'Yes' : 'No')),
          OutlinedButton(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          UserActivityScreen(userId: f['user_id']))),
              child: Text(S.t('Products and orders'))),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ErrorPanel(_error!, _reload),
          if (f['approval_status'] == 'PENDING' &&
              f['submitted_at'] != null) ...[
            FilledButton(
                onPressed: _busy ? null : () => _decide(true),
                child: Text(S.t('Approve'))),
            OutlinedButton(
                onPressed: _busy ? null : () => _decide(false),
                child: Text(S.t('Reject'))),
          ],
        ]));
  }
}

class AdminBuyersScreen extends StatelessWidget {
  const AdminBuyersScreen({super.key});
  @override
  Widget build(BuildContext context) => RecordPage(
      title: 'Buyers',
      path: '/api/v1/admin/users?role=BUYER',
      itemBuilder: (ctx, u, reload) => Card(
          child: ListTile(
              title: Text(u['name'] ?? ''),
              subtitle: Text(
                  '${u['email']}\n${u['phone']} · ${S.t(u['is_active'] == true ? 'Active' : 'Inactive')}'),
              onTap: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(
                      builder: (_) => UserActivityScreen(userId: u['id']))))));
}

class UserActivityScreen extends StatefulWidget {
  final String userId;
  const UserActivityScreen({super.key, required this.userId});
  @override
  State<UserActivityScreen> createState() => _UserActivityScreenState();
}

class _UserActivityScreenState extends State<UserActivityScreen>
    with LanguageRebuild<UserActivityScreen> {
  final _api = ApiClient();
  Map<String, dynamic>? _data;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d =
          await _api.request('/api/v1/admin/users/${widget.userId}/activity');
      if (mounted) setState(() => _data = Map<String, dynamic>.from(d));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: VayalAppBar(title: S.t('Products and orders'), showBack: true),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_data == null && _error == null) const LinearProgressIndicator(),
        if (_error != null) ErrorPanel(_error!, _load),
        if (_data != null) ...[
          detailLine('Total orders', _data!['total_orders']),
          detailLine('Total listings', _data!['total_products']),
          Text(S.t('Latest 100 records')),
          for (final p in _data!['products'])
            Card(
                child: ListTile(
                    title: Text(p['product_name'] ?? ''),
                    subtitle: Text(
                        '${p['quantity_available']} ${p['quantity_unit']} · ${S.status(p['status'])}'))),
          for (final o in _data!['orders'])
            Card(
                child: ListTile(
                    title: Text(o['order_number'] ?? ''),
                    subtitle: Text(S.status(o['order_status'])),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                OrderDetailScreen(orderId: o['id']))))),
        ],
      ]));
}

class CommissionScreen extends StatefulWidget {
  final ApiClient api;
  const CommissionScreen({super.key, required this.api});
  @override
  State<CommissionScreen> createState() => _CommissionScreenState();
}

class _CommissionScreenState extends State<CommissionScreen>
    with LanguageRebuild<CommissionScreen> {
  final _rate = TextEditingController();
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.request('/api/v1/admin/commission');
      if (mounted) {
        _rate.text =
            ((d['commission_percentage_bps'] ?? 2000) / 100).toString();
      }
    } catch (e) {
      if (mounted) _error = e.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final text = _rate.text.trim();
    final rate = double.tryParse(text);
    if (rate == null ||
        !rate.isFinite ||
        rate < 0 ||
        rate > 100 ||
        !RegExp(r'^\d{1,3}(\.\d{1,2})?$').hasMatch(text)) {
      setState(() => _error = S.t(
          'Enter a percentage from 0 to 100, with up to two decimal places.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.request('/api/v1/admin/commission',
          method: 'PUT',
          body: {'commission_percentage_bps': (rate * 100).round()});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.t('Commission saved for new orders.'))));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: VayalAppBar(title: S.t('Commission'), showBack: true),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Text(S.t(
            'Buyer total = farmer base + platform commission + delivery charge.')),
        const SizedBox(height: 16),
        TextField(
            controller: _rate,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: S.t('Global commission percentage'),
                suffixText: '%')),
        const SizedBox(height: 12),
        Text(S.t(
            'Changes apply to new orders. Historical order prices remain unchanged.')),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ErrorPanel(_error!, _load),
        FilledButton(onPressed: _busy ? null : _save, child: Text(S.t('Save'))),
      ]));
}

class AdminPayoutsScreen extends StatelessWidget {
  final ApiClient api;
  const AdminPayoutsScreen({super.key, required this.api});
  @override
  Widget build(BuildContext context) => RecordPage(
      title: 'Payouts',
      path: '/api/v1/payouts/',
      api: api,
      itemBuilder: (ctx, p, reload) => Card(
          child: ListTile(
              title:
                  Text('${p['payout_number']} · ${S.money(p['amount_paise'])}'),
              subtitle: Text(S.status(p['status'])),
              onTap: () async {
                await Navigator.push(
                    ctx,
                    MaterialPageRoute(
                        builder: (_) =>
                            PayoutReviewScreen(payout: p, api: api)));
                reload();
              })));
}

class PayoutReviewScreen extends StatefulWidget {
  final Map<String, dynamic> payout;
  final ApiClient api;
  const PayoutReviewScreen(
      {super.key, required this.payout, required this.api});
  @override
  State<PayoutReviewScreen> createState() => _PayoutReviewScreenState();
}

class _PayoutReviewScreenState extends State<PayoutReviewScreen>
    with LanguageRebuild<PayoutReviewScreen> {
  bool _busy = true;
  Map<String, dynamic>? _order;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final o = await widget.api
          .request('/api/v1/orders/${widget.payout['order_id']}');
      if (mounted) setState(() => _order = Map<String, dynamic>.from(o));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(bool approve) async {
    String? reason;
    if (!approve) {
      final c = TextEditingController();
      reason = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: Text(S.t('Rejection reason')),
                  content: TextField(controller: c, maxLength: 500),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(S.t('Cancel'))),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, c.text.trim()),
                        child: Text(S.t('Reject')))
                  ]));
      c.dispose();
      if (reason == null || reason.isEmpty || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await widget.api.request(
          '/api/v1/payouts/${widget.payout['payout_id']}/${approve ? 'approve' : 'reject'}',
          method: 'PUT',
          body: approve ? null : {'rejection_reason': reason});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: VayalAppBar(title: S.t('Payout review'), showBack: true),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        detailLine('Amount', S.money(widget.payout['amount_paise'])),
        detailLine('Status', S.status(widget.payout['status'])),
        if (_order != null) ...[
          detailLine('Orders', _order!['order_number']),
          detailLine('Status', S.status(_order!['order_status'])),
          detailLine('Payment', S.status(_order!['payment_status']))
        ],
        Text(S.t('Payout review requires completed and captured orders.')),
        const SizedBox(height: 12),
        Text(S.t('Bank transfers are disabled in this test demonstration.')),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ErrorPanel(_error!, _load),
        if (widget.payout['status'] == 'PENDING_APPROVAL') ...[
          FilledButton(
              onPressed: _busy ||
                      _order?['order_status'] != 'COMPLETED' ||
                      _order?['payment_status'] != 'CAPTURED'
                  ? null
                  : () => _review(true),
              child: Text(S.t('Approve payout'))),
          OutlinedButton(
              onPressed: _busy ? null : () => _review(false),
              child: Text(S.t('Reject payout'))),
        ],
      ]));
}
