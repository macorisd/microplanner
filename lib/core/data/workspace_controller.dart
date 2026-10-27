import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../features/auth/data/auth_service.dart';
import 'api_client.dart';
import 'workspace_snapshot.dart';
import 'workspace_limits.dart';
import 'workspace_storage.dart';

class WorkspaceController extends ChangeNotifier {
  final AuthService auth;
  final ApiClient api;
  final WorkspaceCache cache;
  final LegacyWorkspace legacy;
  WorkspaceSnapshot _snapshot = const WorkspaceSnapshot();
  String? _ownerId;
  int _generation = 0;
  int _refreshVersion = 0;
  bool _loading = false;
  bool _saving = false;
  bool _online = false;
  bool _hasCache = false;
  bool _canImport = false;
  bool _dismissingImport = false;
  String? _error;
  Completer<void>? _refreshBarrier;
  Future<void> _mutationTail = Future<void>.value();
  WorkspaceController({
    required this.auth,
    required this.api,
    required this.cache,
    required this.legacy,
  }) {
    auth.addListener(_authChanged);
    _authChanged();
  }
  WorkspaceSnapshot get snapshot => _snapshot;
  bool get isLoading => _loading;
  bool get isSaving => _saving;
  bool get isOnline => _online;
  bool get hasData => _hasCache;
  bool get canImport => _canImport && canWrite && !_dismissingImport;
  bool get isDismissingImport => _dismissingImport;
  bool get hasLegacyData => _canImport;
  // Online actions stay available during synchronization; writes wait their turn.
  bool get canWrite => _online && auth.sessionValid;
  String? get error => _error;
  String? get ownerId => _ownerId;
  bool _current(int generation, String ownerId) =>
      generation == _generation && ownerId == _ownerId;

  void _authChanged() {
    final owner = auth.currentUser?.id;
    if (owner == _ownerId) return;
    ++_generation;
    _refreshBarrier?.complete();
    _refreshBarrier = null;
    _mutationTail = Future<void>.value();
    _ownerId = owner;
    _snapshot = const WorkspaceSnapshot();
    _online = false;
    _hasCache = false;
    _canImport = false;
    _dismissingImport = false;
    _saving = false;
    _loading = owner != null;
    _error = null;
    notifyListeners();
    if (owner != null) unawaited(_loadAccount(owner, _generation));
  }

  Future<void> _loadAccount(String owner, int generation) async {
    try {
      final saved = await cache.read(owner);
      if (!_current(generation, owner)) return;
      if (saved != null) {
        _snapshot = saved;
        _hasCache = true;
      }
      final available = await legacy.available(owner);
      if (!_current(generation, owner)) return;
      _canImport = available;
    } catch (_) {
      if (_current(generation, owner)) {
        _error =
            'The local copy could not be read. Reconnect to load your cloud data.';
      }
    }
    if (!_current(generation, owner)) return;
    await refresh();
  }

  Future<void> refresh() async {
    final owner = _ownerId;
    final token = auth.token;
    if (owner == null || token == null || _saving) return;
    final generation = _generation;
    final refreshVersion = ++_refreshVersion;
    _refreshBarrier ??= Completer<void>();
    _loading = true;
    notifyListeners();
    try {
      final response = await api.request('GET', '/workspace', token: token);
      if (!_current(generation, owner) || refreshVersion != _refreshVersion) {
        return;
      }
      _snapshot = WorkspaceSnapshot.fromJson(response);
      _online = true;
      _hasCache = true;
      _error = null;
      await _cache(owner, _snapshot, generation);
    } on ApiException catch (e) {
      if (!_current(generation, owner) || refreshVersion != _refreshVersion) {
        return;
      }
      _online = false;
      _error = e.message;
    } catch (_) {
      if (!_current(generation, owner) || refreshVersion != _refreshVersion) {
        return;
      }
      _online = false;
      _error = 'Could not load your data. Please retry.';
    } finally {
      if (_current(generation, owner) && refreshVersion == _refreshVersion) {
        _loading = false;
        _refreshBarrier?.complete();
        _refreshBarrier = null;
        notifyListeners();
      }
    }
  }

