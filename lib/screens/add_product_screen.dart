import '../utils/form_examples.dart';
import '../utils/language_rebuild.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../services/api_client.dart';
import '../services/session_manager.dart';
import '../utils/commerce_strings.dart';
import '../utils/money_input.dart';
import '../config/api_config.dart';
import '../widgets/vayal_app_bar.dart';
import '../widgets/market_reference_view.dart';

class AddProductScreen extends StatefulWidget {
  final Map<String, dynamic>? product;
  final ApiClient? api;
  const AddProductScreen({super.key, this.product, this.api});
  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen>
    with LanguageRebuild<AddProductScreen> {
  late final _api = widget.api ?? ApiClient();
  final _form = GlobalKey<FormState>();
  late final _fields = {
    for (final k in [
      'product_name',
      'description',
      'quantity',
      'selling_price',
      'location',
      'market',
      'state',
      'district',
      'variety',
      'new_category',
      'stock_adjustment'
    ])
      k: TextEditingController()
  };
  String _category = 'Grains', _unit = 'KG', _grade = 'A', _status = 'ACTIVE';
  DateTime _date = DateTime.now();
  String? _image;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _reference;
  Timer? _referenceTimer;
  int _referenceRequest = 0;
  bool _manualPrice = false;
  bool _referenceLoading = false;
  final Set<String> _registeredCategories = {};
  bool get _editing => widget.product != null;
  @override
  void initState() {
    super.initState();
    _fields['state']!.text = 'Tamil Nadu';
    final p = widget.product;
    if (p != null) {
      _manualPrice = true;
      for (final k in [
        'product_name',
        'description',
        'location',
        'market',
        'state',
        'district',
        'variety'
      ]) {
        _fields[k]!.text = p[k] as String? ?? '';
      }
      _fields['selling_price']!.text =
          ((p['farmer_payout_per_unit_paise'] as num) / 100).toStringAsFixed(2);
      _fields['stock_adjustment']!.text = '0';
      _unit = (p['quantity_unit'] as String? ?? 'KG').toUpperCase();
      _category = p['category'];
      _grade = p['quality_grade'];
      _image = p['image_url'];
      _status = p['status'] == 'INACTIVE' ? 'INACTIVE' : 'ACTIVE';
      _date = DateTime.tryParse(p['harvest_date'] ?? '') ?? DateTime.now();
    }
    _loadCategories();
    if (_editing) _queueReference();
  }

  Future<void> _loadCategories() async {
    try {
      final options =
          await _api.request('/api/v1/market-prices/filter-options');
      final categories = options['categories'];
      if (mounted && categories is List) {
        setState(
            () => _registeredCategories.addAll(categories.whereType<String>()));
      }
    } catch (_) {
      // Crop entry remains available when cached filter options cannot be read.
    }
  }

  @override
  void dispose() {
    _referenceTimer?.cancel();
    for (final c in _fields.values) {
      c.dispose();
    }
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  Future<void> _photo() async {
    setState(() => _busy = true);
    final client = http.Client();
    try {
      final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 82);
      if (picked == null || !mounted) return;
      final req = http.MultipartRequest(
          'POST', Uri.parse('${ApiConfig.baseUrl}/api/v1/media'));
      req.headers['Authorization'] = 'Bearer ${SessionManager().accessToken}';
      req.files.add(http.MultipartFile.fromBytes(
          'file', await picked.readAsBytes(),
          filename: 'crop.jpg'));
      final response = await http.Response.fromStream(await client.send(req))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 201) {
        throw Exception(S.t('Unable to complete this request. Please retry.'));
      }
      if (mounted) {
        setState(() => _image = jsonDecode(response.body)['data']['image_url']);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _queueReference() {
    _referenceTimer?.cancel();
    _referenceRequest++;
    _referenceLoading = false;
    if (!_manualPrice) _fields['selling_price']!.clear();
    final crop = _fields['product_name']!.text.trim().toLowerCase();
    if (!const {
      'tomato',
      'தக்காளி',
      'banana fruit',
      'banana (fruit)',
      'வாழைப்பழம்',
      'jasmine',
      'மல்லிகை',
      'marigold',
    }.contains(crop)) {
      if (crop.isNotEmpty) _reference = {'reference_price_available': false};
      return;
    }
    _referenceLoading = true;
    _referenceTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted && !_busy) _lookup(background: true);
    });
  }

