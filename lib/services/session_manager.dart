import 'package:flutter/foundation.dart';
import '../models/auth_models.dart';
import '../utils/localization.dart';

/// Central Session and State Manager for VayalConnect Flutter
///
/// Manages current authenticated user, active role, access token,
/// language preferences, and explicit Demo / Offline preview mode.
class SessionManager extends ChangeNotifier {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  String? _accessToken;
  UserProfile? _currentUser;
  AppRole _activeRole = AppRole.farmer;
  bool _isTamil = false; // Default language: English
  bool _isDemoMode = false;

  String? get accessToken => _accessToken;
  UserProfile? get currentUser => _currentUser;
  AppRole get activeRole => _activeRole;
  bool get isTamil => _isTamil;
  bool get isDemoMode => _isDemoMode;
  bool get isAuthenticated => (_accessToken != null && _accessToken!.isNotEmpty) || _isDemoMode;

  /// Establish an authentic session from backend API response
  void setSession({
    required String token,
    required UserProfile user,
  }) {
    _accessToken = token;
    _currentUser = user;
    _activeRole = user.role;
    _isDemoMode = false; // Strictly real live session
    notifyListeners();
  }

  void switchRole(AppRole newRole) {
    _activeRole = newRole;
    notifyListeners();
  }

  void toggleLanguage() {
    _isTamil = !_isTamil;
    VayalStrings.setLanguage(_isTamil);
    notifyListeners();
  }

  void setLanguage(bool tamil) {
    _isTamil = tamil;
    VayalStrings.setLanguage(_isTamil);
    notifyListeners();
  }

  void logout() {
    _accessToken = null;
    _currentUser = null;
    _isDemoMode = false;
    notifyListeners();
  }

  /// Explicitly enter offline DEMO / PREVIEW mode.
  /// Clearly flagged so the UI always communicates demo status honestly.
  void enterDemoMode(AppRole role) {
    _isDemoMode = true;
    _activeRole = role;
    switch (role) {
      case AppRole.farmer:
        _currentUser = UserProfile(
          id: 'demo-farmer-01',
          name: 'முருகன் கே. (Murugan K.)',
          email: 'murugan.farmer@vayalconnect.in',
          phone: '+91 98765 43210',
          role: AppRole.farmer,
          address: '45/2 மேலத்தெரு, பாபநாசம்',
          areaLocation: 'Thanjavur, Tamil Nadu',
        );
        break;
      case AppRole.buyer:
        _currentUser = UserProfile(
          id: 'demo-buyer-01',
          name: 'சென்னை ஆர்கானிக்ஸ் (Chennai Organics)',
          email: 'procurement@chennaiorganics.in',
          phone: '+91 94440 12345',
          role: AppRole.buyer,
          address: '12 கோயம்பேடு மொத்த சந்தை வளாகம்',
          areaLocation: 'Chennai, Tamil Nadu',
        );
        break;
      case AppRole.admin:
        _currentUser = UserProfile(
          id: 'demo-admin-01',
          name: 'அரசு APMC மேற்பார்வையாளர் (TN Mandi Admin)',
          email: 'admin@vayalconnect.gov.in',
          phone: '+91 98400 99887',
          role: AppRole.admin,
          address: 'வேளாண்மை விற்பனை வாரியம்',
          areaLocation: 'Madurai, Tamil Nadu',
        );
        break;
    }
    notifyListeners();
  }

  /// Backward-compatible alias
  void setDemoRole(AppRole role) => enterDemoMode(role);
}
