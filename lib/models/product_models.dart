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
      farmerPayoutPerUnitPaise: (json['farmer_payout_per_unit_paise'] as num?)?.toInt() ?? 0,
      farmerPayoutPerUnitDisplay: json['farmer_payout_per_unit_display'] as String? ?? '₹0.00',
      status: json['status'] as String? ?? 'ACTIVE',
    );
  }
}

class BuyerProduct {
  final String productId;
  final String productName;
  final String category;
  final int quantityAvailable;
  final String quantityUnit;
  final String qualityGrade;
  final String? imageUrl;
  final String location;
  final String? farmerName;
  final int buyerPricePerUnitPaise;
  final String buyerPricePerUnitDisplay;
  final String? harvestDate;

  BuyerProduct({
    required this.productId,
    required this.productName,
    required this.category,
    required this.quantityAvailable,
    required this.quantityUnit,
    required this.qualityGrade,
    this.imageUrl,
    required this.location,
    this.farmerName,
    required this.buyerPricePerUnitPaise,
    required this.buyerPricePerUnitDisplay,
    this.harvestDate,
  });

  factory BuyerProduct.fromJson(Map<String, dynamic> json) {
    return BuyerProduct(
      productId: json['product_id'] as String? ?? json['id'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      quantityAvailable: (json['quantity_available'] as num?)?.toInt() ?? 0,
      quantityUnit: json['quantity_unit'] as String? ?? 'Quintal',
      qualityGrade: json['quality_grade'] as String? ?? 'FAQ',
      imageUrl: json['image_url'] as String?,
      location: json['location'] as String? ?? '',
      farmerName: json['farmer_name'] as String?,
      buyerPricePerUnitPaise: (json['buyer_price_per_unit_paise'] as num?)?.toInt() ?? 0,
      buyerPricePerUnitDisplay: json['buyer_price_per_unit_display'] as String? ?? '₹0.00',
      harvestDate: json['harvest_date'] as String?,
    );
  }
}

class CreateProductPayload {
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
