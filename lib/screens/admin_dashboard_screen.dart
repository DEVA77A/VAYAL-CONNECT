import '../theme/app_theme.dart';

import '../widgets/brand_widgets.dart';

import '../utils/language_rebuild.dart';

import 'package:flutter/material.dart';

import '../services/admin_service.dart';

import '../services/api_client.dart';

import '../utils/commerce_strings.dart';

import '../widgets/commerce_widgets.dart';

import '../widgets/vayal_app_bar.dart';

import 'orders_screen.dart';

import '../widgets/bottom_nav_bar.dart';

import '../widgets/vayal_drawer.dart';



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

  Map<String, dynamic>? _marketStatus;

  bool _busy = true;

  String? _error;

  bool _refreshingMarket = false;

  String? _marketRefreshMessage;



  Future<void> _manualRefreshMarketPrices() async {

    setState(() {

      _refreshingMarket = true;

      _marketRefreshMessage = null;

    });

    try {

      await _api.request('/api/v1/market-prices/refresh', method: 'POST');
      if (widget.adminService == null) {
        try {
          final mStatus = await _api.request('/api/v1/market-prices/status');
          if (mounted) setState(() => _marketStatus = Map<String, dynamic>.from(mStatus));
        } catch (_) {}
      }

      if (mounted) {

        setState(() {

          _marketRefreshMessage = S.t('Market prices refreshed successfully.');

        });

        ScaffoldMessenger.of(context).showSnackBar(

          SnackBar(

            content: Text(S.t('Market prices refreshed successfully.')),

            backgroundColor: AppTheme.successGreen,

          ),

        );

      }

    } catch (e) {

      if (mounted) {

        final err = e.toString().replaceFirst('Exception: ', '');

        setState(() => _marketRefreshMessage = err);

      }

    } finally {

      if (mounted) setState(() => _refreshingMarket = false);

    }

  }

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
      if (widget.adminService == null) {
        try {
          final mStatus = await _api.request('/api/v1/market-prices/status');
          if (mounted) setState(() => _marketStatus = Map<String, dynamic>.from(mStatus));
        } catch (_) {}
      }

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



  void _onBottomNavTap(int index) {

    if (index == 0) {

      _load();

    } else if (index == 1) {

      _open(AdminFarmersScreen(api: _api));

    } else if (index == 2) {

      _open(const OrdersScreen());

    }

  }



  @override

  Widget build(BuildContext context) => Scaffold(

      appBar: VayalAppBar(title: S.t('Admin dashboard')),

      drawer: const VayalNavigationDrawer(currentSection: 'overview'),

      bottomNavigationBar: VayalBottomNavBar(

        currentIndex: 0,

        onTap: _onBottomNavTap,

      ),

      body: PageBody(

          child: RefreshIndicator(

              onRefresh: _load,

              child: ListView(padding: const EdgeInsets.all(16), children: [

                BrandHeading(

                    title: S.t('Manage VayalConnect'),

                    icon: Icons.dashboard_outlined),

                const SizedBox(height: 16),

                DropdownButton<String>(

                    isExpanded: true,

                    itemHeight: null,

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

                  Padding(

                    padding: const EdgeInsets.only(top: 8, bottom: 12),

                    child: Text(

                      S.t('Operations & Marketplace'),

                      style: const TextStyle(

                        fontSize: 16,

                        fontWeight: FontWeight.bold,

                        color: AppTheme.textPrimary,

                      ),

                    ),

                  ),

                  Builder(builder: (ctx) {

                    final screenWidth = MediaQuery.sizeOf(ctx).width;

                    final textScale =

                        MediaQuery.textScalerOf(ctx).scale(14) / 14;

                    final int crossAxisCount =

                        (screenWidth < 360 || textScale > 1.25) ? 1 : 2;

                    final double childAspectRatio = crossAxisCount == 1

                        ? (textScale > 1.3 ? 1.4 : 1.8)

                        : 1.15;



                    final operations = [

                      _MetricDef(

                        id: 'total_farmers',

                        label: 'Registered farmers',

                        icon: Icons.people_outline,

                        color: AppTheme.primaryGreen,

                        onTap: () => _open(

                            AdminFarmersScreen(api: _api, initialStatus: '')),

                      ),

                      _MetricDef(

                        id: 'approved_farmers',

                        label: 'Approved farmers',

                        icon: Icons.verified_user_outlined,

                        color: AppTheme.primaryDarkGreen,

                        onTap: () => _open(AdminFarmersScreen(

                            api: _api, initialStatus: 'APPROVED')),

                      ),

                      _MetricDef(

                        id: 'pending_farmer_approvals',

                        label: 'Pending applications',

                        icon: Icons.hourglass_top_outlined,

                        color: AppTheme.warningOrange,

                        onTap: () => _open(AdminFarmersScreen(

                            api: _api, initialStatus: 'PENDING')),

                      ),

                      _MetricDef(

                        id: 'rejected_farmers',

                        label: 'Rejected applications',

                        icon: Icons.highlight_off_outlined,

                        color: AppTheme.errorRed,

                        onTap: () => _open(AdminFarmersScreen(

                            api: _api, initialStatus: 'REJECTED')),

                      ),

                      _MetricDef(

                        id: 'total_buyers',

                        label: 'Registered buyers',

                        icon: Icons.shopping_bag_outlined,

                        color: AppTheme.earthBrown,

                        onTap: () => _open(const AdminBuyersScreen()),

                      ),

                      _MetricDef(

                        id: 'active_products',

                        label: 'Active listings',

                        icon: Icons.inventory_2_outlined,

                        color: AppTheme.primaryGreen,

                        onTap: () => _open(AdminListingsScreen(api: _api)),

                      ),

                      _MetricDef(

                        id: 'total_orders',

                        label: 'Total orders',

                        icon: Icons.receipt_long_outlined,

                        color: AppTheme.deepGreen,

                        onTap: () =>

                            _open(const OrdersScreen(initialStatus: '')),

                      ),

                      _MetricDef(

                        id: 'pending_orders',

                        label: 'Pending orders',

                        icon: Icons.pending_actions_outlined,

                        color: AppTheme.warningOrange,

                        onTap: () =>

                            _open(const OrdersScreen(initialStatus: 'PENDING')),

                      ),

                      _MetricDef(

                        id: 'completed_orders',

                        label: 'Completed orders',

                        icon: Icons.check_circle_outline,

                        color: AppTheme.primaryDarkGreen,

                        onTap: () => _open(

                            const OrdersScreen(initialStatus: 'COMPLETED')),

                      ),

                      _MetricDef(

                        id: 'cancelled_orders',

                        label: 'Cancelled orders',

                        icon: Icons.cancel_outlined,

                        color: AppTheme.errorRed,

                        onTap: () => _open(

                            const OrdersScreen(initialStatus: 'CANCELLED')),

                      ),

                    ];



                    return GridView.builder(

                      shrinkWrap: true,

                      physics: const NeverScrollableScrollPhysics(),

                      itemCount: operations.length,

                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(

                        crossAxisCount: crossAxisCount,

                        childAspectRatio: childAspectRatio,

                        crossAxisSpacing: 10,

                        mainAxisSpacing: 10,

                      ),

                      itemBuilder: (c, i) {

                        final def = operations[i];

                        final val = '${_data![def.id] ?? 0}';

                        return MetricCard(

                          def.label,

                          val,

                          onTap: def.onTap,

                          icon: def.icon,

                          color: def.color,

                        );

                      },

                    );

                  }),

                  const SizedBox(height: 16),

                  SectionCard(

                    title: 'Daily Market Prices',

                    icon: Icons.query_stats_outlined,

                    children: [

                      Row(

                        mainAxisAlignment: MainAxisAlignment.spaceBetween,

                        children: [

                          Expanded(

                            child: Column(

                              crossAxisAlignment: CrossAxisAlignment.start,

                              children: [

                                Text(

                                  S.t('Provider: Government AGMARKNET & Mandi'),

                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),

                                ),

                                const SizedBox(height: 2),

                                Text(

                                  S.t('Schedule: 08:00 IST Daily'),

                                  style: Theme.of(context).textTheme.bodySmall,

                                ),

                              ],

                            ),

                          ),

                          ElevatedButton.icon(

                            onPressed: _refreshingMarket ? null : _manualRefreshMarketPrices,

                            icon: _refreshingMarket

                                ? const SizedBox(

                                    width: 14,

                                    height: 14,

                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),

                                  )

                                : const Icon(Icons.refresh, size: 16),

                            label: Text(S.t('Refresh Now')),

                            style: ElevatedButton.styleFrom(

                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),

                              backgroundColor: AppTheme.primaryGreen,

                              foregroundColor: Colors.white,

                            ),

                          ),

                        ],

                      ),

                      if (_marketStatus != null) ...[

                        const SizedBox(height: 12),

                        const Divider(height: 1),

                        const SizedBox(height: 8),

                        Row(

                          mainAxisAlignment: MainAxisAlignment.spaceBetween,

                          children: [

                            Text(

                              '${S.t('API Requests Today')}: ${_marketStatus!['api_requests_today'] ?? 0} / 100',

                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),

                            ),

                            Text(

                              '${S.t('Remaining')}: ${_marketStatus!['remaining_daily_budget'] ?? 100}',

                              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),

                            ),

                          ],

                        ),

                        const SizedBox(height: 4),

                        Row(

                          mainAxisAlignment: MainAxisAlignment.spaceBetween,

                          children: [

                            Text(

                              '${S.t('Commodities Updated')}: ${_marketStatus!['commodities_updated'] ?? _marketStatus!['commodities_count'] ?? 0}',

                              style: const TextStyle(fontSize: 12, color: AppTheme.primaryDarkGreen, fontWeight: FontWeight.w500),

                            ),

                            Text(

                              '${S.t('Source Date')}: ${_marketStatus!['latest_source_date'] ?? 'Today'}',

                              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),

                            ),

                          ],

                        ),

                      ],

                      if (_marketRefreshMessage != null) ...[

                        const SizedBox(height: 8),

                        Text(

                          _marketRefreshMessage!,

                          style: const TextStyle(fontSize: 12, color: AppTheme.primaryDarkGreen, fontWeight: FontWeight.w500),

                        ),

                      ],

                    ],

                  ),

                  const SizedBox(height: 20),

                  Padding(

                    padding: const EdgeInsets.only(top: 4, bottom: 12),

                    child: Text(

                      S.t('Financial Overview'),

                      style: const TextStyle(

                        fontSize: 16,

                        fontWeight: FontWeight.bold,

                        color: AppTheme.textPrimary,

                      ),

                    ),

                  ),

                  Builder(builder: (ctx) {

                    final screenWidth = MediaQuery.sizeOf(ctx).width;

                    final textScale =

                        MediaQuery.textScalerOf(ctx).scale(14) / 14;

                    final int crossAxisCount =

                        (screenWidth < 360 || textScale > 1.25) ? 1 : 2;

                    final double childAspectRatio = crossAxisCount == 1

                        ? (textScale > 1.3 ? 1.4 : 1.8)

                        : 1.15;



                    const financials = [

                      _MetricDef(

                        id: 'gross_order_value_paise',

                        label: 'Gross order value',

                        icon: Icons.payments_outlined,

                        color: AppTheme.earthBrown,

                        isMoney: true,

                      ),

                      _MetricDef(

                        id: 'total_platform_commission_paise',

                        label: 'Earned commission',

                        icon: Icons.account_balance_wallet_outlined,

                        color: AppTheme.primaryDarkGreen,

                        isMoney: true,

                      ),

                      _MetricDef(

                        id: 'captured_payments_paise',

                        label: 'Captured payments',

                        icon: Icons.price_check_outlined,

                        color: AppTheme.primaryGreen,

                        isMoney: true,

                      ),

                      _MetricDef(

                        id: 'paid_payouts_paise',

                        label: 'Paid payouts',

                        icon: Icons.done_all_outlined,

                        color: AppTheme.deepGreen,

                        isMoney: true,

                      ),

                      _MetricDef(

                        id: 'pending_payouts_paise',

                        label: 'Pending payouts',

                        icon: Icons.schedule_outlined,

                        color: AppTheme.warningOrange,

                        isMoney: true,

                      ),

                    ];



                    return GridView.builder(

                      shrinkWrap: true,

                      physics: const NeverScrollableScrollPhysics(),

                      itemCount: financials.length,

                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(

                        crossAxisCount: crossAxisCount,

                        childAspectRatio: childAspectRatio,

                        crossAxisSpacing: 10,

                        mainAxisSpacing: 10,

                      ),

                      itemBuilder: (c, i) {

                        final def = financials[i];

                        final val = S.money(_data![def.id] ?? 0);

                        return MetricCard(

                          def.label,

                          val,

                          icon: def.icon,

                          color: def.color,

                        );

                      },

                    );

                  }),

                  const SizedBox(height: 16),

                  Text(

                    S.t(

                        'Financial periods use UTC order creation dates. Earned commission requires completed and captured orders.'),

                    style: const TextStyle(

                        fontSize: 12, color: AppTheme.textSecondary),

                  ),

                ],

              ]))));

}



