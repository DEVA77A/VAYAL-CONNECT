/// VayalConnect Product Models
///
/// Follows strict role boundaries implemented in the backend:
/// - Farmer sees farmer payout ONLY
/// - Buyer sees buyer price ONLY
/// - Admin sees full breakdown

class FarmerProduct {
  final String productId;
  final String productName;
  final String category;
  final int quantityAvailable;
  final String quantityUnit;
  final String qualityGrade;
  final String? imageUrl;
  final String location;
  final String market;
  final String? harvestDate;
  final int farmerPayoutPerUnitPaise;
  final String farmerPayoutPerUnitDisplay;
  final String status;

  FarmerProduct({
    required this.productId,
    required this.productName,
    required this.category,
    required this.quantityAvailable,
    required this.quantityUnit,
    required this.qualityGrade,
    this.imageUrl,
    required this.location,
    required this.market,
    this.harvestDate,
    required this.farmerPayoutPerUnitPaise,
    required this.farmerPayoutPerUnitDisplay,
    this.status = 'ACTIVE',
  });

  factory FarmerProduct.fromJson(Map<String, dynamic> json) {
    return FarmerProduct(
      productId: json['product_id'] as String? ?? json['id'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      quantityAvailable: (json['quantity_available'] as num?)?.toInt() ?? 0,
      quantityUnit: json['quantity_unit'] as String? ?? 'Quintal',
      qualityGrade: json['quality_grade'] as String? ?? 'FAQ',
      imageUrl: json['image_url'] as String?,
      location: json['location'] as String? ?? '',
      market: json['market'] as String? ?? '',
      harvestDate: json['harvest_date'] as String?,
      farmerPayoutPerUnitPaise:
          (json['farmer_payout_per_unit_paise'] as num?)?.toInt() ?? 0,
      farmerPayoutPerUnitDisplay:
          json['farmer_payout_per_unit_display'] as String? ?? '₹0.00',
      status: json['status'] as String? ?? 'ACTIVE',
    );
  }
}

class BuyerProduct {
  final int farmerBasePricePaise;
  final int commissionPerUnitPaise;
  final int commissionPercentageBps;
  final String description;
  final Map<String, dynamic>? marketReference;
  final Map<String, dynamic>? farmCoordinates;
  final String productId;
  final String productName;
  final String category;
  final int quantityAvailable;
  final String quantityUnit;
  final String qualityGrade;
  final String? imageUrl;
  final String location;
  final String? farmerName;
  final String? pickupAddress;
  final bool deliveryAvailable;
  final int buyerPricePerUnitPaise;
  final String buyerPricePerUnitDisplay;
  final String? harvestDate;

  BuyerProduct({
    this.farmerBasePricePaise = 0,
    this.commissionPerUnitPaise = 0,
    this.commissionPercentageBps = 0,
    this.description = '',
    this.marketReference,
    this.farmCoordinates,
    required this.productId,
    required this.productName,
    required this.category,
    required this.quantityAvailable,
    required this.quantityUnit,
    required this.qualityGrade,
    this.imageUrl,
    required this.location,
    this.farmerName,
    this.pickupAddress,
    this.deliveryAvailable = false,
    required this.buyerPricePerUnitPaise,
    required this.buyerPricePerUnitDisplay,
    this.harvestDate,
  });

  factory BuyerProduct.fromJson(Map<String, dynamic> json) {
    return BuyerProduct(
      farmerBasePricePaise:
          (json['farmer_base_price_paise'] as num?)?.toInt() ?? 0,
      commissionPerUnitPaise:
          (json['commission_per_unit_paise'] as num?)?.toInt() ?? 0,
      commissionPercentageBps:
          (json['commission_percentage_bps'] as num?)?.toInt() ?? 0,
      description: json['description'] as String? ?? '',
      marketReference: json['market_reference'] as Map<String, dynamic>?,
      farmCoordinates: json['farm_coordinates'] as Map<String, dynamic>?,
      productId: json['product_id'] as String? ?? json['id'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      quantityAvailable: (json['quantity_available'] as num?)?.toInt() ?? 0,
      quantityUnit: json['quantity_unit'] as String? ?? 'Quintal',
      qualityGrade: json['quality_grade'] as String? ?? 'FAQ',
      imageUrl: json['image_url'] as String?,
      location: json['location'] as String? ?? '',
      farmerName: json['farmer_name'] as String?,
      pickupAddress: json['pickup_address'] as String?,
      deliveryAvailable: json['delivery_available'] == true,
      buyerPricePerUnitPaise:
          (json['buyer_price_per_unit_paise'] as num?)?.toInt() ?? 0,
      buyerPricePerUnitDisplay:
          json['buyer_price_per_unit_display'] as String? ?? '₹0.00',
      harvestDate: json['harvest_date'] as String?,
    );
  }
}

class CreateProductPayload {
  final int sellingPricePerUnitPaise;
  final String productName;
  final String category;
  final int quantity;
  final String quantityUnit;
  final String qualityGrade;
  final String location;
  final String market;
  final String? harvestDate;
  final String? imageUrl;

  CreateProductPayload({
    required this.productName,
    required this.sellingPricePerUnitPaise,
    required this.category,
    required this.quantity,
    this.quantityUnit = 'Quintal',
    this.qualityGrade = 'FAQ',
    required this.location,
    required this.market,
    this.harvestDate,
    this.imageUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'product_name': productName,
      'selling_price_per_unit_paise': sellingPricePerUnitPaise,
      'category': category,
      'quantity': quantity,
      'quantity_unit': quantityUnit,
      'quality_grade': qualityGrade,
      'location': location,
      'market': market,
      if (harvestDate != null) 'harvest_date': harvestDate,
      if (imageUrl != null) 'image_url': imageUrl,
    };
  }
}
