import '../utils/language_rebuild.dart';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/location_service.dart';
import '../utils/commerce_strings.dart';
import '../widgets/commerce_widgets.dart';
import '../widgets/vayal_app_bar.dart';

class AddressesScreen extends StatefulWidget {
  final bool select;
  final ApiClient? api;
  const AddressesScreen({super.key, this.select = false, this.api});
  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen>
    with LanguageRebuild<AddressesScreen> {
  late final _api = widget.api ?? ApiClient();
  List<dynamic> _items = [];
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
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await _api.request('/api/v1/buyers/me/addresses');
      if (mounted) setState(() => _items = data['items']);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? address]) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            AddressEditorScreen(address: address, api: widget.api)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: VayalAppBar(
          title: S.t(widget.select ? 'Select address' : 'Addresses'),
          showBack: true),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(),
          icon: const Icon(Icons.add),
          label: Text(S.t('Add address'))),
      body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_error != null) ErrorPanel(_error!, _load),
                if (!_busy && _items.isEmpty && _error == null)
                  Text(S.t('No records yet.')),
                for (final item in _items)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item['recipient_name'],
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    Text([
                                      item['building'],
                                      item['street'],
                                      item['locality'],
                                      item['city'],
                                      item['state'],
                                      item['postal_code']
                                    ].join(', ')),
                                    Text(item['phone']),
                                    if (item['is_default'] == true)
                                      Text(S.t('Default address')),
                                    Wrap(spacing: 8, children: [
                                      TextButton(
                                          onPressed: () => _edit(
                                              Map<String, dynamic>.from(item)),
                                          child: Text(S.t('Edit'))),
                                      if (widget.select)
                                        ElevatedButton(
                                            onPressed: () {
                                              if (item['coordinates'] == null) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(SnackBar(
                                                        content: Text(S.t(
                                                            'Coordinates required for delivery estimate.'))));
                                                _edit(Map<String, dynamic>.from(
                                                    item));
                                                return;
                                              }
                                              final data =
                                                  Map<String, dynamic>.from(
                                                      item)
                                                    ..remove('id')
                                                    ..remove('is_default');
                                              data['address'] = [
                                                item['building'],
                                                item['street'],
                                                item['locality'],
                                                item['city'],
                                                item['state']
                                              ].join(', ');
                                              Navigator.pop(context, data);
                                            },
                                            child: Text(S.t('Select address'))),
                                    ]),
                                  ])))),
              ])));
}

class AddressEditorScreen extends StatefulWidget {
  final Map<String, dynamic>? address;
  final ApiClient? api;
  const AddressEditorScreen({super.key, this.address, this.api});
  @override
  State<AddressEditorScreen> createState() => _AddressEditorScreenState();
}

class _AddressEditorScreenState extends State<AddressEditorScreen>
    with LanguageRebuild<AddressEditorScreen> {
  late final _api = widget.api ?? ApiClient();
  final _form = GlobalKey<FormState>();
  static const _labels = {
    'recipient_name': 'Recipient name',
    'phone': 'Contact number',
    'building': 'House / building',
    'street': 'Street',
    'locality': 'Area / locality',
    'city': 'City / town',
    'state': 'State',
    'postal_code': 'Postal code',
    'instructions': 'Delivery instructions'
  };
  late final _fields = {
    for (final k in _labels.keys)
      k: TextEditingController(text: widget.address?[k] as String? ?? '')
  };
  Map<String, dynamic>? _coordinates;
  bool _default = false;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _coordinates = widget.address?['coordinates'] == null
        ? null
        : Map<String, dynamic>.from(widget.address!['coordinates']);
    _default = widget.address?['is_default'] == true;
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                content: Text(S.t(
                    'Confirm that you are currently at this delivery address before using GPS.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(S.t('Cancel'))),
                  ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(S.t('I am at this address')))
                ]));
    if (confirmed != true) return;
    final result = await LocationService().request();
    if (!mounted) return;
    if (result.state == LocationState.available) {
      setState(() => _coordinates = {
            'latitude': result.latitude,
            'longitude': result.longitude
          });
    } else {
      setState(
          () => _error = S.t('Unable to obtain coordinates. Please retry.'));
      if (result.state == LocationState.disabled ||
          result.state == LocationState.permanentlyDenied) {
        await LocationService.openSettings(
            services: result.state == LocationState.disabled);
      }
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = widget.address?['id'];
      await _api.request(
          '/api/v1/buyers/me/addresses${id == null ? '' : '/$id'}',
          method: id == null ? 'POST' : 'PUT',
          body: {
            for (final e in _fields.entries) e.key: e.value.text.trim(),
            'is_default': _default,
            'coordinates': _coordinates
          });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: VayalAppBar(title: S.t('Addresses'), showBack: true),
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
                    for (final e in _fields.entries)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: TextFormField(
                              controller: e.value,
                              enabled: !_busy,
                              decoration: InputDecoration(
                                  labelText: S.t(_labels[e.key]!)),
                              keyboardType:
                                  ['phone', 'postal_code'].contains(e.key)
                                      ? TextInputType.number
                                      : TextInputType.text,
                              onChanged: e.key == 'instructions' ||
                                      e.key == 'recipient_name' ||
                                      e.key == 'phone'
                                  ? null
                                  : (_) => setState(() => _coordinates = null),
                              validator: (v) {
                                if (e.key == 'instructions') return null;
                                final text = v?.trim() ?? '';
                                if (e.key == 'phone' &&
                                    !RegExp(r'^[6-9][0-9]{9}$')
                                        .hasMatch(text)) {
                                  return S.t('Enter valid details.');
                                }
                                if (e.key == 'postal_code' &&
                                    !RegExp(r'^[1-9][0-9]{5}$')
                                        .hasMatch(text)) {
                                  return S.t('Enter valid details.');
                                }
                                if (text.length <
                                    (e.key == 'building' ? 1 : 2)) {
                                  return S.t('Required');
                                }
                                return null;
                              })),
                    SwitchListTile(
                        title: Text(S.t('Default address')),
                        value: _default,
                        onChanged:
                            _busy ? null : (v) => setState(() => _default = v)),
                    OutlinedButton.icon(
                        onPressed: _busy ? null : _locate,
                        icon: const Icon(Icons.my_location),
                        label: Text(S.t('Save destination coordinates'))),
                    if (_coordinates != null)
                      Text(
                          '${_coordinates!['latitude']}, ${_coordinates!['longitude']}'),
                    ElevatedButton(
                        onPressed: _busy ? null : _save,
                        child: Text(S.t('Save'))),
                    if (widget.address != null)
                      TextButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  setState(() => _busy = true);
                                  try {
                                    await _api.request(
                                        '/api/v1/buyers/me/addresses/${widget.address!['id']}',
                                        method: 'DELETE');
                                    if (context.mounted) {
                                      Navigator.pop(context, true);
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      setState(() => _error = e.toString());
                                    }
                                  } finally {
                                    if (mounted) setState(() => _busy = false);
                                  }
                                },
                          child: Text(S.t('Delete'))),
                  ]))));
}
