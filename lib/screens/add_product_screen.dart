import 'package:flutter/material.dart';
import '../models/product_models.dart';
import '../services/product_service.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import '../utils/money_input.dart';

/// Farmer Add Harvest Listing Screen
///
/// Sends exact backend schema fields:
/// - product_name (str, min 2)
/// - category (str, min 2)
/// - quantity (int > 0)
/// - quantity_unit: "QUINTAL" | "KG" | "TON" | "PIECE" | "DOZEN"
/// - quality_grade: "PREMIUM" | "A" | "B" | "C"
/// - location (str)
/// - market (str)
/// - harvest_date (YYYY-MM-DD)
/// - selling_price_per_unit_paise (positive integer payout price)
class AddProductScreen extends StatefulWidget {
  const AddProductScreen({Key? key}) : super(key: key);

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _productService = ProductService();

  final _nameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _locationController = TextEditingController();
  final _marketController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  bool _referenceBusy = false;
  DateTime _selectedDate = DateTime.now();

  String _category = 'தானியங்கள் (Grains)';
  String _unit = 'QUINTAL';
  String _grade = 'A';
  bool _isSubmitting = false;

  final List<String> _categories = [
    'தானியங்கள் (Grains)',
    'காய்கறிகள் (Vegetables)',
    'பழங்கள் (Fruits)',
    'மசாலா (Spices)',
    'எண்ணெய் வித்துக்கள் (Oilseeds)',
  ];

  // Exactly matching QuantityUnit enum in backend
  final List<Map<String, String>> _units = [
    {'value': 'QUINTAL', 'label': 'குவிண்டால் (Quintal - 100 kg)'},
    {'value': 'KG', 'label': 'கிலோ (Kg)'},
    {'value': 'TON', 'label': 'டன் (Ton - 1000 kg)'},
    {'value': 'PIECE', 'label': 'எண்ணிக்கை (Piece)'},
    {'value': 'DOZEN', 'label': 'டஜன் (Dozen)'},
  ];

  // Exactly matching QualityGrade enum in backend
  final List<Map<String, String>> _grades = [
    {'value': 'PREMIUM', 'label': 'முதல் தரம் (Premium Grade)'},
    {'value': 'A', 'label': 'தரம் A (Grade A Super)'},
    {'value': 'B', 'label': 'தரம் B (Grade B FAQ)'},
    {'value': 'C', 'label': 'தரம் C (Grade C)'},
  ];

  @override
  void dispose() {
    _sellingPriceController.dispose();
    _nameController.dispose();
    _quantityController.dispose();
    _locationController.dispose();
    _marketController.dispose();
    _productService.dispose();
    super.dispose();
  }

  void _submitHarvest() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final isoDate = "${_selectedDate.year.toString().padLeft(4, '0')}-"
          "${_selectedDate.month.toString().padLeft(2, '0')}-"
          "${_selectedDate.day.toString().padLeft(2, '0')}";

      final payload = CreateProductPayload(
        productName: _nameController.text.trim(),
        sellingPricePerUnitPaise: parseSellingPricePaise(_sellingPriceController.text)!,
        category: _category,
        quantity: int.parse(_quantityController.text.trim()),
        quantityUnit: _unit,
        qualityGrade: _grade,
        location: _locationController.text.trim(),
        market: _marketController.text.trim(),
        harvestDate: isoDate,
      );

