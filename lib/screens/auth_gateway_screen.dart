import 'package:flutter/material.dart';
import '../models/auth_models.dart';
import '../services/auth_service.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import '../utils/localization.dart';
import 'farmer_home_screen.dart';
import 'buyer_home_screen.dart';
import 'admin_dashboard_screen.dart';
import '../config/api_config.dart';

/// VayalConnect Mobile Authentication & Login Gateway
///
/// Redesigned to provide a clean, minimal, mobile-first login experience:
/// - Opens directly into the Login view (no competing tabs)
/// - Default language: English, with seamless toggle to Tamil
/// - Dynamic server IP configuration support for LAN testing
/// - Robust network timeout & credential error handling
/// - Unobtrusive, separate entry points for Registration, Forgot Password, and Offline Demo
class AuthGatewayScreen extends StatefulWidget {
  final AuthService? authService;
  const AuthGatewayScreen({super.key, this.authService});

  @override
  State<AuthGatewayScreen> createState() => _AuthGatewayScreenState();
}

class _AuthGatewayScreenState extends State<AuthGatewayScreen> {
  late final _authService = widget.authService ?? AuthService();
  final _loginFormKey = GlobalKey<FormState>();

  // Login controllers
  final _emailPhoneController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailPhoneController.dispose();
    _passwordController.dispose();
    _authService.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (_isLoading) return; // Prevent duplicate concurrent submissions
    if (!_loginFormKey.currentState!.validate()) return;

