import 'package:flutter/material.dart';
import '../models/dashboard_models.dart';
import '../services/admin_service.dart';
import '../services/session_manager.dart';
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
  const AdminDashboardScreen({Key? key}) : super(key: key);

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _adminService = AdminService();
  int _currentNavIndex = 0;
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedTimeline = 'இன்று (Today)';
  AdminDashboardMetrics _metrics = AdminDashboardMetrics();

  final List<Map<String, dynamic>> _pendingFarmers = [
    {
      'id': 'farmer-001',
      'name': 'சுப்பிரமணியன் கே. (Subramanian K.)',
      'location': 'தஞ்சாவூர் (Thanjavur)',
      'crop': 'பொன்னி நெல் - 12 ஏக்கர்',
      'docs': 'ஆதார் & பட்டா சமர்ப்பிக்கப்பட்டது',
    },
    {
      'id': 'farmer-002',
      'name': 'மாரியப்பன் ஆர். (Mariappan R.)',
      'location': 'மதுரை (Madurai)',
      'crop': 'நாட்டுத் தக்காளி - 5 ஏக்கர்',
      'docs': 'வங்கி கணக்கு புத்தகம் சரிபார்க்கப்பட்டது',
    },
  ];

  final List<Map<String, dynamic>> _recentOrders = [
    {
      'num': 'VY-8921',
      'buyer': 'சென்னை ஆர்கானிக்ஸ் (Chennai Organics)',
      'farmer': 'முருகன் கே. (தஞ்சை)',
      'crop': 'பொன்னி நெல் • 50 Quintals',
      'amount': '₹1,12,500',
      'status': 'CONFIRMED',
      'color': AppTheme.successGreen,
    },
    {
      'num': 'VY-8920',
      'buyer': 'கோவை ஃப்ரெஷ் (Kovai Fresh)',
      'farmer': 'செந்தில் குமார் (திண்டுக்கல்)',
      'crop': 'நாட்டுத் தக்காளி • 800 Kg',
      'amount': '₹22,400',
      'status': 'PAID',
      'color': Colors.blue,
    },
    {
      'num': 'VY-8919',
      'buyer': 'ஈரோடு மசாலா பிரைவேட் லிமிடெட்',
      'farmer': 'ராமசாமி பி. (ஈரோடு)',
      'crop': 'விரலி மஞ்சள் • 20 Quintals',
      'amount': '₹2,70,000',
      'status': 'PENDING',
      'color': AppTheme.warningOrange,
    },
  ];

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
      final data = await _adminService.fetchDashboardMetrics();
      if (mounted) {
        setState(() {
          _metrics = data;
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

  void _onBottomNavTapped(int index) {
    if (index == _currentNavIndex) return;
    switch (index) {
      case 0:
        // Overview
        break;
      case 1:
        // Farmers
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
                        onSelected: (_) => setState(() => _selectedTimeline = period),
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
                            subtitle: '+18% இந்த வாரம்',
                            trendText: '+18%',
                            icon: Icons.receipt_long,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StatsKpiCard(
                            title: session.isTamil ? 'மொத்த விற்பனை (GMV)' : 'Gross Sales',
                            value: _metrics.totalSalesDisplay,
                            subtitle: '+24% வளர்ச்சி',
                            trendText: '+24%',
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
                            subtitle: '92.3% பகிர்ந்தளிக்கப்பட்டது',
                            icon: Icons.account_balance_wallet,
                            iconColor: AppTheme.primaryGreen,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StatsKpiCard(
                            title: session.isTamil ? 'தள வருவாய் (Commission)' : 'Platform Commission',
                            value: _metrics.totalPlatformCommissionDisplay,
                            subtitle: '7.7% நிகர வருவாய்',
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          session.isTamil ? 'விவசாயிகள் சரிபார்ப்பு' : 'Farmer KYC Verification',
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
                        'பயிர்: ${f['crop']}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                      ),
                      Text(
                        'ஆவணங்கள்: ${f['docs']}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () async {
                              final farmerId = f['id'] as String? ?? 'demo-id';
                              try {
                                await _adminService.rejectFarmer(farmerId, 'Verification documents incomplete');
                                if (mounted) {
                                  setState(() => _pendingFarmers.remove(f));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('விண்ணப்பம் நிராகரிக்கப்பட்டது.')),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('நிராகரிப்பில் பிழை: $e'),
                                      backgroundColor: AppTheme.errorRed,
                                    ),
                                  );
                                }
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.errorRed,
                              side: const BorderSide(color: AppTheme.errorRed),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                            child: const Text('நிராகரி • Reject', style: TextStyle(fontSize: 11)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () async {
                              final farmerId = f['id'] as String? ?? 'demo-id';
                              try {
                                await _adminService.approveFarmer(farmerId);
                                if (mounted) {
                                  setState(() => _pendingFarmers.remove(f));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('விவசாயி கணக்கு அங்கீகரிக்கப்பட்டது!'),
                                      backgroundColor: AppTheme.primaryGreen,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('அங்கீகாரத்தில் பிழை: $e'),
                                      backgroundColor: AppTheme.errorRed,
                                    ),
                                  );
                                }
                              }
                            },
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
