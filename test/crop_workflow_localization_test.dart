import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayalconnect_flutter/utils/commerce_strings.dart';
import 'package:vayalconnect_flutter/utils/localization.dart';
import 'package:vayalconnect_flutter/widgets/brand_widgets.dart';
import 'package:vayalconnect_flutter/screens/add_product_screen.dart';
import 'package:vayalconnect_flutter/services/api_client.dart';

class MockAddProductApi extends ApiClient {
  bool productCreated = false;
  Map<String, dynamic>? lastBody;

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (path.contains('/api/v1/products')) {
      productCreated = true;
      lastBody = body;
      return {'product_id': 'prod_test_123', 'status': 'ACTIVE'};
    }
    if (path.contains('/api/v1/market-prices/filter-options')) {
      return {'categories': ['Grains', 'Vegetables']};
    }
    return {};
  }
}

void main() {
  group('Crop Name and Static Text Localization Tests', () {
    test('English mode returns canonical crop names and English UI strings', () {
      VayalStrings.setLanguage(false);

      expect(S.crop('Tomato'), equals('Tomato'));
      expect(S.crop('Wheat'), equals('Wheat'));
      expect(S.crop('Banana'), equals('Banana'));
      expect(S.crop('Rice'), equals('Rice'));
      expect(S.crop('Onion'), equals('Onion'));
      expect(S.crop('Potato'), equals('Potato'));
      expect(S.crop('Brinjal'), equals('Brinjal'));
      expect(S.crop('Chilli'), equals('Chilli'));
      expect(S.crop('Coconut'), equals('Coconut'));
      expect(S.crop('Maize'), equals('Maize'));
      expect(S.crop('Jasmine'), equals('Jasmine'));
      expect(S.crop('Marigold'), equals('Marigold'));

      // Static UI strings
      expect(S.t('Crop Image — Required'), equals('Crop Image — Required'));
      expect(S.t('Upload Crop Image'), equals('Upload Crop Image'));
      expect(S.t('Take Photo'), equals('Take Photo'));
      expect(S.t('Choose from Gallery'), equals('Choose from Gallery'));
      expect(S.t('Image Preview'), equals('Image Preview'));
      expect(S.t('Replace Image'), equals('Replace Image'));
      expect(S.t('Remove Image'), equals('Remove Image'));
      expect(S.t('Crop image is required before publishing'),
          equals('Crop image is required before publishing'));
    });

    test('Tamil mode returns natural Tamil crop names and Tamil UI strings', () {
      VayalStrings.setLanguage(true);

      expect(S.crop('Tomato'), equals('தக்காளி'));
      expect(S.crop('Wheat'), equals('கோதுமை'));
      expect(S.crop('Banana'), equals('வாழைப்பழம்'));
      expect(S.crop('Rice'), equals('அரிசி'));
      expect(S.crop('Onion'), equals('வெங்காயம்'));
      expect(S.crop('Potato'), equals('உருளைக்கிழங்கு'));
      expect(S.crop('Brinjal'), equals('கத்தரிக்காய்'));
      expect(S.crop('Chilli'), equals('மிளகாய்'));
      expect(S.crop('Coconut'), equals('தேங்காய்'));
      expect(S.crop('Maize'), equals('மக்காச்சோளம்'));
      expect(S.crop('Jasmine'), equals('மல்லிகை'));
      expect(S.crop('Marigold'), equals('சாமந்தி'));

      // Static UI strings
      expect(S.t('Crop Image — Required'), equals('பயிரின் படம் — கட்டாயம்'));
      expect(S.t('Upload Crop Image'), equals('பயிரின் படத்தைப் பதிவேற்றவும்'));
      expect(S.t('Take Photo'), equals('புகைப்படம் எடுக்கவும்'));
      expect(S.t('Choose from Gallery'), equals('கேலரியிலிருந்து தேர்ந்தெடுக்கவும்'));
      expect(S.t('Image Preview'), equals('பட முன்னோட்டம்'));
      expect(S.t('Replace Image'), equals('படத்தை மாற்றவும்'));
      expect(S.t('Remove Image'), equals('படத்தை நீக்கவும்'));
      expect(S.t('Crop image is required before publishing'),
          equals('வெளியிடுவதற்கு முன் பயிரின் படம் கட்டாயம் தேவை'));

      // Reset to English
      VayalStrings.setLanguage(false);
    });

    test('Unknown crop names are preserved safely without throwing', () {
      VayalStrings.setLanguage(true);
      expect(S.crop('Dragonfruit Special Hybrid'), equals('Dragonfruit Special Hybrid'));
      expect(S.crop(''), equals(''));
      expect(S.crop(null), equals(''));
      VayalStrings.setLanguage(false);
      expect(S.crop('Dragonfruit Special Hybrid'), equals('Dragonfruit Special Hybrid'));
    });

    test('Compound names with delimiter · resolve correctly in both languages', () {
      const compound = 'Wheat · கோதுமை';

      VayalStrings.setLanguage(false);
      expect(S.crop(compound), equals('Wheat'));

      VayalStrings.setLanguage(true);
      expect(S.crop(compound), equals('கோதுமை'));

      VayalStrings.setLanguage(false);
    });
  });

  group('CropImage Widget Fallback and Rendering', () {
    testWidgets('CropImage displays clean fallback when URL is null or empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 100,
              height: 100,
              child: CropImage(null, semanticLabel: 'Empty Crop'),
            ),
          ),
        ),
      );

      expect(find.byType(CropImage), findsOneWidget);
      // Brand fallback icon (eco) should be rendered
      expect(find.byIcon(Icons.eco_outlined), findsOneWidget);
    });
  });

  group('AddProductScreen Mandatory Image Enforcement', () {
    testWidgets('AddProductScreen shows mandatory image section and blocks submission without image',
        (tester) async {
      VayalStrings.setLanguage(false);
      final mockApi = MockAddProductApi();

      await tester.pumpWidget(
        MaterialApp(
          home: AddProductScreen(api: mockApi),
        ),
      );
      await tester.pumpAndSettle();

      // Verify the mandatory section is present
      expect(find.text('Crop Image — Required'), findsOneWidget);
      expect(find.text('Upload Crop Image'), findsOneWidget);
      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Choose from Gallery'), findsOneWidget);

      // Attempt to publish without an image
      final publishButton = find.text('Publish');
      expect(publishButton, findsOneWidget);
      await tester.ensureVisible(publishButton);
      await tester.tap(publishButton);
      await tester.pump();

      // Verification: publish API was NOT called because image is missing
      expect(mockApi.productCreated, isFalse);
      expect(find.text('Crop image is required before publishing'), findsWidgets);
    });

    testWidgets('AddProductScreen shows localized Tamil image section when Tamil selected',
        (tester) async {
      VayalStrings.setLanguage(true);
      final mockApi = MockAddProductApi();

      await tester.pumpWidget(
        MaterialApp(
          home: AddProductScreen(api: mockApi),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('பயிரின் படம் — கட்டாயம்'), findsOneWidget);
      expect(find.text('பயிரின் படத்தைப் பதிவேற்றவும்'), findsOneWidget);
      expect(find.text('புகைப்படம் எடுக்கவும்'), findsOneWidget);
      expect(find.text('கேலரியிலிருந்து தேர்ந்தெடுக்கவும்'), findsOneWidget);

      VayalStrings.setLanguage(false);
    });

    testWidgets(
        'Nearest Mandi field retains focus and typing does not redirect to Quantity',
        (tester) async {
      VayalStrings.setLanguage(false);
      final mockApi = MockAddProductApi();

      await tester.pumpWidget(
        MaterialApp(
          home: AddProductScreen(api: mockApi),
        ),
      );
      await tester.pumpAndSettle();

      final mandiFinder = find.byKey(const ValueKey('field_input_market'));
      final quantityFinder =
          find.byKey(const ValueKey('field_input_quantity'));

      expect(mandiFinder, findsOneWidget);
      expect(quantityFinder, findsOneWidget);

      // Scroll to Nearest Mandi field and tap it
      await tester.ensureVisible(mandiFinder);
      await tester.tap(mandiFinder);
      await tester.pumpAndSettle();

      // Enter text into Nearest Mandi
      await tester.enterText(mandiFinder, 'Madurai APMC Mandi');
      await tester.pumpAndSettle();

      // Verify text is strictly in Nearest Mandi and NOT Quantity
      expect(find.text('Madurai APMC Mandi'), findsOneWidget);
      final quantityField = tester.widget<TextFormField>(quantityFinder);
      expect(quantityField.controller?.text.isEmpty ?? true, isTrue);

      // Now enter quantity
      await tester.ensureVisible(quantityFinder);
      await tester.tap(quantityFinder);
      await tester.enterText(quantityFinder, '250');
      await tester.pumpAndSettle();

      // Verify both fields preserved their respective inputs
      expect(find.text('Madurai APMC Mandi'), findsOneWidget);
      expect(find.text('250'), findsOneWidget);
    });

    testWidgets('Changing crop name marks verified image as needing re-validation',
        (tester) async {
      VayalStrings.setLanguage(false);
      final mockApi = MockAddProductApi();

      await tester.pumpWidget(
        MaterialApp(
          home: AddProductScreen(
            api: mockApi,
            initialImageUrl: '/api/v1/media/mock_tomato_img',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cropNameFinder =
          find.byKey(const ValueKey('field_input_product_name'));
      await tester.enterText(cropNameFinder, 'Tomato');
      await tester.pumpAndSettle();

      // Now change crop name to Banana
      await tester.enterText(cropNameFinder, 'Banana');
      await tester.pumpAndSettle();

      // Verify badge indicates re-validation required
      expect(find.text('Crop changed — re-validation required'), findsOneWidget);
    });
  });
}
