/// Application configuration flags
/// Use these to enable/disable features during development
class AppConfig {
  AppConfig._();

  /// Set to true to enable authentication flow (login screen)
  /// Set to false to bypass authentication and go directly to dashboard
  /// 
  /// When false, the app will skip the login screen entirely
  /// and show the dashboard immediately on launch
  static const bool enableAuthentication = false;

  // Add more feature flags here as needed
  // Example:
  // static const bool enableOnboarding = true;
  // static const bool enableAnalytics = false;
}