class _MetricDef {

  final String id;

  final String label;

  final IconData icon;

  final Color color;

  final VoidCallback? onTap;

  final bool isMoney;



  const _MetricDef({

    required this.id,

    required this.label,

    required this.icon,

    required this.color,

    this.onTap,

    this.isMoney = false,

  });

}



class AdminFarmersScreen extends StatefulWidget {

  final ApiClient api;

  final String initialStatus;

  const AdminFarmersScreen(

      {super.key, required this.api, this.initialStatus = 'PENDING'});

  @override

  State<AdminFarmersScreen> createState() => _AdminFarmersScreenState();

}



class _AdminFarmersScreenState extends State<AdminFarmersScreen>

    with LanguageRebuild<AdminFarmersScreen> {

  late String _status = widget.initialStatus;

  final TextEditingController _search = TextEditingController();

  String _query = '';



  @override

  void dispose() {

    _search.dispose();

    super.dispose();

  }



  @override

  Widget build(BuildContext context) => Scaffold(

      appBar: VayalAppBar(title: S.t('Farmers'), showBack: true),

      body: PageBody(

          child: Column(children: [

        Padding(

            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),

            child: DropdownButtonFormField<String>(

                isExpanded: true,

                decoration: InputDecoration(

                  labelText: S.t('Approval Status'),

                  contentPadding:

                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),

                ),

                value: _status,

                items: ['', 'PENDING', 'APPROVED', 'REJECTED']

                    .map((v) => DropdownMenuItem(

                        value: v,

                        child:

                            Text(v.isEmpty ? S.t('All farmers') : S.status(v))))

                    .toList(),

                onChanged: (v) => setState(() => _status = v!))),

        Padding(

            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),

            child: TextField(

                controller: _search,

                decoration: InputDecoration(

                  hintText: S.t('Search by name, phone or location...'),

                  prefixIcon: const Icon(Icons.search, size: 20),

                  suffixIcon: _query.isNotEmpty

                      ? IconButton(

                          icon: const Icon(Icons.clear, size: 18),

                          onPressed: () => setState(() {

                            _search.clear();

                            _query = '';

                          }),

                        )

                      : null,

                  contentPadding:

                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),

                ),

                onChanged: (v) =>

                    setState(() => _query = v.trim().toLowerCase()))),

        Expanded(

            child: RecordPage(

                key: ValueKey('$_status|$_query'),

                title: 'Farmers',

                embedded: true,

                api: widget.api,

                path:

                    '/api/v1/admin/farmers${_status.isEmpty ? '' : '?status=$_status'}',

                itemBuilder: (ctx, f, reload) {

                  if (_query.isNotEmpty) {

                    final name = (f['name'] ?? '').toString().toLowerCase();

                    final phone = (f['phone'] ?? '').toString().toLowerCase();

                    final area =

                        (f['area_location'] ?? '').toString().toLowerCase();

                    if (!name.contains(_query) &&

                        !phone.contains(_query) &&

                        !area.contains(_query)) {

                      return const SizedBox.shrink();

                    }

                  }

                  final status = f['approval_status'] ?? 'PENDING';

                  final Color statusColor = status == 'APPROVED'

                      ? AppTheme.primaryDarkGreen

                      : (status == 'REJECTED'

                          ? AppTheme.errorRed

                          : AppTheme.warningOrange);



                  return Card(

                      elevation: 1,

                      shape: RoundedRectangleBorder(

                          borderRadius: BorderRadius.circular(12),

                          side: const BorderSide(color: AppTheme.cardBorder)),

                      child: ListTile(

                          contentPadding: const EdgeInsets.symmetric(

                              horizontal: 16, vertical: 8),

                          leading: CircleAvatar(

                              backgroundColor: statusColor.withOpacity(0.12),

                              child: Icon(Icons.agriculture_outlined,

                                  color: statusColor)),

                          title: Text(f['name'] ?? '',

                              style: const TextStyle(

                                  fontWeight: FontWeight.bold, fontSize: 15)),

                          subtitle: Padding(

                            padding: const EdgeInsets.only(top: 4),

                            child: Column(

                              crossAxisAlignment: CrossAxisAlignment.start,

                              children: [

                                Text(

                                    '${f['phone'] ?? ''} · ${f['area_location'] ?? ''}',

                                    style: const TextStyle(

                                        color: AppTheme.textSecondary,

                                        fontSize: 13)),

                                const SizedBox(height: 4),

                                Container(

                                  padding: const EdgeInsets.symmetric(

                                      horizontal: 8, vertical: 2),

                                  decoration: BoxDecoration(

                                    color: statusColor.withOpacity(0.12),

                                    borderRadius: BorderRadius.circular(6),

                                  ),

                                  child: Text(

                                    S.status(status),

                                    style: TextStyle(

                                      fontSize: 11,

                                      fontWeight: FontWeight.w600,

                                      color: statusColor,

                                    ),

                                  ),

                                ),

                              ],

                            ),

                          ),

                          trailing: const Icon(Icons.chevron_right,

                              color: AppTheme.primaryGreen),

                          onTap: () async {

                            final changed = await Navigator.push(

                                ctx,

                                MaterialPageRoute(

                                    builder: (_) => FarmerReviewScreen(

                                        farmer: f, api: widget.api)));

                            if (changed == true) reload();

                          }));

                })),

      ])));

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

  bool _reviewLoaded = false;

  String? _error;



  @override

  void initState() {

    super.initState();

    _reload();

  }



  Future<void> _reload() async {

    setState(() {

      _busy = true;

      _error = null;

      _reviewLoaded = false;

    });

    try {

      final f = await widget.api

          .request("/api/v1/admin/farmers/${widget.farmer['user_id']}");

      if (mounted) {

        setState(() {

          _farmer = Map<String, dynamic>.from(f);

          _reviewLoaded = true;

        });

      }

    } catch (e) {

      if (mounted) {

        setState(() {

          _error = e.toString().replaceFirst('Exception: ', '');

          _reviewLoaded = false;

        });

      }

    } finally {

      if (mounted) setState(() => _busy = false);

    }

  }



  Future<void> _decide(bool approve) async {

    if (_busy || !_reviewLoaded) return;

    String? reason;

    if (!approve) {

      final controller = TextEditingController();

      reason = await showDialog<String>(

          context: context,

          builder: (ctx) => AlertDialog(

                  title: Text(S.t('Rejection reason')),

                  content: TextField(

                    controller: controller,

                    maxLength: 500,

                    decoration: InputDecoration(

                      hintText:

                          S.t('Enter reason for rejecting this application'),

                      border: const OutlineInputBorder(),

                    ),

                  ),

                  actions: [

                    TextButton(

                        onPressed: () => Navigator.pop(ctx),

                        child: Text(S.t('Cancel'))),

                    FilledButton(

                        style: FilledButton.styleFrom(

                            backgroundColor: AppTheme.errorRed),

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

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(

          SnackBar(

            content: Text(approve

                ? S.t('Farmer approved successfully')

                : S.t('Farmer application rejected')),

            backgroundColor:

                approve ? AppTheme.primaryGreen : AppTheme.errorRed,

            behavior: SnackBarBehavior.floating,

          ),

        );

        Navigator.pop(context, true);

      }

    } catch (e) {

      if (mounted) {

        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));

        ScaffoldMessenger.of(context).showSnackBar(

          SnackBar(

            content: Text(_error!),

            backgroundColor: AppTheme.errorRed,

            behavior: SnackBarBehavior.floating,

          ),

        );

      }

    } finally {

      if (mounted) setState(() => _busy = false);

    }

  }



  @override

  Widget build(BuildContext context) {

    final f = _farmer, a = Map<String, dynamic>.from(f['application'] ?? {});

    final status = f['approval_status'] ?? 'PENDING';

    final hasSubmission = f['submitted_at'] != null;



    return Scaffold(

        appBar: VayalAppBar(title: S.t('Farmer application'), showBack: true),

        body: PageBody(

            child: ListView(padding: const EdgeInsets.all(16), children: [

          const FormSection('Farmer application',

              icon: Icons.assignment_ind_outlined),

          detailLine('Name', f['name']),

          detailLine('Email', f['email']),

          detailLine('Contact number', f['phone']),

          detailLine('Status', S.status(status)),

          if (!hasSubmission)

            Container(

              margin: const EdgeInsets.symmetric(vertical: 8),

              padding: const EdgeInsets.all(12),

              decoration: BoxDecoration(

                color: const Color(0xFFFFF3E0),

                borderRadius: BorderRadius.circular(8),

                border: Border.all(color: AppTheme.warningOrange),

              ),

              child: Text(

                S.t(

                    'Application not submitted yet. The farmer must submit their farm details before approval.'),

                style: const TextStyle(

                    color: AppTheme.earthBrown, fontWeight: FontWeight.w500),

              ),

            ),

          const FormSection('Farm details', icon: Icons.agriculture_outlined),

          detailLine('Farm name', a['farm_name']),

          detailLine('Farm address', a['farm_address']),

          detailLine('Farm details', a['farm_details']),

          detailLine('Crops', a['crops']),

          detailLine('Farm coordinates', a['coordinates']),

          if (f['rejection_reason'] != null &&

              f['rejection_reason'].toString().trim().isNotEmpty)

            detailLine('Rejection reason', f['rejection_reason']),

          const FormSection('Bank payout details',

              icon: Icons.account_balance_outlined),

          detailLine('Bank details submitted',

              S.t(f['bank_details_present'] == true ? 'Yes' : 'No')),

          const SizedBox(height: 12),

          OutlinedButton(

              onPressed: () => Navigator.push(

                  context,

                  MaterialPageRoute(

                      builder: (_) =>

                          UserActivityScreen(userId: f['user_id']))),

              child: Text(S.t('Products and orders'))),

          if (_busy) const LinearProgressIndicator(),

          if (_error != null) ErrorPanel(_error!, _reload),

          const SizedBox(height: 16),

          if (status == 'PENDING' && hasSubmission) ...[

            FilledButton.icon(

                icon: const Icon(Icons.check_circle_outline),

                style: FilledButton.styleFrom(

                  backgroundColor: AppTheme.primaryGreen,

                  padding: const EdgeInsets.symmetric(vertical: 14),

                ),

                onPressed: (_busy || !_reviewLoaded) ? null : () => _decide(true),

                label: Text(S.t('Approve'))),

            const SizedBox(height: 10),

            OutlinedButton.icon(

                icon: const Icon(Icons.cancel_outlined,

                    color: AppTheme.errorRed),

                style: OutlinedButton.styleFrom(

                  side: const BorderSide(color: AppTheme.errorRed),

                  foregroundColor: AppTheme.errorRed,

                  padding: const EdgeInsets.symmetric(vertical: 14),

                ),

                onPressed: (_busy || !_reviewLoaded) ? null : () => _decide(false),

                label: Text(S.t('Reject'))),

          ] else if (status == 'APPROVED') ...[

            Container(

              margin: const EdgeInsets.symmetric(vertical: 8),

              padding: const EdgeInsets.all(12),

              decoration: BoxDecoration(

                color: AppTheme.softGreen,

                borderRadius: BorderRadius.circular(8),

                border: Border.all(color: AppTheme.primaryGreen),

              ),

              child: Row(

                children: [

                  const Icon(Icons.verified, color: AppTheme.primaryDarkGreen),

                  const SizedBox(width: 8),

                  Expanded(

                    child: Text(

                      S.t('Farmer is approved and actively selling.'),

                      style: const TextStyle(

                        color: AppTheme.primaryDarkGreen,

                        fontWeight: FontWeight.w600,

                      ),

                    ),

                  ),

                ],

              ),

            ),

            OutlinedButton.icon(

                icon: const Icon(Icons.block_outlined,

                    color: AppTheme.errorRed),

                style: OutlinedButton.styleFrom(

                  side: const BorderSide(color: AppTheme.errorRed),

                  foregroundColor: AppTheme.errorRed,

                ),

                onPressed: _busy ? null : () => _decide(false),

                label: Text(S.t('Revoke / Reject'))),

          ] else if (status == 'REJECTED') ...[

            Container(

              margin: const EdgeInsets.symmetric(vertical: 8),

              padding: const EdgeInsets.all(12),

              decoration: BoxDecoration(

                color: const Color(0xFFFFEBEE),

                borderRadius: BorderRadius.circular(8),

                border: Border.all(color: AppTheme.errorRed),

              ),

              child: Row(

                children: [

                  const Icon(Icons.cancel, color: AppTheme.errorRed),

                  const SizedBox(width: 8),

                  Expanded(

                    child: Text(

                      S.t('Application was rejected.'),

                      style: const TextStyle(

                        color: AppTheme.errorRed,

                        fontWeight: FontWeight.w600,

                      ),

                    ),

                  ),

                ],

              ),

            ),

          ],

        ])));

  }

}



