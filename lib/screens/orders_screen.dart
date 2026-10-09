import 'package:flutter/material.dart';
import '../models/auth_models.dart';
import '../models/order_models.dart';
import '../services/order_service.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/demo_banner.dart';
import '../widgets/vayal_app_bar.dart';

/// Orders History Screen (Role Scoped)
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({Key? key}) : super(key: key);

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _orderService = OrderService();
  bool _isLoading = true;
  String? _errorMessage;
  List<BuyerOrder> _buyerOrders = [];
  List<FarmerOrder> _farmerOrders = [];

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void dispose() {
    _orderService.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final role = SessionManager().activeRole;

    try {
      if (role == AppRole.buyer) {
        final orders = await _orderService.fetchBuyerOrders();
        if (mounted) setState(() => _buyerOrders = orders);
      } else {
        final orders = await _orderService.fetchFarmerOrders();
        if (mounted) setState(() => _farmerOrders = orders);
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionManager();
    final isBuyer = session.activeRole == AppRole.buyer;

    return Scaffold(
      backgroundColor: AppTheme.backgroundWarm,
      appBar: VayalAppBar(
        showBack: true,
        title: session.isTamil ? 'என் ஆர்டர்கள்' : 'My Orders',
        subtitle: isBuyer
            ? (session.isTamil ? 'கொள்முதல் வரலாறு' : 'Procurement History')
            : (session.isTamil ? 'பட்டுவாடா வரலாறு' : 'Payouts & Deliveries'),
      ),
      body: RefreshIndicator(
        color: AppTheme.primaryGreen,
        onRefresh: _loadOrders,
        child: Column(
          children: [
            if (session.isDemoMode) const DemoModeBanner(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen))
                  : _errorMessage != null
                      ? _buildErrorView(session)
                      : isBuyer
                          ? _buildBuyerOrderList()
                          : _buildFarmerOrderList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(SessionManager session) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, color: AppTheme.errorRed, size: 48),
            const SizedBox(height: 12),
            Text(
              session.isTamil ? 'ஆர்டர் தகவல்களைப் பெறுவதில் பிழை' : 'Failed to fetch orders',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.errorRed),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadOrders,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(session.isTamil ? 'மீண்டும் முயற்சிக்கவும்' : 'Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuyerOrderList() {
    if (_buyerOrders.isEmpty) {
      return _buildEmpty();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _buyerOrders.length,
      itemBuilder: (context, index) {
        final ord = _buyerOrders[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: BorderSide(color: AppTheme.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ஆர்டர் #${ord.orderNumber}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.softGreen,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ord.orderStatus,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${ord.productName} • ${ord.quantity} ${ord.unit}',
                style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'மொத்த தொகை: ${ord.buyerTotalDisplay}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                  ),
                  Text(
                    'பணம்: ${ord.paymentStatus}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFarmerOrderList() {
    if (_farmerOrders.isEmpty) {
      return _buildEmpty();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _farmerOrders.length,
      itemBuilder: (context, index) {
        final ord = _farmerOrders[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: BorderSide(color: AppTheme.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ஆர்டர் #${ord.orderNumber}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: ord.payoutStatus == 'PAID' ? AppTheme.softGreen : AppTheme.goldLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ord.payoutStatus,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: ord.payoutStatus == 'PAID' ? AppTheme.primaryGreen : AppTheme.warningOrange,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${ord.productName} • ${ord.quantity} ${ord.unit}',
                style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
              ),
              if (ord.buyerName != null) ...[
                const SizedBox(height: 2),
                Text(
                  'வாங்குபவர்: ${ord.buyerName}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'பட்டுவாடா: ${ord.farmerTotalPayoutDisplay}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                  ),
                  Text(
                    'நிலை: ${ord.orderStatus}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.receipt_long, size: 48, color: AppTheme.textSecondary),
          SizedBox(height: 12),
          Text(
            'ஆர்டர்கள் எதுவும் இல்லை',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
