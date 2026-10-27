import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
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
  String? _refreshToken;
  UserProfile? _currentUser;
  AppRole _activeRole = AppRole.farmer;
  bool _isTamil = false; // Default language: English
  bool _isDemoMode = false;
  bool _savingLanguage = false;
  bool get savingLanguage => _savingLanguage;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  UserProfile? get currentUser => _currentUser;
  AppRole get activeRole => _activeRole;
  bool get isTamil => _isTamil;
  bool get isDemoMode => _isDemoMode;
  bool get isAuthenticated =>
      (_accessToken != null && _accessToken!.isNotEmpty) || _isDemoMode;

  /// Establish an authentic session from backend API response
  Future<void> setSession({
    required String token,
    String? refreshToken,
    required UserProfile user,
  }) async {
    _accessToken = token;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      _refreshToken = refreshToken;
    }
    _currentUser = user;
    _activeRole = user.role;
    _isTamil = user.preferredLanguage == 'ta';
    VayalStrings.setLanguage(_isTamil);
    _isDemoMode = false; // Strictly real live session
    await _persistSession();
    notifyListeners();
  }

  /// Update tokens on successful refresh
  Future<void> updateTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    _accessToken = accessToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      _refreshToken = refreshToken;
    }
    await _persistSession();
    notifyListeners();
  }

  void refreshProfile(UserProfile user) {
    if (user.id != _currentUser?.id || user.role != _activeRole) return;
    _currentUser = user;
    _persistSession();
    notifyListeners();
  }

  void switchRole(AppRole newRole) {
    _activeRole = newRole;
    notifyListeners();
  }

  Future<void> toggleLanguagePersisted({http.Client? client}) async {
    if (_savingLanguage) return;
    if (_accessToken == null || _isDemoMode) {
      toggleLanguage();
      return;
    }
    final nextTamil = !_isTamil;
    final accountId = _currentUser?.id;
    final authToken = _accessToken;
    final api = client ?? http.Client();
    _savingLanguage = true;
    notifyListeners();
    try {
      final response = await api
          .put(Uri.parse('${ApiConfig.baseUrl}/api/v1/users/me/language'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $authToken'
              },
              body: jsonEncode({'preferred_language': nextTamil ? 'ta' : 'en'}))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200 ||
          (jsonDecode(response.body) as Map)['success'] != true) {
        throw Exception('Unable to save language preference. Please retry.');
      }
      if (_currentUser?.id == accountId && _accessToken == authToken) {
        setLanguage(nextTamil);
      }
    } finally {
      if (client == null) api.close();
      _savingLanguage = false;
      notifyListeners();
    }
  }

  void toggleLanguage() {
    setLanguage(!_isTamil);
  }

  void setLanguage(bool tamil) {
    _isTamil = tamil;
    VayalStrings.setLanguage(_isTamil);
    SharedPreferences.getInstance()
        .then((p) => p.setBool('vayal_language_tamil', tamil));
    notifyListeners();
  }

  Future<void> restoreLanguage() async {
    final p = await SharedPreferences.getInstance();
    _isTamil = p.getBool('vayal_language_tamil') ?? false;
    VayalStrings.setLanguage(_isTamil);
    notifyListeners();
  }

  Future<void> _persistSession() async {
    final p = await SharedPreferences.getInstance();
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      await p.setString('vayal_access_token', _accessToken!);
    } else {
      await p.remove('vayal_access_token');
    }
    if (_refreshToken != null && _refreshToken!.isNotEmpty) {
      await p.setString('vayal_refresh_token', _refreshToken!);
    } else {
      await p.remove('vayal_refresh_token');
    }
    if (_currentUser != null) {
      await p.setString('vayal_user_profile', jsonEncode(_currentUser!.toJson()));
    } else {
      await p.remove('vayal_user_profile');
    }
    await p.setString('vayal_active_role', _activeRole.name);
    await p.setBool('vayal_is_demo_mode', _isDemoMode);
  }

  Future<void> restoreSession() async {
    try {
      final p = await SharedPreferences.getInstance();
      final token = p.getString('vayal_access_token');
      final refreshToken = p.getString('vayal_refresh_token');
      final userJson = p.getString('vayal_user_profile');
      final roleName = p.getString('vayal_active_role');
      final isDemo = p.getBool('vayal_is_demo_mode') ?? false;

      if (token != null && token.isNotEmpty && userJson != null) {
        final Map<String, dynamic> decoded = jsonDecode(userJson);
        _accessToken = token;
        _refreshToken = refreshToken;
        _currentUser = UserProfile.fromJson(decoded);
        if (roleName != null) {
          _activeRole = AppRole.values.firstWhere(
            (r) => r.name == roleName,
            orElse: () => _currentUser!.role,
          );
        } else {
          _activeRole = _currentUser!.role;
        }
        _isDemoMode = false;
        notifyListeners();
      } else if (isDemo && !kReleaseMode && roleName != null) {
        final role = AppRole.values.firstWhere(
          (r) => r.name == roleName,
          orElse: () => AppRole.farmer,
        );
        enterDemoMode(role);
      }
    } catch (_) {
      // Corrupted session, clear safely
      final p = await SharedPreferences.getInstance();
      p.remove('vayal_access_token');
      p.remove('vayal_refresh_token');
      p.remove('vayal_user_profile');
      p.remove('vayal_active_role');
      p.remove('vayal_is_demo_mode');
    }
  }

  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    _currentUser = null;
    _isDemoMode = false;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('vayal_access_token');
      await p.remove('vayal_refresh_token');
      await p.remove('vayal_user_profile');
      await p.remove('vayal_active_role');
      await p.remove('vayal_is_demo_mode');
    } catch (_) {}
    notifyListeners();
  }

  /// Explicitly enter offline DEMO / PREVIEW mode.
  /// Clearly flagged so the UI always communicates demo status honestly.
  void enterDemoMode(AppRole role) {
    if (kReleaseMode) {
      throw StateError("Preview accounts are disabled in release builds.");
    }
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

  /// For testing memory-resets
  @visibleForTesting
  void resetForTests() {
    _accessToken = null;
    _refreshToken = null;
    _currentUser = null;
    _activeRole = AppRole.farmer;
    _isDemoMode = false;
  }
}