  Future<void> _cache(
    String owner,
    WorkspaceSnapshot data,
    int generation,
  ) async {
    try {
      await cache.write(owner, data);
    } catch (_) {
      if (_current(generation, owner)) {
        _error = 'Saved in the cloud. The offline copy could not be updated.';
      }
    }
  }

  Future<bool> mutate(
    WorkspaceSnapshot? Function(WorkspaceSnapshot) change,
  ) => _enqueue(() async {
    final next = change(_snapshot.clone());
    if (next == null) {
      _error =
          'This item changed while syncing. Your latest data have been kept.';
      notifyListeners();
      return false;
    }
    return _save(next);
  });

  bool _rejectWrite() {
    _error ??= 'Connect to the server and refresh before editing.';
    notifyListeners();
    return false;
  }

  Future<bool> _enqueue(Future<bool> Function() write) {
    final owner = _ownerId;
    final generation = _generation;
    if (owner == null || !canWrite) return Future.value(_rejectWrite());
    final result = _mutationTail.then((_) async {
      // A later refresh can supersede the one that was active at click time.
      while (_current(generation, owner) && _loading) {
        final barrier = _refreshBarrier;
        if (barrier == null) return false;
        await barrier.future;
      }
      if (!_current(generation, owner)) return false;
      if (!canWrite) return _rejectWrite();
      return write();
    });
    // Keep subsequent actions usable even if a caller's transformation throws.
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<bool> _save(WorkspaceSnapshot data, {String? sourceId}) async {
    final validationError = WorkspaceLimits.validate(data);
    if (validationError != null) {
      _error = validationError;
      notifyListeners();
      return false;
    }
    final owner = _ownerId!;
    final token = auth.token!;
    final generation = _generation;
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      final response = await api.request(
        sourceId == null ? 'PUT' : 'POST',
        sourceId == null ? '/workspace' : '/workspace/import',
        token: token,
        body: {
          'revision': _snapshot.revision,
          'operationId': const Uuid().v4(),
          'data': data.data,
          'sourceId': ?sourceId,
        },
      );
      if (!_current(generation, owner)) return false;
      _snapshot = WorkspaceSnapshot.fromJson(response);
      _online = true;
      _hasCache = true;
      if (sourceId != null) {
        _canImport = false;
        try {
          await legacy.imported(owner);
        } catch (_) {
          /* Server receipt prevents duplicate imports. */
        }
      }
      await _cache(owner, _snapshot, generation);
      return _current(generation, owner);
    } on ApiException catch (e) {
      if (!_current(generation, owner)) return false;
      _error = e.message;
      if (e.isOffline) _online = false;
      if (e.code == 'already_imported') _canImport = false;
      if (e.code == 'revision_conflict') {
        _saving = false;
        await refresh();
        if (_current(generation, owner)) _error = e.message;
      }
      return false;
    } catch (_) {
      if (_current(generation, owner)) {
        _online = false;
        _error =
            'The save could not be confirmed. Refresh before trying again.';
      }
      return false;
    } finally {
      if (_current(generation, owner)) {
        _saving = false;
        notifyListeners();
      }
    }
  }

  Future<bool> importLegacy() async {
    if (!canImport) return false;
    final generation = _generation;
    final owner = _ownerId!;
    try {
      final source = await legacy.sourceId;
      final data = await legacy.read();
      if (!_current(generation, owner)) return false;
      return _enqueue(() async {
        if (!canImport) return false;
        return _save(data, sourceId: source);
      });
    } catch (_) {
      if (_current(generation, owner)) {
        _error =
            'Could not read the old local data. The originals have been kept.';
        notifyListeners();
      }
      return false;
    }
  }

  Future<void> dismissImport() async {
    final owner = _ownerId;
    final generation = _generation;
    if (owner == null || _dismissingImport) return;
    _dismissingImport = true;
    notifyListeners();
    try {
      await legacy.dismiss(owner);
      if (_current(generation, owner)) _canImport = false;
    } catch (_) {
      if (_current(generation, owner)) {
        _error = 'Could not dismiss the import offer. Please try again.';
      }
    } finally {
      if (_current(generation, owner)) {
        _dismissingImport = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    _refreshBarrier?.complete();
    _refreshBarrier = null;
    auth.removeListener(_authChanged);
    super.dispose();
  }
}
