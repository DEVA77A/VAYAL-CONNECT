/// Data models representing official Government AGMARKNET mandi rates
/// as provided by the VayalConnect FastAPI backend.

class MarketPriceItem {
  final String priceId;
  final String commodity;
  final String market;
  final String state;
  final String district;
  final String variety;
  final String grade;
  final int minPricePaise;
  final int maxPricePaise;
  final int modalPricePaise;
  final String minPriceDisplay;
  final String maxPriceDisplay;
  final String modalPriceDisplay;
  final int pricePerKgPaise;
  final String pricePerKgDisplay;
  final String unit;
  final String? arrivalDate;
  final String source;
  final String? retrievedAt;

  MarketPriceItem({
    required this.priceId,
    required this.commodity,
    required this.market,
    required this.state,
    required this.district,
    required this.variety,
    required this.grade,
    required this.minPricePaise,
    required this.maxPricePaise,
    required this.modalPricePaise,
    required this.minPriceDisplay,
    required this.maxPriceDisplay,
    required this.modalPriceDisplay,
    required this.pricePerKgPaise,
    required this.pricePerKgDisplay,
    required this.unit,
    this.arrivalDate,
    required this.source,
    this.retrievedAt,
  });

  factory MarketPriceItem.fromJson(Map<String, dynamic> json) {
    return MarketPriceItem(
      priceId: json['price_id'] as String? ?? json['id'] as String? ?? '',
      commodity: json['commodity'] as String? ?? '',
      market: json['market'] as String? ?? '',
      state: json['state'] as String? ?? '',
      district: json['district'] as String? ?? '',
      variety: json['variety'] as String? ?? 'Common',
      grade: json['grade'] as String? ?? 'FAQ',
      minPricePaise: (json['min_price_paise'] as num?)?.toInt() ?? 0,
      maxPricePaise: (json['max_price_paise'] as num?)?.toInt() ?? 0,
      modalPricePaise: (json['modal_price_paise'] as num?)?.toInt() ?? 0,
      minPriceDisplay: json['min_price_display'] as String? ?? '₹0.00',
      maxPriceDisplay: json['max_price_display'] as String? ?? '₹0.00',
      modalPriceDisplay: json['modal_price_display'] as String? ?? '₹0.00',
      pricePerKgPaise: (json['price_per_kg_paise'] as num?)?.toInt() ?? 0,
      pricePerKgDisplay: json['price_per_kg_display'] as String? ?? '₹0.00 / kg',
      unit: json['unit'] as String? ?? 'Quintal',
      arrivalDate: json['arrival_date'] as String?,
      source: json['source'] as String? ?? 'data.gov.in AGMARKNET',
      retrievedAt: json['retrieved_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'price_id': priceId,
      'commodity': commodity,
      'market': market,
      'state': state,
      'district': district,
      'variety': variety,
      'grade': grade,
      'min_price_paise': minPricePaise,
      'max_price_paise': maxPricePaise,
      'modal_price_paise': modalPricePaise,
      'min_price_display': minPriceDisplay,
      'max_price_display': maxPriceDisplay,
      'modal_price_display': modalPriceDisplay,
      'price_per_kg_paise': pricePerKgPaise,
      'price_per_kg_display': pricePerKgDisplay,
      'unit': unit,
      'arrival_date': arrivalDate,
      'source': source,
      'retrieved_at': retrievedAt,
    };
  }
}

class MarketPriceListResponse {
  final List<MarketPriceItem> records;
  final int count;
  final bool isLive;
  final String source;
  final String? message;

  MarketPriceListResponse({
    required this.records,
    required this.count,
    required this.isLive,
    required this.source,
    this.message,
  });

  factory MarketPriceListResponse.fromJson(Map<String, dynamic> json) {
    final rawRecords = json['records'] as List<dynamic>? ?? [];
    final items = rawRecords
        .map((r) => MarketPriceItem.fromJson(r as Map<String, dynamic>))
        .toList();

    return MarketPriceListResponse(
      records: items,
      count: (json['count'] as num?)?.toInt() ?? items.length,
      isLive: json['live'] as bool? ?? false,
      source: json['source'] as String? ?? 'data.gov.in AGMARKNET',
      message: json['message'] as String?,
    );
  }
}

class FilterOptions {
  final List<String> commodities;
  final List<String> districts;
  final String defaultState;

  FilterOptions({
    required this.commodities,
    required this.districts,
    required this.defaultState,
  });

  factory FilterOptions.fromJson(Map<String, dynamic> json) {
    return FilterOptions(
      commodities: (json['commodities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      districts: (json['districts'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      defaultState: json['default_state'] as String? ?? 'Tamil Nadu',
    );
  }
}
