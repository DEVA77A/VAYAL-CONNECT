import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vayalconnect_flutter/config/api_config.dart';
import 'package:vayalconnect_flutter/models/auth_models.dart';
import 'package:vayalconnect_flutter/screens/auth_gateway_screen.dart';
import 'package:vayalconnect_flutter/screens/orders_screen.dart';
import 'package:vayalconnect_flutter/screens/buyer_home_screen.dart';
import 'package:vayalconnect_flutter/screens/product_details_screen.dart';
import 'package:vayalconnect_flutter/widgets/marketplace_product_card.dart';
import 'package:vayalconnect_flutter/services/api_client.dart';
import 'package:vayalconnect_flutter/services/session_manager.dart';
import 'package:vayalconnect_flutter/theme/app_theme.dart';
import 'package:vayalconnect_flutter/utils/commerce_strings.dart';
import 'package:vayalconnect_flutter/widgets/brand_widgets.dart';

const previewDir = String.fromEnvironment('UI_PREVIEW_DIR');

class RealHttpOverrides extends HttpOverrides {}

Future<void> capture(WidgetTester tester, String name) async {
  if (previewDir.isEmpty) return;
  await tester.runAsync(() => precacheImage(
      const AssetImage('assets/branding/vayalconnect-logo.jpeg'),
      tester.element(find.byType(Scaffold).first)));
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('premium-preview')));
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 1);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await Directory(previewDir).create(recursive: true);
    await File('$previewDir/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    img.dispose();
  });
}

Future<void> fonts(WidgetTester tester) async {
  if (previewDir.isEmpty) return;
  await tester.runAsync(() async {
    for (final pair in [
      [
        'Roboto',
        'C:/src/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf'
      ],
      [
        'MaterialIcons',
        'C:/src/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf'
      ],
      ['Nirmala UI', 'C:/Windows/Fonts/Nirmala.ttc'],
      ['Ahem', 'C:/Windows/Fonts/Nirmala.ttc'],
    ]) {
      final file = File(pair[1]);
      if (!await file.exists()) continue;
      final loader = FontLoader(pair[0]);
      loader.addFont(
          Future.value(ByteData.sublistView(await file.readAsBytes())));
      await loader.load();
    }
  });
}

Widget app(Widget home, {bool tamil = false, double scale = 1}) =>
    RepaintBoundary(
        key: const ValueKey('premium-preview'),
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            locale: Locale(tamil ? 'ta' : 'en'),
            supportedLocales: const [Locale('en'), Locale('ta')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: home));

void setRole(AppRole role, bool tamil) => SessionManager().setSession(
    token: 'test-only-token',
    user: UserProfile(
        id: 'test',
        name: 'Test',
        email: 'test@example.invalid',
        role: role,
        preferredLanguage: tamil ? 'ta' : 'en'));

Map<String, dynamic> order(AppRole role) => {
      'order_id': 'historical',
      'order_number': 'VC-2026-VERY-LONG-ORDER-ID',
      'product_name': 'தக்காளி · Farmer harvest with a long crop name',
      'quantity': 12,
      'unit': 'KG',
      'order_status': 'COMPLETED',
      'payment_status': 'CAPTURED',
      'created_at': '2026-10-15T05:10:00Z',
      'farmer_base_total_paise': 1481400,
      'commission_total_paise': 296280,
      'delivery_fee_paise': 0,
      if (role != AppRole.farmer) 'buyer_total_paise': 1777680,
      if (role == AppRole.farmer) 'farmer_total_payout_display': '₹14814.00',
      'fulfillment_method': 'DELIVERY',
      'delivery_address': {
        'recipient_name': 'Recipient with a long name',
        'phone': '9876543210',
        'address':
            '12 Agricultural Road, Long locality, Pollachi, Coimbatore, Tamil Nadu — நீண்ட முகவரி',
        'postal_code': '642001'
      },
      'delivery_estimate': {
        'available': true,
        'distance_km': 12.6,
        'arrival_from': '2026-10-16',
        'arrival_to': '2026-10-17'
      },
    };

