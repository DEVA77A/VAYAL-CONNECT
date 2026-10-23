import '../widgets/brand_widgets.dart';
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
import '../theme/app_theme.dart';

class AddProductScreen extends StatefulWidget {
  final Map<String, dynamic>? product;
  final ApiClient? api;
  final String? initialImageUrl;
  const AddProductScreen(
      {super.key, this.product, this.api, this.initialImageUrl});
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
  late final _focusNodes = {
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
      k: FocusNode()
  };
  String _category = 'Grains', _unit = 'KG', _grade = 'A', _status = 'ACTIVE';
  DateTime _date = DateTime.now();
  String? _image;
  String? _imageError;
  bool _imageUploading = false;
  bool _imageVerified = false;
  String? _validatedCropName;
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
      _imageVerified = _image != null && _image!.isNotEmpty;
      _validatedCropName = p['product_name'] as String?;
      _status = p['status'] == 'INACTIVE' ? 'INACTIVE' : 'ACTIVE';
      _date = DateTime.tryParse(p['harvest_date'] ?? '') ?? DateTime.now();
    } else if (widget.initialImageUrl != null) {
      _image = widget.initialImageUrl;
      _imageVerified = true;
      _validatedCropName = _fields['product_name']?.text;
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
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    for (final c in _fields.values) {
      c.dispose();
    }
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final cropName = _fields['product_name']!.text.trim();
    if (cropName.isEmpty) {
      _focusNodes['product_name']?.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.t('Please enter crop name before selecting image')),
          backgroundColor: AppTheme.earthBrown,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 82,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _imageUploading = true;
      _imageError = null;
      _error = null;
    });

    final client = http.Client();
    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/api/v1/media'),
      );
      req.headers['Authorization'] = 'Bearer ${SessionManager().accessToken}';
      req.fields['crop_name'] = cropName;
      final bytes = await picked.readAsBytes();
      req.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: picked.name.isNotEmpty ? picked.name : 'crop.jpg',
      ));

      final streamed =
          await client.send(req).timeout(const Duration(seconds: 45));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _image = data['data']?['image_url'] ?? data['image_url'];
            _imageVerified = true;
            _validatedCropName = cropName;
            _imageError = null;
          });
        }
      } else {
        String msg = S.t('Unable to complete this request. Please retry.');
        try {
          final errJson = jsonDecode(response.body);
          if (errJson['detail'] != null) {
            msg = errJson['detail'].toString();
          } else if (errJson['message'] != null) {
            msg = errJson['message'].toString();
          }
        } catch (_) {}
        if (mounted) {
          setState(() {
            _image = null;
            _imageVerified = false;
            _imageError = msg;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _image = null;
          _imageVerified = false;
          _imageError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      client.close();
      if (mounted) setState(() => _imageUploading = false);
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                S.t('Upload Crop Image'),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined,
                    color: AppTheme.primaryGreen),
                title: Text(S.t('Take Photo')),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined,
                    color: AppTheme.primaryGreen),
                title: Text(S.t('Choose from Gallery')),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCropImageSection() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _imageError != null
              ? Colors.red.shade400
              : (_image == null
                  ? Colors.orange.shade300
                  : AppTheme.primaryGreen.withOpacity(0.5)),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.photo_camera_rounded,
                  color: AppTheme.primaryGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  S.t('Crop Image — Required'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _image != null && _imageVerified
                      ? AppTheme.softGreen
                      : (_image != null && !_imageVerified
                          ? const Color(0xFFFFF3E0)
                          : Colors.orange.shade50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _image != null && _imageVerified
                        ? AppTheme.primaryGreen
                        : (_image != null && !_imageVerified
                            ? AppTheme.warningOrange
                            : Colors.orange),
                  ),
                ),
                child: Text(
                  _image != null && _imageVerified
                      ? '✓ ${S.t('Image verified successfully')}'
                      : (_image != null && !_imageVerified
                          ? S.t('Crop changed — re-validation required')
                          : S.t('Required')),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _image != null && _imageVerified
                        ? AppTheme.primaryDarkGreen
                        : (_image != null && !_imageVerified
                            ? AppTheme.warningOrange
                            : Colors.orange.shade800),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            S.t('Please upload a genuine photograph of your crop.'),
            style:
                const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          if (_imageUploading) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    S.t('Validating image with AI...'),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ] else if (_image != null && _image!.isNotEmpty) ...[
            Text(
              S.t('Image Preview'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: CropImage(
                  _image,
                  fit: BoxFit.cover,
                  semanticLabel: _fields['product_name']!.text,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy || _imageUploading
                        ? null
                        : _showImageSourceDialog,
                    icon: const Icon(Icons.cached_rounded, size: 18),
                    label: Text(S.t('Replace Image')),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _busy || _imageUploading
                      ? null
                      : () => setState(() {
                            _image = null;
                            _imageError = null;
                          }),
                  tooltip: S.t('Remove Image'),
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.red),
                ),
              ],
            ),
          ] else ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.backgroundWarm,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.grey.shade300,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  const Icon(Icons.add_photo_alternate_outlined,
                      size: 48, color: AppTheme.primaryGreen),
                  const SizedBox(height: 8),
                  Text(
                    S.t('Upload Crop Image'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _busy || _imageUploading
                            ? null
                            : () => _pickImage(ImageSource.camera),
                        icon:
                            const Icon(Icons.camera_alt_rounded, size: 18),
                        label: Text(S.t('Take Photo')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryGreen,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy || _imageUploading
                            ? null
                            : () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_rounded,
                            size: 18),
                        label: Text(S.t('Choose from Gallery')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (_imageError != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _imageError!,
                      style: TextStyle(
                        color: Colors.red.shade900,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
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
    final formValid = _form.currentState!.validate();
    final hasImage = _image != null && _image!.trim().isNotEmpty;
    if (!hasImage || _imageError != null) {
      setState(() {
        _imageError = S.t('Crop image is required before publishing');
      });
      _focusNodes['product_name']?.unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.t('Crop image is required before publishing')),
          backgroundColor: AppTheme.errorRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!formValid) return;
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
        'image_url': _image!,
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
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (mounted) {
        setState(() {
          _error = msg;
          if (msg.toLowerCase().contains('image') || msg.contains('படம்')) {
            _imageError = msg;
            _imageVerified = false;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String key, String label,
          {bool required = false, bool number = false, bool editable = true}) =>
      Padding(
          key: ValueKey('field_padding_$key'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TextFormField(
              key: ValueKey('field_input_$key'),
              controller: _fields[key],
              focusNode: _focusNodes[key],
              onChanged: (value) {
                if (key == 'selling_price') {
                  _manualPrice = true;
                } else if (key == 'product_name') {
                  final cur = _fields['product_name']!.text.trim();
                  if (_validatedCropName != null &&
                      cur.toLowerCase() != _validatedCropName!.toLowerCase()) {
                    setState(() {
                      _imageVerified = false;
                    });
                  }
                  _reference = null;
                  _queueReference();
                } else if (key == 'variety') {
                  _reference = null;
                  _queueReference();
                }
              },
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
        body: PageBody(
            child: SingleChildScrollView(
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
                          _buildCropImageSection(),
                          const FormSection('Crop name'),
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
                                      value: c,
                                      child: Text(S.t(c),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis)))
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
                                  labelText:
                                      S.t('New crop category (optional)'),
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
                          const FormSection('Available stock',
                              icon: Icons.inventory_2_outlined),
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
                              isExpanded: true,
                              itemHeight: null,
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
                                  .map((u) => DropdownMenuItem(
                                      value: u, child: Text(u)))
                                  .toList(),
                              onChanged: _editing || _busy
                                  ? null
                                  : (v) => setState(() {
                                        _unit = v!;
                                        _reference = null;
                                        _queueReference();
                                      })),
                          const FormSection('Your selling price',
                              icon: Icons.payments_outlined),
                          _field('selling_price', 'Your selling price',
                              required: true, number: true),
                          Padding(
                            key: const ValueKey('price_suggestion_box'),
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_referenceLoading) ...[
                                  const LinearProgressIndicator(minHeight: 3),
                                  const SizedBox(height: 4),
                                  Text(
                                    S.t('Loading verified price suggestion...'),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary),
                                  ),
                                ] else if (_reference != null) ...[
                                  Text(
                                    S.t(!_manualPrice &&
                                            _fields['selling_price']!
                                                .text
                                                .isNotEmpty
                                        ? 'Verified suggestion filled in. You can change your selling price.'
                                        : _manualPrice
                                            ? 'Your entered selling price is preserved.'
                                            : 'No current verified suggestion is available. Enter your own selling price.'),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const FormSection('Farm location',
                              icon: Icons.location_on_outlined),
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
                          const FormSection('Harvest date',
                              icon: Icons.calendar_today_outlined),
                          ListTile(
                              title: Text(S.t('Harvest date')),
                              subtitle: Text(
                                  _date.toIso8601String().substring(0, 10)),
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
                                isExpanded: true,
                                itemHeight: null,
                                value: _status,
                                items: ['ACTIVE', 'INACTIVE']
                                    .map((s) => DropdownMenuItem(
                                        value: s, child: Text(S.status(s))))
                                    .toList(),
                                onChanged: _busy
                                    ? null
                                    : (v) => setState(() => _status = v!)),
                          OutlinedButton(
                              onPressed: _busy ? null : _lookup,
                              child: Text(S.t('Verified market reference'))),
                          if (_reference != null)
                            MarketReferenceView(
                                reference: _reference,
                                sellingPricePaise: parseSellingPricePaise(
                                    _fields['selling_price']!.text)),
                          const SizedBox(height: 24),
                          ElevatedButton(
                              onPressed: (_busy || _imageUploading) ? null : _save,
                              child: Text(S.t(_editing ? 'Save' : 'Publish'))),
                        ])))));
  }
}
