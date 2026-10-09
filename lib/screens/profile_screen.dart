import 'package:flutter/material.dart';
import '../models/auth_models.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/demo_banner.dart';
import '../widgets/vayal_app_bar.dart';
import 'auth_gateway_screen.dart';
import 'farmer_home_screen.dart';
import 'buyer_home_screen.dart';
import 'admin_dashboard_screen.dart';

/// Profile & Settings Screen
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  void _switchRoleAndNavigate(AppRole role) {
    SessionManager().setDemoRole(role);
    Widget target;
    switch (role) {
      case AppRole.farmer:
        target = const FarmerHomeScreen();
        break;
      case AppRole.buyer:
        target = const BuyerHomeScreen();
        break;
      case AppRole.admin:
        target = const AdminDashboardScreen();
        break;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => target),
      (route) => false,
    );
  }

  void _handleLogout() {
    SessionManager().logout();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGatewayScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionManager();
    final user = session.currentUser;

    return Scaffold(
      backgroundColor: AppTheme.backgroundWarm,
      appBar: VayalAppBar(
        showBack: true,
        title: session.isTamil ? 'விவரக்குறிப்பு & கணக்கு' : 'Profile & Account',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Demo Banner
            if (session.isDemoMode) ...[
              const DemoModeBanner(),
              const SizedBox(height: 12),
            ],
            // User Header Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppTheme.softGreen,
                    child: const Icon(Icons.person, size: 36, color: AppTheme.primaryGreen),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? 'பயனர் (User)',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?.phone ?? '+91 98765 43210',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        Text(
                          user?.areaLocation ?? 'Tamil Nadu',
                          style: const TextStyle(fontSize: 12, color: AppTheme.primaryGreen, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Bank Account Security Card (Masked as per security guidelines)
            Container(
              padding: const EdgeInsets.all(16),
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
                      Row(
                        children: [
                          const Icon(Icons.account_balance, color: AppTheme.primaryGreen, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            session.isTamil ? 'வங்கி கணக்கு (Bank Details)' : 'Bank Payout Details',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.softGreen,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'சரிபார்க்கப்பட்டது',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'வங்கி: State Bank of India • தஞ்சாவூர் கிளை',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'கணக்கு எண்: XXXX XXXX 4289 (பாதுகாப்பானது)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Quick Role Switcher for Developer / Evaluator Testing (Demo mode only)
            if (session.isDemoMode) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCream,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  border: Border.all(color: AppTheme.accentGold.withOpacity(0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.swap_horiz, color: AppTheme.accentGold, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          session.isTamil ? 'டெமோ பாத்திரத்தை மாற்று (Role Switch)' : 'Switch Active Demo Persona',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _switchRoleAndNavigate(AppRole.farmer),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: session.activeRole == AppRole.farmer ? AppTheme.primaryGreen : Colors.white,
                              foregroundColor: session.activeRole == AppRole.farmer ? Colors.white : AppTheme.primaryGreen,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            child: const Text('விவசாயி', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _switchRoleAndNavigate(AppRole.buyer),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: session.activeRole == AppRole.buyer ? AppTheme.primaryGreen : Colors.white,
                              foregroundColor: session.activeRole == AppRole.buyer ? Colors.white : AppTheme.primaryGreen,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            child: const Text('வாங்குபவர்', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _switchRoleAndNavigate(AppRole.admin),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: session.activeRole == AppRole.admin ? AppTheme.primaryGreen : Colors.white,
                              foregroundColor: session.activeRole == AppRole.admin ? Colors.white : AppTheme.primaryGreen,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            child: const Text('நிர்வாகி', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Logout Button
            OutlinedButton.icon(
              onPressed: _handleLogout,
              icon: const Icon(Icons.logout, size: 18),
              label: Text(
                session.isTamil ? 'வெளியேறு • Logout' : 'Logout',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.errorRed,
                side: const BorderSide(color: AppTheme.errorRed),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
