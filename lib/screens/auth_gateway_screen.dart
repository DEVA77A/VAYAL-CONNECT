import 'package:flutter/material.dart';
import '../models/auth_models.dart';
import '../services/auth_service.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import 'farmer_home_screen.dart';
import 'buyer_home_screen.dart';
import 'admin_dashboard_screen.dart';

/// VayalConnect Login & Registration Gateway
///
/// Implements Stitch Screen b092d478375940738f19b6ede4f90af3
class AuthGatewayScreen extends StatefulWidget {
  const AuthGatewayScreen({Key? key}) : super(key: key);

  @override
  State<AuthGatewayScreen> createState() => _AuthGatewayScreenState();
}

class _AuthGatewayScreenState extends State<AuthGatewayScreen> {
  final _authService = AuthService();
  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();

  // Login controllers
  final _emailPhoneController = TextEditingController(text: 'farmer@vayalconnect.in');
  final _passwordController = TextEditingController(text: 'Pass1234');

  // Register controllers
  final _regNameController = TextEditingController();
  final _regEmailController = TextEditingController();
  final _regPhoneController = TextEditingController();
  final _regPasswordController = TextEditingController();
  final _regAddressController = TextEditingController();
  final _regLocationController = TextEditingController();
  final _regAgeController = TextEditingController(text: '32');
  String _regGender = 'male';
  AppRole _regRole = AppRole.farmer;

  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _isLoading = false;
  bool _isLoginTab = true;
  String? _errorMessage;