  Future<void> _lookup({bool background = false}) async {
    final request = ++_referenceRequest;
    if (_fields['product_name']!.text.trim().length < 2) {
      setState(() => _error = S.t('Enter crop name.'));
      return;
    }
    setState(() {
      if (!background) _busy = true;
      _error = null;
      _reference = null;
      _referenceLoading = true;
      if (!_manualPrice) _fields['selling_price']!.clear();
    });
    try {
      final uri =
          Uri(path: '/api/v1/products/price-reference', queryParameters: {
        'commodity': _fields['product_name']!.text.trim(),
        'unit': _unit,
        if (_fields['variety']!.text.trim().isNotEmpty)
          'variety': _fields['variety']!.text.trim(),
      });
      // Backend reads MongoDB only. Upload registers crops for future daily runs.
      final r = await _api.request(uri.toString());
      if (mounted && request == _referenceRequest) {
        setState(() {
          _reference = Map<String, dynamic>.from(r);
          final suggested = r['reference_price_per_listing_unit_paise'];
          if (!_manualPrice &&
              r['reference_price_available'] == true &&
              r['reference_verification_status'] == 'verified' &&
              r['reference_price_stale'] == false &&
              suggested is int &&
              suggested > 0 &&
              suggested <= 100000000) {
            _fields['selling_price']!.text =
                (suggested / 100).toStringAsFixed(2);
          }
        });
      }
    } catch (e) {
      if (mounted && request == _referenceRequest) {
        setState(() {
          _reference = {'reference_price_available': false};
          if (!background) _error = e.toString();
        });
      }
    } finally {
      if (mounted && request == _referenceRequest) {
        setState(() => _referenceLoading = false);
      }
      if (mounted && !background) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final price = parseSellingPricePaise(_fields['selling_price']!.text)!;
      final body = <String, dynamic>{
        'selling_price_per_unit_paise': price,
        'description': _fields['description']!.text.trim(),
        'harvest_date': _date.toIso8601String().substring(0, 10),
        'quality_grade': _grade,
        if (_image != null) 'image_url': _image
      };
      if (_editing) {
        body.addAll({
          'stock_adjustment': int.parse(_fields['stock_adjustment']!.text),
          'status': _status
        });
      } else {
        body.addAll({
          'product_name': _fields['product_name']!.text.trim(),
          'category': _category,
          'quantity': int.parse(_fields['quantity']!.text),
          'quantity_unit': _unit,
          'location': _fields['location']!.text.trim(),
          'market': _fields['market']!.text.trim(),
          if (_fields['state']!.text.trim().isNotEmpty)
            'state': _fields['state']!.text.trim(),
          if (_fields['district']!.text.trim().isNotEmpty)
            'district': _fields['district']!.text.trim(),
          if (_fields['variety']!.text.trim().isNotEmpty)
            'variety': _fields['variety']!.text.trim(),
        });
      }
      await _api.request(
          '/api/v1/products/${_editing ? widget.product!['product_id'] : ''}',
          method: _editing ? 'PUT' : 'POST',
          timeout: const Duration(seconds: 150),
          body: body);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String key, String label,
          {bool required = false, bool number = false, bool editable = true}) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TextFormField(
              controller: _fields[key],
              onChanged: (value) => setState(() {
                    if (key == 'selling_price') _manualPrice = true;
                    if ([
                      'product_name',
                      'market',
                      'state',
                      'district',
                      'variety'
                    ].contains(key)) {
                      _reference = null;
                      _queueReference();
                    }
                  }),
              enabled: !_busy && editable,
              keyboardType: number
                  ? TextInputType.numberWithOptions(
                      decimal: key == 'selling_price',
                      signed: key == 'stock_adjustment')
                  : TextInputType.text,
              maxLines: key == 'description' ? 3 : 1,
              textCapitalization: number
                  ? TextCapitalization.none
                  : key == 'description'
                      ? TextCapitalization.sentences
                      : TextCapitalization.words,
              decoration: InputDecoration(
                  labelText: S.t(label),
                  hintText: FormExamples.hint(key),
                  hintStyle: FormExamples.style),
              validator: (value) {
                final v = value?.trim() ?? '';
                if (key == 'selling_price' &&
                    parseSellingPricePaise(v) == null) {
                  return S
                      .t('Enter a valid price with up to two decimal places.');
                }
                if (key == 'quantity' &&
                    (int.tryParse(v) == null ||
                        int.parse(v) <= 0 ||
                        int.parse(v) > 1000000)) {
                  return S.t('Enter a valid quantity.');
                }
                if (key == 'stock_adjustment' &&
                    (int.tryParse(v) == null || int.parse(v).abs() > 1000000)) {
                  return S.t('Enter a valid quantity.');
                }
                if (required && v.length < 2) return S.t('Required');
                return null;
              }));
  @override
  Widget build(BuildContext context) {
    final categories = {
      'Grains',
      'Pulses and legumes',
      'Vegetables',
      'Fruits',
      'Flowers',
      'Spices',
      'Oilseeds',
      'Plantation crops',
      'Sugarcane',
      'Fodder',
      'Medicinal and aromatic plants',
      'Nursery and horticultural products',
      'Other agricultural products',
      ..._registeredCategories,
      _category
    };
    return Scaffold(
        appBar: VayalAppBar(
            title: S.t(_editing ? 'Edit' : 'Add crop'), showBack: true),
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
                key: _form,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_busy) const LinearProgressIndicator(),
                      if (_error != null)
                        Text(_error!,
                            style: const TextStyle(color: Colors.red)),
                      Text(S.t(
                          'Farmer receives the full base price. Commission is added for buyers.')),
                      _field('product_name', 'Crop name',
                          required: true, editable: !_editing),
                      _field('description', 'Description'),
                      DropdownButtonFormField<String>(
                          value: _category,
                          isExpanded: true,
                          decoration:
                              InputDecoration(labelText: S.t('Category')),
                          items: categories
                              .map((c) => DropdownMenuItem(
                                  value: c, child: Text(S.t(c))))
                              .toList(),
                          onChanged: _editing || _busy
                              ? null
                              : (v) => setState(() {
                                    _category = v!;
                                    _fields['new_category']!.clear();
                                    _reference = null;
                                    _queueReference();
                                  })),
                      if (!_editing)
                        TextFormField(
                          controller: _fields['new_category'],
                          enabled: !_busy,
                          maxLength: 100,
                          decoration: InputDecoration(
                              labelText: S.t('New crop category (optional)'),
                              hintText: FormExamples.hint('new_category'),
                              hintStyle: FormExamples.style),
                          validator: (value) => value != null &&
                                  value.trim().isNotEmpty &&
                                  value.trim().length < 2
                              ? S.t('Required')
                              : null,
                          onChanged: (value) => setState(() {
                            if (value.trim().length >= 2) {
                              _category = value.trim();
                            }
                            _reference = null;
                            _queueReference();
                          }),
                        ),
                      if (!_editing)
                        _field('quantity', 'Quantity',
                            required: true, number: true),
                      if (_editing) ...[
                        _field('stock_adjustment', 'Stock adjustment',
                            number: true),
                        Text(S.t(
                            'Add units with a positive number; remove with a negative number.'))
                      ],
                      DropdownButtonFormField<String>(
                          value: _unit,
                          decoration: InputDecoration(
                              labelText: S.t('Unit'),
                              helperText: _unit.toLowerCase()),
                          items: [
                            'KG',
                            'QUINTAL',
                            'TON',
                            'PIECE',
                            'DOZEN',
                            'BUNCH',
                            'BUNDLE',
                            'COUNT'
                          ]
                              .map((u) =>
                                  DropdownMenuItem(value: u, child: Text(u)))
                              .toList(),
                          onChanged: _editing || _busy
                              ? null
                              : (v) => setState(() {
                                    _unit = v!;
                                    _reference = null;
                                    _queueReference();
                                  })),
                      _field('selling_price', 'Your selling price',
                          required: true, number: true),
                      if (_referenceLoading) ...[
                        const LinearProgressIndicator(),
                        Text(S.t('Loading verified price suggestion...')),
                      ] else if (_reference != null)
                        Text(S.t(!_manualPrice &&
                                _fields['selling_price']!.text.isNotEmpty
                            ? 'Verified suggestion filled in. You can change your selling price.'
                            : _manualPrice
                                ? 'Your entered selling price is preserved.'
                                : 'No current verified suggestion is available. Enter your own selling price.')),
                      _field('location', 'Farm location',
                          required: true, editable: !_editing),
                      _field('market', 'Nearest mandi',
                          required: true, editable: !_editing),
                      ExpansionTile(
                          title: Text(S.t('Price lookup context')),
                          children: [
                            _field('state', 'State for price lookup'),
                            _field('district', 'District for price lookup'),
                            _field('variety', 'Variety for price lookup'),
                          ]),
                      ListTile(
                          title: Text(S.t('Harvest date')),
                          subtitle:
                              Text(_date.toIso8601String().substring(0, 10)),
                          trailing: const Icon(Icons.calendar_today),
                          onTap: _busy
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                      context: context,
                                      initialDate: _date,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now()
                                          .add(const Duration(days: 365)));
                                  if (picked != null) {
                                    setState(() => _date = picked);
                                  }
                                }),
                      if (_editing)
                        DropdownButtonFormField<String>(
                            value: _status,
                            items: ['ACTIVE', 'INACTIVE']
                                .map((s) => DropdownMenuItem(
                                    value: s, child: Text(S.status(s))))
                                .toList(),
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _status = v!)),
                      OutlinedButton.icon(
                          onPressed: _busy ? null : _photo,
                          icon: const Icon(Icons.add_a_photo),
                          label: Text(S.t('Crop photograph'))),
                      if (_image != null) Text(S.t('Photograph saved')),
                      OutlinedButton(
                          onPressed: _busy ? null : _lookup,
                          child: Text(S.t('Verified market reference'))),
                      if (_reference != null)
                        MarketReferenceView(
                            reference: _reference,
                            sellingPricePaise: parseSellingPricePaise(
                                _fields['selling_price']!.text)),
                      ElevatedButton(
                          onPressed: _busy ? null : _save,
                          child: Text(S.t(_editing ? 'Save' : 'Publish'))),
                    ]))));
  }
}
