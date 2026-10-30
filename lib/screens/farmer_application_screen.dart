import '../widgets/brand_widgets.dart';
import '../utils/form_examples.dart';
import '../utils/language_rebuild.dart';
import 'package:flutter/material.dart';
import '../services/farmer_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import '../utils/commerce_strings.dart';
import '../widgets/vayal_app_bar.dart';
import 'farmer_bank_screen.dart';

class FarmerApplicationScreen extends StatefulWidget {
  final FarmerService? service;
  final Map<String, dynamic>? initialCoordinates;
  const FarmerApplicationScreen({super.key, this.service, this.initialCoordinates});

  @override
  State<FarmerApplicationScreen> createState() =>
      _FarmerApplicationScreenState();
}

class _FarmerApplicationScreenState extends State<FarmerApplicationScreen>
    with LanguageRebuild<FarmerApplicationScreen> {
  late final _service = widget.service ?? FarmerService();
  final _form = GlobalKey<FormState>();
  final _bankFormKey = GlobalKey<FormState>();

  // Step 1: Farm Details fields
  final _fields = {
    for (final k in [
      'farm_name',
      'farm_address',
      'pickup_address',
      'crops',
      'farm_details'
    ])
      k: TextEditingController()
  };

  // Step 2: Bank Payout Details fields
  final _bankFields = {
    for (final key in [
      'account_holder_name',
      'bank_name',
      'account_number',
      'ifsc',
      'upi_id'
    ])
      key: TextEditingController()
  };

  int _currentStep = 0; // 0 = Farm Details, 1 = Bank Details
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _coordinates;
  bool _busy = false, _delivery = false;
  String? _error;
  bool _submitted = false;
  bool _obscureAccountNumber = true;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialCoordinates != null) {
      _coordinates = Map<String, dynamic>.from(widget.initialCoordinates!);
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant FarmerApplicationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCoordinates != null &&
        widget.initialCoordinates != oldWidget.initialCoordinates) {
      _coordinates = Map<String, dynamic>.from(widget.initialCoordinates!);
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    for (final c in _bankFields.values) {
      c.dispose();
    }
    _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profile = await _service.fetchProfile();
      if (!mounted) return;
      final a = profile['application'] as Map? ?? {};
      for (final e in _fields.entries) {
        e.value.text = a[e.key] as String? ?? '';
      }

      // If bank details already exist on the profile, prefill non-sensitive fields
      if (profile['bank_details_present'] == true) {
        try {
          final bank = await _service.fetchBankDetails();
          if (mounted && bank.isNotEmpty) {
            if (_bankFields['bank_name']!.text.isEmpty && bank['bank_name'] is String) {
              _bankFields['bank_name']!.text = bank['bank_name'] as String;
            }
            if (_bankFields['ifsc']!.text.isEmpty && bank['ifsc'] is String) {
              _bankFields['ifsc']!.text = bank['ifsc'] as String;
            }
            if (_bankFields['account_holder_name']!.text.isEmpty && profile['name'] is String) {
              _bankFields['account_holder_name']!.text = profile['name'] as String;
            }
          }
        } catch (_) {}
      } else if (_bankFields['account_holder_name']!.text.isEmpty && profile['name'] is String) {
        _bankFields['account_holder_name']!.text = profile['name'] as String;
      }

      setState(() {
        _profile = profile;
        _submitted = _submitted && profile['approval_status'] == 'PENDING';
        _delivery = a['delivery_available'] == true;
        _coordinates = a['coordinates'] == null
            ? (widget.initialCoordinates ?? _coordinates)
            : Map<String, dynamic>.from(a['coordinates']);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _locate() async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                content:
                    Text(S.t('Use this only while physically at your farm.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(S.t('Cancel'))),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(S.t('Save current farm coordinates')))
                ]));
    if (confirm != true) return;
    final location = await LocationService().request();
    if (!mounted) return;
    if (location.state == LocationState.available) {
      setState(() {
        _coordinates = {
          'latitude': location.latitude,
          'longitude': location.longitude
        };
        _error = null;
      });
    } else {
      setState(
          () => _error = S.t('Unable to obtain coordinates. Please retry.'));
      if (location.state == LocationState.disabled ||
          location.state == LocationState.permanentlyDenied) {
        await LocationService.openSettings(
            services: location.state == LocationState.disabled);
      }
    }
  }

  void _nextStep() {
    if (!_form.currentState!.validate()) return;
    if (_coordinates == null) {
      setState(() => _error =
          S.t('Please save current farm coordinates before proceeding.'));
      return;
    }
    setState(() {
      _currentStep = 1;
      _error = null;
    });
  }

  void _previousStep() {
    setState(() {
      _currentStep = 0;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_bankFormKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final acctNum = _bankFields['account_number']!.text.trim();
      final holderName = _bankFields['account_holder_name']!.text.trim();
      final bankName = _bankFields['bank_name']!.text.trim();
      final ifsc = _bankFields['ifsc']!.text.trim().toUpperCase();
      final upi = _bankFields['upi_id']!.text.trim();

      // Step A: Save bank details if entered
      if (acctNum.isNotEmpty) {
        await _service.saveBankDetails({
          'account_holder_name': holderName,
          'bank_name': bankName,
          'account_number': acctNum,
          'ifsc': ifsc,
          'upi_id': upi.isEmpty ? null : upi,
        });
      }

      // Step B: Submit farm details application
      final result = await _service.submitApplication({
        for (final e in _fields.entries) e.key: e.value.text.trim(),
        'coordinates': _coordinates,
        'delivery_available': _delivery,
        'application_revision': _profile?['application_revision'] ?? 0,
      });

      if (!mounted) return;
      setState(() {
        _profile = {...?_profile, ...result, 'approval_status': 'PENDING'};
        _submitted = true;
        _isEditing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.t(
              'Application submitted successfully! Awaiting administrator review.')),
          backgroundColor: AppTheme.successGreen,
        ),
      );

      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCream,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: AppTheme.primaryGreen,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${_currentStep + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _currentStep == 0
                      ? S.t('Step 1 of 2: Farm Details')
                      : S.t('Step 2 of 2: Bank Details'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Text(
                _currentStep == 0 ? '50%' : '100%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _currentStep == 0 ? 0.5 : 1.0,
              backgroundColor: AppTheme.sandBeige.withOpacity(0.5),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1FarmDetails() {
    const labels = {
      'farm_name': 'Farm name',
      'farm_address': 'Farm address',
      'pickup_address': 'Pickup address',
      'crops': 'Crops grown',
      'farm_details': 'Farm details'
    };

    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormSection(S.t('Farm Information'),
              icon: Icons.agriculture_outlined),
          const SizedBox(height: 8),
          for (final e in _fields.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TextFormField(
                controller: e.value,
                textCapitalization: TextCapitalization.words,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: S.t(labels[e.key]!),
                  hintText: FormExamples.hint(e.key),
                  hintStyle: FormExamples.style,
                ),
                maxLength: e.key == 'farm_name' ? 200 : 500,
                validator: (v) => e.key == 'farm_details'
                    ? null
                    : (v?.trim().length ?? 0) <
                            (e.key.contains('address') ? 10 : 2)
                        ? S.t('Enter valid details.')
                        : null,
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _locate,
            icon: const Icon(Icons.my_location),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: const BorderSide(color: AppTheme.primaryGreen),
            ),
            label: Text(S.t('Save current farm coordinates')),
          ),
          if (_coordinates != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.softGreen,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: AppTheme.successGreen, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_coordinates!['latitude']}, ${_coordinates!['longitude']}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryDarkGreen),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text(S.t('Offer delivery')),
            subtitle: Text(S.t('Delivery included')),
            value: _delivery,
            activeColor: AppTheme.primaryGreen,
            contentPadding: EdgeInsets.zero,
            onChanged: _busy ? null : (v) => setState(() => _delivery = v),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _busy ? null : _nextStep,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
            ),
            child: Text(
              S.t('Next'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2BankDetails() {
    const labels = {
      'account_holder_name': 'Account holder name',
      'bank_name': 'Bank name',
      'account_number': 'Account number',
      'ifsc': 'IFSC code',
      'upi_id': 'UPI ID',
    };

    return Form(
      key: _bankFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormSection(S.t('Bank payout details'),
              icon: Icons.account_balance_outlined),
          const SizedBox(height: 4),
          Text(
            S.t('Enter your own bank details. Full account numbers are never displayed.'),
            style: const TextStyle(
                fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          for (final e in _bankFields.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TextFormField(
                controller: e.value,
                enabled: !_busy,
                obscureText: e.key == 'account_number' ? _obscureAccountNumber : false,
                maxLength: e.key == 'account_number'
                    ? 20
                    : e.key == 'ifsc'
                        ? 11
                        : e.key == 'upi_id'
                            ? 100
                            : 200,
                keyboardType: e.key == 'account_number'
                    ? TextInputType.number
                    : TextInputType.text,
                textCapitalization: e.key == 'ifsc'
                    ? TextCapitalization.characters
                    : e.key == 'bank_name' || e.key == 'account_holder_name'
                        ? TextCapitalization.words
                        : TextCapitalization.none,
                decoration: InputDecoration(
                  labelText: S.t(labels[e.key] ?? e.key.replaceAll('_', ' ')),
                  hintText: FormExamples.hint(e.key),
                  hintStyle: FormExamples.style,
                  suffixIcon: e.key == 'account_number'
                      ? IconButton(
                          icon: Icon(
                            _obscureAccountNumber
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                            color: AppTheme.textSecondary,
                          ),
                          onPressed: () => setState(() =>
                              _obscureAccountNumber = !_obscureAccountNumber),
                        )
                      : null,
                ),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (_profile?['bank_details_present'] == true && value.isEmpty) {
                    return null;
                  }
                  if (e.key == 'account_number') {
                    return RegExp(r'^[0-9]{8,20}$').hasMatch(value)
                        ? null
                        : S.t('Enter 8–20 digits.');
                  }
                  if (e.key == 'ifsc') {
                    return RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$')
                            .hasMatch(value.toUpperCase())
                        ? null
                        : S.t('Enter a valid IFSC.');
                  }
                  if (e.key == 'upi_id') return null;
                  return value.length < 2 ? S.t('Required') : null;
                },
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  onPressed: _busy ? null : _previousStep,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    side: const BorderSide(color: AppTheme.primaryGreen),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusMedium),
                    ),
                  ),
                  child: Text(
                    S.t('Back'),
                    style: const TextStyle(
                      color: AppTheme.primaryGreen,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusMedium),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          S.t('Submit for review'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final approvalStatus = _profile?['approval_status'];
    final isApproved = approvalStatus == 'APPROVED';
    final isPending =
        (approvalStatus == 'PENDING' && _profile?['submitted_at'] != null) ||
            _submitted;

    return PopScope(
      canPop: _currentStep == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentStep == 1) {
          _previousStep();
        }
      },
      child: Scaffold(
        appBar: VayalAppBar(
          title: S.t('Farmer application'),
          showBack: true,
        ),
        body: PageBody(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                          color: AppTheme.errorRed, fontSize: 13),
                    ),
                  ),

                // Approved State: do not show onboarding form
                if (isApproved && !_isEditing) ...[
                  Card(
                    color: AppTheme.softGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusMedium),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.verified,
                                  color: AppTheme.successGreen, size: 28),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  S.status('APPROVED'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                          color: AppTheme.primaryDarkGreen,
                                          fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            S.t('Complete onboarding and obtain administrator approval.'),
                            style: const TextStyle(
                                fontSize: 13, color: AppTheme.textSecondary),
                          ),
                          const Divider(height: 24),
                          Text(
                            '${S.t('Farm name')}: ${_fields['farm_name']?.text}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${S.t('Crops grown')}: ${_fields['crops']?.text}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const FarmerBankScreen()),
                    ),
                    icon: const Icon(Icons.account_balance),
                    label: Text(S.t('Bank payout details')),
                  ),
                ] else if (isPending && !_isEditing) ...[
                  // Pending Review State
                  Card(
                    color: AppTheme.surfaceCream,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusMedium),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.hourglass_top,
                                  color: AppTheme.warningOrange, size: 28),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  S.status('PENDING'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                          color: AppTheme.darkBrown,
                                          fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            S.t('Application submitted. Awaiting administrator review.'),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                          if (_profile?['rejection_reason'] != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              '${S.t('Review reason')}: ${_profile!['rejection_reason']}',
                              style: const TextStyle(
                                  color: AppTheme.errorRed, fontSize: 13),
                            ),
                          ],
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () => setState(() => _isEditing = true),
                            child: Text(S.t('Revise application')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  // Active Two-Step Onboarding Form
                  if (_profile?['rejection_reason'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '${S.t('Review reason')}: ${_profile!['rejection_reason']}',
                        style: const TextStyle(
                            color: AppTheme.errorRed,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (_profile != null &&
                      _profile!['submitted_at'] == null &&
                      !_submitted)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        S.t('Application not submitted yet. Complete the details below and submit for review.'),
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    ),
                  _buildStepIndicator(),
                  if (_currentStep == 0)
                    _buildStep1FarmDetails()
                  else
                    _buildStep2BankDetails(),
                ],
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _busy ? null : _load,
                  child: Text(S.t('Refresh')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