    // Unfocus keyboard
    FocusScope.of(context).unfocus();

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
      if (!res.user.hasAssignedRole) {
        final role = await _chooseRegistrationRole();
        if (role == null) { SessionManager().logout(); return; }
        await _authService.selectRole(role);
        final confirmed = await _authService.login(_emailPhoneController.text, _passwordController.text);
        if (!mounted) return;
        _navigateToRoleHome(confirmed.user.role);
      } else {
        _navigateToRoleHome(res.user.role);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<AppRole?> _chooseRegistrationRole() => showDialog<AppRole>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Choose your account role'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, AppRole.farmer), child: const Text('Farmer')),
        TextButton(onPressed: () => Navigator.pop(ctx, AppRole.buyer), child: const Text('Buyer')),
      ],
    ),
  );

  Future<void> _resumeVerification() async {
    if (_isLoading) return;
    final role = await _chooseRegistrationRole();
    if (role == null || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await _authService.requestOtp(_emailPhoneController.text);
      if (!mounted) return;
      _showOtpVerificationDialog(_emailPhoneController.text.trim(), role, _passwordController.text);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

  void _enterDemoMode(AppRole role) {
    SessionManager().enterDemoMode(role);
    _navigateToRoleHome(role);
  }

  void _showServerConfigDialog() {
    final urlController = TextEditingController(text: ApiConfig.baseUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.dns_rounded, color: AppTheme.primaryGreen),
            SizedBox(width: 8),
            Text('Server IP / URL', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configure the FastAPI backend server URL for local phone testing:',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: InputDecoration(
                hintText: 'https://vayal-connect.onrender.com',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                prefixIcon: const Icon(Icons.link, size: 20),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              ApiConfig.setBaseUrl(urlController.text.trim());
              Navigator.pop(ctx);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Server connected: ${ApiConfig.baseUrl}'),
                  backgroundColor: AppTheme.primaryGreen,
                ),
              );
            },
            child: const Text('Save URL'),
          ),
        ],
      ),
    );
  }

  void _showForgotPasswordSheet() {
    final emailController = TextEditingController(text: _emailPhoneController.text.trim());
    final otpController = TextEditingController();
    final newPasswordController = TextEditingController();
    bool otpSent = false;
    bool isSubmitting = false;
    String? dialogError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.lock_reset, color: AppTheme.primaryGreen),
                          const SizedBox(width: 8),
                          Text(
                            VayalStrings.resetPasswordTitle,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    VayalStrings.resetPasswordSubtitle,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  if (dialogError != null)
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        dialogError!,
                        style: const TextStyle(color: AppTheme.errorRed, fontSize: 12),
                      ),
                    ),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !otpSent,
                    decoration: InputDecoration(
                      labelText: VayalStrings.phoneOrEmail,
                      prefixIcon: const Icon(Icons.email_outlined, size: 20),
                    ),
                  ),
                  if (otpSent) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: VayalStrings.enterOtp,
                        prefixIcon: const Icon(Icons.security, size: 20),
                        hintText: '6-digit OTP',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: newPasswordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: VayalStrings.newPassword,
                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final email = emailController.text.trim();
                            if (email.isEmpty) {
                              setSheetState(() => dialogError = VayalStrings.emailRequired);
                              return;
                            }

                            setSheetState(() {
                              isSubmitting = true;
                              dialogError = null;
                            });

                            if (!otpSent) {
                              try {
                                await _authService.forgotPassword(email);
                                setSheetState(() {
                                  otpSent = true;
                                  isSubmitting = false;
                                });
                              } catch (e) {
                                setSheetState(() {
                                  dialogError = e.toString().replaceFirst('Exception: ', '');
                                  isSubmitting = false;
                                });
                              }
                            } else {
                              final otp = otpController.text.trim();
                              final newPass = newPasswordController.text;
                              if (otp.length < 6 || newPass.length < 8) {
                                setSheetState(() { isSubmitting = false; dialogError = 'Please enter a valid 6-digit OTP and 8+ char password.'; });
                                return;
                              }

                              try {
                                await _authService.resetPassword(
                                  email: email,
                                  otp: otp,
                                  newPassword: newPass,
                                );
                                if (!context.mounted) return;
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Password reset successfully! Please login.'),
                                    backgroundColor: AppTheme.successGreen,
                                  ),
                                );
                              } catch (e) {
                                setSheetState(() {
                                  dialogError = e.toString().replaceFirst('Exception: ', '');
                                  isSubmitting = false;
                                });
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(otpSent ? VayalStrings.resetPasswordBtn : VayalStrings.sendOtp),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showRegistrationSheet() {
    final regFormKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final passwordController = TextEditingController();
    final addressController = TextEditingController();
    final locationController = TextEditingController();
    final ageController = TextEditingController(text: '30');
    AppRole selectedRole = AppRole.farmer;
    bool isSubmitting = false;
    bool accountCreated = false;
    String? regError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.88,
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person_add_rounded, color: AppTheme.primaryGreen),
                          const SizedBox(width: 8),
                          Text(
                            VayalStrings.register,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Form(
                        key: regFormKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (regError != null)
                              Container(
                                padding: const EdgeInsets.all(10),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFEBEE),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  regError!,
                                  style: const TextStyle(color: AppTheme.errorRed, fontSize: 12),
                                ),
                              ),
                            TextFormField(
                              enabled: !accountCreated && !isSubmitting,
                              controller: nameController,
                              validator: (v) => v == null || v.trim().length < 2 ? 'Enter valid name' : null,
                              decoration: const InputDecoration(
                                labelText: 'Full Name',
                                prefixIcon: Icon(Icons.badge_outlined, size: 20),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                              enabled: !accountCreated && !isSubmitting,
                                    controller: emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    validator: (v) => v == null || !v.contains('@') ? 'Valid email required' : null,
                                    decoration: const InputDecoration(
                                      labelText: 'Email Address',
                                      prefixIcon: Icon(Icons.email_outlined, size: 20),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                              enabled: !accountCreated && !isSubmitting,
                                    controller: ageController,
                                    keyboardType: TextInputType.number,
                                    validator: (v) => (int.tryParse(v ?? '') ?? 0) < 18 || (int.tryParse(v ?? '') ?? 0) > 120 ? '18-120' : null,
                                    decoration: const InputDecoration(
                                      labelText: 'Age',
                                      prefixIcon: Icon(Icons.cake_outlined, size: 20),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              enabled: !accountCreated && !isSubmitting,
                              controller: phoneController,
                              keyboardType: TextInputType.phone,
                              validator: (v) => v == null || v.trim().length < 10 ? '10-digit phone required' : null,
                              decoration: const InputDecoration(
                                labelText: 'Phone Number',
                                prefixIcon: Icon(Icons.phone_outlined, size: 20),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              enabled: !accountCreated && !isSubmitting,
                              controller: passwordController,
                              obscureText: true,
                              validator: (v) => v == null || v.length < 8 || !RegExp(r'[A-Z]').hasMatch(v) || !RegExp(r'[0-9]').hasMatch(v) ? '8+ chars, uppercase letter and number' : null,
                              decoration: const InputDecoration(
                                labelText: 'Password',
                                prefixIcon: Icon(Icons.lock_outline, size: 20),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              enabled: !accountCreated && !isSubmitting,
                              controller: addressController,
                              validator: (v) => v == null || v.trim().length < 5 ? 'Address required' : null,
                              decoration: const InputDecoration(
                                labelText: 'Address',
                                prefixIcon: Icon(Icons.home_outlined, size: 20),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              enabled: !accountCreated && !isSubmitting,
                              controller: locationController,
                              validator: (v) => v == null || v.trim().length < 2 ? 'District required' : null,
                              decoration: const InputDecoration(
                                labelText: 'District / Area',
                                prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Select Account Role:',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Text('🌾 Farmer'),
                                    selected: selectedRole == AppRole.farmer,
                                    onSelected: (_) => setSheetState(() => selectedRole = AppRole.farmer),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Text('🛒 Buyer'),
                                    selected: selectedRole == AppRole.buyer,
                                    onSelected: (_) => setSheetState(() => selectedRole = AppRole.buyer),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: isSubmitting
                                  ? null
                                  : () async {
                                      if (!regFormKey.currentState!.validate()) return;
                                      setSheetState(() {
                                        isSubmitting = true;
                                        regError = null;
                                      });

                                      try {
                                        final email = emailController.text.trim();
                                        if (!accountCreated) {
                                        await _authService.register(
                                          name: nameController.text.trim(),
                                          email: email,
                                          phone: phoneController.text.trim(),
                                          password: passwordController.text,
                                          address: addressController.text.trim(),
                                          areaLocation: locationController.text.trim(),
                                          gender: 'other',
                                          age: int.tryParse(ageController.text) ?? 25,
                                        );

                                        accountCreated = true;
                                        }
                                        await _authService.requestOtp(email);
                                        if (!context.mounted) return;
                                        Navigator.pop(ctx);
                                        _showOtpVerificationDialog(email, selectedRole, passwordController.text);
                                      } catch (e) {
                                        setSheetState(() {
                                          regError = e.toString().replaceFirst('Exception: ', '');
                                          isSubmitting = false;
                                        });
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryGreen,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: isSubmitting
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : Text(VayalStrings.register),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showOtpVerificationDialog(String email, AppRole role, String password) {
    final otpController = TextEditingController();
    bool busy = false;
    bool verified = false;
    bool roleAssigned = false;
    String? error;
    DateTime resendAfter = DateTime.now().add(const Duration(seconds: 60));
    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
        title: const Text('Email OTP Verification'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Email provider accepted the OTP email for $email. Check your inbox and spam folder. Delivery may take a few minutes.'),
          if (error != null) Text(error!, style: const TextStyle(color: AppTheme.errorRed)),
          TextField(controller: otpController, enabled: !busy && !verified,
            keyboardType: TextInputType.number, maxLength: 6,
            decoration: const InputDecoration(hintText: 'Enter 6-digit OTP')),
        ]),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: busy || verified ? null : () async {
            if (DateTime.now().isBefore(resendAfter)) {
              update(() => error = 'Please wait 60 seconds between OTP requests.');
              return;
            }
            update(() { busy = true; error = null; });
            try {
              await _authService.requestOtp(email);
              resendAfter = DateTime.now().add(const Duration(seconds: 60));
            } catch (e) {
              if (ctx.mounted) update(() => error = e.toString().replaceFirst('Exception: ', ''));
            } finally {
              if (ctx.mounted) update(() => busy = false);
            }
          }, child: const Text('Resend OTP')),
          ElevatedButton(onPressed: busy ? null : () async {
            if (!verified && !RegExp(r'^\d{6}$').hasMatch(otpController.text.trim())) {
              update(() => error = 'Enter a valid 6-digit OTP.');
              return;
            }
            update(() { busy = true; error = null; });
            try {
              if (!verified) {
                if (!await _authService.verifyOtp(email, otpController.text.trim())) {
                  throw Exception('Email verification was not confirmed.');
                }
                verified = true;
              }
              final initial = await _authService.login(email, password);
              if (!roleAssigned && !initial.user.hasAssignedRole) {
                await _authService.selectRole(role);
                roleAssigned = true;
              }
              final session = await _authService.login(email, password);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _navigateToRoleHome(session.user.role);
            } catch (e) {
              if (ctx.mounted) update(() => error = e.toString().replaceFirst('Exception: ', ''));
            } finally {
              if (ctx.mounted) update(() => busy = false);
            }
          }, child: Text(busy ? 'Please wait...' : verified ? 'Continue' : 'Verify')),
        ],
      )),
    );
  }

  void _showDemoPreviewSheet(SessionManager session) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.preview_rounded, color: AppTheme.accentGold),
                      const SizedBox(width: 8),
                      Text(
                        VayalStrings.offlineDemoPreview,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                VayalStrings.offlineDemoSubtitle,
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _enterDemoMode(AppRole.farmer);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: AppTheme.primaryGreen),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('🌾', style: TextStyle(fontSize: 20)),
                          SizedBox(height: 4),
                          Text('Farmer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _enterDemoMode(AppRole.buyer);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: AppTheme.primaryGreen),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('🛒', style: TextStyle(fontSize: 20)),
                          SizedBox(height: 4),
                          Text('Buyer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _enterDemoMode(AppRole.admin);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: AppTheme.primaryGreen),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('🛡️', style: TextStyle(fontSize: 20)),
                          SizedBox(height: 4),
                          Text('Admin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionManager();

    return Scaffold(
      backgroundColor: AppTheme.backgroundWarm,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 24),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top Compact Bar: Attribution Badge + Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Left Network Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppTheme.softGreen,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.eco, color: AppTheme.primaryGreen, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  VayalStrings.governmentAttribution,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primaryGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Right Controls: Server IP & Language Toggle
                          Row(
                            children: [
                              // Server IP Config Button
                              InkWell(
                                onTap: _showServerConfigDialog,
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: AppTheme.cardBorder),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.dns_rounded, size: 13, color: AppTheme.primaryGreen),
                                      SizedBox(width: 4),
                                      Text(
                                        'IP',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primaryGreen,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Language Selector
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
                                    border: Border.all(color: AppTheme.cardBorder),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.language, size: 14, color: AppTheme.primaryGreen),
                                      const SizedBox(width: 4),
                                      Text(
                                        session.isTamil ? 'English' : 'தமிழ்',
                                        style: const TextStyle(
                                          fontSize: 11,
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
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Brand Hero Section (Compact)
                      Center(
                        child: Column(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryGreen,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primaryGreen.withOpacity(0.2),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(Icons.agriculture_rounded, size: 32, color: Colors.white),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              VayalStrings.appName,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              VayalStrings.tagline,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Error Banner
                      if (_errorMessage?.contains('Email not verified') == true)
                        TextButton(onPressed: _isLoading ? null : _resumeVerification,
                          child: const Text('Verify email / Resend OTP')),
                      if (_errorMessage != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.errorRed.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, size: 20, color: AppTheme.errorRed),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.errorRed,
                                    fontWeight: FontWeight.w500,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Direct Login Form Card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.cardBorder),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _loginFormKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Email / Phone Field
                              Text(
                                VayalStrings.phoneOrEmail,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _emailPhoneController,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return VayalStrings.emailRequired;
                                  }
                                  return null;
                                },
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.mail_outline_rounded, size: 20, color: AppTheme.textSecondary),
                                  hintText: VayalStrings.phoneOrEmailHint,
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Password Field
                              Text(
                                VayalStrings.password,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _handleLogin(),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return VayalStrings.passwordRequired;
                                  }
                                  return null;
                                },
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: AppTheme.textSecondary),
                                  hintText: VayalStrings.passwordHint,
                                  suffixIcon: IconButton(
                                    key: const Key('password_visibility_toggle'),
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                      size: 20,
                                      color: AppTheme.textSecondary,
                                    ),
                                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 10),

                              // Remember Me & Forgot Password Row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: Checkbox(
                                          value: _rememberMe,
                                          activeColor: AppTheme.primaryGreen,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                          onChanged: (val) => setState(() => _rememberMe = val ?? true),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        VayalStrings.rememberMe,
                                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                      ),
                                    ],
                                  ),
                                  TextButton(
                                    onPressed: _showForgotPasswordSheet,
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      VayalStrings.forgotPassword,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.primaryGreen,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 18),

                              // Primary Login Button
                              ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryGreen,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: AppTheme.primaryGreen.withOpacity(0.6),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            VayalStrings.login,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Icon(Icons.arrow_forward_rounded, size: 18),
                                        ],
                                      ),
                              ),

                              const SizedBox(height: 16),

                              // Registration Option
                              Center(
                                child: InkWell(
                                  onTap: _showRegistrationSheet,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    child: RichText(
                                      text: TextSpan(
                                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                                        children: [
                                          TextSpan(text: VayalStrings.dontHaveAccount),
                                          TextSpan(
                                            text: VayalStrings.registerNow,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.primaryGreen,
                                              decoration: TextDecoration.underline,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const Spacer(),

                      const SizedBox(height: 16),

                      // Offline Demo Entry Point (Clean & Unobtrusive)
                      OutlinedButton.icon(
                        onPressed: () => _showDemoPreviewSheet(session),
                        icon: const Icon(Icons.explore_outlined, size: 16, color: AppTheme.accentGold),
                        label: Text(
                          VayalStrings.tryOfflineDemo,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                        ),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: AppTheme.surfaceCream,
                          side: BorderSide(color: AppTheme.accentGold.withOpacity(0.35)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Unobtrusive Kisan Support Helpline
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.cardBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.support_agent_rounded, size: 20, color: AppTheme.primaryGreen),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                VayalStrings.kisanHelplineTitle,
                                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                              ),
                            ),
                            Text(
                              VayalStrings.kisanHelplineNumber,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
