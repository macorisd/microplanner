class AppConfig {
  AppConfig._();
  static const bool enableAuthentication = true;
  static const windowsClientId = String.fromEnvironment(
    'GOOGLE_WINDOWS_CLIENT_ID',
    defaultValue:
        '853649790752-s8t10u7gj5u3b4m8gd0paqhsabshv131.apps.googleusercontent.com',
  );
  static const webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '853649790752-vm13udq65n5ul6o3vferd10a8gora651.apps.googleusercontent.com',
  );
  static String get apiUrl {
    return const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://microplanner-api.vercel.app',
    );
  }
}
