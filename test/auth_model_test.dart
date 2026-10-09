import 'package:flutter_test/flutter_test.dart';
import 'package:vayalconnect_flutter/models/auth_models.dart';

void main() {
  group('Auth & User Model Tests', () {
    test('Correctly parses UserProfile from json', () {
      final json = {
        'id': 'usr_123',
        'name': 'முருகன்',
        'email': 'murugan@vayalconnect.in',
        'phone': '9876543210',
        'role': 'FARMER',
        'area_location': 'Thanjavur',
        'preferred_language': 'ta',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.id, 'usr_123');
      expect(profile.name, 'முருகன்');
      expect(profile.email, 'murugan@vayalconnect.in');
      expect(profile.role, AppRole.farmer);
      expect(profile.areaLocation, 'Thanjavur');
      expect(profile.preferredLanguage, 'ta');
    });

    test('Correctly maps Buyer and Admin roles', () {
      expect(AppRoleExtension.fromString('BUYER'), AppRole.buyer);
      expect(AppRoleExtension.fromString('ADMIN'), AppRole.admin);
      expect(AppRoleExtension.fromString('UNKNOWN'), AppRole.farmer);
    });

    test('Parses AuthTokenResponse correctly', () {
      final json = {
        'access_token': 'jwt_access_abc',
        'refresh_token': 'jwt_refresh_xyz',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'buyer_1',
          'name': 'Selvaraj',
          'email': 'buyer@vayal.in',
          'role': 'BUYER',
        },
      };

      final res = AuthTokenResponse.fromJson(json);

      expect(res.accessToken, 'jwt_access_abc');
      expect(res.refreshToken, 'jwt_refresh_xyz');
      expect(res.expiresIn, 3600);
      expect(res.user.role, AppRole.buyer);
    });
  });
}
