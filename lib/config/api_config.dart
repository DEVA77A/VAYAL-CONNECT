/// VayalConnect Flutter — Centralized API Configuration
///
/// Centralized API endpoint configuration pointing to the FastAPI backend.
/// Note: The mobile app NEVER communicates directly with data.gov.in.
/// All government mandi rates flow securely through the VayalConnect backend.
class ApiConfig {
  ApiConfig._();

  /// Default endpoints
  static const String productionBaseUrl = 'https://vayal-connect.onrender.com';
  static const String emulatorBaseUrl = 'http://10.0.2.2:8000';
  static const String localhostBaseUrl = 'http://localhost:8000';

  /// Base URL for VayalConnect Backend API.
  /// Points to live production on Render by default, or configurable via
  /// `--dart-define=BACKEND_BASE_URL=...` or runtime call to `setBaseUrl()`.
  static String baseUrl = const String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: productionBaseUrl,
  );

  /// Centralized setter for physical device IP or dynamic runtime configuration
  static void setBaseUrl(String url) {
    baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  // Market prices endpoints on the FastAPI backend
  static String get marketPricesUrl => '$baseUrl/api/v1/market-prices';
  static String get latestMarketPriceUrl => '$baseUrl/api/v1/market-prices/latest';
  static String get filterOptionsUrl => '$baseUrl/api/v1/market-prices/filter-options';

  // Authentication endpoints
  static String get registerUrl => '$baseUrl/api/v1/auth/register';
  static String get loginUrl => '$baseUrl/api/v1/auth/login';
  static String get requestOtpUrl => '$baseUrl/api/v1/auth/request-otp';
  static String get verifyOtpUrl => '$baseUrl/api/v1/auth/verify-otp';
  static String get selectRoleUrl => '$baseUrl/api/v1/auth/select-role';
  static String get refreshUrl => '$baseUrl/api/v1/auth/refresh';
  static String get logoutUrl => '$baseUrl/api/v1/auth/logout';
  static String get forgotPasswordUrl => '$baseUrl/api/v1/auth/forgot-password';
  static String get resetPasswordUrl => '$baseUrl/api/v1/auth/reset-password';

  // Products endpoints
  static String get productsUrl => '$baseUrl/api/v1/products/';
  static String get myProductsUrl => '$baseUrl/api/v1/products/my';

  // Orders endpoints
  static String get ordersUrl => '$baseUrl/api/v1/orders/';

  // Farmer endpoints
  static String get farmerProfileUrl => '$baseUrl/api/v1/farmers/me/profile';
  static String get farmerDashboardUrl => '$baseUrl/api/v1/farmers/me/dashboard';

  // Admin endpoints
  static String get adminDashboardUrl => '$baseUrl/api/v1/admin/dashboard';
  static String get adminUsersUrl => '$baseUrl/api/v1/admin/users';
}
