import '../widgets/brand_widgets.dart';
import '../utils/commerce_strings.dart';
import '../utils/form_examples.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import '../models/auth_models.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import '../utils/localization.dart';
import '../widgets/vayal_logo.dart';
import '../utils/registration_validation.dart';
import 'location_gate_screen.dart';
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
        if (role == null) {
          SessionManager().logout();
          return;
        }
        await _authService.selectRole(role);
        final confirmed = await _authService.login(
            _emailPhoneController.text, _passwordController.text);
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
          title: Text(S.t('Choose your account role')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, AppRole.farmer),
                child: Text(S.t('Farmer'))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, AppRole.buyer),
                child: Text(S.t('Buyer'))),
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
      _showOtpVerificationDialog(
          _emailPhoneController.text.trim(), role, _passwordController.text);
    } catch (e) {
      if (mounted) {
        setState(
            () => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
      }
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
      MaterialPageRoute(
          builder: (_) =>
              role == AppRole.admin ? home : LocationGateScreen(home: home)),
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
            Text('Server IP / URL',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
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
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                prefixIcon: const Icon(Icons.link, size: 20),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.t('Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
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
    final emailController =
        TextEditingController(text: _emailPhoneController.text.trim());
    final otpController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool otpSent = false;
    bool isSubmitting = false;
    bool obscureNewPassword = true;
    bool obscureConfirmPassword = true;
    String? dialogError;

    String? validateNewPasswordPolicy(String pwd) {
      if (pwd.length < 8) {
        return S.t('Password must be at least 8 characters long.');
      }
      final missing = <String>[];
      if (!RegExp(r'[A-Z]').hasMatch(pwd)) {
        missing.add(S.t('one uppercase letter'));
      }
      if (!RegExp(r'[0-9]').hasMatch(pwd)) {
        missing.add(S.t('one number'));
      }
      if (missing.isNotEmpty) {
        return '${S.t("Your password must contain at least")} ${missing.join(S.t(" and "))}.';
      }
      return null;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceCream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.9),
                child: SingleChildScrollView(
                    child: Padding(
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
                      SheetTitle(
                          title: VayalStrings.resetPasswordTitle,
                          icon: Icons.lock_reset,
                          onClose: () => Navigator.pop(ctx)),
                      const SizedBox(height: 6),
                      Text(
                        VayalStrings.resetPasswordSubtitle,
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary),
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
                            S.message(dialogError!),
                            style: const TextStyle(
                                color: AppTheme.errorRed, fontSize: 12),
                          ),
                        ),
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        enabled: !otpSent,
                        onChanged: (_) {
                          if (dialogError != null) {
                            setSheetState(() => dialogError = null);
                          }
                        },
                        decoration: InputDecoration(
                          labelText: VayalStrings.phoneOrEmail,
                          prefixIcon:
                              const Icon(Icons.email_outlined, size: 20),
                        ),
                      ),
                      if (otpSent) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: otpController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          onChanged: (_) {
                            if (dialogError != null) {
                              setSheetState(() => dialogError = null);
                            }
                          },
                          decoration: InputDecoration(
                            labelText: VayalStrings.enterOtp,
                            prefixIcon: const Icon(Icons.security, size: 20),
                            hintText: FormExamples.hint('otp'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: newPasswordController,
                          obscureText: obscureNewPassword,
                          onChanged: (_) {
                            if (dialogError != null) {
                              setSheetState(() => dialogError = null);
                            }
                          },
                          decoration: InputDecoration(
                            labelText: VayalStrings.newPassword,
                            prefixIcon:
                                const Icon(Icons.lock_outline, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscureNewPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 20,
                                color: AppTheme.textSecondary,
                              ),
                              onPressed: () => setSheetState(() =>
                                  obscureNewPassword = !obscureNewPassword),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: confirmPasswordController,
                          obscureText: obscureConfirmPassword,
                          onChanged: (_) {
                            if (dialogError != null) {
                              setSheetState(() => dialogError = null);
                            }
                          },
                          decoration: InputDecoration(
                            labelText: VayalStrings.confirmPassword,
                            prefixIcon:
                                const Icon(Icons.lock_outline, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscureConfirmPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 20,
                                color: AppTheme.textSecondary,
                              ),
                              onPressed: () => setSheetState(() =>
                                  obscureConfirmPassword =
                                      !obscureConfirmPassword),
                            ),
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
                                  setSheetState(() =>
                                      dialogError = VayalStrings.emailRequired);
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
                                      dialogError = e
                                          .toString()
                                          .replaceFirst('Exception: ', '');
                                      isSubmitting = false;
                                    });
                                  }
                                } else {
                                  final otp = otpController.text.trim();
                                  final newPass = newPasswordController.text;
                                  final confirmPass =
                                      confirmPasswordController.text;

                                  if (otp.length != 6 ||
                                      !RegExp(r'^[0-9]{6}$').hasMatch(otp)) {
                                    setSheetState(() {
                                      isSubmitting = false;
                                      dialogError = S.t('Enter a valid 6-digit OTP.');
                                    });
                                    return;
                                  }

                                  final policyError =
                                      validateNewPasswordPolicy(newPass);
                                  if (policyError != null) {
                                    setSheetState(() {
                                      isSubmitting = false;
                                      dialogError = policyError;
                                    });
                                    return;
                                  }

                                  if (confirmPass.isEmpty) {
                                    setSheetState(() {
                                      isSubmitting = false;
                                      dialogError =
                                          VayalStrings.pleaseConfirmPassword;
                                    });
                                    return;
                                  }

                                  if (newPass != confirmPass) {
                                    setSheetState(() {
                                      isSubmitting = false;
                                      dialogError =
                                          VayalStrings.passwordsDoNotMatch;
                                    });
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
                                      SnackBar(
                                        content: Text(S.t(
                                            'Password reset successfully! Please login.')),
                                        backgroundColor: AppTheme.successGreen,
                                      ),
                                    );
                                  } catch (e) {
                                    setSheetState(() {
                                      dialogError = e
                                          .toString()
                                          .replaceFirst('Exception: ', '');
                                      isSubmitting = false;
                                    });
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text(otpSent
                                ? VayalStrings.resetPasswordBtn
                                : VayalStrings.sendOtp),
                      ),
                    ],
                  ),
                )));
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
    final confirmPasswordController = TextEditingController();
    final addressController = TextEditingController();
    final locationController = TextEditingController();
    final ageController = TextEditingController(text: '30');
    AppRole selectedRole = AppRole.farmer;
    bool isSubmitting = false;
    bool accountCreated = false;
    bool locating = false;
    bool obscurePassword = true;
    bool obscureConfirmPassword = true;
    LocationResult? registrationLocation;
    String? locationMessage;
    String? regError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceCream,
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
                  SheetTitle(
                      title: VayalStrings.register,
                      icon: Icons.person_add_outlined,
                      onClose: () => Navigator.pop(ctx)),
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
                                  style: const TextStyle(
                                      color: AppTheme.errorRed, fontSize: 12),
                                ),
                              ),
                            TextFormField(
                              enabled: !accountCreated && !isSubmitting,
                              controller: nameController,
                              validator: (v) => v == null || v.trim().length < 2
                                  ? S.t('Enter valid name')
                                  : null,
                              decoration: InputDecoration(
                                labelText: S.t('Full Name'),
                                hintText: FormExamples.hint('name'),
                                hintStyle: FormExamples.style,
                                prefixIcon:
                                    const Icon(Icons.badge_outlined, size: 20),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  enabled: !accountCreated && !isSubmitting,
                                  controller: emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (v) =>
                                      v == null || !v.contains('@')
                                          ? S.t('Valid email required')
                                          : null,
                                  decoration: InputDecoration(
                                    labelText: S.t('Email Address'),
                                    hintText: FormExamples.hint('email'),
                                    hintStyle: FormExamples.style,
                                    prefixIcon: const Icon(Icons.email_outlined,
                                        size: 20),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  enabled: !accountCreated && !isSubmitting,
                                  controller: ageController,
                                  keyboardType: TextInputType.number,
                                  validator: (v) =>
                                      (int.tryParse(v ?? '') ?? 0) < 18 ||
                                              (int.tryParse(v ?? '') ?? 0) > 120
                                          ? '18-120'
                                          : null,
                                  decoration: InputDecoration(
                                    labelText: S.t('Age'),
                                    hintText: FormExamples.hint('age'),
                                    hintStyle: FormExamples.style,
                                    prefixIcon: const Icon(Icons.cake_outlined,
                                        size: 20),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              enabled: !accountCreated && !isSubmitting,
                              controller: phoneController,
                              keyboardType: TextInputType.phone,
                              validator: validateRegistrationPhone,
                              decoration: InputDecoration(
                                labelText: S.t('Phone Number'),
                                hintText: FormExamples.hint('phone'),
                                hintStyle: FormExamples.style,
                                helperText: S.t(
                                    '10 digits or +91 followed by 10 digits'),
                                prefixIcon:
                                    const Icon(Icons.phone_outlined, size: 20),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              enabled: !accountCreated && !isSubmitting,
                              controller: passwordController,
                              obscureText: obscurePassword,
                              validator: (v) => v == null ||
                                      v.length < 8 ||
                                      !RegExp(r'[A-Z]').hasMatch(v) ||
                                      !RegExp(r'[0-9]').hasMatch(v)
                                  ? S.t('8+ chars, uppercase letter and number')
                                  : null,
                              decoration: InputDecoration(
                                labelText: S.t('Password'),
                                hintText: FormExamples.hint('password'),
                                hintStyle: FormExamples.style,
                                prefixIcon:
                                    const Icon(Icons.lock_outline, size: 20),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 20,
                                    color: AppTheme.textSecondary,
                                  ),
                                  onPressed: () => setSheetState(() =>
                                      obscurePassword = !obscurePassword),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              enabled: !accountCreated && !isSubmitting,
                              controller: confirmPasswordController,
                              obscureText: obscureConfirmPassword,
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return S.t('Please confirm your password');
                                }
                                if (v != passwordController.text) {
                                  return S.t('Passwords do not match');
                                }
                                return null;
                              },
                              decoration: InputDecoration(
                                labelText: S.t('Confirm Password'),
                                hintText: S.t('Please confirm your password'),
                                hintStyle: FormExamples.style,
                                prefixIcon: const Icon(
                                    Icons.lock_reset_outlined,
                                    size: 20),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    obscureConfirmPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 20,
                                    color: AppTheme.textSecondary,
                                  ),
                                  onPressed: () => setSheetState(() =>
                                      obscureConfirmPassword =
                                          !obscureConfirmPassword),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(VayalStrings.locationExplanation,
                                style: const TextStyle(fontSize: 12)),
                            TextButton.icon(
                              icon: const Icon(Icons.my_location),
                              label: Text(VayalStrings.useLocation),
                              onPressed: locating ||
                                      isSubmitting ||
                                      accountCreated
                                  ? null
                                  : () async {
                                      setSheetState(() => locating = true);
                                      final result =
                                          await LocationService().request();
                                      if (!ctx.mounted) return;
                                      setSheetState(() {
                                        locating = false;
                                        registrationLocation = result;
                                        locationMessage =
                                            switch (result.state) {
                                          LocationState.available =>
                                            VayalStrings.locationSaved,
                                          LocationState.denied =>
                                            VayalStrings.locationDenied,
                                          LocationState.permanentlyDenied =>
                                            VayalStrings.locationPermanent,
                                          LocationState.disabled =>
                                            VayalStrings.locationDisabled,
                                          LocationState.unavailable =>
                                            VayalStrings.locationUnavailable,
                                        };
                                      });
                                    },
                            ),
                            if (locationMessage != null)
                              Text(locationMessage!,
                                  style: const TextStyle(fontSize: 12)),
                            if (registrationLocation?.state ==
                                    LocationState.permanentlyDenied ||
                                registrationLocation?.state ==
                                    LocationState.disabled)
                              TextButton(
                                  onPressed: () async {
                                    await LocationService.openSettings(
                                        services: registrationLocation?.state ==
                                            LocationState.disabled);
                                  },
                                  child: Text(VayalStrings.openSettings)),
                            TextFormField(
                              enabled: !accountCreated && !isSubmitting,
                              controller: addressController,
                              validator: (v) => v == null || v.trim().length < 5
                                  ? S.t('Address required')
                                  : null,
                              decoration: InputDecoration(
                                labelText: S.t('Address'),
                                hintText: FormExamples.hint('address'),
                                hintStyle: FormExamples.style,
                                prefixIcon:
                                    const Icon(Icons.home_outlined, size: 20),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              enabled: !accountCreated && !isSubmitting,
                              controller: locationController,
                              validator: (v) => v == null || v.trim().length < 2
                                  ? S.t('District required')
                                  : null,
                              decoration: InputDecoration(
                                labelText: S.t('District / Area'),
                                hintText: FormExamples.hint('district'),
                                hintStyle: FormExamples.style,
                                prefixIcon: const Icon(
                                    Icons.location_on_outlined,
                                    size: 20),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              S.t('Select Account Role:'),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textSecondary),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ChoiceChip(
                                  avatar:
                                      const Icon(Icons.agriculture_outlined),
                                  label: Text(S.t('Farmer')),
                                  selected: selectedRole == AppRole.farmer,
                                  onSelected: (_) => setSheetState(
                                      () => selectedRole = AppRole.farmer),
                                ),
                                ChoiceChip(
                                  avatar:
                                      const Icon(Icons.shopping_bag_outlined),
                                  label: Text(S.t('Buyer')),
                                  selected: selectedRole == AppRole.buyer,
                                  onSelected: (_) => setSheetState(
                                      () => selectedRole = AppRole.buyer),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: isSubmitting
                                  ? null
                                  : () async {
                                      if (!regFormKey.currentState!
                                          .validate()) {
                                        return;
                                      }
                                      setSheetState(() {
                                        isSubmitting = true;
                                        regError = null;
                                      });

                                      try {
                                        final email =
                                            emailController.text.trim();
                                        if (!accountCreated) {
                                          await _authService.register(
                                            name: nameController.text.trim(),
                                            email: email,
                                            phone: phoneController.text.trim(),
                                            password: passwordController.text,
                                            address:
                                                addressController.text.trim(),
                                            areaLocation:
                                                locationController.text.trim(),
                                            gender: 'other',
                                            age: int.tryParse(
                                                    ageController.text) ??
                                                25,
                                            preferredLanguage:
                                                SessionManager().isTamil
                                                    ? 'ta'
                                                    : 'en',
                                            latitude:
                                                registrationLocation?.latitude,
                                            longitude:
                                                registrationLocation?.longitude,
                                          );

                                          accountCreated = true;
                                        }
                                        await _authService.requestOtp(email);
                                        if (!context.mounted) return;
                                        Navigator.pop(ctx);
                                        _showOtpVerificationDialog(
                                            email,
                                            selectedRole,
                                            passwordController.text);
                                      } catch (e) {
                                        setSheetState(() {
                                          regError = e
                                              .toString()
                                              .replaceFirst('Exception: ', '');
                                          isSubmitting = false;
                                        });
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryGreen,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              child: isSubmitting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
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
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
                title: Text(S.t('Email OTP Verification')),
                scrollable: true,
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                      '${S.t('Email provider accepted the OTP email.')}\n$email\n${S.t('Check your inbox and spam folder. Delivery may take a few minutes.')}'),
                  if (error != null)
                    Text(S.message(error!),
                        style: const TextStyle(color: AppTheme.errorRed)),
                  TextField(
                      controller: otpController,
                      enabled: !busy && !verified,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                          labelText: VayalStrings.enterOtp,
                          hintText: FormExamples.hint('otp'))),
                ]),
                actions: [
                  TextButton(
                      onPressed: busy ? null : () => Navigator.pop(ctx),
                      child: Text(S.t('Cancel'))),
                  TextButton(
                      onPressed: busy || verified
                          ? null
                          : () async {
                              if (DateTime.now().isBefore(resendAfter)) {
                                update(() => error = S.t(
                                    'Please wait 60 seconds between OTP requests.'));
                                return;
                              }
                              update(() {
                                busy = true;
                                error = null;
                              });
                              try {
                                await _authService.requestOtp(email);
                                resendAfter = DateTime.now()
                                    .add(const Duration(seconds: 60));
                              } catch (e) {
                                if (ctx.mounted) {
                                  update(() => error = e
                                      .toString()
                                      .replaceFirst('Exception: ', ''));
                                }
                              } finally {
                                if (ctx.mounted) update(() => busy = false);
                              }
                            },
                      child: Text(S.t('Resend OTP'))),
                  ElevatedButton(
                      onPressed: busy
                          ? null
                          : () async {
                              if (!verified &&
                                  !RegExp(r'^\d{6}$')
                                      .hasMatch(otpController.text.trim())) {
                                update(() =>
                                    error = S.t('Enter a valid 6-digit OTP.'));
                                return;
                              }
                              update(() {
                                busy = true;
                                error = null;
                              });
                              try {
                                if (!verified) {
                                  if (!await _authService.verifyOtp(
                                      email, otpController.text.trim())) {
                                    throw Exception(S.t(
                                        'Email verification was not confirmed.'));
                                  }
                                  verified = true;
                                }
                                final initial =
                                    await _authService.login(email, password);
                                if (!roleAssigned &&
                                    !initial.user.hasAssignedRole) {
                                  await _authService.selectRole(role);
                                  roleAssigned = true;
                                }
                                final session =
                                    await _authService.login(email, password);
                                if (!ctx.mounted) return;
                                Navigator.pop(ctx);
                                _navigateToRoleHome(session.user.role);
                              } catch (e) {
                                if (ctx.mounted) {
                                  update(() => error = e
                                      .toString()
                                      .replaceFirst('Exception: ', ''));
                                }
                              } finally {
                                if (ctx.mounted) update(() => busy = false);
                              }
                            },
                      child: Text(busy
                          ? S.t('Please wait...')
                          : verified
                              ? S.t('Continue')
                              : S.t('Verify'))),
                ],
              )),
    );
  }

  void _showDemoPreviewSheet(SessionManager session) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceCream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SingleChildScrollView(
            child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetTitle(
                  title: VayalStrings.offlineDemoPreview,
                  icon: Icons.preview_outlined,
                  onClose: () => Navigator.pop(ctx)),
              const SizedBox(height: 4),
              Text(
                VayalStrings.offlineDemoSubtitle,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 18),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _enterDemoMode(AppRole.farmer);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: AppTheme.primaryGreen),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.agriculture_outlined, size: 24),
                        const SizedBox(height: 4),
                        Text(S.t('Farmer'),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _enterDemoMode(AppRole.buyer);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: AppTheme.primaryGreen),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shopping_bag_outlined, size: 24),
                        const SizedBox(height: 4),
                        Text(S.t('Buyer'),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _enterDemoMode(AppRole.admin);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: AppTheme.primaryGreen),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.admin_panel_settings_outlined,
                            size: 24),
                        const SizedBox(height: 4),
                        Text(S.t('Admin'),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionManager();

    return Scaffold(
      backgroundColor: AppTheme.backgroundWarm,
      body: PageBody(child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(minHeight: constraints.maxHeight - 24),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top Actions Bar: Server IP (Dev Only) & Language Toggle
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // Server configuration is limited to development builds.
                            if (!kReleaseMode)
                              InkWell(
                                onTap: _showServerConfigDialog,
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 9, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceCream,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color: AppTheme.cardBorder),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.dns_rounded,
                                          size: 13,
                                          color: AppTheme.primaryGreen),
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
                            // Language Selector Pill
                            InkWell(
                              onTap: () {
                                setState(() {
                                  session.toggleLanguage();
                                });
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppTheme.cardBorder),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.02),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.language,
                                        size: 14,
                                        color: AppTheme.primaryGreen),
                                    const SizedBox(width: 5),
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
                      ),

                      const SizedBox(height: 16),

                      // Brand Hero Section
                      Center(
                        child: Column(
                          children: [
                            const VayalLogo(width: 96, height: 96),
                            const SizedBox(height: 14),
                            Text(
                              VayalStrings.appName,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              VayalStrings.tagline,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textSecondary,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Error Banner
                      if (_errorMessage?.contains('Email not verified') == true)
                        TextButton(
                            onPressed: _isLoading ? null : _resumeVerification,
                            child: Text(S.t('Verify email / Resend OTP'))),
                      if (_errorMessage != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppTheme.errorRed.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  size: 20, color: AppTheme.errorRed),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  S.message(_errorMessage!),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 24),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceCream,
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: AppTheme.cardBorder, width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.035),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
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
                                  prefixIcon: const Icon(
                                      Icons.mail_outline_rounded,
                                      size: 20,
                                      color: AppTheme.textSecondary),
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
                                  prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                      size: 20,
                                      color: AppTheme.textSecondary),
                                  hintText: VayalStrings.passwordHint,
                                  suffixIcon: IconButton(
                                    key:
                                        const Key('password_visibility_toggle'),
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: 20,
                                      color: AppTheme.textSecondary,
                                    ),
                                    onPressed: () => setState(() =>
                                        _obscurePassword = !_obscurePassword),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 12),

                              // Remember Me & Forgot Password Row
                              Builder(
                                builder: (context) {
                                  final isLargeText =
                                      MediaQuery.textScalerOf(context).scale(14) > 18 ||
                                      MediaQuery.sizeOf(context).width < 340;
                                  final checkboxWidget = SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: Checkbox(
                                      value: _rememberMe,
                                      activeColor: AppTheme.primaryGreen,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(4)),
                                      onChanged: (val) => setState(
                                          () => _rememberMe = val ?? true),
                                    ),
                                  );

                                  final rememberTextWidget = Text(
                                    VayalStrings.rememberMe,
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        color: AppTheme.textSecondary),
                                  );

                                  final forgotButton = TextButton(
                                    onPressed: _showForgotPasswordSheet,
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 4),
                                      minimumSize: const Size(48, 36),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      VayalStrings.forgotPassword,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.primaryGreen,
                                      ),
                                    ),
                                  );

                                  if (isLargeText) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            checkboxWidget,
                                            const SizedBox(width: 8),
                                            Expanded(child: rememberTextWidget),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        forgotButton,
                                      ],
                                    );
                                  }

                                  return Row(
                                    children: [
                                      checkboxWidget,
                                      const SizedBox(width: 8),
                                      Expanded(child: rememberTextWidget),
                                      const SizedBox(width: 8),
                                      forgotButton,
                                    ],
                                  );
                                },
                              ),

                              const SizedBox(height: 18),

                              // Primary Login Button
                              ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryGreen,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      AppTheme.primaryGreen.withOpacity(0.55),
                                  minimumSize:
                                      const Size(double.infinity, 50),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Flexible(
                                              child: Text(
                                            VayalStrings.login,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.3,
                                            ),
                                          )),
                                          const SizedBox(width: 8),
                                          const Icon(
                                              Icons.arrow_forward_rounded,
                                              size: 18),
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
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    child: RichText(
                                      textAlign: TextAlign.center,
                                      text: TextSpan(
                                        style: const TextStyle(
                                            fontFamily: 'Roboto',
                                            fontFamilyFallback: [
                                              'Noto Sans Tamil',
                                              'Nirmala UI'
                                            ],
                                            fontSize: 13,
                                            color: AppTheme.textSecondary),
                                        children: [
                                          TextSpan(
                                              text:
                                                  VayalStrings.dontHaveAccount),
                                          TextSpan(
                                            text: VayalStrings.registerNow,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.primaryGreen,
                                              decoration:
                                                  TextDecoration.underline,
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

                      // Preview accounts are limited to development builds.
                      if (!kReleaseMode)
                        OutlinedButton.icon(
                          onPressed: () => _showDemoPreviewSheet(session),
                          icon: const Icon(Icons.explore_outlined,
                              size: 16, color: AppTheme.accentGold),
                          label: Text(
                            VayalStrings.tryOfflineDemo,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: AppTheme.surfaceCream,
                            side: BorderSide(
                                color: AppTheme.accentGold.withOpacity(0.35)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
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
      )),
    );
  }
}