  @override
  void dispose() {
    _emailPhoneController.dispose();
    _passwordController.dispose();
    _regNameController.dispose();
    _regEmailController.dispose();
    _regPhoneController.dispose();
    _regPasswordController.dispose();
    _regAddressController.dispose();
    _regLocationController.dispose();
    _regAgeController.dispose();
    _authService.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _authService.login(
        _emailPhoneController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;
      _navigateToRoleHome(res.user.role);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleRegister() async {
    if (!_registerFormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _regEmailController.text.trim();
      await _authService.register(
        name: _regNameController.text.trim(),
        email: email,
        phone: _regPhoneController.text.trim(),
        password: _regPasswordController.text,
        address: _regAddressController.text.trim(),
        areaLocation: _regLocationController.text.trim(),
        gender: _regGender,
        age: int.tryParse(_regAgeController.text) ?? 25,
      );

      if (!mounted) return;
      _showOtpDialog(email);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showOtpDialog(String email) {
    final otpController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('மின்னஞ்சல் சரிபார்ப்பு (OTP Verification)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('OTP அனுப்பப்பட்ட முகவரி: $email', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                hintText: '6-இலக்க OTP உள்ளிடவும்',
                prefixIcon: Icon(Icons.security),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('ரத்து செய்'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _authService.verifyOtp(email, otpController.text.trim());
                await _authService.selectRole(_regRole);
                if (!mounted) return;
                Navigator.of(ctx).pop();
                _navigateToRoleHome(_regRole);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('சரிபார்ப்பு பிழை: $e'), backgroundColor: AppTheme.errorRed),
                );
              }
            },
            child: const Text('சரிபார்'),
          ),
        ],
      ),
    );
  }

  void _enterDemoMode(AppRole role) {
    SessionManager().enterDemoMode(role);
    _navigateToRoleHome(role);
  }

  void _navigateToRoleHome(AppRole role) {
    Widget home;
    switch (role) {
      case AppRole.farmer:
        home = const FarmerHomeScreen();
        break;
      case AppRole.buyer:
        home = const BuyerHomeScreen();
        break;
      case AppRole.admin:
        home = const AdminDashboardScreen();
        break;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => home),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionManager();

    return Scaffold(
      backgroundColor: AppTheme.backgroundWarm,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Bar: Leaf Emblem & Language Switcher
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.softGreen,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.eco, color: AppTheme.primaryGreen, size: 20),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'தமிழ்நாடு APMC நெட்வொர்க்',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () {
                      setState(() {
                        session.toggleLanguage();
                      });
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.cardBorder, width: 1),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.language, size: 14, color: AppTheme.primaryGreen),
                          const SizedBox(width: 4),
                          Text(
                            session.isTamil ? 'தமிழ்' : 'Eng',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Brand Hero Card
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGreen,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryGreen.withOpacity(0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.agriculture_rounded, size: 34, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      session.isTamil ? 'வயல் Connect' : 'VayalConnect',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      session.isTamil ? '\"நம்ம வயல், நேரடி CONNECT\"' : 'Direct Farmer-to-Buyer Marketplace',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Auth Tab Segmented Switcher
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFEFE9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _isLoginTab = true),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: _isLoginTab ? AppTheme.primaryGreen : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            session.isTamil ? 'உள்நுழைக (Login)' : 'Login',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _isLoginTab ? Colors.white : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _isLoginTab = false),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: !_isLoginTab ? AppTheme.primaryGreen : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            session.isTamil ? 'பதிவு செய் (Register)' : 'Register',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: !_isLoginTab ? Colors.white : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Error Banner
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.errorRed.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 18, color: AppTheme.errorRed),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 12, color: AppTheme.errorRed, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),

              // Form: Login vs Register
              if (_isLoginTab) _buildLoginForm(session) else _buildRegisterForm(session),

              const SizedBox(height: 20),

              // ISOLATED DEMO PREVIEW SECTION
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCream,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accentGold.withOpacity(0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.visibility_outlined, size: 16, color: AppTheme.accentGold),
                        const SizedBox(width: 6),
                        Text(
                          session.isTamil ? 'ஆஃப்லைன் டெமோ முன்னோட்டம் (Demo Preview)' : 'Offline Demo Preview',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      session.isTamil
                          ? 'பரிசோதனைக்காக ஆஃப்லைன் மாதிரி தரவுகளுடன் திரைகளை உடனடியாகப் பார்வையிடவும்.'
                          : 'Explore the full UI experience using isolated sample fixtures without a live backend.',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _enterDemoMode(AppRole.farmer),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              side: const BorderSide(color: AppTheme.primaryGreen),
                            ),
                            child: const Text('🌾 Farmer', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _enterDemoMode(AppRole.buyer),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              side: const BorderSide(color: AppTheme.primaryGreen),
                            ),
                            child: const Text('🛒 Buyer', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _enterDemoMode(AppRole.admin),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              side: const BorderSide(color: AppTheme.primaryGreen),
                            ),
                            child: const Text('🛡️ Admin', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Helpline footer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.support_agent_rounded, size: 24, color: AppTheme.primaryGreen),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.isTamil ? 'உழவர் உதவி மையம் (Toll-Free Kisan Help)' : 'Kisan Support Helpline',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                          const Text(
                            '1800-425-1661',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(SessionManager session) {
    return Form(
      key: _loginFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            session.isTamil ? 'கைபேசி அல்லது மின்னஞ்சல்' : 'Phone or Email',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _emailPhoneController,
            validator: (v) => v == null || v.trim().isEmpty ? 'மின்னஞ்சல் அல்லது கைபேசி எண் உள்ளிடவும்' : null,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.email_outlined, size: 20, color: AppTheme.textSecondary),
              hintText: 'உதாரணம்: farmer@vayalconnect.in',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            session.isTamil ? 'கடவுச்சொல் (Password)' : 'Password',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            validator: (v) => v == null || v.isEmpty ? 'கடவுச்சொல் உள்ளிடவும்' : null,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock_outline, size: 20, color: AppTheme.textSecondary),
              hintText: '••••••••',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _rememberMe,
                      activeColor: AppTheme.primaryGreen,
                      onChanged: (val) => setState(() => _rememberMe = val ?? true),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    session.isTamil ? 'நினைவில் கொள்' : 'Remember me',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
              TextButton(
                onPressed: () {},
                child: Text(
                  session.isTamil ? 'கடவுச்சொல் மறந்ததா?' : 'Forgot Password?',
                  style: const TextStyle(fontSize: 12, color: AppTheme.primaryGreen),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(session.isTamil ? 'உள்நுழைக • Login' : 'Login', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterForm(SessionManager session) {
    return Form(
      key: _registerFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(session.isTamil ? 'முழு பெயர் (Full Name)' : 'Full Name', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextFormField(
            controller: _regNameController,
            validator: (v) => v == null || v.trim().length < 2 ? 'பெயர் குறைந்தது 2 எழுத்துக்கள் இருக்க வேண்டும்' : null,
            decoration: const InputDecoration(hintText: 'எ.கா: சுப்பிரமணியன்'),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(session.isTamil ? 'மின்னஞ்சல் (Email)' : 'Email', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _regEmailController,
                      validator: (v) => v == null || !v.contains('@') ? 'சரியான மின்னஞ்சல் உள்ளிடவும்' : null,
                      decoration: const InputDecoration(hintText: 'farmer@vayal.in'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(session.isTamil ? 'வயது (Age)' : 'Age', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _regAgeController,
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < 18) return '18+';
                        return null;
                      },
                      decoration: const InputDecoration(hintText: '32'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Text(session.isTamil ? 'கைபேசி எண் (Phone)' : 'Phone', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextFormField(
            controller: _regPhoneController,
            validator: (v) => v == null || v.trim().length < 10 ? 'சரியான கைபேசி எண் உள்ளிடவும்' : null,
            decoration: const InputDecoration(hintText: '9876543210'),
          ),
          const SizedBox(height: 10),

          Text(session.isTamil ? 'கடவுச்சொல் (Password)' : 'Password', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextFormField(
            controller: _regPasswordController,
            obscureText: _obscurePassword,
            validator: (v) {
              if (v == null || v.length < 8) return 'குறைந்தது 8 எழுத்துக்கள் தேவை';
              if (!v.contains(RegExp(r'[A-Z]'))) return 'ஒரு பெரிய எழுத்து (Uppercase) தேவை';
              if (!v.contains(RegExp(r'[0-9]'))) return 'ஒரு எண் (Digit) தேவை';
              return null;
            },
            decoration: InputDecoration(
              hintText: 'குறைந்தது 8 எழுத்துக்கள் (A-Z & 0-9)',
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 20),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 10),

          Text(session.isTamil ? 'முகவரி (Address)' : 'Address', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextFormField(
            controller: _regAddressController,
            validator: (v) => v == null || v.trim().length < 5 ? 'முகவரி உள்ளிடவும்' : null,
            decoration: const InputDecoration(hintText: '12 மேலத்தெரு, பாபநாசம்'),
          ),
          const SizedBox(height: 10),

          Text(session.isTamil ? 'பகுதி / மாவட்டம் (Location)' : 'Location / District', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextFormField(
            controller: _regLocationController,
            validator: (v) => v == null || v.trim().length < 2 ? 'மாவட்டத்தை உள்ளிடவும்' : null,
            decoration: const InputDecoration(hintText: 'தஞ்சாவூர் (Thanjavur)'),
          ),
          const SizedBox(height: 10),

          // Role Selection for Registration
          Text(session.isTamil ? 'கணக்கு வகை (Role)' : 'Role', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('🌾 விவசாயி (Farmer)'),
                  selected: _regRole == AppRole.farmer,
                  onSelected: (_) => setState(() => _regRole = AppRole.farmer),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Text('🛒 வாங்குபவர் (Buyer)'),
                  selected: _regRole == AppRole.buyer,
                  onSelected: (_) => setState(() => _regRole = AppRole.buyer),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          ElevatedButton(
            onPressed: _isLoading ? null : _handleRegister,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(session.isTamil ? 'பதிவு செய் & OTP பெறு' : 'Register & Get OTP', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
