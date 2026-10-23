import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android launcher icon and branding verification', () {
    const resDir = 'android/app/src/main/res';
    const manifestPath = 'android/app/src/main/AndroidManifest.xml';
    const pubspecPath = 'pubspec.yaml';
    const officialLogoPath = 'assets/branding/vayalconnect-logo.jpeg';

    test('official brand logo asset exists and is intact', () {
      final logoFile = File(officialLogoPath);
      expect(logoFile.existsSync(), isTrue,
          reason: 'Official VayalConnect brand logo must exist');
      expect(logoFile.lengthSync(), greaterThan(100000),
          reason: 'Official logo file size must match original asset');
    });

    test('pubspec version is 1.1.0+7 or higher', () {
      final pubspec = File(pubspecPath).readAsStringSync();
      final match = RegExp(r'version: 1\.1\.0\+(\d+)').firstMatch(pubspec);
      expect(match, isNotNull);
      final code = int.parse(match!.group(1)!);
      expect(code, greaterThanOrEqualTo(7),
          reason: 'pubspec.yaml must have version code higher than latest candidate 6');
    });

    test('AndroidManifest configures both standard and round launcher icons and preserves Tamil label', () {
      final manifest = File(manifestPath).readAsStringSync();
      expect(manifest.contains('android:icon="@mipmap/ic_launcher"'), isTrue);
      expect(manifest.contains('android:roundIcon="@mipmap/ic_launcher_round"'), isTrue);
      expect(manifest.contains('android:label="வயல் Connect"'), isTrue);
    });

    test('adaptive icon XML descriptors exist and reference valid resources', () {
      final anydpiDir = Directory('$resDir/mipmap-anydpi-v26');
      expect(anydpiDir.existsSync(), isTrue);

      final iconXml = File('$resDir/mipmap-anydpi-v26/ic_launcher.xml');
      expect(iconXml.existsSync(), isTrue);
      final iconContent = iconXml.readAsStringSync();
      expect(iconContent.contains('<adaptive-icon'), isTrue);
      expect(iconContent.contains('@color/ic_launcher_background'), isTrue);
      expect(iconContent.contains('@mipmap/ic_launcher_foreground'), isTrue);

      final roundIconXml = File('$resDir/mipmap-anydpi-v26/ic_launcher_round.xml');
      expect(roundIconXml.existsSync(), isTrue);
      final roundContent = roundIconXml.readAsStringSync();
      expect(roundContent.contains('<adaptive-icon'), isTrue);
      expect(roundContent.contains('@color/ic_launcher_background'), isTrue);
      expect(roundContent.contains('@mipmap/ic_launcher_foreground'), isTrue);
    });

    test('launcher background colors are defined for light and dark system themes', () {
      final lightColors = File('$resDir/values/colors.xml');
      expect(lightColors.existsSync(), isTrue);
      expect(lightColors.readAsStringSync().contains('name="ic_launcher_background">#FFFFFF'), isTrue);

      final darkColors = File('$resDir/values-night/colors.xml');
      expect(darkColors.existsSync(), isTrue);
      expect(darkColors.readAsStringSync().contains('name="ic_launcher_background">#FFFFFF'), isTrue);
    });

    const densities = {
      'mipmap-mdpi': {'adaptive': 108, 'legacy': 48},
      'mipmap-hdpi': {'adaptive': 162, 'legacy': 72},
      'mipmap-xhdpi': {'adaptive': 216, 'legacy': 96},
      'mipmap-xxhdpi': {'adaptive': 324, 'legacy': 144},
      'mipmap-xxxhdpi': {'adaptive': 432, 'legacy': 192},
    };

    for (final entry in densities.entries) {
      final density = entry.key;
      test('$density contains complete launcher resources with nonzero sizes', () {
        final fg = File('$resDir/$density/ic_launcher_foreground.png');
        final bg = File('$resDir/$density/ic_launcher_background.png');
        final leg = File('$resDir/$density/ic_launcher.png');
        final roundLeg = File('$resDir/$density/ic_launcher_round.png');

        expect(fg.existsSync(), isTrue, reason: '$density ic_launcher_foreground must exist');
        expect(bg.existsSync(), isTrue, reason: '$density ic_launcher_background must exist');
        expect(leg.existsSync(), isTrue, reason: '$density ic_launcher must exist');
        expect(roundLeg.existsSync(), isTrue, reason: '$density ic_launcher_round must exist');

        expect(fg.lengthSync(), greaterThan(100), reason: '$density fg non-empty');
        expect(bg.lengthSync(), greaterThan(50), reason: '$density bg non-empty');
        expect(leg.lengthSync(), greaterThan(100), reason: '$density leg non-empty');
        expect(roundLeg.lengthSync(), greaterThan(100), reason: '$density roundLeg non-empty');
      });
    }
  });
}