class AdminListingsScreen extends StatelessWidget {

  final ApiClient? api;

  const AdminListingsScreen({super.key, this.api});



  @override

  Widget build(BuildContext context) => RecordPage(

      title: 'Active listings',

      path: '/api/v1/products',

      api: api,

      itemBuilder: (ctx, p, reload) => Card(

          elevation: 1,

          shape: RoundedRectangleBorder(

              borderRadius: BorderRadius.circular(12),

              side: const BorderSide(color: AppTheme.cardBorder)),

          child: ListTile(

              contentPadding:

                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),

              leading: ClipRRect(

                  borderRadius: BorderRadius.circular(8),

                  child: Container(

                      width: 52,

                      height: 52,

                      color: AppTheme.surfaceCream,

                      child: CropImage(

                        p['image_url'],

                        fit: BoxFit.cover,

                        semanticLabel: p['product_name'],

                      ))),

              title: Text(

                S.crop(p['product_name'] ?? ''),

                style: const TextStyle(

                    fontWeight: FontWeight.bold, fontSize: 15),

              ),

              subtitle: Padding(

                padding: const EdgeInsets.only(top: 4),

                child: Text(

                  '${p['quantity_available'] ?? 0} ${p['quantity_unit'] ?? 'KG'} · ${p['location'] ?? ''}\n${S.money(p['buyer_price_per_unit_paise'] ?? p['farmer_payout_per_unit_paise'])} / ${p['quantity_unit'] ?? 'KG'}',

                  style: const TextStyle(

                      color: AppTheme.textSecondary, fontSize: 13),

                ),

              ),

              isThreeLine: true,

              trailing: const Icon(Icons.chevron_right,

                  color: AppTheme.primaryGreen))));

}



