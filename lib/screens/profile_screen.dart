import '../theme/app_theme.dart';
import '../widgets/brand_widgets.dart';
import '../utils/form_examples.dart';
import 'package:flutter/material.dart';
import '../models/auth_models.dart';
import '../services/session_manager.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../utils/commerce_strings.dart';
import '../utils/language_rebuild.dart';
import '../widgets/commerce_widgets.dart';
import '../widgets/vayal_app_bar.dart';
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

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: VayalAppBar(title: S.t('Profile'), showBack: true),
      body: PageBody(
          child: ListView(padding: const EdgeInsets.all(20), children: [
        BrandHeading(title: S.t('Profile'), icon: Icons.person_outline),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ErrorPanel(_error!, _load),
        if (_profile != null)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CircleAvatar(
                            radius: 32,
                            backgroundColor: AppTheme.softGreen,
                            child: Icon(Icons.person_outline,
                                size: 32, color: AppTheme.primaryGreen)),
                        detailLine('Name', _profile!['name']),
                        detailLine('Email', _profile!['email']),
                        detailLine('Contact number', _profile!['phone']),
                        detailLine('Address', _profile!['address']),
                        detailLine(
                            'Area / locality', _profile!['area_location']),
                      ]))),
        if (_profile != null)
          OutlinedButton.icon(
              onPressed: _busy ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
              label: Text(S.t('Edit profile'))),
        if (SessionManager().activeRole == AppRole.farmer) ...[
          OutlinedButton.icon(
              onPressed:
                  _busy ? null : () => _open(const FarmerApplicationScreen()),
              icon: const Icon(Icons.agriculture),
              label: Text(S.t('Farmer application'))),
          OutlinedButton.icon(
              onPressed: _busy ? null : () => _open(const FarmerBankScreen()),
              icon: const Icon(Icons.account_balance),
              label: Text(S.t('Bank payout details'))),
          if (_bank != null)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          detailLine('Bank name', _bank!['bank_name']),
                          detailLine('Account number',
                              _bank!['account_number_masked']),
                          Text(S.t(_bank!['bank_details_verified'] == true
                              ? 'Verified'
                              : 'Not verified')),
                        ]))),
        ],
        if (SessionManager().activeRole == AppRole.buyer)
          OutlinedButton.icon(
              onPressed: _busy ? null : () => _open(const AddressesScreen()),
              icon: const Icon(Icons.location_on),
              label: Text(S.t('Addresses'))),
        OutlinedButton.icon(
            onPressed: _busy ? null : _password,
            icon: const Icon(Icons.password),
            label: Text(S.t('Change password'))),
        OutlinedButton.icon(
            onPressed: _busy ? null : _logout,
            icon: const Icon(Icons.logout),
            label: Text(S.t('Logout'))),
      ])));
}
