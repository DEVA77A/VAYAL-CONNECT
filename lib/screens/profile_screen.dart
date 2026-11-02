import 'package:flutter/material.dart';
import '../models/auth_models.dart';
import '../services/session_manager.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../utils/commerce_strings.dart';
import '../utils/form_examples.dart';
import '../utils/language_rebuild.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/commerce_widgets.dart';
import '../widgets/vayal_app_bar.dart';
import '../widgets/logout_dialog.dart';
import 'auth_gateway_screen.dart';
import 'farmer_application_screen.dart';
import 'farmer_bank_screen.dart';
import 'addresses_screen.dart';

class ProfileScreen extends StatefulWidget {
  final ApiClient? api;
  const ProfileScreen({super.key, this.api});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with LanguageRebuild<ProfileScreen> {
  late final _api = widget.api ?? ApiClient();
  final _auth = AuthService();
  Map<String, dynamic>? _profile, _bank;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.dispose();
    _auth.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profile = await _api.request('/api/v1/users/me');
      if (mounted) {
        setState(() => _profile = Map<String, dynamic>.from(profile));
        SessionManager().refreshProfile(UserProfile.fromJson(_profile!));
      }
      if (SessionManager().activeRole == AppRole.farmer) {
        final bank = await _api.request('/api/v1/farmers/me/bank');
        if (mounted) setState(() => _bank = Map<String, dynamic>.from(bank));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final fields = {
      for (final k in ['name', 'phone', 'address', 'area_location'])
        k: TextEditingController(text: _profile?[k] ?? '')
    };
    final key = GlobalKey<FormState>();
    final save = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(S.t('Edit profile')),
                content: SingleChildScrollView(
                    child: Form(
                        key: key,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          for (final e in fields.entries)
                            TextFormField(
                                controller: e.value,
                                keyboardType: e.key == 'phone'
                                    ? TextInputType.phone
                                    : TextInputType.text,
                                decoration: InputDecoration(
                                    hintText: FormExamples.hint(e.key),
                                    hintStyle: FormExamples.style,
                                    labelText: S.t({
                                      'name': 'Name',
                                      'phone': 'Contact number',
                                      'address': 'Address',
                                      'area_location': 'Area / locality'
                                    }[e.key]!)),
                                validator: (v) {
                                  if (e.key == 'phone') {
                                    return RegExp(r'^[6-9][0-9]{9}$')
                                            .hasMatch(v ?? '')
                                        ? null
                                        : S.t('Enter a valid mobile number.');
                                  }
                                  return (v?.trim().length ?? 0) <
                                          (e.key == 'address' ? 5 : 2)
                                      ? S.t('Enter valid details.')
                                      : null;
                                }),
                        ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(S.t('Cancel'))),
                  TextButton(
                      onPressed: () {
                        if (key.currentState!.validate()) {
                          Navigator.pop(ctx, true);
                        }
                      },
                      child: Text(S.t('Save')))
                ]));
    final body = {for (final e in fields.entries) e.key: e.value.text.trim()};
    for (final c in fields.values) {
      c.dispose();
    }
    if (save != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.request('/api/v1/users/me', method: 'PUT', body: body);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _password() async {
    final current = TextEditingController(), next = TextEditingController();
    final key = GlobalKey<FormState>();
    final save = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(S.t('Change password')),
                content: Form(
                    key: key,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextFormField(
                          controller: current,
                          obscureText: true,
                          decoration: InputDecoration(
                              labelText: S.t('Current password'),
                              hintText: FormExamples.hint('password')),
                          validator: (v) =>
                              v == null || v.isEmpty ? S.t('Required') : null),
                      TextFormField(
                          controller: next,
                          obscureText: true,
                          decoration: InputDecoration(
                              labelText: S.t('New password'),
                              hintText: FormExamples.hint('password')),
                          validator: (v) => v == null ||
                                  v.length < 8 ||
                                  v.length > 128 ||
                                  !RegExp(r'[A-Z]').hasMatch(v) ||
                                  !RegExp(r'[0-9]').hasMatch(v)
                              ? S.t('8-128 characters, uppercase and a number')
                              : null),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(S.t('Cancel'))),
                  TextButton(
                      onPressed: () {
                        if (key.currentState!.validate()) {
                          Navigator.pop(ctx, true);
                        }
                      },
                      child: Text(S.t('Save')))
                ]));
    final old = current.text, fresh = next.text;
    current.dispose();
    next.dispose();
    if (save != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _auth.changePassword(old, fresh);
      if (mounted) _signOut();
    } catch (e) {
      if (mounted) {
        setState(() => _error = S.t(
            'Unable to change password. Check your current password and requirements.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _signOut() {
    SessionManager().logout();
    Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthGatewayScreen()),
        (_) => false);
  }

  Future<void> _logout() async {
    setState(() => _busy = true);
    try {
      await _auth.logout();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(S.t(
                'Signed out on this device. Server session revocation could not be confirmed.'))));
      }
    }
    if (mounted) _signOut();
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) _load();
  }

  Future<void> _checkForUpdate() async {
    setState(() => _busy = true);
    try {
      final release = await UpdateService(api: _api).checkForUpdate();
      if (!mounted) return;
      if (release != null) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => UpdateDialog(release: release),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(S.t('App is up to date!')),
          backgroundColor: AppTheme.primaryGreen,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${S.t('Could not check for updates')}: $e'),
          backgroundColor: AppTheme.errorRed,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = SessionManager().activeRole;
    final roleName = role == AppRole.farmer
        ? S.t('Farmer')
        : (role == AppRole.admin ? S.t('Admin') : S.t('Buyer'));

    return Scaffold(
      backgroundColor: AppTheme.backgroundWarm,
      appBar: VayalAppBar(title: S.t('Profile'), showBack: true),
      body: PageBody(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppTheme.primaryGreen,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            children: [
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: LinearProgressIndicator(
                    color: AppTheme.primaryGreen,
                    backgroundColor: AppTheme.softGreen,
                  ),
                ),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ErrorPanel(_error!, _load),
                ),

              // A. Profile Header & Hero Card
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.softGreen.withOpacity(0.85),
                      AppTheme.surfaceCream,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.cardBorder, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Avatar with subtle glow
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.primaryGreen,
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryGreen.withOpacity(0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          (_profile?['name']?.toString().isNotEmpty == true)
                              ? _profile!['name'][0].toUpperCase()
                              : 'V',
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryDarkGreen,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // User Name
                    Text(
                      _profile?['name'] ?? S.t('VayalConnect User'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryDarkGreen,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Role Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGreen,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        roleName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // B. Profile Information Card
              if (_profile != null) ...[
                _buildSectionHeader(
                  title: S.t('Personal Information'),
                  icon: Icons.badge_outlined,
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCream,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.cardBorder, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildInfoTile(
                        icon: Icons.person_outline,
                        label: S.t('Name'),
                        value: _profile!['name'],
                      ),
                      _buildDivider(),
                      _buildInfoTile(
                        icon: Icons.email_outlined,
                        label: S.t('Email'),
                        value: _profile!['email'],
                      ),
                      _buildDivider(),
                      _buildInfoTile(
                        icon: Icons.phone_outlined,
                        label: S.t('Contact number'),
                        value: _profile!['phone'],
                      ),
                      _buildDivider(),
                      _buildInfoTile(
                        icon: Icons.home_outlined,
                        label: S.t('Address'),
                        value: _profile!['address'],
                      ),
                      _buildDivider(),
                      _buildInfoTile(
                        icon: Icons.location_city_outlined,
                        label: S.t('Area / locality'),
                        value: _profile!['area_location'],
                        isLast: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Farmer Bank Payout Details Card
              if (role == AppRole.farmer && _bank != null) ...[
                _buildSectionHeader(
                  title: S.t('Bank Payout Details'),
                  icon: Icons.account_balance_outlined,
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCream,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.cardBorder, width: 1),
                  ),
                  child: Column(
                    children: [
                      _buildInfoTile(
                        icon: Icons.account_balance,
                        label: S.t('Bank name'),
                        value: _bank!['bank_name'],
                      ),
                      _buildDivider(),
                      _buildInfoTile(
                        icon: Icons.numbers,
                        label: S.t('Account number'),
                        value: _bank!['account_number_masked'],
                      ),
                      _buildDivider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              S.t('Status'),
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (_bank!['bank_details_verified'] == true)
                                    ? AppTheme.successGreen.withOpacity(0.12)
                                    : AppTheme.warningOrange.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                S.t(_bank!['bank_details_verified'] == true
                                    ? 'Verified'
                                    : 'Not verified'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      (_bank!['bank_details_verified'] == true)
                                          ? AppTheme.successGreen
                                          : AppTheme.warningOrange,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // C. Profile Action Buttons
              _buildSectionHeader(
                title: S.t('Account Actions'),
                icon: Icons.tune_rounded,
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCream,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.cardBorder, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // 1. Edit Profile
                    _buildActionTile(
                      icon: Icons.edit_outlined,
                      iconColor: AppTheme.primaryGreen,
                      title: S.t('Edit profile'),
                      onTap: _busy ? null : _edit,
                    ),
                    _buildDivider(),

                    // 2. Role Specific Actions
                    if (role == AppRole.farmer) ...[
                      _buildActionTile(
                        icon: Icons.agriculture_outlined,
                        iconColor: AppTheme.earthBrown,
                        title: S.t('Farmer application'),
                        onTap: _busy
                            ? null
                            : () => _open(const FarmerApplicationScreen()),
                      ),
                      _buildDivider(),
                      _buildActionTile(
                        icon: Icons.account_balance_outlined,
                        iconColor: AppTheme.earthBrown,
                        title: S.t('Bank payout details'),
                        onTap: _busy
                            ? null
                            : () => _open(const FarmerBankScreen()),
                      ),
                      _buildDivider(),
                    ],

                    if (role == AppRole.buyer) ...[
                      _buildActionTile(
                        icon: Icons.location_on_outlined,
                        iconColor: AppTheme.primaryGreen,
                        title: S.t('Addresses'),
                        onTap:
                            _busy ? null : () => _open(const AddressesScreen()),
                      ),
                      _buildDivider(),
                    ],

                    // 3. Check for Updates
                    _buildActionTile(
                      icon: Icons.system_update_alt_rounded,
                      iconColor: AppTheme.primaryGreen,
                      title: S.t('Check for updates'),
                      onTap: _busy ? null : _checkForUpdate,
                    ),
                    _buildDivider(),

                    // 4. Change Password
                    _buildActionTile(
                      icon: Icons.lock_outline_rounded,
                      iconColor: AppTheme.primaryGreen,
                      title: S.t('Change password'),
                      onTap: _busy ? null : _password,
                    ),
                    _buildDivider(),

                    // 5. Logout
                    _buildActionTile(
                      icon: Icons.logout_rounded,
                      iconColor: AppTheme.errorRed,
                      title: S.t('Logout'),
                      textColor: AppTheme.errorRed,
                      isLast: true,
                      onTap: _busy
                          ? null
                          : () {
                              LogoutConfirmationDialog.show(
                                context,
                                onConfirm: _logout,
                              );
                            },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({required String title, required IconData icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.earthBrown),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryDarkGreen,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required dynamic value,
    bool isLast = false,
  }) {
    final strVal = (value == null || value.toString().trim().isEmpty)
        ? '—'
        : value.toString();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.softGreen.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: AppTheme.primaryDarkGreen),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  strVal,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required VoidCallback? onTap,
    Color? textColor,
    bool isLast = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: isLast
            ? const BorderRadius.vertical(bottom: Radius.circular(16))
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: textColor ?? AppTheme.textPrimary,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: textColor ?? AppTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: AppTheme.dividerColor,
    );
  }
}
