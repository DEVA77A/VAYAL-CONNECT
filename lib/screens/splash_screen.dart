import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/session_manager.dart';
import '../utils/localization.dart';
import '../theme/app_theme.dart';
import '../widgets/vayal_logo.dart';
import 'auth_gateway_screen.dart';
import 'farmer_home_screen.dart';
import 'buyer_home_screen.dart';
import 'admin_dashboard_screen.dart';
import 'add_product_screen.dart';
import '../models/auth_models.dart';

/// Splash & Brand Entry Screen
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 0.65, curve: Curves.easeIn)),
    );

    _scaleAnimation = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 0.65, curve: Curves.easeOutCubic)),
    );

    _controller.forward();

    // Auto navigate after short splash
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      _navigateToNext();
    });
  }

  Future<void> _navigateToNext() async {
    final session = SessionManager();
    Widget target;

    if (session.isAuthenticated) {
      final p = await SharedPreferences.getInstance();
      final pendingScreen = p.getString('vayal_pending_camera_screen');

      switch (session.activeRole) {
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

      if (!mounted) return;

      if (session.activeRole == AppRole.farmer && pendingScreen == 'add_product') {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => target,
            transitionDuration: Duration.zero,
          ),
        );
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddProductScreen()),
        );
        return;
      }
    } else {
      target = const AuthGatewayScreen();
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => target,
        transitionsBuilder: (context, animation, __, child) {
          if (MediaQuery.disableAnimationsOf(context)) return child;
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: AppTheme.motionStandard,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: AppTheme.deepGreen,
      body: SafeArea(
          child: Center(
              child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Opacity(
                  opacity: reducedMotion ? 1 : _fadeAnimation.value,
                  child: Transform.scale(
                      scale: reducedMotion ? 1 : _scaleAnimation.value,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const VayalLogo(width: 240, height: 240),
                        const SizedBox(height: 32),
                        Text(VayalStrings.appName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 30,
                                height: 1.3,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                        const SizedBox(height: 12),
                        Text(VayalStrings.tagline,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 15,
                                height: 1.5,
                                color: Color(0xFFDDEBDF))),
                        const SizedBox(height: 32),
                        Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                                color: AppTheme.earthBrown,
                                borderRadius: BorderRadius.circular(4))),
                      ])),
                )),
      ))),
    );
  }
}