      final created = await _productService.createProduct(payload);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'பயிர் வெற்றிகரமாக பட்டியலிடப்பட்டது! கணக்கிடப்பட்ட பட்டுவாடா: ${created.farmerPayoutPerUnitDisplay}',
          ),
          backgroundColor: AppTheme.primaryGreen,
          duration: const Duration(seconds: 3),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('சேர்க்க முடியவில்லை: $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _showReference() async {
    if (_nameController.text.trim().length < 2 || _marketController.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter the official commodity and mandi names first.')));
      return;
    }
    setState(() => _referenceBusy = true);
    try {
      final ref = await _productService.fetchPriceReference(commodity: _nameController.text.trim(), market: _marketController.text.trim(), unit: _unit);
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        title: Text(ref['reference_commodity'].toString() + ' • ' + ref['reference_market'].toString()),
        content: Text('Source: ' + ref['reference_price_source'].toString() + '\nDate: ' + ref['reference_price_date'].toString() +
          '\nReported: ₹' + ((ref['government_reference_price_paise'] as num) / 100).toStringAsFixed(2) + ' / ' + ref['reference_price_unit'].toString() +
          '\nComparison: ₹' + ((ref['reference_price_per_listing_unit_paise'] as num) / 100).toStringAsFixed(2) + ' / ' + ref['reference_listing_unit'].toString() +
          '\n' + (ref['reference_price_cached'] == true ? 'Cached official record' : 'Fetched official record') +
          '\n' + (ref['reference_price_stale'] == true ? 'Historical rate (older than one day)' : 'Rate dated today or yesterday') +
          '\nReference only. Your selected selling price is unchanged.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Verified reference unavailable: ' + e.toString())));
    } finally { if (mounted) setState(() => _referenceBusy = false); }
  }

  void _pickHarvestDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryGreen,
              onPrimary: Colors.white,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionManager();
    final dateDisplay = "${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}";

    return Scaffold(
      backgroundColor: AppTheme.backgroundWarm,
      appBar: AppBar(
        title: Text(session.isTamil ? 'புதிய பயிர் சேர்' : 'List New Harvest'),
        backgroundColor: AppTheme.primaryGreen,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info Banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCream,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accentGold.withOpacity(0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppTheme.accentGold, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        session.isTamil
                            ? 'உங்கள் விற்பனை விலையை தேர்வு செய்யவும். மண்டி விலை ஒப்பீட்டுக்கு மட்டுமே.'
                            : 'Choose your payout price per listing unit. The server adds platform commission for buyers. Mandi rates are references only.',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Text(
                session.isTamil ? 'பயிர் பெயர் (Crop Name)' : 'Crop Name',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                validator: (v) => v == null || v.trim().length < 2 ? 'பயிர் பெயரை உள்ளிடவும் (குறைந்தது 2 எழுத்துக்கள்)' : null,
                decoration: const InputDecoration(hintText: 'எ.கா: பொன்னி நெல், தக்காளி'),
              ),

              const SizedBox(height: 14),

              Text(
                session.isTamil ? 'பயிர் வகை (Category)' : 'Category',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(),
                items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),

              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.isTamil ? 'அளவு (Quantity)' : 'Quantity',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _quantityController,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = int.tryParse(v ?? '');
                            if (n == null || n <= 0) return 'சரியான அளவை உள்ளிடவும்';
                            return null;
                          },
                          decoration: const InputDecoration(hintText: 'எ.கா: 25'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.isTamil ? 'அலகு (Unit)' : 'Unit',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          value: _unit,
                          decoration: const InputDecoration(),
                          items: _units.map((u) => DropdownMenuItem(
                            value: u['value'],
                            child: Text(u['label']!, style: const TextStyle(fontSize: 13)),
                          )).toList(),
                          onChanged: (v) => setState(() => _unit = v ?? _unit),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              Text(
                session.isTamil ? 'தரம் (Quality Grade)' : 'Quality Grade',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _grade,
                decoration: const InputDecoration(),
                items: _grades.map((g) => DropdownMenuItem(
                  value: g['value'],
                  child: Text(g['label']!, style: const TextStyle(fontSize: 13)),
                )).toList(),
                onChanged: (v) => setState(() => _grade = v ?? _grade),
              ),

              const SizedBox(height: 14),

              Text(
                session.isTamil ? 'அறுவடை தேதி (Harvest Date)' : 'Harvest Date',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: _pickHarvestDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(dateDisplay, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      const Icon(Icons.calendar_today, size: 18, color: AppTheme.primaryGreen),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              Text(
                session.isTamil ? 'பண்ணை இருப்பிடம் (Location)' : 'Farm Location',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _locationController,
                validator: (v) => v == null || v.trim().length < 2 ? 'இருப்பிடத்தை உள்ளிடவும்' : null,
                decoration: const InputDecoration(hintText: 'எ.கா: பாபநாசம், தஞ்சாவூர்'),
              ),

              const SizedBox(height: 14),

              Text(
                session.isTamil ? 'அருகிலுள்ள APMC மண்டி (Nearest Mandi)' : 'Nearest Mandi',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _marketController,
                validator: (v) => v == null || v.trim().length < 2 ? 'மண்டியை உள்ளிடவும்' : null,
                decoration: const InputDecoration(hintText: 'எ.கா: தஞ்சாவூர் ஒழுங்குமுறை விற்பனைக்கூடம்'),
              ),

              const SizedBox(height: 14),
              OutlinedButton.icon(onPressed: _referenceBusy || _isSubmitting ? null : _showReference,
                icon: const Icon(Icons.compare_arrows), label: const Text('Look up verified mandi reference')),
              TextFormField(controller: _sellingPriceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Your selling price (₹ per ' + _unit + ')'),
                validator: (v) => parseSellingPricePaise(v ?? '') == null ? 'Enter ₹0.01–₹1,000,000 with up to 2 decimal places.' : null),
              const Text('Delivery, if offered, is included in this price. A valid official reference is required to publish.'),
              const SizedBox(height: 24),

              ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitHarvest,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  session.isTamil ? 'பட்டியலை உறுதிசெய் • Submit Listing' : 'Submit Listing',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
