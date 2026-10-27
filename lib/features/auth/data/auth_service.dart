import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/data/api_client.dart';
import '../../../core/data/private_storage.dart';
import 'google_authenticator.dart';

class AppUser {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
  });
  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    email: json['email'] as String,
    displayName: json['displayName'] as String,
    photoUrl: json['photoUrl'] as String?,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'displayName': displayName,
    'photoUrl': photoUrl,
  };
}

class AuthService extends ChangeNotifier {
  final ApiClient api;
  final PrivateStorage storage;
  final GoogleAuthenticator google;
  AppUser? _currentUser;
  String? _token;
  DateTime? _expiresAt;
  bool _isLoading = true;
  bool _signingIn = false;
  bool _cancelRequested = false;
  String? _error;
  int _generation = 0;
  AuthService({
    required this.api,
    required this.storage,
    GoogleAuthenticator? google,
  }) : google = google ?? PlatformGoogleAuthenticator() {
    api.onUnauthorized = (token) {
      if (token == _token) _invalidate();
    };
  }
  AppUser? get currentUser => _currentUser;
  String? get token => _token;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  bool get canCancelSignIn => _signingIn && !_cancelRequested;
  String? get error => _error;
  bool get sessionValid => _expiresAt?.isAfter(DateTime.now()) ?? false;

  Future<void> initialize() async {
    try {
      await _flushRevocations();
      final value = await storage.read('session');
      if (value != null) {
        final session = jsonDecode(value) as Map<String, dynamic>;
        final expiresAt = DateTime.parse(session['expiresAt'] as String);
        if (expiresAt.isAfter(DateTime.now())) {
          _token = session['token'] as String;
          _expiresAt = expiresAt;
          _currentUser = AppUser.fromJson(
            session['user'] as Map<String, dynamic>,
          );
          try {
            final verified = await api.request(
              'GET',
              '/auth/me',
              token: _token,
            );
            if (_token != null) {
              _currentUser = AppUser.fromJson(
                verified['user'] as Map<String, dynamic>,
              );
            }
          } on ApiException catch (e) {
            if (!e.isOffline) rethrow;
          }
        } else {
          await storage.delete('session');
        }
      }
    } catch (_) {
      _currentUser = null;
      _token = null;
      _expiresAt = null;
      _error = 'Could not restore your session. Please sign in again.';
      try {
        await storage.delete('session');
      } catch (_) {
        /* Keep access closed. */
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> signInWithGoogle() async {
    if (_isLoading) return false;
    _isLoading = true;
    _signingIn = true;
    _cancelRequested = false;
    _error = null;
    final generation = ++_generation;
    notifyListeners();
    try {
      await _flushRevocations();
      final session = await google.signIn(api);
      if (session == null) return false;
      if (generation != _generation || _cancelRequested) {
        await _revokeLater(session['token'] as String);
        return false;
      }
      try {
        await storage.write('session', jsonEncode(session));
      } catch (_) {
        await _revokeLater(session['token'] as String);
        rethrow;
      }
      if (generation != _generation || _cancelRequested) {
        await storage.delete('session');
        await _revokeLater(session['token'] as String);
        return false;
      }
      _token = session['token'] as String;
      _expiresAt = DateTime.parse(session['expiresAt'] as String);
      _currentUser = AppUser.fromJson(session['user'] as Map<String, dynamic>);
      return true;
    } on ApiException catch (e) {
      if (generation == _generation) _error = e.message;
      return false;
    } catch (_) {
      if (generation == _generation) {
        _error =
            'Could not sign in or store the session securely. Please try again.';
      }
      return false;
    } finally {
      if (generation == _generation) {
        _isLoading = false;
        _signingIn = false;
        notifyListeners();
      }
    }
  }

  void cancelSignIn() {
    if (!_signingIn || _cancelRequested) return;
    _cancelRequested = true;
    google.cancel();
    notifyListeners();
  }

  void _invalidate() {
    ++_generation;
    _token = null;
    _currentUser = null;
    _expiresAt = null;
    _error = 'Your session expired. Please sign in again.';
    _isLoading = false;
    _signingIn = false;
    notifyListeners();
    storage.delete('session').catchError((_) {});
  }

  Future<void> _revokeLater(String token) async {
    final pending =
        (jsonDecode(await storage.read('revocations') ?? '[]') as List)
            .cast<String>();
    if (!pending.contains(token)) pending.add(token);
    await storage.write('revocations', jsonEncode(pending));
    await _flushRevocations();
  }

  Future<void> _flushRevocations() async {
    final pending =
        (jsonDecode(await storage.read('revocations') ?? '[]') as List)
            .cast<String>();
    final remaining = <String>[];
    for (final token in pending) {
      try {
        await api.request('POST', '/auth/logout', token: token);
      } catch (_) {
        remaining.add(token);
      }
    }
    await storage.write('revocations', jsonEncode(remaining));
  }

  Future<void>? _signOutFuture;
  Future<void> signOut() =>
      _signOutFuture ??= _performSignOut().whenComplete(() {
        _signOutFuture = null;
      });

  Future<void> _performSignOut() async {
    final oldToken = _token;
    ++_generation;
    _token = null;
    _currentUser = null;
    _expiresAt = null;
    _error = null;
    _isLoading = true;
    _signingIn = false;
    google.cancel();
    notifyListeners();
    try {
      await storage.delete('session');
      if (oldToken != null) await _revokeLater(oldToken);
      await google.signOut();
    } catch (_) {
      _error =
          'Signed out here. Server sign-out will be retried when the connection returns.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
