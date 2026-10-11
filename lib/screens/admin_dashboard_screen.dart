import 'package:flutter/material.dart';
import '../models/dashboard_models.dart';
import '../services/admin_service.dart';
import '../services/session_manager.dart';
import '../utils/localization.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/demo_banner.dart';
import '../widgets/stats_kpi_card.dart';
import '../widgets/vayal_app_bar.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';

/// Admin Dashboard & Market Portal
///
/// Implements Stitch Screen 9960b4207c924cbdbde84f0c82eaec15
class AdminDashboardScreen extends StatefulWidget {
  final AdminService? adminService;
  const AdminDashboardScreen({super.key, this.adminService});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final _adminService = widget.adminService ?? AdminService();
  int _currentNavIndex = 0;
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedTimeline = 'இன்று (Today)';
  AdminDashboardMetrics _metrics = AdminDashboardMetrics();

  final List<Map<String, dynamic>> _pendingFarmers = [];
  final List<Map<String, dynamic>> _recentOrders = [];
  final Set<String> _decidingFarmers = {};
  final _farmersKey = GlobalKey();
  String get _period => _selectedTimeline.contains('Week') ? 'week' : _selectedTimeline.contains('Month') ? 'month' : 'today';

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  @override
  void dispose() {
    _adminService.dispose();
    super.dispose();
  }

