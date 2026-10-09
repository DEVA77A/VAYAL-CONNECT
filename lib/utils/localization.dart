/// VayalConnect Localization Helper
///
/// Provides bilingual Tamil (தமிழ்) and English strings for the VayalConnect ecosystem.
class VayalStrings {
  VayalStrings._();

  static bool isTamil = true; // Tamil default for authentic agricultural experience

  static void setLanguage(bool tamil) {
    isTamil = tamil;
  }

  // Brand
  static String get appName => isTamil ? 'வயல் Connect' : 'VayalConnect';
  static String get tagline => isTamil ? 'நம்ம வயல், நேரடி CONNECT' : 'Direct Farm-to-Buyer Marketplace';
  static String get governmentAttribution => isTamil
      ? 'AGMARKNET • data.gov.in அரசு அங்கீகாரம்'
      : 'Official data.gov.in AGMARKNET Rates';

  // Auth & Roles
  static String get login => isTamil ? 'உள்நுழைக' : 'Login';
  static String get register => isTamil ? 'பதிவு செய்' : 'Register';
  static String get logout => isTamil ? 'வெளியேறு' : 'Logout';
  static String get chooseRole => isTamil ? 'உங்கள் வகையைத் தேர்ந்தெடுக்கவும்' : 'Select Your Role';
  static String get farmer => isTamil ? 'விவசாயி' : 'Farmer';
  static String get buyer => isTamil ? 'வாங்குபவர்' : 'Buyer';
  static String get admin => isTamil ? 'நிர்வாகி' : 'Admin';
  static String get farmerSubtitle => isTamil
      ? 'விற்பனை, மண்டி விலை, அறுவடை பட்டியல்'
      : 'Sell crops, check mandi rates, track payouts';
  static String get buyerSubtitle => isTamil
      ? 'நேரடி கொள்முதல், மொத்த விலை ஒப்பந்தம்'
      : 'Direct farm sourcing, zero middleman markups';
  static String get adminSubtitle => isTamil
      ? 'சந்தை மேற்பார்வை, சரிபார்ப்பு, ஒப்புதல்'
      : 'Market oversight, approvals, revenue tracking';

  // Navigation Tabs
  static String get home => isTamil ? 'முகப்பு' : 'Home';
  static String get mandiPrices => isTamil ? 'மண்டி நிலவரம்' : 'Mandi Rates';
  static String get myCrops => isTamil ? 'என் பயிர்கள்' : 'My Crops';
  static String get marketplace => isTamil ? 'சந்தை' : 'Market';
  static String get orders => isTamil ? 'ஆர்டர்கள்' : 'Orders';
  static String get profile => isTamil ? 'விவரக்குறிப்பு' : 'Profile';
  static String get reports => isTamil ? 'அறிக்கைகள்' : 'Reports';
  static String get users => isTamil ? 'பயனர்கள்' : 'Users';

  // Mandi & Produce
  static String get liveRates => isTamil ? 'நேரலை' : 'LIVE';
  static String get searchCropOrMandi => isTamil
      ? 'பயிர் அல்லது மண்டி தேடுக...'
      : 'Search crop or mandi market...';
  static String get all => isTamil ? 'அனைத்தும்' : 'All';
  static String get grains => isTamil ? 'தானியங்கள்' : 'Grains';
  static String get vegetables => isTamil ? 'காய்கறிகள்' : 'Vegetables';
  static String get fruits => isTamil ? 'பழங்கள்' : 'Fruits';
  static String get spices => isTamil ? 'மசாலா' : 'Spices';

  // Dashboard Stats
  static String get totalPayout => isTamil ? 'மொத்த பட்டுவாடா' : 'Total Payout';
  static String get pendingPayout => isTamil ? 'நிலுவை பட்டுவாடா' : 'Pending Payout';
  static String get activeListings => isTamil ? 'செயலில் உள்ள பயிர்கள்' : 'Active Listings';
  static String get totalOrders => isTamil ? 'மொத்த ஆர்டர்கள்' : 'Total Orders';
  static String get totalSales => isTamil ? 'மொத்த விற்பனை' : 'Gross Sales';
  static String get platformRevenue => isTamil ? 'நிறுவன வருவாய்' : 'Platform Revenue';

  // Actions
  static String get addCrop => isTamil ? 'பயிர் சேர் • Add Crop' : 'Add New Harvest';
  static String get orderNow => isTamil ? 'முன்பதிவு செய்' : 'Order Now';
  static String get viewDetails => isTamil ? 'விவரம் பார்க்க' : 'View Details';
  static String get callFarmer => isTamil ? 'அழைக்க' : 'Call Farmer';
  static String get approve => isTamil ? 'ஒப்புதல்' : 'Approve';
  static String get reject => isTamil ? 'நிராகரி' : 'Reject';
  static String get pullToRefresh => isTamil ? 'கீழே இழுத்து புதுப்பிக்கவும்' : 'Pull down to refresh';
}