void main() {
  final originalBase = ApiConfig.baseUrl;
  tearDown(() {
    SessionManager().logout();
    ApiConfig.baseUrl = originalBase;
    debugNetworkImageHttpClientProvider = null;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('marketplace preserves each uploaded image into checkout',
      (tester) async {
    setRole(AppRole.buyer, false);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var reads = 0;
    final api = ApiClient(client: MockClient((r) async {
      reads++;
      expect(r.url.queryParameters['limit'], '20');
      expect(r.url.queryParameters['sort'], 'newest');
      return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'total': 2,
              'items': [
                for (var i = 0; i < 2; i++)
                  {
                    'product_id': 'crop-$i',
                    'product_name': 'Farmer crop $i',
                    'quantity_available': 12,
                    'quantity_unit': 'KG',
                    'location': 'Pollachi',
                    'buyer_price_per_unit_paise': 4200,
                    'image_url': '/api/v1/media/upload-$i',
                  }
              ]
            }
          }),
          200);
    }));
    addTearDown(api.dispose);
    await tester.pumpWidget(app(BuyerHomeScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byType(MarketplaceProductCard).first, 200,
        scrollable: find
            .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    final cards = tester
        .widgetList<MarketplaceProductCard>(find.byType(MarketplaceProductCard))
        .toList();
    expect(cards.map((c) => c.product.imageUrl),
        ['/api/v1/media/upload-0', '/api/v1/media/upload-1']);
    await tester.scrollUntilVisible(find.text('Farmer crop 0'), 150,
        scrollable: find
            .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('Farmer crop 0'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductDetailsScreen), findsOneWidget);
    expect(tester.widget<CropImage>(find.byType(CropImage)).url,
        '/api/v1/media/upload-0');
    expect(reads, 1,
        reason: 'opening checkout must retain the supplied product snapshot');
    expect(tester.takeException(), isNull);
  });

  test('image resolution rejects missing, malformed and unsafe schemes', () {
    for (final url in <String?>[
      null,
      '',
      '   ',
      'tomato.jpg',
      '//unknown.invalid/image',
      'file:///crop.jpg',
      'data:image/jpeg;base64,AA',
      'https://',
      'http://[bad',
      'https://name:secret@example.invalid/crop'
    ]) {
      expect(resolveCropImage(url), isNull, reason: '$url');
    }
    expect(resolveCropImage(' /api/v1/media/abc ')?.toString(),
        '$originalBase/api/v1/media/abc');
  });

  for (final absolute in [false, true]) {
    testWidgets('backend media receives authorization absolute=$absolute',
        (tester) async {
      setRole(AppRole.buyer, false);
      final url = '${absolute ? originalBase : ''}/api/v1/media/crop';
      await tester.pumpWidget(app(Scaffold(
          body: SizedBox(width: 200, height: 150, child: CropImage(url)))));
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(
          find.byWidgetPredicate((w) => w is Image && w.image is ResizeImage));
      final resized = image.image as ResizeImage;
      final provider = resized.imageProvider as NetworkImage;
      expect(provider.url, '$originalBase/api/v1/media/crop');
      expect(provider.headers?['Authorization'], 'Bearer test-only-token');
      expect(resized.width, lessThanOrEqualTo(1600));
      expect(find.byIcon(Icons.broken_image), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('external product photos never receive the session token',
      (tester) async {
    setRole(AppRole.buyer, false);
    await tester.pumpWidget(app(const Scaffold(
        body: SizedBox(
            width: 80,
            height: 80,
            child: CropImage('https://farmer.example.invalid/crop.jpg')))));
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(
        find.byWidgetPredicate((w) => w is Image && w.image is ResizeImage));
    expect(((image.image as ResizeImage).imageProvider as NetworkImage).headers,
        isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'actual image bytes render, survive rebuild, and failed images fall back',
      (tester) async {
    late HttpServer server;
    late HttpClient client;
    var successfulReads = 0;
    await tester.runAsync(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      // Uses local official artwork as test bytes only, never as fake crop data.
      final bytes =
          await File('assets/branding/vayalconnect-logo.jpeg').readAsBytes();
      server.listen((request) async {
        if (request.uri.path == '/crop.jpg') {
          successfulReads++;
          request.response.headers.contentType = ContentType('image', 'jpeg');
          request.response.add(bytes);
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });
      client = HttpOverrides.runWithHttpOverrides(
          () => HttpClient(), RealHttpOverrides());
    });
    debugNetworkImageHttpClientProvider = () => client;
    addTearDown(() async {
      client.close(force: true);
      await server.close(force: true);
    });
    final url = 'http://127.0.0.1:${server.port}/crop.jpg';
    Future<void> load(String source) async {
      await tester.pumpWidget(app(Scaffold(
          body: SizedBox(
              width: 240,
              height: 180,
              child: CropImage(source, semanticLabel: 'Actual crop')))));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    await load(url);
    final photograph = find.byWidgetPredicate(
        (w) => w is RawImage && w.image != null && w.image!.width == 768);
    expect(photograph, findsOneWidget);
    expect(successfulReads, 1);
    await load(url);
    expect(successfulReads, 1,
        reason: 'unchanged image must reuse Flutter cache');
    await load('http://127.0.0.1:${server.port}/missing.jpg');
    expect(
        find.byWidgetPredicate((w) =>
            w is Semantics &&
            w.properties.label == 'Crop photograph unavailable'),
        findsOneWidget);
    expect(find.byIcon(Icons.broken_image), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugNetworkImageHttpClientProvider = null;
    client.close(force: true);
    await tester.runAsync(() => server.close(force: true));
  });

  for (final tamil in [false, true]) {
    for (final width in [320.0, 800.0]) {
      for (final role in AppRole.values) {
        testWidgets('historical ${role.name} order fits $width Tamil=$tamil',
            (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          setRole(role, tamil);
          await fonts(tester);
          var reads = 0;
          final api = ApiClient(client: MockClient((r) async {
            reads++;
            expect(r.url.path, '/api/v1/orders/historical');
            return http.Response(
                jsonEncode({'success': true, 'data': order(role)}), 200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          }));
          addTearDown(api.dispose);
          await tester.pumpWidget(app(
              OrderDetailScreen(orderId: 'historical', api: api),
              tamil: tamil,
              scale: width == 320 ? 2 : 1));
          await tester.pumpAndSettle();
          expect(find.text(S.t('Order summary')), findsOneWidget);
          expect(
              find.byWidgetPredicate((w) =>
                  w is Semantics &&
                  w.properties.label == S.t('Crop photograph unavailable')),
              findsOneWidget);
          expect(reads, 1,
              reason: 'historical records must not trigger product requests');
          expect(tester.takeException(), isNull);
          await capture(tester,
              'order-${role.name}-${tamil ? 'ta' : 'en'}-${width.toInt()}');
          await tester.scrollUntilVisible(
              find.text(S.t('Payment breakdown')), 300);
          await tester.pumpAndSettle();
          if (role == AppRole.buyer) {
            expect(find.text(S.t('Farmer earnings')), findsNothing);
          }
          await tester.scrollUntilVisible(
              find.text(S.t('Delivery information')), 250);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await capture(tester,
              'delivery-${role.name}-${tamil ? 'ta' : 'en'}-${width.toInt()}');
          await tester.scrollUntilVisible(
              find.text(S.t('Contact number')), 200);
          expect(find.text('9876543210'), findsOneWidget);
          expect(find.textContaining('null'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }

  testWidgets('farmer order action keeps the existing server transition',
      (tester) async {
    setRole(AppRole.farmer, false);
    var transitions = 0;
    final api = ApiClient(client: MockClient((r) async {
      if (r.method == 'PUT') {
        transitions++;
        expect(r.url.path, '/api/v1/orders/historical/status');
        expect(jsonDecode(r.body), {'order_status': 'CONFIRMED'});
      }
      return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              ...order(AppRole.farmer),
              'order_status': transitions == 0 ? 'PAID' : 'CONFIRMED',
            }
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    addTearDown(api.dispose);
    await tester
        .pumpWidget(app(OrderDetailScreen(orderId: 'historical', api: api)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Accept order'), 300);
    await tester.tap(find.text('Accept order'));
    await tester.pumpAndSettle();
    expect(transitions, 1);
    expect(find.text('Start preparing'), findsOneWidget);
    expect(find.text('Buyer total'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final tamil in [false, true]) {
    testWidgets('auth sheets fit 320px 2x with keyboard Tamil=$tamil',
        (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      setRole(AppRole.buyer, tamil);
      await fonts(tester);
      await tester
          .pumpWidget(app(const AuthGatewayScreen(), tamil: tamil, scale: 2));
      await tester.pumpAndSettle();
      final register = find
          .textContaining(tamil ? 'பதிவு செய்' : 'Register', findRichText: true)
          .last;
      await tester.ensureVisible(register);
      await tester.tap(register);
      await tester.pumpAndSettle();
      expect(find.byType(SheetTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, 'register-${tamil ? 'ta' : 'en'}-320');
      tester.view.resetViewInsets();
      await tester.tap(find.descendant(
          of: find.byType(SheetTitle), matching: find.byIcon(Icons.close)));
      await tester.pumpAndSettle();
      final forgot = find
          .textContaining(tamil ? 'கடவுச்சொல் மறந்ததா?' : 'Forgot Password?');
      await tester.ensureVisible(forgot);
      await tester.tap(forgot);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, 'recovery-${tamil ? 'ta' : 'en'}-320');
      tester.view.resetViewInsets();
      await tester.pumpWidget(const SizedBox());
    });
  }
}
