import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'api_client.dart';
import 'workspace_delta.dart';
import 'workspace_operation.dart';
import 'workspace_snapshot.dart';
import 'workspace_storage.dart';

/// Serializes durable intents for one account, while keeping uncertain requests
/// intact until a retry can establish whether the server committed them.
class WorkspaceOutbox extends ChangeNotifier {
  final String owner;
  final WorkspaceJournal journal;
  final Future<WorkspaceSnapshot> Function() readCloud;
  final Future<WorkspaceSnapshot> Function(
    Map<String, dynamic> body,
    String? sourceId,
  )
  send;
  final bool Function() active;
  final void Function(String message) onOffline;
  final Future<void> Function(
    WorkspaceSnapshot snapshot,
    WorkspaceOperation? operation,
  )
  onConfirmed;
  WorkspaceSnapshot _confirmed;
  final _operations = <WorkspaceOperation>[];
  final _results = <String, Completer<bool>>{};
  bool _alive = true;
  bool _working = false;
  Completer<void>? _idle;
  bool _online = false;
  String? storageError;
  bool _unreadable = false;
  Set<String>? _pendingTaskIds;
  WorkspaceSnapshot? _projected;

  void _invalidate() {
    _pendingTaskIds = null;
    _projected = null;
  }

  @override
  void notifyListeners() {
    _invalidate();
    super.notifyListeners();
  }

  void _storageFailed() {
    if (!_valid) return;
    storageError =
        'Pending actions could not be stored. Review them before closing the app.';
    for (final operation in _operations) {
      if (operation.request == null && operation.failure == null) {
        operation.failure = 'This action could not be stored on this device.';
        _finish(operation, false);
      }
    }
    notifyListeners();
  }

  void _persistInBackground() {
    unawaited(_persist().catchError((Object _) => _storageFailed()));
  }

  WorkspaceOutbox({
    required this.owner,
    required this.journal,
    required this.readCloud,
    required this.send,
    required this.active,
    required this.onOffline,
    required this.onConfirmed,
    required WorkspaceSnapshot initial,
  }) : _confirmed = initial;

  List<WorkspaceOperation> get operations => List.unmodifiable(_operations);
  bool get working => _working;
  Future<void> get idle => _idle?.future ?? Future<void>.value();
  bool get hasPending =>
      _operations.any((operation) => operation.failure == null);
  bool get hasFailures =>
      _operations.any((operation) => operation.failure != null);
  bool get waitingForConnection => hasPending && !_online;
  bool get _valid => _alive && active();

  Set<String> get pendingTaskIds => _pendingTaskIds ??= Set.unmodifiable({
    for (final operation in _operations)
      if (operation.failure == null)
        for (final item in operation.delta.items)
          if (item.kind == 'tasks') item.id,
  });

  WorkspaceSnapshot get projected {
    if (_projected != null) return _projected!;
    var value = _confirmed;
    for (final operation in _operations) {
      if (operation.failure == null) {
        value = operation.delta.apply(value) ?? value;
      }
    }
    return _projected = value;
  }

