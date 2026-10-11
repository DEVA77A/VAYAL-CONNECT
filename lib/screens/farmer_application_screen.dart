import 'package:flutter/material.dart';
import '../services/farmer_service.dart';

class FarmerApplicationScreen extends StatefulWidget {
  final FarmerService? service;
  const FarmerApplicationScreen({super.key, this.service});
  @override
  State<FarmerApplicationScreen> createState() =>
      _FarmerApplicationScreenState();
}

class _FarmerApplicationScreenState extends State<FarmerApplicationScreen> {
  late final FarmerService _service = widget.service ?? FarmerService();
  final _form = GlobalKey<FormState>();
  final _fields = {
    'farm_name': TextEditingController(),
    'farm_address': TextEditingController(),
    'pickup_address': TextEditingController(),
    'crops': TextEditingController(),
  };
  Map<String, dynamic>? _profile;
  String? _error;
  bool _busy = false;
  bool _delivery = false;
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
      final application = profile['application'] as Map? ?? {};
      for (final field in _fields.entries) {
        field.value.text = application[field.key] as String? ?? '';
      }
      setState(() {
        _profile = profile;
        _delivery = application['delivery_available'] == true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.submitApplication({
        for (final e in _fields.entries) e.key: e.value.text.trim(),
        'delivery_available': _delivery,
        'application_revision': _profile?['application_revision'] ?? 0,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Application submitted for administrator review.')));
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final approved = _profile?['approval_status'] == 'APPROVED';
    const labels = {
      'farm_name': 'Farm name / பண்ணை பெயர்',
      'farm_address': 'Farm address / பண்ணை முகவரி',
      'pickup_address': 'Buyer pickup address / பெறும் முகவரி',
      'crops': 'Crops grown / பயிர்கள்'
    };
    return Scaffold(
      appBar:
          AppBar(title: const Text('Farmer application / விவசாயி விண்ணப்பம்')),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    TextButton(
                        onPressed: _busy ? null : _load,
                        child: const Text('Reload'))
                  ],
                  if (_profile != null) ...[
                    Text(
                        'Approval: ' + _profile!['approval_status'].toString()),
                    Text(_profile!['submitted_at'] == null
                        ? 'Complete and submit your farm details for review.'
                        : 'Submitted: ' + _profile!['submitted_at'].toString()),
                    if (_profile!['rejection_reason'] != null)
                      Text('Review reason: ' +
                          _profile!['rejection_reason'].toString()),
                    const Text(
                        'Approval permits selling. Bank payout details are managed separately and are not bank verification.'),
                    for (final field in _fields.entries)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: TextFormField(
                            controller: field.value,
                            enabled: !_busy && !approved,
                            maxLength: field.key == 'farm_name' ? 200 : 500,
                            decoration:
                                InputDecoration(labelText: labels[field.key]),
                            validator: (v) => (v?.trim().length ?? 0) <
                                    (field.key.contains('address') ? 10 : 2)
                                ? 'Please enter complete details.'
                                : null,
                          )),
                    SwitchListTile(
                        title: const Text('Offer delivery / விநியோகம்'),
                        subtitle: const Text(
                            'Delivery is included in the selling price. No separate delivery fee or estimated arrival is promised.'),
                        value: _delivery,
                        onChanged: _busy || approved
                            ? null
                            : (value) => setState(() => _delivery = value)),
                    if (!approved)
                      ElevatedButton(
                          onPressed: _busy ? null : _submit,
                          child: const Text('Submit for review / சமர்ப்பி')),
                    if (approved)
                      const Text(
                          'Your application is approved. You can publish harvest listings.'),
                    TextButton(
                        onPressed: _busy ? null : _load,
                        child: const Text('Refresh approval status')),
                  ],
                ],
              ))),
    );
  }
}
