import 'package:flutter/material.dart';
import '../services/farmer_service.dart';

class FarmerBankScreen extends StatefulWidget {
  final FarmerService? service;
  const FarmerBankScreen({super.key, this.service});
  @override
  State<FarmerBankScreen> createState() => _FarmerBankScreenState();
}

class _FarmerBankScreenState extends State<FarmerBankScreen> {
  late final _service = widget.service ?? FarmerService();
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final key in [
      'account_holder_name',
      'bank_name',
      'account_number',
      'ifsc',
      'upi_id'
    ])
      key: TextEditingController()
  };
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _service.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.saveBankDetails({
        for (final e in _fields.entries)
          e.key: e.key == 'upi_id' && e.value.text.trim().isEmpty
              ? null
              : e.value.text.trim()
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bank details saved. Verification remains pending.')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar:
            AppBar(title: const Text('Bank payout details / வங்கி விவரங்கள்')),
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                        'Enter your own bank details. Saving replaces the previous details and resets verification. Your full account number is never returned for display.'),
                    if (_busy) const LinearProgressIndicator(),
                    if (_error != null)
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    for (final e in _fields.entries)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: TextFormField(
                            controller: e.value,
                            enabled: !_busy,
                            obscureText: e.key == 'account_number',
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
                            decoration: InputDecoration(
                                labelText: e.key.replaceAll('_', ' ')),
                            validator: (v) {
                              final value = v?.trim() ?? '';
                              if (e.key == 'account_number')
                                return RegExp(r'^[0-9]{8,20}$').hasMatch(value)
                                    ? null
                                    : 'Enter 8–20 digits.';
                              if (e.key == 'ifsc')
                                return RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$')
                                        .hasMatch(value.toUpperCase())
                                    ? null
                                    : 'Enter a valid IFSC.';
                              if (e.key == 'upi_id') return null;
                              return value.length < 2 ? 'Required' : null;
                            },
                          )),
                    ElevatedButton(
                        onPressed: _busy ? null : _save,
                        child: const Text('Save bank details')),
                  ],
                ))),
      );
}