  Future<void> restore() async {
    try {
      final raw = await journal.readJournal(owner);
      if (!_valid || raw == null) return;
      final data = jsonDecode(raw);
      if (data is! Map ||
          data['version'] != 1 ||
          data['operations'] is! List ||
          (data['operations'] as List).length > 13300) {
        throw const FormatException('Invalid operation journal');
      }
      final restored = (data['operations'] as List)
          .map(
            (value) => WorkspaceOperation.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList();
      final ids = <String>{};
      for (final operation in restored) {
        final request = operation.request;
        if (operation.id.isEmpty ||
            operation.id.length > 150 ||
            !ids.add(operation.id) ||
            operation.conflicts < 0 ||
            (operation.sourceId == null) != (operation.importData == null) ||
            (operation.sourceId == null && operation.delta.items.isEmpty) ||
            (request != null &&
                (request['operationId'] != operation.id ||
                    request['revision'] is! int ||
                    request['data'] is! Map ||
                    request['sourceId'] != operation.sourceId))) {
          throw const FormatException('Invalid saved operation');
        }
      }
      if (!_valid) return;
      for (final operation in restored) {
        // A recorded request may have reached the server before process death.
        if (operation.request != null && operation.failure == null) {
          operation.uncertain = true;
        }
      }
      _operations.addAll(restored);
      notifyListeners();
    } catch (_) {
      if (_valid) {
        _unreadable = true;
        storageError =
            'Pending actions could not be read. Their local copy was kept.';
        notifyListeners();
      }
    }
  }

  Future<bool> repairStorage() async {
    if (!_valid) return false;
    if (storageError == null) return true;
    if (_unreadable) {
      storageError = null;
      _unreadable = false;
      await restore();
      if (!_valid || storageError != null) return false;
    } else {
      try {
        await _persist();
      } catch (_) {
        _storageFailed();
        return false;
      }
      if (!_valid) return false;
      storageError = null;
    }
    notifyListeners();
    if (_online) unawaited(_pump());
    return true;
  }

  void updateConfirmed(WorkspaceSnapshot snapshot, {required bool online}) {
    if (!_valid) return;
    _confirmed = snapshot;
    _invalidate();
    _online = online;
    notifyListeners();
    if (online) unawaited(_pump());
  }

  Future<bool> enqueue(WorkspaceDelta delta) {
    if (!_valid || storageError != null || delta.items.isEmpty) {
      return Future.value(false);
    }
    final taskIds = pendingTaskIds;
    if (delta.items.any(
      (item) => item.kind == 'tasks' && taskIds.contains(item.id),
    )) {
      return Future.value(false);
    }
    final operation = WorkspaceOperation(
      id: const Uuid().v4(),
      delta: delta,
      createdAt: DateTime.now(),
    );
    if (delta.apply(projected) == null) {
      operation.failure =
          'This item changed elsewhere. Review the saved draft.';
      _operations.add(operation);
      notifyListeners();
      _persistInBackground();
      return Future.value(false);
    }
    return _accept(operation);
  }

  Future<bool> enqueueImport(String sourceId, WorkspaceSnapshot data) {
    if (!_valid ||
        storageError != null ||
        _operations.any(
          (item) => item.sourceId == sourceId && item.failure == null,
        )) {
      return Future.value(false);
    }
    return _accept(
      WorkspaceOperation(
        id: const Uuid().v4(),
        delta: const WorkspaceDelta([]),
        createdAt: DateTime.now(),
        sourceId: sourceId,
        importData: data.data,
      ),
    );
  }

  Future<bool> _accept(WorkspaceOperation operation) {
    final result = Completer<bool>();
    _operations.add(operation);
    _results[operation.id] = result;
    notifyListeners();
    // Persist every acceptance, including those queued behind a slow request.
    _persistInBackground();
    unawaited(_pump());
    return result.future;
  }

  Future<bool> retry(String id) {
    final operation = _operations.where((item) => item.id == id).firstOrNull;
    if (!_valid ||
        operation == null ||
        operation.failure == null ||
        storageError != null ||
        operation.delta.items.any(
          (item) => item.kind == 'tasks' && pendingTaskIds.contains(item.id),
        )) {
      return Future.value(false);
    }
    operation.failure = null;
    operation.request = null;
    operation.uncertain = false;
    operation.conflicts = 0;
    final result = Completer<bool>();
    _results[id] = result;
    notifyListeners();
    _persistInBackground();
    unawaited(_pump());
    return result.future;
  }

  /// Replace a definitively failed intent only after the user reviews its draft.
  /// The journal persists the replacement before the writer can transmit it.
  Future<bool> replaceFailure(String id, WorkspaceDelta replacement) {
    final operation = _operations.where((item) => item.id == id).firstOrNull;
    if (!_valid ||
        storageError != null ||
        operation?.failure == null ||
        replacement.items.isEmpty ||
        replacement.apply(projected) == null ||
        replacement.items.any(
          (item) => item.kind == 'tasks' && pendingTaskIds.contains(item.id),
        )) {
      return Future.value(false);
    }
    operation!.delta = replacement;
    operation.failure = null;
    operation.request = null;
    operation.uncertain = false;
    operation.conflicts = 0;
    final result = Completer<bool>();
    _results[id] = result;
    notifyListeners();
    _persistInBackground();
    unawaited(_pump());
    return result.future;
  }

  Future<void> discardFailure(String id) async {
    final operation = _operations.where((item) => item.id == id).firstOrNull;
    if (!_valid || operation?.failure == null) return;
    final index = _operations.indexOf(operation!);
    _operations.removeAt(index);
    try {
      await _persist();
    } catch (_) {
      _operations.insert(index.clamp(0, _operations.length), operation);
      _storageFailed();
      return;
    }
    if (_valid) notifyListeners();
  }

  Future<void> _persist() => journal.writeJournal(
    owner,
    jsonEncode({
      'version': 1,
      'operations': _operations.map((operation) => operation.toJson()).toList(),
    }),
  );

  void _finish(WorkspaceOperation operation, bool value) {
    final result = _results.remove(operation.id);
    if (result != null && !result.isCompleted) result.complete(value);
  }

  Future<void> _pump() async {
    if (!_valid || _working || storageError != null) return;
    _working = true;
    final idle = _idle = Completer<void>();
    try {
      // Make accepted work durable even when the server is temporarily offline.
      await _persist();
      while (_valid && _online && storageError == null) {
        final operation = _operations
            .where((item) => item.failure == null)
            .firstOrNull;
        if (operation == null) break;
        if (operation.request == null) {
          final next = operation.sourceId == null
              ? operation.delta.apply(_confirmed)
              : _confirmed;
          if (next == null) {
            operation.failure =
                'This item changed elsewhere. Review the saved draft.';
            _finish(operation, false);
            await _persist();
            if (_valid) notifyListeners();
            continue;
          }
          operation.request = {
            'revision': _confirmed.revision,
            'operationId': operation.id,
            'data': operation.importData ?? next.data,
            if (operation.sourceId != null) 'sourceId': operation.sourceId,
          };
          await _persist(); // Record the exact payload before it can reach the server.
        }
        if (!_valid || storageError != null) break;
        try {
          final result = await send(operation.request!, operation.sourceId);
          if (!_valid) break;
          _confirmed = result;
          _invalidate();
          await onConfirmed(result, operation);
          if (!_valid) break;
          final index = _operations.indexOf(operation);
          _operations.removeAt(index);
          try {
            await _persist();
          } catch (_) {
            // The server committed, but the old on-disk receipt is still the
            // only durable record. Keep it in memory for safe reconciliation.
            _operations.insert(index.clamp(0, _operations.length), operation);
            operation.uncertain = true;
            _finish(operation, true);
            rethrow;
          }
          _finish(operation, true);
          if (_valid) notifyListeners();
        } on ApiException catch (error) {
          if (!_valid) break;
          if (error.code == 'revision_conflict' && !operation.uncertain) {
            try {
              _confirmed = await readCloud();
              _invalidate();
              if (!_valid) break;
              await onConfirmed(_confirmed, null);
              if (!_valid) break;
              operation.conflicts++;
              if (operation.sourceId == null &&
                  operation.delta.apply(_confirmed) == null) {
                operation.failure =
                    'This item changed elsewhere. Review the saved draft.';
                _finish(operation, false);
              } else if (operation.conflicts >= 3) {
                operation.failure =
                    'The workspace kept changing. Review the saved draft.';
                _finish(operation, false);
              } else {
                // A definitive 409 means this request did not commit.
                operation.request = null;
              }
              await _persist();
              if (_valid) notifyListeners();
              continue;
            } catch (_) {
              if (!_valid) break;
              _online = false;
              onOffline(
                'Could not refresh pending changes. Reconnect to continue.',
              );
            }
          } else if (error.isOffline || error.code == 'revision_conflict') {
            operation.uncertain = true;
            _online = false;
            onOffline(error.message);
          } else {
            operation.failure = error.message;
            _finish(operation, false);
          }
          await _persist();
          if (_valid) notifyListeners();
        } catch (_) {
          if (!_valid) break;
          operation.uncertain = true;
          _online = false;
          onOffline('The save could not be confirmed. Reconnect to continue.');
          await _persist();
          if (_valid) notifyListeners();
        }
      }
    } catch (_) {
      _storageFailed();
    } finally {
      _working = false;
      if (!idle.isCompleted) idle.complete();
      if (identical(_idle, idle)) _idle = null;
      if (_valid) notifyListeners();
    }
  }

  @override
  void dispose() {
    _alive = false;
    for (final result in _results.values) {
      if (!result.isCompleted) result.complete(false);
    }
    _results.clear();
    super.dispose();
  }
}
