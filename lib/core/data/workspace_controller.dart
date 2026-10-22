import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../features/auth/data/auth_service.dart';
import 'api_client.dart';
import 'workspace_snapshot.dart';
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
  String? _error;
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
  bool get canImport => _canImport && canWrite;
  bool get canWrite => _online && !_loading && !_saving && auth.sessionValid;
  String? get error => _error;
  String? get ownerId => _ownerId;
  bool _current(int generation, String ownerId) =>
      generation == _generation && ownerId == _ownerId;

  void _authChanged() {
    final owner = auth.currentUser?.id;
    if (owner == _ownerId) return;
    ++_generation;
    _ownerId = owner;
    _snapshot = const WorkspaceSnapshot();
    _online = false;
    _hasCache = false;
    _canImport = false;
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
    WorkspaceSnapshot Function(WorkspaceSnapshot) change,
  ) async {
    if (!canWrite) {
      _error = _saving
          ? 'A save is already in progress.'
          : 'Connect to the server and refresh before editing.';
      notifyListeners();
      return false;
    }
    return _save(change(_snapshot.clone()));
  }

  Future<bool> _save(WorkspaceSnapshot data, {String? sourceId}) async {
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
          if (sourceId != null) 'sourceId': sourceId,
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
      if (!_current(generation, owner) || !canWrite) return false;
      return _save(data, sourceId: source);
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
    if (owner == null) return;
    await legacy.dismiss(owner);
    if (owner == _ownerId) {
      _canImport = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    ++_generation;
    auth.removeListener(_authChanged);
    super.dispose();
  }
}
