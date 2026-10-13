import '../utils/form_examples.dart';
import '../utils/language_rebuild.dart';

import 'package:flutter/material.dart';

import '../services/farmer_service.dart';
import '../services/location_service.dart';
import '../utils/commerce_strings.dart';
import '../widgets/vayal_app_bar.dart';
import 'farmer_bank_screen.dart';

class FarmerApplicationScreen extends StatefulWidget {
  final FarmerService? service;
  const FarmerApplicationScreen({super.key, this.service});
  @override
  State<FarmerApplicationScreen> createState() =>
      _FarmerApplicationScreenState();
}

class _FarmerApplicationScreenState extends State<FarmerApplicationScreen>
    with LanguageRebuild<FarmerApplicationScreen> {
  late final _service = widget.service ?? FarmerService();
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final k in [
      'farm_name',
      'farm_address',
      'pickup_address',
      'crops',
      'farm_details',
    ])
      k: TextEditingController(),
  };
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _coordinates;
  bool _busy = false, _delivery = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
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
      setState(() {
        _profile = profile;
        _delivery = a['delivery_available'] == true;
        _coordinates = a['coordinates'] == null
            ? null
            : Map<String, dynamic>.from(a['coordinates']);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _locate() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(S.t('Use this only while physically at your farm.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.t('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.t('Save current farm coordinates')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final location = await LocationService().request();
    if (!mounted) return;
    if (location.state == LocationState.available) {
      setState(
        () => _coordinates = {
          'latitude': location.latitude,
          'longitude': location.longitude,
        },
      );
    } else {
      setState(
        () => _error = S.t('Unable to obtain coordinates. Please retry.'),
      );
      if (location.state == LocationState.disabled ||
          location.state == LocationState.permanentlyDenied) {
        await LocationService.openSettings(
          services: location.state == LocationState.disabled,
        );
      }
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _busy) return;
    if (_coordinates == null) {
      setState(
        () => _error = S.t('Unable to obtain coordinates. Please retry.'),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.submitApplication({
        for (final e in _fields.entries) e.key: e.value.text.trim(),
        'coordinates': _coordinates,
        'delivery_available': _delivery,
        'application_revision': _profile?['application_revision'] ?? 0,
      });
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const labels = {
      'farm_name': 'Farm name',
      'farm_address': 'Farm address',
      'pickup_address': 'Pickup address',
      'crops': 'Crops grown',
      'farm_details': 'Farm details',
    };
    return Scaffold(
      appBar: VayalAppBar(title: S.t('Farmer application'), showBack: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              if (_profile != null) ...[
                Text(
                  S.status(_profile!['approval_status'] ?? 'PENDING'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (_profile!['rejection_reason'] != null)
                  Text(
                    '${S.t('Review reason')}: ${_profile!['rejection_reason']}',
                  ),
                if (_profile!['can_publish'] != true)
                  Text(
                    S.t(
                      'Complete onboarding and obtain administrator approval.',
                    ),
                  ),
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
                OutlinedButton.icon(
                  onPressed: _busy ? null : _locate,
                  icon: const Icon(Icons.my_location),
                  label: Text(S.t('Save current farm coordinates')),
                ),
                if (_coordinates != null)
                  Text(
                    '${_coordinates!['latitude']}, ${_coordinates!['longitude']}',
                  ),
                SwitchListTile(
                  title: Text(S.t('Offer delivery')),
                  subtitle: Text(S.t('Delivery included')),
                  value: _delivery,
                  onChanged:
                      _busy ? null : (v) => setState(() => _delivery = v),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const FarmerBankScreen(),
                            ),
                          );
                          if (mounted) _load();
                        },
                  icon: const Icon(Icons.account_balance),
                  label: Text(S.t('Bank payout details')),
                ),
                ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(S.t('Submit for review')),
                ),
              ],
              TextButton(
                onPressed: _busy ? null : _load,
                child: Text(S.t('Refresh')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
