// Source-verified market records provided by the VayalConnect backend.

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
  final String? sourceUrl;
  final String priceType;
  final String verificationStatus;
  final bool stale;
  final String priceDisplay;
  final int? pricePaise;
  final String currency;
  final String? commodityId;
  final String verificationMethod;
  final String quoteType;
  final String freshnessStatus;
  final String? referenceScope;
  final String? aggregationMethod;
  final int? observationCount;
  final List<String> observationDates;

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
    this.sourceUrl,
    this.priceType = 'unknown',
    this.verificationStatus = 'unverified',
    this.stale = false,
    this.priceDisplay = 'Unavailable',
    this.pricePaise,
    this.currency = 'INR',
    this.commodityId,
    this.verificationMethod = '',
    this.quoteType = 'unknown',
    this.freshnessStatus = 'unavailable',
    this.referenceScope,
    this.aggregationMethod,
    this.observationCount,
    this.observationDates = const [],
  });

  factory MarketPriceItem.fromJson(Map<String, dynamic> json) {
    return MarketPriceItem(
      priceId: json['price_id'] as String? ?? json['id'] as String? ?? '',
      commodity: json['commodity'] as String? ?? '',
      market: json['market'] as String? ?? '',
      state: json['state'] as String? ?? '',
      district: json['district'] as String? ?? '',
      variety: json['variety'] as String? ?? 'Unknown',
      grade: json['grade'] as String? ?? 'Unknown',
      minPricePaise: (json['min_price_paise'] as num?)?.toInt() ?? 0,
      maxPricePaise: (json['max_price_paise'] as num?)?.toInt() ?? 0,
      modalPricePaise: (json['modal_price_paise'] as num?)?.toInt() ?? 0,
      minPriceDisplay: json['min_price_display'] as String? ?? 'Unavailable',
      maxPriceDisplay: json['max_price_display'] as String? ?? 'Unavailable',
      modalPriceDisplay:
          json['modal_price_display'] as String? ?? 'Unavailable',
      pricePerKgPaise: (json['price_per_kg_paise'] as num?)?.toInt() ?? 0,
      pricePerKgDisplay:
          json['price_per_kg_display'] as String? ?? 'Unavailable',
      unit: json['unit'] as String? ?? 'Unknown',
      arrivalDate: json['arrival_date'] as String?,
      source: json['source'] as String? ?? 'Unknown source',
      retrievedAt: json['retrieved_at'] as String?,
      sourceUrl: json['source_url'] as String?,
      priceType: json['price_type'] as String? ?? 'unknown',
      verificationStatus:
          json['verification_status'] as String? ?? 'unverified',
      stale: json['stale'] == true,
      pricePaise: (json['price_paise'] as num?)?.toInt(),
      currency: json['currency'] as String? ?? 'INR',
      commodityId: json['commodity_id'] as String?,
      verificationMethod: json['verification_method'] as String? ?? '',
      quoteType: json['quote_type'] as String? ?? 'unknown',
      freshnessStatus: json['freshness_status'] as String? ??
          (json['stale'] == true ? 'stale' : 'unavailable'),
      priceDisplay: json['price_display'] as String? ??
          json['modal_price_display'] as String? ??
          'Unavailable',
      referenceScope: json['reference_scope'] as String?,
      aggregationMethod: json['aggregation_method'] as String?,
      observationCount: (json['observation_count'] as num?)?.toInt(),
      observationDates: (json['observation_dates'] as List?)
              ?.map((v) => v.toString())
              .toList() ??
          const [],
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
      'source_url': sourceUrl,
      'price_type': priceType,
      'verification_status': verificationStatus,
      'stale': stale,
      'price_display': priceDisplay,
      'price_paise': pricePaise,
      'currency': currency,
      'commodity_id': commodityId,
      'verification_method': verificationMethod,
      'quote_type': quoteType,
      'freshness_status': freshnessStatus,
      'reference_scope': referenceScope,
      'aggregation_method': aggregationMethod,
      'observation_count': observationCount,
      'observation_dates': observationDates,
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
      source: json['source'] as String? ?? 'Unknown source',
      message: json['message'] as String?,
    );
  }
}

class FilterOptions {
  final List<String> categories;
  final List<String> commodities;
  final List<String> districts;
  final String defaultState;

  FilterOptions({
    this.categories = const [],
    required this.commodities,
    required this.districts,
    required this.defaultState,
  });

  factory FilterOptions.fromJson(Map<String, dynamic> json) {
    return FilterOptions(
      categories: (json['categories'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
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