class AdminBuyersScreen extends StatelessWidget {

  const AdminBuyersScreen({super.key});

  @override

  Widget build(BuildContext context) => RecordPage(

      title: 'Buyers',

      path: '/api/v1/admin/users?role=BUYER',

      itemBuilder: (ctx, u, reload) => Card(

          child: ListTile(

              leading: const CircleAvatar(

                  backgroundColor: AppTheme.softGreen,

                  child: Icon(Icons.person_outline, color: AppTheme.primaryGreen)),

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

      body: PageBody(

          child: ListView(padding: const EdgeInsets.all(16), children: [

        if (_data == null && _error == null) const LinearProgressIndicator(),

        if (_error != null) ErrorPanel(_error!, _load),

        if (_data != null) ...[

          const FormSection('Products and orders',

              icon: Icons.inventory_2_outlined),

          detailLine('Total orders', _data!['total_orders']),

          detailLine('Total listings', _data!['total_products']),

          Text(S.t('Latest 100 records')),

          for (final p in _data!['products'])

            Card(

                child: ListTile(

                    leading: ClipRRect(

                        borderRadius: BorderRadius.circular(12),

                        child: SizedBox(

                            width: 56,

                            height: 56,

                            child: CropImage(p['image_url'] as String?,

                                semanticLabel: p['product_name']))),

                    title: Text(S.crop(p['product_name'] ?? '')),

                    subtitle: Text(

                        '${p['quantity_available']} ${S.t((p['quantity_unit'] as String? ?? 'KG').toUpperCase())} · ${S.status(p['status'])}'))),

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

      ])));

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

      body: PageBody(

          child: ListView(padding: const EdgeInsets.all(24), children: [

        const FormSection('Commission', icon: Icons.percent_rounded),

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

      ])));

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



  Future<void> _processTransfer() async {

    setState(() => _busy = true);

    try {

      await widget.api.request(

          '/api/v1/payouts/${widget.payout['payout_id']}/process',

          method: 'POST');

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

      body: PageBody(

          child: ListView(padding: const EdgeInsets.all(20), children: [

        const FormSection('Payout review',

            icon: Icons.account_balance_wallet_outlined),

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

        if (widget.payout['status'] == 'APPROVED' ||

            widget.payout['status'] == 'FAILED') ...[

          FilledButton(

              onPressed: _busy || _order?['payment_status'] != 'CAPTURED'

                  ? null

                  : _processTransfer,

              child: Text(S.t('Process payout'))),

        ],

      ])));

}

