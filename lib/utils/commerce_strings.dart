import 'localization.dart';

/// Shared catalog for every authenticated commerce workflow.
class S {
  static String t(String key) => VayalStrings.isTamil ? (_ta[key] ?? key) : key;
  static String money(num? paise) =>
      '₹${((paise ?? 0) / 100).toStringAsFixed(2)}';
  static String status(String code) => VayalStrings.isTamil
      ? t(code)
      : (const {
            'PENDING_PAYMENT': 'Awaiting payment',
            'PENDING': 'Pending',
            'APPROVED': 'Approved',
            'REJECTED': 'Rejected',
            'PAID': 'Paid',
            'CONFIRMED': 'Confirmed',
            'PROCESSING': 'Preparing',
            'SHIPPED': 'In transit',
            'COMPLETED': 'Completed',
            'CANCELLED': 'Cancelled',
            'CAPTURED': 'Verified',
            'FAILED': 'Failed',
            'ACTIVE': 'Available',
            'INACTIVE': 'Inactive',
            'PENDING_APPROVAL': 'Pending approval',
            'NOT_INITIATED': 'Not initiated',
            'PICKUP': 'Pickup',
            'DELIVERY': 'Delivery',
          }[code] ??
          code);
  static String message(String text) {
    final value = text.replaceFirst('Exception: ', '');
    if (_ta.containsKey(value)) return t(value);
    for (final e in _ta.entries) {
      if (e.value == value) return t(e.key);
    }
    return value;
  }

