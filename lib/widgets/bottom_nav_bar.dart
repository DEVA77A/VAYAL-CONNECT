import 'package:flutter/material.dart';
import '../models/auth_models.dart';
import '../services/session_manager.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/commerce_strings.dart';
import '../screens/market_prices_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/addresses_screen.dart';
import '../screens/farmer_application_screen.dart';
import '../screens/farmer_bank_screen.dart';
import '../screens/farmer_home_screen.dart';
import '../screens/admin_dashboard_screen.dart';

/// Clean, role-aware bottom navigation bar with compact destinations and More menu.
class VayalBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const VayalBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final session = SessionManager();
    final role = session.activeRole;

    List<BottomNavigationBarItem> items;
    switch (role) {
      case AppRole.farmer:
        items = [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard),
            label: S.t('Dashboard'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.agriculture_outlined),
            activeIcon: const Icon(Icons.agriculture),
            label: S.t('My Crops'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.receipt_long_outlined),
            activeIcon: const Icon(Icons.receipt_long),
            label: S.t('Orders'),
          ),
        ];
        break;

      case AppRole.buyer:
        items = [
          BottomNavigationBarItem(
            icon: const Icon(Icons.storefront_outlined),
            activeIcon: const Icon(Icons.storefront),
            label: S.t('Market'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.receipt_long_outlined),
            activeIcon: const Icon(Icons.receipt_long),
            label: S.t('Orders'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person_outline),
            activeIcon: const Icon(Icons.person),
            label: S.t('Profile'),
          ),
        ];
        break;

      case AppRole.admin:
        items = [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard),
            label: S.t('Overview'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.agriculture_outlined),
            activeIcon: const Icon(Icons.agriculture),
            label: S.t('Farmers'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.receipt_long_outlined),
            activeIcon: const Icon(Icons.receipt_long),
            label: S.t('Orders'),
          ),
        ];
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
              color: AppTheme.cardBorder.withOpacity(0.8), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: currentIndex.clamp(0, items.length - 1),
          onTap: onTap,
          items: items,
          selectedItemColor: AppTheme.primaryGreen,
          unselectedItemColor: AppTheme.textSecondary,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          elevation: 0,
        ),
      ),
    );
  }

  /// Displays the role-appropriate secondary destinations in a clean bottom sheet
  static void showMoreMenu(BuildContext context, {AppRole? role}) {
    final currentRole = role ?? SessionManager().activeRole;
    final session = SessionManager();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          S.t('More Options'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          session.currentUser?.name ?? '',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: AppTheme.textSecondary),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                if (currentRole == AppRole.farmer) ...[
                  _MoreTile(
                    icon: Icons.price_change_outlined,
                    title: S.t('Market prices'),
                    subtitle: S.t('Verified APMC mandi rates'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const MarketPricesScreen()));
                    },
                  ),
                  _MoreTile(
                    icon: Icons.bar_chart_outlined,
                    title: S.t('Sales'),
                    subtitle: S.t('Monthly earnings & volume'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const FarmerSalesScreen()));
                    },
                  ),
                  _MoreTile(
                    icon: Icons.account_balance_outlined,
                    title: S.t('Payouts'),
                    subtitle: S.t('Bank account transfer records'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const FarmerPayoutsScreen()));
                    },
                  ),
                  _MoreTile(
                    icon: Icons.analytics_outlined,
                    title: S.t('Verified Mandi Prices'),
                    subtitle: S.t('Daily reference commodity prices'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const MarketPricesScreen()));
                    },
                  ),
                  _MoreTile(
                    icon: Icons.account_balance_wallet_outlined,
                    title: S.t('Bank Details'),
                    subtitle: S.t('Manage payout account'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const FarmerBankScreen()));
                    },
                  ),
                  _MoreTile(
                    icon: Icons.assignment_ind_outlined,
                    title: S.t('Farmer Application'),
                    subtitle: S.t('Identity & verification'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const FarmerApplicationScreen()));
                    },
                  ),
                  _MoreTile(
                    icon: Icons.person_outline,
                    title: S.t('Profile & Settings'),
                    subtitle: S.t('Language and account settings'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ProfileScreen()));
                    },
                  ),
                ] else if (currentRole == AppRole.buyer) ...[
                  _MoreTile(
                    icon: Icons.location_on_outlined,
                    title: S.t('Delivery Addresses'),
                    subtitle: S.t('Manage shipping locations'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AddressesScreen()));
                    },
                  ),
                  _MoreTile(
                    icon: Icons.analytics_outlined,
                    title: S.t('Verified Mandi Prices'),
                    subtitle: S.t('Daily reference commodity prices'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const MarketPricesScreen()));
                    },
                  ),
                  _MoreTile(
                    icon: Icons.person_outline,
                    title: S.t('Profile & Settings'),
                    subtitle: S.t('Language, phone, and account'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ProfileScreen()));
                    },
                  ),
                ] else if (currentRole == AppRole.admin) ...[
                  _MoreTile(
                    icon: Icons.people_outline,
                    title: S.t('Buyers'),
                    subtitle: S.t('Registered buyers & procurement'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AdminBuyersScreen()));
                    },
                  ),
                  _MoreTile(
                    icon: Icons.percent_outlined,
                    title: S.t('Commission'),
                    subtitle: S.t('Marketplace platform fee'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  CommissionScreen(api: ApiClient())));
                    },
                  ),
                  _MoreTile(
                    icon: Icons.account_balance_wallet_outlined,
                    title: S.t('Payouts'),
                    subtitle: S.t('Farmer remittance history'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  AdminPayoutsScreen(api: ApiClient())));
                    },
                  ),
                  _MoreTile(
                    icon: Icons.person_outline,
                    title: S.t('Profile & Settings'),
                    subtitle: S.t('Administrator settings'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ProfileScreen()));
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.softGreen,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppTheme.primaryGreen, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
