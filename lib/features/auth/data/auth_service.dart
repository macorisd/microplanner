import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/data/account_deletion.dart';
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
  final Future<void> Function(String owner)? purgeAccount;
  AppUser? _currentUser;
  String? _token;
  DateTime? _expiresAt;
  bool _isLoading = true;
  bool _isInitializing = true;
  bool _signingIn = false;
  bool _cancelRequested = false;
  String? _error;
  int _generation = 0;
  String? _accountStatusKey;
  bool _recoveringDeletion = false;
  bool _submittingDeletion = false;
  Future<void>? _checkingSession;
  AuthService({
    required this.api,
    required this.storage,
    GoogleAuthenticator? google,
    this.purgeAccount,
  }) : google = google ?? PlatformGoogleAuthenticator() {
    api.onUnauthorized = (token) {
      if (token == _token && !_submittingDeletion && !_recoveringDeletion) {
        unawaited(_checkInvalidSession(token));
      }
    };
  }
  AppUser? get currentUser => _currentUser;
  String? get token => _token;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  bool get canCancelSignIn => _signingIn && !_cancelRequested;
  String? get error => _error;
  bool get recoveringDeletion => _recoveringDeletion;
  bool get submittingDeletion => _submittingDeletion;
  bool get canVerifyDeletion =>
      _accountStatusKey != null &&
      purgeAccount != null &&
      google is AccountDeletionAuthenticator;
  bool get sessionValid => _expiresAt?.isAfter(DateTime.now()) ?? false;
  DateTime? get sessionExpiresAt => _expiresAt;

  Future<void> initialize() async {
    try {
      final pending = AccountDeletion.decode(
        await storage.read(accountDeletionJournal),
      );
      if (pending != null) {
        _recoveringDeletion = true;
        if (!await _finishDeletion(pending)) return;
      }
      await _flushRevocations();
      final value = await storage.read('session');
      if (value != null) {
        final session = jsonDecode(value) as Map<String, dynamic>;
        final expiresAt = DateTime.parse(session['expiresAt'] as String);
        final user = AppUser.fromJson(session['user'] as Map<String, dynamic>);
        _accountStatusKey =
            session['accountStatusKey'] as String? ??
            (await readAccountStatusKeys(storage))[user.id];
        if (expiresAt.isAfter(DateTime.now())) {
          _token = session['token'] as String;
          _expiresAt = expiresAt;
          _currentUser = user;
          try {
            final verified = await api.request(
              'GET',
              '/auth/me',
              token: _token,
              invalidateSession: false,
            );
            if (_token != null) {
              _currentUser = AppUser.fromJson(
                verified['user'] as Map<String, dynamic>,
              );
              await _saveAccountStatusKey(
                user.id,
                verified['accountStatusKey'] as String?,
              );
            }
          } on ApiException catch (e) {
            if (e.status == 401) {
              await _checkInvalidSession(_token!);
            } else if (!e.isOffline) {
              rethrow;
            }
          }
        } else {
          if (!await _checkRemoteDeletion(user.id)) {
            await storage.delete('session');
          }
        }
      }
      if (!_recoveringDeletion) await _checkStoredAccounts();
    } catch (_) {
      _currentUser = null;
      _token = null;
      _expiresAt = null;
      if (!_recoveringDeletion) {
        _error = 'Could not restore your session. Please sign in again.';
        try {
          await storage.delete('session');
        } catch (_) {
          /* Keep access closed. */
        }
      }
    } finally {
      _isInitializing = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> signInWithGoogle() async {
    if (_isLoading || _recoveringDeletion || _submittingDeletion) return false;
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
        final signedIn = AppUser.fromJson(
          session['user'] as Map<String, dynamic>,
        );
        await _checkStoredAccounts(except: signedIn.id);
        if (_recoveringDeletion) {
          await _revokeLater(session['token'] as String);
          return false;
        }
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
      await _saveAccountStatusKey(
        _currentUser!.id,
        session['accountStatusKey'] as String?,
      );
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
    _accountStatusKey = null;
    _error = 'Your session expired. Please sign in again.';
    _isLoading = false;
    _signingIn = false;
    notifyListeners();
    storage.delete('session').catchError((_) {});
  }

  Future<void> _saveAccountStatusKey(String owner, String? key) async {
    if (key == null) return;
    _accountStatusKey = key;
    try {
      final keys = await readAccountStatusKeys(storage);
      keys[owner] = key;
      await writeAccountStatusKeys(storage, keys);
    } catch (_) {
      // The established session remains usable if this optional migration fails.
    }
  }

  Future<void> _checkStoredAccounts({String? except}) async {
    if (purgeAccount == null) return;
    final keys = await readAccountStatusKeys(storage);
    for (final entry in keys.entries) {
      if (entry.key == (except ?? _currentUser?.id)) continue;
      try {
        if (!await accountWasDeleted(api, entry.key, entry.value)) continue;
      } on ApiException catch (error) {
        if (error.isOffline) return;
        continue;
      }
      final pending = AccountDeletion(entry.key);
      await storage.write(accountDeletionJournal, pending.encode());
      if (!await _finishDeletion(pending)) return;
    }
  }

  Future<void> refreshDeletionAvailability() async {
    final owner = _currentUser?.id;
    final token = _token;
    if (owner == null || token == null || canVerifyDeletion) return;
    try {
      final session = await api.request('GET', '/auth/me', token: token);
      if (_token != token) return;
      await _saveAccountStatusKey(
        owner,
        session['accountStatusKey'] as String?,
      );
      if (_token == token && canVerifyDeletion) notifyListeners();
    } on ApiException {
      // The dialog reports unavailability until it can reach the compatible API.
    }
  }

  Future<void> _checkInvalidSession(String token) =>
      _checkingSession ??= _verifyInvalidSession(token).whenComplete(() {
        _checkingSession = null;
      });

  Future<void> _verifyInvalidSession(String token) async {
    final owner = _currentUser?.id;
    try {
      if (owner != null && await _checkRemoteDeletion(owner)) return;
      if (token == _token) _invalidate();
    } catch (_) {
      // Keep a session whose deletion was verified available for cleanup retry.
      _recoveringDeletion = true;
      _error = 'Could not save the account cleanup state. Try again.';
      notifyListeners();
    }
  }

  Future<bool> _checkRemoteDeletion(String owner) async {
    final key = _accountStatusKey;
    if (key == null || purgeAccount == null) return false;
    final generation = _generation;
    bool deleted;
    try {
      deleted = await accountWasDeleted(api, owner, key);
    } on ApiException {
      return false;
    }
    if (!deleted ||
        generation != _generation ||
        _submittingDeletion ||
        _recoveringDeletion) {
      return false;
    }
    _recoveringDeletion = true;
    final pending = AccountDeletion(owner);
    await storage.write(accountDeletionJournal, pending.encode());
    await _finishDeletion(pending);
    notifyListeners();
    return true;
  }

  Future<String?> verifyDeletion(String owner) async {
    final verifier = google;
    final token = _token;
    if (!canVerifyDeletion ||
        owner != _currentUser?.id ||
        token == null ||
        verifier is! AccountDeletionAuthenticator) {
      return null;
    }
    final result = await (verifier as AccountDeletionAuthenticator)
        .verifyDeletion(api, token);
    if (token != _token) return null;
    return result?['grant'] as String?;
  }

  Future<bool> deleteAccount(String owner, String grant) async {
    final key = _accountStatusKey;
    if (owner != _currentUser?.id ||
        key == null ||
        purgeAccount == null ||
        _checkingSession != null ||
        _submittingDeletion ||
        _recoveringDeletion) {
      return false;
    }
    _submittingDeletion = true;
    notifyListeners();
    try {
      final pending = AccountDeletion(owner, key: key, grant: grant);
      // Save the exact confirmed operation before its first network request.
      await storage.write(accountDeletionJournal, pending.encode());
      await _finishDeletion(pending);
      return _currentUser == null;
    } finally {
      _submittingDeletion = false;
      notifyListeners();
    }
  }

  Future<void> retryDeletion() async {
    if (_isLoading || !_recoveringDeletion) return;
    _isLoading = true;
    notifyListeners();
    try {
      final pending = AccountDeletion.decode(
        await storage.read(accountDeletionJournal),
      );
      if (pending != null && await _finishDeletion(pending)) {
        // Recovery can leave another account's saved session available.
        if (_currentUser == null && await storage.read('session') != null) {
          await initialize();
        }
      } else if (pending == null) {
        _recoveringDeletion = false;
        if (_token != null) await _checkInvalidSession(_token!);
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> _finishDeletion(AccountDeletion pending) async {
    try {
      if (!pending.confirmed) {
        final owner = pending.owner;
        final key = pending.key!;
        final raw = await storage.read('session');
        final session = raw == null ? null : jsonDecode(raw) as Map;
        final sessionUser = session?['user'] as Map?;
        final token = sessionUser?['id'] == owner
            ? (session?['token'] as String?)
            : null;
        if (!await accountWasDeleted(api, owner, key)) {
          try {
            if (token == null) {
              throw const ApiException(
                401,
                'unauthorized',
                'Please sign in again.',
              );
            }
            final result = await api.request(
              'POST',
              '/account/deletion/commit',
              token: token,
              body: {'grant': pending.grant},
              invalidateSession: false,
            );
            if (result['status'] != 'deleted') {
              throw const ApiException(
                503,
                'invalid_response',
                'Invalid deletion result.',
              );
            }
          } on ApiException catch (error) {
            if (!await accountWasDeleted(api, owner, key)) {
              if (!{
                'unauthorized',
                'deletion_not_authorized',
              }.contains(error.code)) {
                rethrow;
              }
              await storage.delete(accountDeletionJournal);
              _recoveringDeletion = false;
              if (error.code == 'unauthorized' && token == _token) {
                _invalidate();
              }
              _error = error.message;
              return true;
            }
          }
        }
        // From now on recovery needs neither a cloud request nor old credentials.
        await storage.write(
          accountDeletionJournal,
          AccountDeletion(owner).encode(),
        );
      }
      final cleanup = purgeAccount;
      if (cleanup == null) {
        throw StateError('Local account cleanup is unavailable.');
      }
      _recoveringDeletion = true;
      final raw = await storage.read('session');
      final session = raw == null ? null : jsonDecode(raw) as Map;
      if ((session?['user'] as Map?)?['id'] == pending.owner) {
        await storage.delete('session');
      }
      if (_currentUser?.id == pending.owner) {
        ++_generation;
        _token = null;
        _currentUser = null;
        _expiresAt = null;
        _accountStatusKey = null;
        notifyListeners();
        // Google state is device-local and clearing it must not prevent cleanup.
        await google.signOut().catchError((Object _) {});
      }
      await cleanup(pending.owner);
      final keys = await readAccountStatusKeys(storage);
      keys.remove(pending.owner);
      await writeAccountStatusKeys(storage, keys);
      await storage.delete(accountDeletionJournal);
      _recoveringDeletion = false;
      _error = null;
      return true;
    } catch (_) {
      _recoveringDeletion = true;
      _error = 'Account deletion could not be verified or finished. Try again.';
      return false;
    }
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
  Future<void> signOut() {
    if (_submittingDeletion || _recoveringDeletion) return Future.value();
    return _signOutFuture ??= _performSignOut().whenComplete(() {
      _signOutFuture = null;
    });
  }

  Future<void> _performSignOut() async {
    final oldToken = _token;
    ++_generation;
    _token = null;
    _currentUser = null;
    _expiresAt = null;
    _accountStatusKey = null;
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