  static const _ta = <String, String>{
    'Tamil Nadu Uzhavar Santhai reference — median of available market range midpoints':
        'தமிழ்நாடு உழவர் சந்தை குறிப்பு விலை — கிடைக்கும் சந்தை விலை வரம்புகளின் நடுப்புள்ளிகளின் இடைநிலை',
    'median_distinct_market_range_midpoint':
        'தனித்த சந்தை விலை வரம்பு நடுப்புள்ளிகளின் இடைநிலை',
    'median_range_midpoint': 'விலை வரம்பு நடுப்புள்ளிகளின் இடைநிலை',
    'range_midpoint': 'விலை வரம்பின் நடுப்புள்ளி',
    'Full Name': 'முழுப் பெயர்',
    'Email Address': 'மின்னஞ்சல் முகவரி',
    'Age': 'வயது',
    'Phone Number': 'கைபேசி எண்',
    'Password': 'கடவுச்சொல்',
    'District / Area': 'மாவட்டம் / பகுதி',
    'Tamil Nadu statewide reference price — calculated from available market observations':
        'தமிழ்நாடு மாநில அளவிலான குறிப்பு விலை — கிடைக்கும் சந்தைப் பதிவுகளிலிருந்து கணக்கிடப்பட்டது',
    'Eligible observations': 'தகுதியான சந்தைப் பதிவுகள்',
    'Aggregation method': 'கணக்கீட்டு முறை',
    'median_distinct_market_modal':
        'தனித்தனி சந்தைகளின் வழக்கமான விலைகளின் இடைநிலை',
    'Enter crop name.': 'பயிரின் பெயரை உள்ளிடவும்.',
    'First 50 matching records. Search by crop for more specific results.':
        'முதல் 50 பதிவுகள். குறிப்பிட்ட முடிவுகளுக்கு பயிரின் பெயரால் தேடவும்.',
    'Market price unavailable': 'சந்தை விலை கிடைக்கவில்லை',
    'Stale market reference': 'பழைய சந்தை குறிப்பு விலை',
    'Source-reported market reference': 'ஆதாரம் வழங்கிய சந்தை குறிப்பு விலை',
    'Currency': 'நாணயம்',
    'Price type': 'விலை வகை',
    'unknown': 'தெரியவில்லை',
    'Price lookup context': 'சந்தை விலை தேடல் விவரங்கள்',
    'Flowers': 'பூக்கள்',
    'Pulses and legumes': 'பருப்பு வகைகள்',
    'Oilseeds': 'எண்ணெய் வித்துகள்',
    'Plantation crops': 'தோட்டப் பயிர்கள்',
    'Sugarcane': 'கரும்பு',
    'Fodder': 'தீவனப் பயிர்கள்',
    'Medicinal and aromatic plants': 'மருத்துவ மற்றும் நறுமணச் செடிகள்',
    'Nursery and horticultural products':
        'நாற்றங்கால் மற்றும் தோட்டக்கலைப் பொருட்கள்',
    'Other agricultural products': 'பிற வேளாண் பொருட்கள்',
    'Verified market reference': 'சரிபார்க்கப்பட்ட சந்தை விலை',
    'Historical verified reference': 'முந்தைய சரிபார்க்கப்பட்ட சந்தை விலை',
    'Quoted price': 'குறிப்பிடப்பட்ட விலை',
    'Trade type': 'விற்பனை வகை',
    'Verification': 'சரிபார்ப்பு',
    'State for price lookup': 'விலை தேடலுக்கான மாநிலம்',
    'District for price lookup': 'விலை தேடலுக்கான மாவட்டம்',
    'Variety for price lookup': 'விலை தேடலுக்கான பயிர் ரகம்',
    'Enter crop name and nearest market.':
        'பயிரின் பெயர் மற்றும் அருகிலுள்ள சந்தையை உள்ளிடவும்.',
    'Original unit preserved. No valid conversion to your listing unit.':
        'அசல் அலகு பயன்படுத்தப்படுகிறது. உங்கள் விற்பனை அலகிற்கு மாற்ற முடியவில்லை.',
    'Verified market prices are references. Farmers set their own selling price.':
        'சரிபார்க்கப்பட்ட சந்தை விலைகள் குறிப்புக்கானவை. விவசாயிகள் தங்கள் விற்பனை விலையை நிர்ணயிக்கிறார்கள்.',
    'Retrieved verified market records':
        'சரிபார்க்கப்பட்ட சந்தை விவரங்கள் பெறப்பட்டன',
    'Cached verified records': 'சேமிக்கப்பட்ட சரிபார்க்கப்பட்ட விவரங்கள்',
    'No matching verified market prices found.':
        'பொருத்தமான சரிபார்க்கப்பட்ட சந்தை விலைகள் கிடைக்கவில்லை.',
    'Difference from comparable reference':
        'ஒப்பிடக்கூடிய ஆதார விலையிலிருந்து வேறுபாடு',
    'Unable to save language preference. Please retry.':
        'மொழித் தேர்வைச் சேமிக்க முடியவில்லை. மீண்டும் முயற்சிக்கவும்.',
    'Stock reservation expired. Select the crop again.':
        'இருப்பு ஒதுக்கீடு காலாவதியானது. பயிரை மீண்டும் தேர்ந்தெடுக்கவும்.',
    'Stock reserved until': 'இருப்பு ஒதுக்கீடு முடியும் நேரம்',
    'Enter a valid mobile number.': 'செல்லுபடியாகும் கைபேசி எண்ணை உள்ளிடவும்.',
    'Dashboard': 'கண்ணோட்டம்',
    'Marketplace': 'சந்தை',
    'My crops': 'என் பயிர்கள்',
    'Add crop': 'பயிர் சேர்',
    'Orders': 'ஆர்டர்கள்',
    'Sales': 'விற்பனை',
    'Payouts': 'பட்டுவாடா',
    'Profile': 'சுயவிவரம்',
    'Market prices': 'மண்டி விலைகள்',
    'Farmers': 'விவசாயிகள்',
    'Buyers': 'வாங்குபவர்கள்',
    'Commission': 'கமிஷன்',
    'Refresh': 'புதுப்பி',
    'Retry': 'மீண்டும் முயற்சி',
    'Save': 'சேமி',
    'Edit': 'திருத்து',
    'Delete': 'நீக்கு',
    'Cancel': 'ரத்து செய்',
    'Close': 'மூடு',
    'Day': 'நாள்',
    'Month': 'மாதம்',
    'Year': 'ஆண்டு',
    'All': 'அனைத்தும்',
    'No records yet.': 'இன்னும் பதிவுகள் இல்லை.',
    'No crops published yet.': 'இன்னும் பயிர்கள் வெளியிடப்படவில்லை.',
    'No matching crops found.': 'பொருத்தமான பயிர்கள் இல்லை.',
    'No orders in this period.': 'இந்தக் காலத்தில் ஆர்டர்கள் இல்லை.',
    'No farmers awaiting review.':
        'மதிப்பாய்விற்காக விவசாயிகள் காத்திருக்கவில்லை.',
    'Loading…': 'ஏற்றப்படுகிறது…',
    'Search crops': 'பயிர்களைத் தேடு',
    'Category': 'வகை',
    'New crop category (optional)': 'புதிய பயிர் வகை (விருப்பம்)',
    'Grains': 'தானியங்கள்',
    'Vegetables': 'காய்கறிகள்',
    'Fruits': 'பழங்கள்',
    'Spices': 'மசாலா',
    'Newest': 'புதியவை',
    'Price: low to high': 'விலை: குறைவிலிருந்து அதிகம்',
    'Price: high to low': 'விலை: அதிகத்திலிருந்து குறைவு',
    'Load more': 'மேலும் ஏற்று',
    'Farmer': 'விவசாயி',
    'Harvest date': 'அறுவடை தேதி',
    'Available stock': 'கிடைக்கும் இருப்பு',
    'Active listings': 'செயலில் உள்ள பட்டியல்கள்',
    'Pending orders': 'நிலுவை ஆர்டர்கள்',
    'Completed sales': 'நிறைவடைந்த விற்பனை',
    'Farmer earnings': 'விவசாயி வருமானம்',
    'Platform commission': 'தள கமிஷன்',
    'Farmer base price': 'விவசாயி அடிப்படை விலை',
    'Delivery charge': 'விநியோகக் கட்டணம்',
    'Buyer total': 'வாங்குபவர் மொத்தம்',
    'Delivery included': 'விநியோகம் விலையில் அடங்கும்',
    'Reference unavailable': 'ஆதார விலை கிடைக்கவில்லை',
    'Historical official reference': 'முந்தைய அரசு ஆதார விலை',
    'Official reference': 'அரசு ஆதார விலை',
    'Reported date': 'அறிக்கையிடப்பட்ட தேதி',
    'Retrieved at': 'பெறப்பட்ட நேரம்',
    'Source': 'ஆதாரம்',
    'Market': 'மண்டி',
    'State': 'மாநிலம்',
    'Minimum': 'குறைந்தபட்சம்',
    'Maximum': 'அதிகபட்சம்',
    'Modal': 'அதிகம் நிலவும் விலை',
    'Quantity': 'அளவு',
    'Unit': 'அலகு',
    'Description': 'விளக்கம்',
    'Crop name': 'பயிர் பெயர்',
    'Your selling price': 'உங்கள் விற்பனை விலை',
    'Farm location': 'பண்ணை இருப்பிடம்',
    'Nearest mandi': 'அருகிலுள்ள மண்டி',
    'Stock adjustment': 'இருப்பு மாற்றம்',
    'Add units with a positive number; remove with a negative number.':
        'சேர்க்க நேர்ம எண்ணையும் குறைக்க எதிர்ம எண்ணையும் உள்ளிடவும்.',
    'Active': 'செயலில்',
    'Inactive': 'செயலற்றது',
    'Publish': 'வெளியிடு',
    'Publishing locked': 'வெளியிடுதல் பூட்டப்பட்டுள்ளது',
    'Complete onboarding and obtain administrator approval.':
        'விவரங்களை நிறைவுசெய்து நிர்வாகியின் ஒப்புதல் பெறவும்.',
    'Farmer application': 'விவசாயி விண்ணப்பம்',
    'Farm name': 'பண்ணை பெயர்',
    'Farm address': 'பண்ணை முகவரி',
    'Pickup address': 'பெறும் முகவரி',
    'Crops grown': 'பயிர்கள்',
    'Farm details': 'பண்ணை விவரங்கள்',
    'Offer delivery': 'விநியோகம் வழங்கு',
    'Submit for review': 'மதிப்பாய்வுக்குச் சமர்ப்பி',
    'Review reason': 'மதிப்பாய்வு காரணம்',
    'Bank payout details': 'வங்கி பட்டுவாடா விவரங்கள்',
    'Account holder name': 'கணக்கு வைத்திருப்பவர் பெயர்',
    'Bank name': 'வங்கியின் பெயர்',
    'Account number': 'கணக்கு எண்',
    'IFSC code': 'IFSC குறியீடு',
    'Bank verification is pending.': 'வங்கி சரிபார்ப்பு நிலுவையில் உள்ளது.',
    'Save current farm coordinates': 'தற்போதைய பண்ணை ஆயங்களைச் சேமி',
    'Use this only while physically at your farm.':
        'பண்ணையில் நேரில் இருக்கும்போது மட்டும் இதைப் பயன்படுத்தவும்.',
    'Location required': 'இருப்பிட அனுமதி தேவை',
    'Location supports farm discovery and distance estimates. Allow foreground location to continue. GPS does not replace a delivery address.':
        'பண்ணைகளைக் கண்டறியவும் தூரம் கணக்கிடவும் இருப்பிடம் தேவை. தொடர இருப்பிட அனுமதி வழங்கவும். GPS விநியோக முகவரிக்குப் பதிலாகாது.',
    'Allow location': 'இருப்பிட அனுமதி வழங்கு',
    'Open settings': 'அமைப்புகளைத் திற',
    'Location saved': 'இருப்பிடம் சேமிக்கப்பட்டது',
    'Permission denied. Retry when ready.':
        'அனுமதி மறுக்கப்பட்டது. தயாரானதும் மீண்டும் முயற்சிக்கவும்.',
    'Enable location permission in app settings.':
        'செயலி அமைப்புகளில் இருப்பிட அனுமதியை வழங்கவும்.',
    'Turn on location services, then retry.':
        'இருப்பிட சேவைகளை இயக்கி மீண்டும் முயற்சிக்கவும்.',
    'Unable to obtain coordinates. Please retry.':
        'இருப்பிட ஆயங்களைப் பெற இயலவில்லை. மீண்டும் முயற்சிக்கவும்.',
    'Addresses': 'முகவரிகள்',
    'Add address': 'முகவரி சேர்',
    'Select address': 'முகவரியைத் தேர்ந்தெடு',
    'Recipient name': 'பெறுநர் பெயர்',
    'Contact number': 'தொடர்பு எண்',
    'House / building': 'வீடு / கட்டிடம்',
    'Street': 'தெரு',
    'Area / locality': 'பகுதி',
    'City / town': 'நகரம்',
    'Postal code': 'அஞ்சல் குறியீடு',
    'Delivery instructions': 'விநியோக வழிமுறைகள்',
    'Default address': 'இயல்புநிலை முகவரி',
    'Save destination coordinates': 'விநியோக இட ஆயங்களைச் சேமி',
    'Confirm that you are currently at this delivery address before using GPS.':
        'GPS பயன்படுத்துவதற்கு முன் நீங்கள் தற்போது இந்த விநியோக முகவரியில் இருப்பதை உறுதிப்படுத்தவும்.',
    'I am at this address': 'நான் இந்த முகவரியில் இருக்கிறேன்',
    'Coordinates required for delivery estimate.':
        'விநியோகக் கணிப்பிற்கு இருப்பிட ஆயங்கள் தேவை.',
    'Pickup': 'நேரில் பெறுதல்',
    'Delivery': 'விநியோகம்',
    'Checkout': 'ஆர்டர் உறுதிசெய்',
    'Place order': 'ஆர்டர் செய்',
    'Order recorded. Payment pending.':
        'ஆர்டர் பதிவாகியுள்ளது. பணம் செலுத்துதல் நிலுவையில் உள்ளது.',
    'View orders': 'ஆர்டர்களைப் பார்',
    'Order details': 'ஆர்டர் விவரங்கள்',
    'Order date': 'ஆர்டர் தேதி',
    'Payment': 'பணம் செலுத்துதல்',
    'Pay in test mode': 'சோதனை முறையில் செலுத்து',
    'Razorpay TEST MODE — no real money':
        'Razorpay சோதனை முறை — உண்மையான பணம் இல்லை',
    'Payment awaiting server verification. Refresh order status.':
        'சேவையக பணச் சரிபார்ப்பு நிலுவையில் உள்ளது. ஆர்டர் நிலையைப் புதுப்பிக்கவும்.',
    'Payment cancelled or failed. Your order remains pending.':
        'பணம் செலுத்துதல் ரத்து அல்லது தோல்வி. ஆர்டர் நிலுவையில் உள்ளது.',
    'Verified test payment.': 'சரிபார்க்கப்பட்ட சோதனைப் பணம்.',
    'Accept order': 'ஆர்டரை ஏற்று',
    'Start preparing': 'தயாரிக்கத் தொடங்கு',
    'Mark shipped': 'அனுப்பப்பட்டதாகக் குறி',
    'Complete order': 'ஆர்டரை நிறைவுசெய்',
    'Cancel unpaid order': 'பணம் செலுத்தாத ஆர்டரை ரத்து செய்',
    'Cancellation reason': 'ரத்து காரணம்',
    'Straight-line distance': 'நேர்கோட்டுத் தூரம்',
    'Estimated arrival window': 'மதிப்பிடப்பட்ட வருகைக் காலம்',
    'Farmer confirmation required. Road distance and exact arrival are unavailable.':
        'விவசாயியின் உறுதிப்படுத்தல் தேவை. சாலைத் தூரமும் சரியான வருகை நேரமும் கிடைக்கவில்லை.',
    'Required': 'தேவை',
    'Enter valid details.': 'சரியான விவரங்களை உள்ளிடவும்.',
    'Enter a valid quantity.': 'சரியான அளவை உள்ளிடவும்.',
    'Enter a valid price with up to two decimal places.':
        'இரண்டு தசம இடங்கள் வரை சரியான விலையை உள்ளிடவும்.',
    'Check the required fields and values.':
        'தேவையான விவரங்களையும் மதிப்புகளையும் சரிபார்க்கவும்.',
    'Session expired. Sign in again.':
        'அமர்வு காலாவதியானது. மீண்டும் உள்நுழைக.',
    'Price changed. Reload before ordering.':
        'விலை மாறியுள்ளது. ஆர்டர் செய்வதற்கு முன் புதுப்பிக்கவும்.',
    'Official market source unavailable. Please retry later.':
        'அரசு மண்டி தரவு கிடைக்கவில்லை. பின்னர் முயற்சிக்கவும்.',
    'Verified cached price unavailable. Daily discovery runs at 06:00 IST.':
        'சரிபார்க்கப்பட்ட சேமித்த விலை கிடைக்கவில்லை. தினமும் காலை 6:00 மணிக்கு விலை தேடல் நடைபெறும்.',
    'This action is unavailable for your account.':
        'உங்கள் கணக்கிற்கு இந்தச் செயல் அனுமதிக்கப்படவில்லை.',
    'Data changed. Reload before retrying.':
        'தரவு மாறியுள்ளது. மீண்டும் முயற்சிக்கும் முன் புதுப்பிக்கவும்.',
    'Unable to complete this request. Please retry.':
        'கோரிக்கையை நிறைவுசெய்ய முடியவில்லை. மீண்டும் முயற்சிக்கவும்.',
    'Request timed out. Please retry.':
        'கோரிக்கை நேரம் முடிந்தது. மீண்டும் முயற்சிக்கவும்.',
    'Invalid server response. Please retry.':
        'தவறான சேவையக பதில். மீண்டும் முயற்சிக்கவும்.',
    'Cannot reach the server. Check your connection.':
        'சேவையகத்தை அணுக இயலவில்லை. இணைய இணைப்பைச் சரிபார்க்கவும்.',
    'Commission percentage (0–100)': 'கமிஷன் சதவீதம் (0–100)',
    'Applies to new orders only. Historical prices stay unchanged.':
        'புதிய ஆர்டர்களுக்கு மட்டும் பொருந்தும். பழைய விலைகள் மாறாது.',
    'Buyer total = farmer base + platform commission + delivery charge.':
        'வாங்குபவர் மொத்தம் = விவசாயி விலை + தள கமிஷன் + விநியோகக் கட்டணம்.',
    'Farmer receives the full base price. Commission is added for buyers.':
        'விவசாயி முழு அடிப்படை விலையைப் பெறுகிறார். வாங்குபவர் விலையில் கமிஷன் சேர்க்கப்படுகிறது.',
    'Approve': 'ஒப்புதல்',
    'Reject': 'நிராகரி',
    'Rejection reason': 'நிராகரிப்பு காரணம்',
    'Review application': 'விண்ணப்பத்தை மதிப்பாய்வு செய்',
    'Account active': 'கணக்கு செயலில் உள்ளது',
    'Registered farmers': 'பதிவுசெய்த விவசாயிகள்',
    'Approved farmers': 'ஒப்புதல் பெற்ற விவசாயிகள்',
    'Pending applications': 'நிலுவை விண்ணப்பங்கள்',
    'Rejected applications': 'நிராகரிக்கப்பட்ட விண்ணப்பங்கள்',
    'Registered buyers': 'பதிவுசெய்த வாங்குபவர்கள்',
    'Total orders': 'மொத்த ஆர்டர்கள்',
    'Completed orders': 'நிறைவடைந்த ஆர்டர்கள்',
    'Cancelled orders': 'ரத்தான ஆர்டர்கள்',
    'Gross order value': 'மொத்த ஆர்டர் மதிப்பு',
    'Earned commission': 'ஈட்டிய கமிஷன்',
    'Captured payments': 'பெறப்பட்ட பணம்',
    'Paid payouts': 'செலுத்திய பட்டுவாடா',
    'Pending payouts': 'நிலுவை பட்டுவாடா',
    'Financial periods use UTC order creation dates. Earned commission requires completed and captured orders.':
        'நிதிக் காலங்கள் UTC ஆர்டர் உருவாக்கிய தேதியைப் பயன்படுத்துகின்றன. நிறைவடைந்த மற்றும் பணம் பெறப்பட்ட ஆர்டர்களில் மட்டுமே கமிஷன் ஈட்டப்படும்.',
    'PENDING': 'நிலுவையில்',
    'APPROVED': 'ஒப்புதல்',
    'REJECTED': 'நிராகரிப்பு',
    'ACTIVE': 'செயலில்',
    'INACTIVE': 'செயலற்றது',
    'OUT_OF_STOCK': 'இருப்பு இல்லை',
    'PENDING_PAYMENT': 'பணம் நிலுவையில்',
    'CREATED': 'உருவாக்கப்பட்டது',
    'AUTHORIZED': 'அங்கீகரிக்கப்பட்டது',
    'CAPTURED': 'பணம் பெறப்பட்டது',
    'FAILED': 'தோல்வி',
    'PAID': 'செலுத்தப்பட்டது',
    'CONFIRMED': 'உறுதிசெய்யப்பட்டது',
    'PROCESSING': 'தயாராகிறது',
    'SHIPPED': 'அனுப்பப்பட்டது',
    'COMPLETED': 'நிறைவடைந்தது',
    'CANCELLED': 'ரத்து செய்யப்பட்டது',
    'REFUNDED': 'திரும்பச் செலுத்தப்பட்டது',
    'NOT_INITIATED': 'தொடங்கப்படவில்லை',
    'PENDING_APPROVAL': 'ஒப்புதல் நிலுவையில்',
    'PICKUP': 'நேரில் பெறுதல்',
    'DELIVERY': 'விநியோகம்',
    'Admin dashboard': 'நிர்வாகப் பலகை',
    'All farmers': 'அனைத்து விவசாயிகள்',
    'Bank details submitted': 'வங்கி விவரங்கள் சமர்ப்பிக்கப்பட்டன',
    'Changes apply to new orders. Historical order prices remain unchanged.':
        'மாற்றங்கள் புதிய ஆர்டர்களுக்குப் பொருந்தும். முந்தைய ஆர்டர்களின் விலை மாறாது.',
    'Commission saved for new orders.':
        'புதிய ஆர்டர்களுக்கான கமிஷன் சேமிக்கப்பட்டது.',
    'Commodity': 'விளைபொருள்',
    'Comparable reference': 'ஒப்பிடக்கூடிய குறிப்பு விலை',
    'Crop photograph': 'விளைபொருளின் படம்',
    'Crops': 'பயிர்கள்',
    'Email': 'மின்னஞ்சல்',
    'Enter 8–20 digits.': '8 முதல் 20 இலக்கங்களை உள்ளிடவும்.',
    'Enter a percentage from 0 to 100, with up to two decimal places.':
        '0 முதல் 100 வரை, இரண்டு தசம இடங்கள் வரை சதவீதத்தை உள்ளிடவும்.',
    'Enter a valid IFSC.': 'சரியான IFSC குறியீட்டை உள்ளிடவும்.',
    'Enter your own bank details. Saving resets verification. Full account numbers are never displayed.':
        'உங்கள் வங்கி விவரங்களை உள்ளிடவும். சேமித்தால் சரிபார்ப்பு மீண்டும் தேவை. முழு கணக்கு எண் காட்டப்படாது.',
    'Farm coordinates': 'பண்ணையின் புவியிடத் தகவல்',
    'First 50 matching records. Narrow the filters for a specific market.':
        'முதல் 50 பொருந்தும் பதிவுகள். குறிப்பிட்ட சந்தையைத் தேர்வு செய்ய வடிகட்டிகளைப் பயன்படுத்தவும்.',
    'Global commission percentage': 'பொதுவான கமிஷன் சதவீதம்',
    'Government prices are references. Farmers set their own selling price.':
        'அரசு விலைகள் குறிப்புக்காக மட்டுமே. விவசாயிகள் தங்கள் விற்பனை விலையை நிர்ணயிக்கிறார்கள்.',
    'Latest 100 records': 'சமீபத்திய 100 பதிவுகள்',
    'Manage VayalConnect': 'வயல் கனெக்டை நிர்வகிக்கவும்',
    'Name': 'பெயர்',
    'No available crops match your search.':
        'உங்கள் தேடலுக்குப் பொருந்தும் விளைபொருட்கள் இல்லை.',
    'No matching official market prices found.':
        'பொருந்தும் அதிகாரப்பூர்வ சந்தை விலைகள் கிடைக்கவில்லை.',
    'Photograph saved': 'படம் சேமிக்கப்பட்டது',
    'Products and orders': 'விளைபொருட்களும் ஆர்டர்களும்',
    'Save bank details': 'வங்கி விவரங்களைச் சேமிக்கவும்',
    'Search': 'தேடு',
    'Status': 'நிலை',
    'Total listings': 'மொத்தப் பட்டியல்கள்',
    'Welcome': 'வரவேற்கிறோம்',
    'Bank details saved. Verification remains pending.':
        'வங்கி விவரங்கள் சேமிக்கப்பட்டன. சரிபார்ப்பு நிலுவையில் உள்ளது.',
    'Yes': 'ஆம்',
    'No': 'இல்லை',
    'All crops': 'அனைத்து பயிர்கள்',
    'Retrieved from official source':
        'அதிகாரப்பூர்வ மூலத்திலிருந்து பெறப்பட்டது',
    'Cached official records': 'சேமிக்கப்பட்ட அதிகாரப்பூர்வ பதிவுகள்',
    'Current password': 'தற்போதைய கடவுச்சொல்',
    'New password': 'புதிய கடவுச்சொல்',
    '8-128 characters, uppercase and a number':
        '8–128 எழுத்துகள், ஓர் ஆங்கிலப் பெரிய எழுத்து மற்றும் ஓர் எண் தேவை',
    'Unable to change password. Check your current password and requirements.':
        'கடவுச்சொல்லை மாற்ற முடியவில்லை. தற்போதைய கடவுச்சொல்லையும் விதிகளையும் சரிபார்க்கவும்.',
    'Signed out on this device. Server session revocation could not be confirmed.':
        'இந்தச் சாதனத்தில் வெளியேறிவிட்டீர்கள். சேவையக அமர்வு ரத்தானதை உறுதிப்படுத்த முடியவில்லை.',
    'account holder name': 'கணக்கு வைத்திருப்பவர் பெயர்',
    'bank name': 'வங்கியின் பெயர்',
    'account number': 'கணக்கு எண்',
    'ifsc': 'IFSC குறியீடு',
    'upi id': 'UPI முகவரி',
    'Edit profile': 'விவரங்களைத் திருத்தவும்',
    'Address': 'முகவரி',
    'Change password': 'கடவுச்சொல்லை மாற்றவும்',
    'Logout': 'வெளியேறு',
    'Verified': 'சரிபார்க்கப்பட்டது',
    'Not verified': 'சரிபார்க்கப்படவில்லை',
    'Payment captured after cancellation. Refund review required.':
        'ரத்துசெய்த பின் பணம் பெறப்பட்டது. பணத்தைத் திரும்பச் செலுத்த ஆய்வு தேவை.',
    'Payment request in progress. Retry after one minute.':
        'பணக் கோரிக்கை செயல்பாட்டில் உள்ளது. ஒரு நிமிடத்திற்குப் பின் முயற்சிக்கவும்.',
    'Bank transfers are disabled in this test demonstration.':
        'இந்தச் சோதனை விளக்கத்தில் வங்கிப் பரிமாற்றங்கள் முடக்கப்பட்டுள்ளன.',
    'Payout review': 'பட்டுவாடா ஆய்வு',
    'View payout': 'பட்டுவாடாவைப் பார்',
    'Amount': 'தொகை',
    'All statuses': 'அனைத்து நிலைகள்',
    'All dates': 'அனைத்து தேதிகள்',
    'Payout review requires completed and captured orders.':
        'பட்டுவாடா ஆய்வுக்கு நிறைவடைந்து பணம் பெறப்பட்ட ஆர்டர்கள் தேவை.',
    'Approve payout': 'பட்டுவாடாவை அனுமதிக்கவும்',
    'Reject payout': 'பட்டுவாடாவை நிராகரிக்கவும்',
  };
}
