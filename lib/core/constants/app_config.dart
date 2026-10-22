import 'dart:io';

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
    const configured = String.fromEnvironment('API_BASE_URL');
    return configured.isNotEmpty
        ? configured
        : Platform.isAndroid
        ? 'http://10.0.2.2:3000'
        : 'http://127.0.0.1:3000';
  }
}
