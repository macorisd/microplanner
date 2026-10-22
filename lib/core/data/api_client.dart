import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  const ApiException(this.status, this.code, this.message);
  bool get isOffline => status == 0 || status >= 500;
  @override
  String toString() => message;
}

class ApiClient {
  final Uri baseUrl;
  final http.Client _client;
  void Function(String token)? onUnauthorized;
  ApiClient(String url, {http.Client? client})
    : baseUrl = Uri.parse(url),
      _client = client ?? http.Client() {
    if (!['http', 'https'].contains(baseUrl.scheme) ||
        baseUrl.host.isEmpty ||
        baseUrl.userInfo.isNotEmpty ||
        baseUrl.hasQuery ||
        baseUrl.hasFragment) {
      throw ArgumentError('API_BASE_URL must be an HTTP(S) server URL.');
    }
  }
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    final request = http.Request(method, baseUrl.resolve(path));
    request.headers['Content-Type'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);
    try {
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid response');
      }
      if (response.statusCode >= 400) {
        if (response.statusCode == 401 && token != null) {
          onUnauthorized?.call(token);
        }
        throw ApiException(
          response.statusCode,
          decoded['code'] as String? ?? 'request_failed',
          decoded['message'] as String? ??
              'The request failed. Please try again.',
        );
      }
      return decoded;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        0,
        'offline',
        'The server did not respond. Check your connection and try again.',
      );
    } on SocketException {
      throw const ApiException(
        0,
        'offline',
        'Cannot reach the server. Check your connection.',
      );
    } on http.ClientException {
      throw const ApiException(
        0,
        'offline',
        'Cannot reach the server. Check your connection.',
      );
    } on FormatException {
      throw const ApiException(
        503,
        'invalid_response',
        'The server returned an invalid response.',
      );
    }
  }
}
