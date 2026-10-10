/// VayalConnect Localization Helper
///
/// Provides bilingual Tamil (தமிழ்) and English strings for the VayalConnect ecosystem.
class VayalStrings {
  VayalStrings._();

  static bool isTamil = false; // English default as per project requirements

  static void setLanguage(bool tamil) {
    isTamil = tamil;
  }

  static String get locationExplanation => isTamil ? 'இருப்பிடத்தைப் பகிர்வது பண்ணை அல்லது விநியோகப் பகுதியைக் கண்டறிய உதவும். முழு முகவரியைத் தனியாக உள்ளிடவும். இது விருப்பத்தேர்வு.' : 'Optionally share your location to locate your farm or delivery area. Enter the full address separately.';
  static String get useLocation => isTamil ? 'என் இருப்பிடத்தைப் பயன்படுத்து' : 'Use my location';
  static String get locationSaved => isTamil ? 'இருப்பிடம் பெறப்பட்டது. முழு முகவரியை உள்ளிடவும்.' : 'Location obtained. Enter your full address below.';
  static String get locationDenied => isTamil ? 'அனுமதி வழங்கப்படவில்லை. மீண்டும் முயற்சிக்கவும் அல்லது முகவரியை உள்ளிடவும்.' : 'Permission denied. Retry or enter your location manually.';
  static String get locationDisabled => isTamil ? 'இருப்பிட சேவையை இயக்கவும் அல்லது முகவரியை உள்ளிடவும்.' : 'Location services are disabled. Enable them or enter your location manually.';
  static String get locationUnavailable => isTamil ? 'இருப்பிடம் கிடைக்கவில்லை. மீண்டும் முயற்சிக்கவும் அல்லது முகவரியை உள்ளிடவும்.' : 'Location unavailable. Retry or enter your location manually.';
  static String get locationPermanent => isTamil ? 'அமைப்புகளில் அனுமதி வழங்கவும் அல்லது முகவரியை உள்ளிடவும்.' : 'Allow location in device settings or enter your location manually.';
  static String get openSettings => isTamil ? 'அமைப்புகளைத் திற' : 'Open settings';
  static String get changePassword => isTamil ? 'கடவுச்சொல்லை மாற்று' : 'Change password';
  static String get rejectionReason => isTamil ? 'நிராகரிப்புக்கான காரணம்' : 'Reason for rejection';

  // Brand
  static String get appName => isTamil ? 'வயல் Connect' : 'VayalConnect';
  static String get tagline => isTamil ? 'நம்ம வயல், நேரடி CONNECT' : 'Direct Farmer-to-Buyer Marketplace';
  static String get governmentAttribution => isTamil
      ? 'தமிழ்நாடு APMC நெட்வொர்க்'
      : 'TN APMC Network';

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

  // Login Form Localizations
  static String get phoneOrEmail => isTamil ? 'கைபேசி அல்லது மின்னஞ்சல்' : 'Phone or Email';
  static String get phoneOrEmailHint => isTamil ? 'எ.கா: farmer@vayalconnect.in' : 'e.g. farmer@vayalconnect.in';
  static String get password => isTamil ? 'கடவுச்சொல்' : 'Password';
  static String get passwordHint => isTamil ? '••••••••' : '••••••••';
  static String get rememberMe => isTamil ? 'நினைவில் கொள்' : 'Remember me';
  static String get forgotPassword => isTamil ? 'கடவுச்சொல் மறந்ததா?' : 'Forgot Password?';
  static String get dontHaveAccount => isTamil ? 'கணக்கு இல்லையா? ' : "Don't have an account? ";
  static String get registerNow => isTamil ? 'பதிவு செய்' : 'Register';
  static String get emailRequired => isTamil ? 'மின்னஞ்சல் அல்லது கைபேசி எண் உள்ளிடவும்' : 'Please enter your email or phone number';
  static String get passwordRequired => isTamil ? 'கடவுச்சொல் உள்ளிடவும்' : 'Please enter your password';

  // Error Messages (Strictly compliant with Section 10)
  static String get errorNoNetwork => isTamil
      ? 'இணையம் அல்லது Wi-Fi இணைப்பைச் சரிபார்க்கவும்.'
      : 'Please check your internet or Wi-Fi connection.';
  static String get errorBackendUnavailable => isTamil
      ? 'சேவையகத்துடன் இணைக்க முடியவில்லை. மீண்டும் முயற்சிக்கவும்.'
      : 'Unable to connect to the server. Please try again.';
  static String get errorTimeout => isTamil
      ? 'கோரிக்கை நேரம் முடிந்தது. மீண்டும் முயற்சிக்கவும்.'
      : 'The request took too long. Please try again.';
  static String get errorInvalidCredentials => isTamil
      ? 'தவறான மின்னஞ்சல் அல்லது கடவுச்சொல்.'
      : 'Invalid email/phone or password.';

  // Password Recovery Dialog Localizations
  static String get resetPasswordTitle => isTamil ? 'கடவுச்சொல் மீட்டமைக்க' : 'Reset Password';
  static String get resetPasswordSubtitle => isTamil
      ? 'உங்கள் பதிவு செய்யப்பட்ட மின்னஞ்சலை உள்ளிட்டு OTP பெறவும்.'
      : 'Enter your registered email to receive a password reset OTP.';
  static String get sendOtp => isTamil ? 'OTP அனுப்புக' : 'Send OTP';
  static String get enterOtp => isTamil ? 'OTP உள்ளிடவும்' : 'Enter OTP';
  static String get newPassword => isTamil ? 'புதிய கடவுச்சொல்' : 'New Password';
  static String get resetPasswordBtn => isTamil ? 'கடவுச்சொல் மாற்று' : 'Confirm Reset';
  static String get cancel => isTamil ? 'ரத்து செய்' : 'Cancel';

  // Demo & Support
  static String get offlineDemoPreview => isTamil ? 'ஆஃப்லைன் டெமோ முன்னோட்டம்' : 'Offline Demo Preview';
  static String get offlineDemoSubtitle => isTamil
      ? 'மாதிரித் தரவுகளுடன் செயலியை ஆராயுங்கள் (Farmer, Buyer, Admin).'
      : 'Explore the UI with sample fixtures without live backend.';
  static String get tryOfflineDemo => isTamil ? 'ஆஃப்லைன் டெமோ முயற்சிக்க' : 'Try Offline Demo';
  static String get kisanHelplineTitle => isTamil ? 'உழவர் உதவி மையம்' : 'Kisan Support Helpline';
  static String get kisanHelplineNumber => '1800-425-1661';

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
