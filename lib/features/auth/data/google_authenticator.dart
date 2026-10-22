import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_config.dart';
import '../../../core/data/api_client.dart';

abstract interface class GoogleAuthenticator {
  Future<Map<String, dynamic>?> signIn(ApiClient api);
  Future<void> signOut();
  void cancel();
}

class PlatformGoogleAuthenticator implements GoogleAuthenticator {
  Future<void>? _initialization;
  Completer<String?>? _callback;
  bool _canceled = false;
  static String _random() => base64UrlEncode(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  ).replaceAll('=', '');
  @override
  Future<Map<String, dynamic>?> signIn(ApiClient api) async {
    _canceled = false;
    if (Platform.isWindows) return _windows(api);
    if (!Platform.isAndroid) {
      throw const ApiException(
        400,
        'unsupported',
        'Google sign-in is available on Windows and Android.',
      );
    }
    _initialization ??= GoogleSignIn.instance.initialize(
      serverClientId: AppConfig.webClientId,
    );
    await _initialization;
    try {
      final account = await GoogleSignIn.instance.authenticate();
      if (_canceled) return null;
      final token = account.authentication.idToken;
      if (token == null) {
        throw const ApiException(
          401,
          'google_token',
          'Google did not return an identity token.',
        );
      }
      return await api.request(
        'POST',
        '/auth/google',
        body: {'idToken': token, 'platform': 'android'},
      );
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      throw const ApiException(
        401,
        'google_sign_in',
        'Google sign-in failed. Please try again or contact support.',
      );
    }
  }

  Future<Map<String, dynamic>?> _windows(ApiClient api) async {
    final verifier = _random();
    final state = _random();
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
    final listener = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final callback = Completer<String?>();
    _callback = callback;
    listener.listen((request) async {
      if (request.uri.path != '/oauth/callback') {
        request.response.statusCode = HttpStatus.notFound;
      } else if (request.uri.queryParameters['state'] != state) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write(
          'Invalid sign-in state. Return to microplanner and try again.',
        );
      } else {
        request.response.headers.contentType = ContentType.html;
        request.response.headers.set('Cache-Control', 'no-store');
        request.response.headers.set('Referrer-Policy', 'no-referrer');
        request.response.write(
          '<!doctype html><html><head><title>microplanner</title></head>'
          '<body><p>You can close this tab and return to microplanner.</p></body></html>',
        );
        if (!callback.isCompleted) {
          callback.complete(request.uri.queryParameters['code']);
        }
      }
      await request.response.close();
    });
    try {
      final start = await api.request(
        'POST',
        '/auth/windows/start',
        body: {
          'redirectUri': 'http://127.0.0.1:${listener.port}/oauth/callback',
          'codeChallenge': challenge,
          'state': state,
        },
      );
      if (_canceled) return null;
      final authorizationUrl = Uri.parse(start['authorizationUrl'] as String);
      if (authorizationUrl.scheme != 'https' ||
          authorizationUrl.host != 'accounts.google.com') {
        throw const ApiException(
          400,
          'google_url',
          'Invalid Google authorization address.',
        );
      }
      if (!await launchUrl(
        authorizationUrl,
        mode: LaunchMode.externalApplication,
      )) {
        throw const ApiException(
          0,
          'browser',
          'Could not open the browser. Please try again.',
        );
      }
      final code = await callback.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => null,
      );
      if (code == null || _canceled) return null;
      return await api.request(
        'POST',
        '/auth/windows/complete',
        body: {
          'challengeId': start['challengeId'],
          'code': code,
          'verifier': verifier,
        },
      );
    } finally {
      await listener.close(force: true);
      if (identical(_callback, callback)) _callback = null;
    }
  }

  @override
  void cancel() {
    _canceled = true;
    final callback = _callback;
    if (callback != null && !callback.isCompleted) callback.complete(null);
  }

  @override
  Future<void> signOut() async {
    cancel();
    if (Platform.isAndroid && _initialization != null) {
      await GoogleSignIn.instance.signOut();
    }
  }
}
