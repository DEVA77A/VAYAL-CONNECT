import 'package:flutter/material.dart';
import '../models/auth_models.dart';
import '../services/api_client.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import '../utils/commerce_strings.dart';
import 'vayal_logo.dart';
import '../screens/auth_gateway_screen.dart';
import '../screens/farmer_home_screen.dart';
import '../screens/add_product_screen.dart';
import '../screens/farmer_application_screen.dart';
import '../screens/farmer_bank_screen.dart';
import '../screens/market_prices_screen.dart';
import '../screens/orders_screen.dart';
import '../screens/buyer_home_screen.dart';
import '../screens/addresses_screen.dart';
import '../screens/admin_dashboard_screen.dart';
import '../screens/profile_screen.dart';

/// Top-left Material navigation drawer for Farmer, Buyer, and Admin roles.
class VayalNavigationDrawer extends StatelessWidget {
  final String currentSection;

  const VayalNavigationDrawer({
    super.key,
    required this.currentSection,
  });

  @override
  Widget build(BuildContext context) {
    final session = SessionManager();
    final role = session.activeRole;
    final user = session.currentUser;

    String roleLabel;
    IconData roleIcon;
    switch (role) {
      case AppRole.farmer:
        roleLabel = session.isTamil ? 'விவசாயி' : 'Farmer';
        roleIcon = Icons.agriculture;
        break;
      case AppRole.buyer:
        roleLabel = session.isTamil ? 'வாங்குபவர்' : 'Buyer';
        roleIcon = Icons.storefront;
        break;
      case AppRole.admin:
        roleLabel = session.isTamil ? 'நிர்வாகி' : 'Admin';
        roleIcon = Icons.admin_panel_settings;
        break;
    }

    return Drawer(
      backgroundColor: AppTheme.backgroundWarm,
      child: Column(
        children: [
          _buildDrawerHeader(context, session, user, roleLabel, roleIcon),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                if (role == AppRole.farmer) ..._buildFarmerItems(context),
                if (role == AppRole.buyer) ..._buildBuyerItems(context),
                if (role == AppRole.admin) ..._buildAdminItems(context),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.cardBorder),
          _buildDrawerFooter(context, session),
        ],
      ),
    );
  }

  Widget _buildDrawerHeader(
    BuildContext context,
    SessionManager session,
    dynamic user,
    String roleLabel,
    IconData roleIcon,
  ) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 16,
        16,
        18,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryGreen, AppTheme.primaryDarkGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const VayalLogo(width: 40, height: 40),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.isTamil ? 'வயல் Connect' : 'VayalConnect',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(roleIcon, size: 12, color: AppTheme.softGreen),
                          const SizedBox(width: 4),
                          Text(
                            roleLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            user?.name ?? (session.isTamil ? 'பயனர்' : 'User'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            user?.phone ?? user?.email ?? '',
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.softGreen,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFarmerItems(BuildContext context) {
    return [
      _DrawerItem(
        icon: Icons.dashboard_outlined,
        activeIcon: Icons.dashboard,
        title: S.t('Dashboard'),
        isSelected: currentSection == 'dashboard',
        onTap: () {
          Navigator.pop(context);
          if (currentSection != 'dashboard') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const FarmerHomeScreen()),
            );
          }
        },
      ),
      _DrawerItem(
        icon: Icons.agriculture_outlined,
        activeIcon: Icons.agriculture,
        title: S.t('My Crops'),
        isSelected: currentSection == 'my_crops',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyCropsScreen()),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.add_photo_alternate_outlined,
        activeIcon: Icons.add_photo_alternate,
        title: S.t('Add Crop'),
        isSelected: currentSection == 'add_crop',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddProductScreen()),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.price_change_outlined,
        activeIcon: Icons.price_change,
        title: S.t('Market Prices'),
        isSelected: currentSection == 'market_prices',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MarketPricesScreen()),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.receipt_long_outlined,
        activeIcon: Icons.receipt_long,
        title: S.t('Orders'),
        isSelected: currentSection == 'orders',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OrdersScreen()),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.bar_chart_outlined,
        activeIcon: Icons.bar_chart,
        title: S.t('Sales & Earnings'),
        isSelected: currentSection == 'sales',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FarmerSalesScreen()),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.account_balance_outlined,
        activeIcon: Icons.account_balance,
        title: S.t('Payouts'),
        isSelected: currentSection == 'payouts',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FarmerPayoutsScreen()),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.account_balance_wallet_outlined,
        activeIcon: Icons.account_balance_wallet,
        title: S.t('Bank Details'),
        isSelected: currentSection == 'bank_details',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FarmerBankScreen()),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.assignment_ind_outlined,
        activeIcon: Icons.assignment_ind,
        title: S.t('Farmer Application'),
        isSelected: currentSection == 'farmer_application',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FarmerApplicationScreen()),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.location_on_outlined,
        activeIcon: Icons.location_on,
        title: S.t('Delivery Addresses'),
        isSelected: currentSection == 'addresses',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddressesScreen()),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        title: S.t('Profile & Settings'),
        isSelected: currentSection == 'profile',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          );
        },
      ),
    ];
  }

  List<Widget> _buildBuyerItems(BuildContext context) {
    return [
      _DrawerItem(
        icon: Icons.storefront_outlined,
        activeIcon: Icons.storefront,
        title: S.t('Marketplace'),
        isSelected: currentSection == 'market',
        onTap: () {
          Navigator.pop(context);
          if (currentSection != 'market') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const BuyerHomeScreen()),
            );
          }
        },
      ),
      _DrawerItem(
        icon: Icons.search_outlined,
        activeIcon: Icons.search,
        title: S.t('Browse Products'),
        isSelected: currentSection == 'browse',
        onTap: () {
          Navigator.pop(context);
          if (currentSection != 'market') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const BuyerHomeScreen()),
            );
          }
        },
      ),
      _DrawerItem(
        icon: Icons.receipt_long_outlined,
        activeIcon: Icons.receipt_long,
        title: S.t('Orders'),
        isSelected: currentSection == 'orders',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OrdersScreen()),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.location_on_outlined,
        activeIcon: Icons.location_on,
        title: S.t('Delivery Addresses'),
        isSelected: currentSection == 'addresses',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddressesScreen()),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.price_change_outlined,
        activeIcon: Icons.price_change,
        title: S.t('Market Prices'),
        isSelected: currentSection == 'market_prices',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MarketPricesScreen()),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        title: S.t('Profile & Settings'),
        isSelected: currentSection == 'profile',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          );
        },
      ),
    ];
  }

  List<Widget> _buildAdminItems(BuildContext context) {
    final api = ApiClient();
    return [
      _DrawerItem(
        icon: Icons.dashboard_outlined,
        activeIcon: Icons.dashboard,
        title: S.t('Overview'),
        isSelected: currentSection == 'overview',
        onTap: () {
          Navigator.pop(context);
          if (currentSection != 'overview') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
            );
          }
        },
      ),
      _DrawerItem(
        icon: Icons.agriculture_outlined,
        activeIcon: Icons.agriculture,
        title: S.t('Farmers'),
        isSelected: currentSection == 'farmers',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    AdminFarmersScreen(api: api, initialStatus: '')),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.hourglass_top_outlined,
        activeIcon: Icons.hourglass_top,
        title: S.t('Farmer Applications'),
        isSelected: currentSection == 'farmer_applications',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    AdminFarmersScreen(api: api, initialStatus: 'PENDING')),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.people_outline,
        activeIcon: Icons.people,
        title: S.t('Buyers'),
        isSelected: currentSection == 'buyers',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminBuyersScreen()),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.inventory_2_outlined,
        activeIcon: Icons.inventory_2,
        title: S.t('Products & Listings'),
        isSelected: currentSection == 'listings',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => AdminListingsScreen(api: api)),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.receipt_long_outlined,
        activeIcon: Icons.receipt_long,
        title: S.t('Orders'),
        isSelected: currentSection == 'orders',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OrdersScreen()),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.percent_outlined,
        activeIcon: Icons.percent,
        title: S.t('Commission Management'),
        isSelected: currentSection == 'commission',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => CommissionScreen(api: api)),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.account_balance_wallet_outlined,
        activeIcon: Icons.account_balance_wallet,
        title: S.t('Payouts'),
        isSelected: currentSection == 'payouts',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => AdminPayoutsScreen(api: api)),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.price_change_outlined,
        activeIcon: Icons.price_change,
        title: S.t('Market Prices'),
        isSelected: currentSection == 'market_prices',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MarketPricesScreen()),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        title: S.t('Profile & Settings'),
        isSelected: currentSection == 'profile',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          );
        },
      ),
    ];
  }

  Widget _buildDrawerFooter(BuildContext context, SessionManager session) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              leading: const Icon(Icons.language_rounded,
                  color: AppTheme.primaryGreen, size: 22),
              title: Text(
                session.isTamil ? 'English' : 'தமிழ்',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.softGreen,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.5)),
                ),
                child: Text(
                  session.isTamil ? 'Switch' : 'மாற்று',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryDarkGreen,
                  ),
                ),
              ),
              onTap: () async {
                try {
                  await session.toggleLanguagePersisted();
                } catch (_) {}
              },
            ),
            ListTile(
              dense: true,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              leading: const Icon(Icons.logout_rounded,
                  color: AppTheme.errorRed, size: 22),
              title: Text(
                S.t('Logout'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.errorRed,
                ),
              ),
              onTap: () => _confirmLogout(context, session),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context, SessionManager session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('Confirm Logout')),
        content: Text(S.t('Are you sure you want to log out?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.t('Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.errorRed),
            onPressed: () async {
              Navigator.pop(ctx);
              Navigator.pop(context); // Close drawer
              await session.logout();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AuthGatewayScreen()),
                  (route) => false,
                );
              }
            },
            child: Text(S.t('Logout')),
          ),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.activeIcon,
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected ? AppTheme.softGreen : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(color: AppTheme.primaryGreen.withOpacity(0.5))
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  size: 22,
                  color: isSelected
                      ? AppTheme.primaryDarkGreen
                      : AppTheme.textSecondary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected
                          ? AppTheme.primaryDarkGreen
                          : AppTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppTheme.primaryDarkGreen,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
