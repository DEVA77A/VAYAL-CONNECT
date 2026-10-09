import 'package:flutter/material.dart';
import '../models/product_models.dart';
import '../services/product_service.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';

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
class AddProductScreen extends StatefulWidget {
  const AddProductScreen({Key? key}) : super(key: key);

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _productService = ProductService();

  final _nameController = TextEditingController(text: 'பொன்னி நெல் (Ponni Paddy)');
  final _quantityController = TextEditingController(text: '25');
  final _locationController = TextEditingController(text: 'பாபநாசம், தஞ்சாவூர்');
  final _marketController = TextEditingController(text: 'தஞ்சாவூர் ஒழுங்குமுறை விற்பனைக்கூடம்');
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
    _nameController.dispose();
    _quantityController.dispose();
    _locationController.dispose();
    _marketController.dispose();
    _productService.dispose();
    super.dispose();
  }

  void _submitHarvest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final isoDate = "${_selectedDate.year.toString().padLeft(4, '0')}-"
          "${_selectedDate.month.toString().padLeft(2, '0')}-"
          "${_selectedDate.day.toString().padLeft(2, '0')}";

      final payload = CreateProductPayload(
        productName: _nameController.text.trim(),
        category: _category,
        quantity: int.tryParse(_quantityController.text.trim()) ?? 10,
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
                            ? 'அரசு மண்டி விலை அடிப்படையில் உங்களுக்கான பட்டுவாடா தானாக கணக்கிடப்படும்.'
                            : 'Farmer payout is calculated server-side from official mandi rates.',
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
