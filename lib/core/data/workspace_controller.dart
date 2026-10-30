import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../features/auth/data/auth_service.dart';
import 'api_client.dart';
import 'workspace_snapshot.dart';
import 'workspace_limits.dart';
import 'workspace_storage.dart';
import 'workspace_delta.dart';
import 'workspace_outbox.dart';

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
  WorkspaceOutbox? _outbox;
  DateTime? _cachedSeenAt;
  WorkspaceSnapshot? _legacyDraft;
  String? _legacySource;
  DateTime? get cachedSeenAt => _cachedSeenAt;
  WorkspaceOutbox? get outbox => _outbox;
  WorkspaceController({
    required this.auth,
    required this.api,
    required this.cache,
    required this.legacy,
  }) {
    auth.addListener(_authChanged);
    _authChanged();
  }
  WorkspaceSnapshot get snapshot {
    final queue = _outbox;
    if (queue == null || !queue.hasPending) return _snapshot;
    final existing = _snapshot.tasks.map((task) => task.id).toSet();
    final pendingNew = {
      for (final operation in queue.operations)
        if (operation.failure == null)
          for (final item in operation.delta.items)
            if (item.kind == 'tasks' &&
                item.before == null &&
                item.after != null)
              item.id,
    };
    if (pendingNew.isEmpty) return _snapshot;
    final additions = queue.projected.tasks.where(
      (task) => pendingNew.contains(task.id) && !existing.contains(task.id),
    );
    return _snapshot.copyWith(tasks: [..._snapshot.tasks, ...additions]);
  }

  bool get isLoading => _loading;
  bool get isSaving => _saving || (_online && (_outbox?.hasPending ?? false));
  bool get isOnline => _online;
  bool get hasData => _hasCache;
  bool get canImport => _canImport && canWrite && !_dismissingImport;
  bool get isDismissingImport => _dismissingImport;
  bool get hasLegacyData => _canImport;
  // Online actions stay available during synchronization; writes wait their turn.
  bool get canWrite =>
      _online && auth.sessionValid && _outbox?.storageError == null;
  String? get error => _error;
  String? get ownerId => _ownerId;
  Future<void> repairStorage() async {
    final queue = _outbox;
    if (queue == null) return;
    if (await queue.repairStorage() && identical(queue, _outbox)) {
      _error = null;
      notifyListeners();
    }
  }

  bool _current(int generation, String ownerId) =>
      generation == _generation && ownerId == _ownerId;

  void _authChanged() {
    final owner = auth.currentUser?.id;
    if (owner == _ownerId) return;
    ++_generation;
    _outbox?.removeListener(_outboxChanged);
    _outbox?.dispose();
    _outbox = null;
    _cachedSeenAt = null;
    _legacyDraft = null;
    _legacySource = null;
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
        if (cache is WorkspaceHistory) {
          try {
            _cachedSeenAt = await (cache as WorkspaceHistory).readSeenAt(owner);
          } catch (_) {
            _cachedSeenAt = null;
          }
          if (!_current(generation, owner)) return;
        }
        _snapshot = saved;
        _hasCache = true;
      }
      final available = await legacy.available(owner);
      if (!_current(generation, owner)) return;
      _canImport = available;
      if (available) {
        try {
          final source = await legacy.sourceId;
          final data = await legacy.read();
          if (!_current(generation, owner)) return;
          _legacySource = source;
          _legacyDraft = data;
        } catch (_) {
          // The import prompt can retry reading the original data on demand.
        }
      }
    } catch (_) {
      if (_current(generation, owner)) {
        _error =
            'The local copy could not be read. Reconnect to load your cloud data.';
      }
    }
    if (!_current(generation, owner)) return;
    final journal = cache;
    if (journal is WorkspaceJournal) {
      final queue = WorkspaceOutbox(
        owner: owner,
        journal: journal as WorkspaceJournal,
        initial: _snapshot,
        active: () => _current(generation, owner),
        readCloud: () async {
          final token = auth.token;
          if (!_current(generation, owner) || token == null) {
            throw const ApiException(
              401,
              'unauthorized',
              'Please sign in again.',
            );
          }
          return WorkspaceSnapshot.fromJson(
            await api.request('GET', '/workspace', token: token),
          );
        },
        send: (body, sourceId) async {
          final token = auth.token;
          if (!_current(generation, owner) || token == null) {
            throw const ApiException(
              401,
              'unauthorized',
              'Please sign in again.',
            );
          }
          return WorkspaceSnapshot.fromJson(
            await api.request(
              sourceId == null ? 'PUT' : 'POST',
              sourceId == null ? '/workspace' : '/workspace/import',
              token: token,
              body: body,
            ),
          );
        },
        onOffline: (message) {
          if (_current(generation, owner)) {
            _online = false;
            _error = message;
            notifyListeners();
          }
        },
        onConfirmed: (data, operation) async {
          if (!_current(generation, owner)) return;
          _snapshot = data;
          _online = true;
          _hasCache = true;
          _error = null;
          if (operation?.sourceId != null) {
            _canImport = false;
            try {
              await legacy.imported(owner);
            } catch (_) {
              /* The server receipt prevents duplicate import. */
            }
          }
          await _cache(owner, data, generation);
          if (_current(generation, owner)) notifyListeners();
        },
      );
      _outbox = queue;
      queue.addListener(_outboxChanged);
      await queue.restore();
    }
    if (!_current(generation, owner)) return;
    await refresh();
  }

  void markSeen() {
    final owner = _ownerId;
    final history = cache;
    if (owner == null ||
        !_hasCache ||
        _loading ||
        history is! WorkspaceHistory) {
      return;
    }
    unawaited(
      (history as WorkspaceHistory)
          .markSeenAt(owner, DateTime.now())
          .catchError((Object _) {}),
    );
  }

  void _outboxChanged() {
    final queue = _outbox;
    if (queue == null) return;
    if (queue.storageError != null) _error = queue.storageError;
    notifyListeners();
  }

  Future<void> refresh() async {
    final owner = _ownerId;
    if (owner == null || auth.token == null || _saving) return;
    final generation = _generation;
    // A refresh requested just as a save finishes must not be silently lost.
    // Wait for the serial writer before pausing it and reading the server.
    final queue = _outbox;
    while (_current(generation, owner) && (queue?.working ?? false)) {
      await queue!.idle;
    }
    if (!_current(generation, owner)) return;
    final token = auth.token;
    if (token == null) return;
    final refreshVersion = ++_refreshVersion;
    _refreshBarrier ??= Completer<void>();
    _loading = true;
    _outbox?.updateConfirmed(_snapshot, online: false);
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
        _outbox?.updateConfirmed(_snapshot, online: _online);
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

  Future<bool> mutate(WorkspaceSnapshot? Function(WorkspaceSnapshot) change) {
    final queue = _outbox;
    if (queue != null) {
      if (!canWrite) return Future.value(_rejectWrite());
      final before = queue.projected;
      final next = change(before.clone());
      if (next == null) {
        _error =
            'This item changed while syncing. Your latest data have been kept.';
        notifyListeners();
        return Future.value(false);
      }
      return queue.enqueue(WorkspaceDelta.between(before, next));
    }
    return _enqueue(() async {
      final next = change(_snapshot.clone());
      if (next == null) {
        _error =
            'This item changed while syncing. Your latest data have been kept.';
        notifyListeners();
        return false;
      }
      return _save(next);
    });
  }

  Future<bool> applyDelta(WorkspaceDelta delta) {
    final queue = _outbox;
    if (queue != null) {
      if (!canWrite) return Future.value(_rejectWrite());
      return queue.enqueue(delta);
    }
    return mutate((snapshot) => delta.apply(snapshot));
  }

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
      final source = _legacySource ?? await legacy.sourceId;
      final data = _legacyDraft ?? await legacy.read();
      if (!_current(generation, owner)) return false;
      final queue = _outbox;
      if (queue != null) return queue.enqueueImport(source, data);
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
    _outbox?.removeListener(_outboxChanged);
    _outbox?.dispose();
    auth.removeListener(_authChanged);
    super.dispose();
  }
}
