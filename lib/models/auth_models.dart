/// VayalConnect Auth & User Data Models
///
/// Matches FastAPI backend schemas in app.schemas.auth & app.schemas.common

enum AppRole {
  farmer,
  buyer,
  admin,
}

extension AppRoleExtension on AppRole {
  String get value {
    switch (this) {
      case AppRole.farmer:
        return 'FARMER';
      case AppRole.buyer:
        return 'BUYER';
      case AppRole.admin:
        return 'ADMIN';
    }
  }

  static AppRole fromString(String? role) {
    if (role == null) return AppRole.farmer;
    switch (role.toUpperCase()) {
      case 'BUYER':
        return AppRole.buyer;
      case 'ADMIN':
        return AppRole.admin;
      case 'FARMER':
      default:
        return AppRole.farmer;
    }
  }
}

class UserProfile {
  final String id;
  final String name;
  final String email;
  final String phone;
  final AppRole role;
  final bool hasAssignedRole;
  final String? address;
  final String? areaLocation;
  final String preferredLanguage;

  UserProfile({
    required this.id,
    required this.name,
    required this.email,
    this.phone = '',
    required this.role,
    this.hasAssignedRole = true,
    this.address,
    this.areaLocation,
    this.preferredLanguage = 'en',
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String? ?? json['user_id'] as String? ?? '',
      name: json['name'] as String? ?? 'User',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      role: AppRoleExtension.fromString(json['role'] as String?),
      hasAssignedRole: ['FARMER', 'BUYER', 'ADMIN'].contains(json['role']),
      address: json['address'] as String?,
      areaLocation: json['area_location'] as String?,
      preferredLanguage: json['preferred_language'] as String? ?? 'en',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role.value,
      'address': address,
      'area_location': areaLocation,
      'preferred_language': preferredLanguage,
    };
  }
}

class AuthTokenResponse {
  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final int expiresIn;
  final UserProfile user;

  AuthTokenResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
    required this.user,
  });

  factory AuthTokenResponse.fromJson(Map<String, dynamic> json) {
    return AuthTokenResponse(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String? ?? '',
      tokenType: json['token_type'] as String? ?? 'bearer',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 3600,
      user: UserProfile.fromJson(json['user'] as Map<String, dynamic>? ?? {}),
    );
  }
}
