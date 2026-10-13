import 'package:flutter/material.dart';
import 'localization.dart';

/// Examples are decorations only; never assign them to a controller or payload.
class FormExamples {
  static const style = TextStyle(color: Color(0xFF566573));
  static String? hint(String field) {
    final pair = _examples[field];
    return pair == null ? null : pair[VayalStrings.isTamil ? 1 : 0];
  }

  static const _examples = <String, List<String>>{
    'name': ['Arun Kumar', 'அருண் குமார்'],
    'phone': ['9876543210', '9876543210'],
    'email': ['arun@example.com', 'arun@example.com'],
    'age': ['30', '30'],
    'address': ['Main Road, Pollachi', 'மெயின் ரோடு, பொள்ளாச்சி'],
    'area_location': ['Pollachi', 'பொள்ளாச்சி'],
    'district': ['Coimbatore', 'கோயம்புத்தூர்'],
    'farm_name': ['Green Valley Farm', 'பசுமைப் பள்ளத்தாக்கு பண்ணை'],
    'farm_address': ['Main Road, Pollachi', 'மெயின் ரோடு, பொள்ளாச்சி'],
    'pickup_address': ['Main Road, Pollachi', 'மெயின் ரோடு, பொள்ளாச்சி'],
    'crops': ['Tomato', 'தக்காளி'],
    'farm_details': [
      'Vegetables grown on our farm',
      'எங்கள் பண்ணையில் விளையும் காய்கறிகள்'
    ],
    'product_name': ['Tomato', 'தக்காளி'],
    'description': [
      'Freshly harvested tomatoes',
      'புதிதாக அறுவடை செய்த தக்காளிகள்'
    ],
    'quantity': ['100', '100'],
    'stock_adjustment': ['100', '100'],
    'selling_price': ['10', '10'],
    'location': ['Pollachi', 'பொள்ளாச்சி'],
    'market': ['Pollachi', 'பொள்ளாச்சி'],
    'state': ['Tamil Nadu', 'தமிழ்நாடு'],
    'variety': ['Local', 'நாட்டு வகை'],
    'new_category': ['Vegetables', 'காய்கறிகள்'],
    'account_holder_name': ['Arun Kumar', 'அருண் குமார்'],
    'bank_name': ['State Bank of India', 'பாரத ஸ்டேட் வங்கி'],
    'account_number': ['123456789012', '123456789012'],
    'ifsc': ['SBIN0001234', 'SBIN0001234'],
    'upi_id': ['arun@upi', 'arun@upi'],
    'cancellation': ['Order no longer needed', 'இந்த ஆர்டர் இனி தேவையில்லை'],
    'password': ['••••••••', '••••••••'],
    'otp': ['123456', '123456'],
  };
}
