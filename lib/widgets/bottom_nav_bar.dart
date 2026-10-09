import 'package:flutter/material.dart';
import '../models/auth_models.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';

/// Role-aware bottom navigation bar matching Stitch Design System
class VayalBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const VayalBottomNavBar({
    Key? key,
    required this.currentIndex,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final session = SessionManager();
    final role = session.activeRole;

    List<BottomNavigationBarItem> items;
    switch (role) {
      case AppRole.farmer:
        items = [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home_outlined),
            activeIcon: const Icon(Icons.home),
            label: session.isTamil ? 'முகப்பு' : 'Home',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.inventory_2_outlined),
            activeIcon: const Icon(Icons.inventory_2),
            label: session.isTamil ? 'பயிர்கள்' : 'My Crops',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.analytics_outlined),
            activeIcon: const Icon(Icons.analytics),
            label: session.isTamil ? 'மண்டி' : 'Mandi Rates',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.receipt_long_outlined),
            activeIcon: const Icon(Icons.receipt_long),
            label: session.isTamil ? 'ஆர்டர்கள்' : 'Orders',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person_outline),
            activeIcon: const Icon(Icons.person),
            label: session.isTamil ? 'கணக்கு' : 'Profile',
          ),
        ];
        break;

      case AppRole.buyer:
        items = [
          BottomNavigationBarItem(
            icon: const Icon(Icons.storefront_outlined),
            activeIcon: const Icon(Icons.storefront),
            label: session.isTamil ? 'சந்தை' : 'Market',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.analytics_outlined),
            activeIcon: const Icon(Icons.analytics),
            label: session.isTamil ? 'மண்டி' : 'Mandi Rates',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.shopping_bag_outlined),
            activeIcon: const Icon(Icons.shopping_bag),
            label: session.isTamil ? 'ஆர்டர்கள்' : 'Orders',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person_outline),
            activeIcon: const Icon(Icons.person),
            label: session.isTamil ? 'கணக்கு' : 'Profile',
          ),
        ];
        break;

      case AppRole.admin:
        items = [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard),
            label: session.isTamil ? 'மேற்பார்வை' : 'Overview',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.group_outlined),
            activeIcon: const Icon(Icons.group),
            label: session.isTamil ? 'விவசாயிகள்' : 'Farmers',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.receipt_outlined),
            activeIcon: const Icon(Icons.receipt),
            label: session.isTamil ? 'ஆர்டர்கள்' : 'Orders',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.admin_panel_settings_outlined),
            activeIcon: const Icon(Icons.admin_panel_settings),
            label: session.isTamil ? 'நிர்வாகம்' : 'Admin',
          ),
        ];
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppTheme.cardBorder.withOpacity(0.8), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex.clamp(0, items.length - 1),
        onTap: onTap,
        items: items,
        selectedItemColor: AppTheme.primaryGreen,
        unselectedItemColor: AppTheme.textSecondary,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
    );
  }
}
