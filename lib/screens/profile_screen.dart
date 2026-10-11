import 'package:flutter/material.dart';
import '../models/auth_models.dart';
import '../services/session_manager.dart';
import '../utils/localization.dart';
import '../services/auth_service.dart';
import '../services/farmer_service.dart';
import '../theme/app_theme.dart';
import '../widgets/demo_banner.dart';
import '../widgets/vayal_app_bar.dart';
import 'auth_gateway_screen.dart';
import 'farmer_application_screen.dart';
import 'farmer_bank_screen.dart';
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
  final _authService = AuthService();
  final _farmerService = FarmerService();
  late Future<Map<String, dynamic>>? _bank;
  bool _securityBusy = false;
  @override
  void initState() {
    super.initState();
    final session = SessionManager();
    _bank = !session.isDemoMode && session.activeRole == AppRole.farmer ? _farmerService.fetchBankDetails() : null;
  }
  @override
  void dispose() { _authService.dispose(); _farmerService.dispose(); super.dispose(); }
  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final key = GlobalKey<FormState>();
    final submit = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(VayalStrings.changePassword),
      content: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: current, obscureText: true, decoration: const InputDecoration(labelText: 'Current password'), validator: (v) => v == null || v.isEmpty ? 'Required' : null),
        TextFormField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'New password'), validator: (v) => v == null || v.length < 8 || v.length > 128 || !RegExp(r'[A-Z]').hasMatch(v) || !RegExp(r'[0-9]').hasMatch(v) ? '8-128 characters, uppercase and a number' : null),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('Save'))],
    ));
    if (submit != true || !mounted) return;
    setState(() => _securityBusy = true);
    try {
      await _authService.changePassword(current.text, next.text);
      if (mounted) _finishLogout();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to change password. Check your current password and requirements.')));
    } finally { if (mounted) setState(() => _securityBusy = false); }
  }

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

  Future<void> _handleLogout() async {
    if (_securityBusy) return;
    setState(() => _securityBusy = true);
    bool serverConfirmed = true;
    try { if (!SessionManager().isDemoMode) await _authService.logout(); }
    catch (_) { serverConfirmed = false; }
    if (!mounted) return;
    if (!serverConfirmed) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signed out on this device. Server session revocation could not be confirmed.')));
    _finishLogout();
  }

  void _finishLogout() {
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
                          user?.phone ?? '',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        Text(
                          user?.areaLocation ?? '',
                          style: const TextStyle(fontSize: 12, color: AppTheme.primaryGreen, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (!session.isDemoMode && session.activeRole == AppRole.farmer) OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FarmerApplicationScreen())),
              icon: const Icon(Icons.agriculture), label: const Text('Farmer application / Approval status')),
            if (_bank != null) OutlinedButton.icon(onPressed: () async {
              final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const FarmerBankScreen()));
              if (saved == true && mounted) setState(() => _bank = _farmerService.fetchBankDetails());
            }, icon: const Icon(Icons.account_balance), label: const Text('Add / replace bank payout details')),
            if (_bank != null) FutureBuilder<Map<String, dynamic>>(
              future: _bank,
              builder: (context, snapshot) => Card(child: Padding(padding: const EdgeInsets.all(16), child:
                snapshot.connectionState != ConnectionState.done ? const LinearProgressIndicator() :
                snapshot.hasError ? const Text('Unable to load bank details. Please retry later.') :
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Bank payout details', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(snapshot.data?['bank_name'] as String? ?? 'Not configured'),
                  Text(snapshot.data?['account_number_masked'] as String? ?? ''),
                  Text(snapshot.data?['bank_details_verified'] == true ? 'Verified' : 'Not verified'),
                ]))),
            ),
            if (!session.isDemoMode) OutlinedButton.icon(
              onPressed: _securityBusy ? null : _changePassword,
              icon: const Icon(Icons.password), label: Text(VayalStrings.changePassword)),
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
              onPressed: _securityBusy ? null : _handleLogout,
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