  Future<void> _loadMetrics() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait<Object>([
        _adminService.fetchDashboardMetrics(period: _period),
        _adminService.fetchPendingFarmers(),
        _adminService.fetchRecentOrders(period: _period),
      ]);
      if (mounted) {
        setState(() {
          _metrics = results[0] as AdminDashboardMetrics;
          _pendingFarmers
            ..clear()
            ..addAll((results[1] as List<Map<String, dynamic>>).map((f) => {
              ...f, 'id': f['user_id'], 'location': f['area_location'] ?? '',
            }));
          _recentOrders
            ..clear()
            ..addAll((results[2] as List<Map<String, dynamic>>).map((o) => {
              ...o, 'num': o['order_number'] ?? '', 'buyer': o['buyer_name'] ?? '',
              'farmer': o['farmer_name'] ?? '', 'crop': o['product_name'] ?? '',
              'amount': o['buyer_total_display'] ?? '', 'status': o['order_status'] ?? '',
              'color': AppTheme.primaryGreen,
            }));
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _decideFarmer(Map<String, dynamic> farmer, bool approved) async {
    final id = farmer['id'];
    if (id is! String || id.isEmpty || _decidingFarmers.contains(id)) return;
    String? reason;
    if (!approved) {
      final controller = TextEditingController();
      reason = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
        title: Text(VayalStrings.rejectionReason),
        content: TextField(controller: controller, maxLength: 500, maxLines: 3),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () { if (controller.text.trim().isNotEmpty) Navigator.pop(ctx, controller.text.trim()); }, child: const Text('Reject'))],
      ));
      // The dialog route disposes its TextField after its transition.
      if (reason == null || !mounted) return;
    }
    setState(() => _decidingFarmers.add(id));
    try {
      if (approved) { await _adminService.approveFarmer(id, applicationRevision: farmer['application_revision'] as int? ?? 0); }
      else { await _adminService.rejectFarmer(id, reason!, applicationRevision: farmer['application_revision'] as int? ?? 0); }
      await _loadMetrics();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to save the decision. Please retry.')));
    } finally {
      if (mounted) setState(() => _decidingFarmers.remove(id));
    }
  }

  void _onBottomNavTapped(int index) {
    if (index == _currentNavIndex) return;
    switch (index) {
      case 0:
        // Overview
        break;
      case 1:
        final target = _farmersKey.currentContext;
        if (target != null) Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 300));
        break;
      case 2:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const OrdersScreen()),
        );
        break;
      case 3:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionManager();

    return Scaffold(
      backgroundColor: AppTheme.backgroundWarm,
      appBar: VayalAppBar(
        title: session.isTamil ? 'நிர்வாக டாஷ்போர்டு' : 'Admin Portal',
        subtitle: session.isTamil ? 'சந்தை மேற்பார்வை & ஒப்புதல்கள்' : 'Marketplace Oversight',
      ),
      body: RefreshIndicator(
        color: AppTheme.primaryGreen,
        onRefresh: _loadMetrics,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Demo Banner
              if (session.isDemoMode) const DemoModeBanner(),

              // Timeline Selector
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: ['இன்று (Today)', 'இந்த வாரம் (Week)', 'இந்த மாதம் (Month)'].map((period) {
                    final isSel = _selectedTimeline == period;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(period),
                        selected: isSel,
                        selectedColor: AppTheme.primaryGreen,
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isSel ? Colors.white : AppTheme.textPrimary,
                        ),
                        onSelected: _isLoading ? null : (_) {
                          setState(() => _selectedTimeline = period);
                          _loadMetrics();
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 12),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: LinearProgressIndicator(color: AppTheme.primaryGreen),
                ),

              if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.wifi_off_rounded, color: AppTheme.errorRed, size: 36),
                      const SizedBox(height: 8),
                      Text(
                        session.isTamil ? 'நிர்வாக தகவல்களைப் பெறுவதில் பிழை' : 'Failed to fetch admin metrics',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.errorRed),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _loadMetrics,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: Text(session.isTamil ? 'மீண்டும் முயற்சிக்கவும்' : 'Retry'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen),
                      ),
                    ],
                  ),
                ),

              // Top 2x2 Metric Grid
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: StatsKpiCard(
                            title: session.isTamil ? 'மொத்த ஆர்டர்கள்' : 'Total Orders',
                            value: '${_metrics.totalOrders}',
                            subtitle: 'Orders in selected period',

                            icon: Icons.receipt_long,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StatsKpiCard(
                            title: session.isTamil ? 'மொத்த விற்பனை (GMV)' : 'Gross Sales',
                            value: _metrics.totalSalesDisplay,
                            subtitle: 'Completed, captured orders',

                            icon: Icons.trending_up,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: StatsKpiCard(
                            title: session.isTamil ? 'விவசாயி பட்டுவாடா' : 'Farmer Payouts',
                            value: _metrics.totalFarmerPayoutDisplay,
                            subtitle: 'Order payout totals',
                            icon: Icons.account_balance_wallet,
                            iconColor: AppTheme.primaryGreen,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StatsKpiCard(
                            title: session.isTamil ? 'தள வருவாய் (Commission)' : 'Platform Commission',
                            value: _metrics.totalPlatformCommissionDisplay,
                            subtitle: 'Stored order commissions',
                            icon: Icons.account_balance,
                            iconColor: AppTheme.accentGold,
                            iconBgColor: AppTheme.surfaceCream,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Actionable Section: Pending Farmer Approvals
              Padding(
                key: _farmersKey,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          session.isTamil ? 'விவசாயிகள் சரிபார்ப்பு' : 'Farmer Application Review',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.goldLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.accentGold.withOpacity(0.4)),
                          ),
                          child: Text(
                            '${_pendingFarmers.length} காத்திருப்பில்',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.warningOrange),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              if (!_isLoading && _pendingFarmers.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No farmers awaiting review.')),
              ..._pendingFarmers.map((f) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  padding: const EdgeInsets.all(14),
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
                          Expanded(
                            child: Text(
                              f['name'] as String,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text(
                            f['location'] as String,
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Email: ${f['email'] ?? ''}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                      ),
                      Text(
                        'Phone: ${f['phone'] ?? ''}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                      ExpansionTile(title: const Text('Review submitted farm details'), children: [
                        if (f['application'] is Map) ...[
                          for (final key in ['farm_name', 'farm_address', 'pickup_address', 'crops', 'delivery_available'])
                            ListTile(title: Text(key.replaceAll('_', ' ')), subtitle: Text(f['application'][key].toString())),
                          ListTile(title: Text('Submitted: ' + f['submitted_at'].toString() + ' • Revision: ' + f['application_revision'].toString())),
                        ] else const ListTile(title: Text('Application not submitted. Approval is unavailable.')),
                        ListTile(title: Text('Email verified: ' + (f['email_verified'] == true).toString())),
                      ]),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: _decidingFarmers.contains(f['id']) ? null : () => _decideFarmer(f, false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.errorRed,
                              side: const BorderSide(color: AppTheme.errorRed),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                            child: const Text('நிராகரி • Reject', style: TextStyle(fontSize: 11)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _decidingFarmers.contains(f['id']) || f['application'] == null ? null : () => _decideFarmer(f, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryGreen,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            ),
                            child: const Text('ஒப்புதல் • Approve', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 16),

              // Section: Recent Marketplace Orders
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  session.isTamil ? 'சமீபத்திய ஆர்டர்கள் (Recent Orders)' : 'Recent Orders',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ),

              const SizedBox(height: 8),

              if (!_isLoading && _recentOrders.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No orders in this period.')),
              ..._recentOrders.map((ord) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.softGreen,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.receipt, color: AppTheme.primaryGreen, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'ஆர்டர் #${ord['num']}',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (ord['color'] as Color).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    ord['status'] as String,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: ord['color'] as Color,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${ord['buyer']} • ${ord['crop']}',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                            Text(
                              'மொத்தம்: ${ord['amount']}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomNavigationBar: VayalBottomNavBar(
        currentIndex: _currentNavIndex,
        onTap: _onBottomNavTapped,
      ),
    );
  }
}
