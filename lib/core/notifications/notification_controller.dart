import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import '../data/private_storage.dart';
import '../data/workspace_controller.dart';
import 'notification_preferences.dart';
import 'notification_adapter.dart';
import 'reminder_planner.dart';

class NotificationTarget {
  final String owner, task, board;
  const NotificationTarget(this.owner, this.task, this.board);
}

class NotificationController extends ChangeNotifier
    with WidgetsBindingObserver {
  final WorkspaceController workspace;
  final PrivateStorage storage;
  final NotificationAdapter adapter;
  final DateTime Function() now;
  DeviceNotificationPreferences device = const DeviceNotificationPreferences();
  String? error;
  bool permitted = false, precise = false, busy = false;
  int scheduled = 0, eligible = 0;
  int outsideSession = 0;
  DateTime? coverageEnds;
  NotificationTarget? target;
  String? _owner;
  bool _loaded = false;
  Map<String, dynamic> _ledger = {};
  final Set<String> _issued = {};
  Future<void> _tail = Future.value();
  bool _disposed = false;
  int _generation = 0;
  Timer? _debounce;
  NotificationController({
    required this.workspace,
    required this.storage,
    required this.adapter,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now {
    workspace.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    adapter.onActivated = readActivation;
    _changed();
  }
  void _changed() {
    if (_disposed) return;
    // Account replacement invalidates in-flight work immediately.
    _generation++;
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 80),
      () => unawaited(reconcile()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refreshStatus());
      _changed();
      unawaited(readActivation());
    }
  }

  Future<void> _saveLedger() async {
    if (_owner != null) {
      await storage.write(
        'reminders-ledger:$_owner',
        jsonEncode({'events': _ledger, 'issued': _issued.toList()}),
      );
    }
  }

  Future<void> refreshStatus({bool request = false}) async {
    try {
      final status = await adapter.status(request: request);
      permitted = status['enabled'] == true;
      precise = status['precise'] == true;
      error = null;
    } catch (_) {
      permitted = false;
      error = 'Notification setup failed. Try again.';
    }
    if (!_disposed) notifyListeners();
  }

  Future<bool> updateDevice(DeviceNotificationPreferences next) async {
    if (busy || _owner == null) return false;
    busy = true;
    notifyListeners();
    final owner = _owner;
    try {
      if (next.enabled && !device.enabled) await refreshStatus(request: true);
      if (owner != _owner || owner != workspace.ownerId) return false;
      await storage.write('reminders-device:$owner', jsonEncode(next.toJson()));
      device = next;
      _generation++;
      error = null;
      await reconcile();
      return true;
    } catch (_) {
      error = 'Could not save notification settings. Try again.';
      return false;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> updateDefaults(NotificationPreferences preferences) =>
      workspace.mutate((s) => s.copyWith(notificationPreferences: preferences));
  Future<void> reconcile() {
    final completer = Completer<void>();
    _tail = _tail.catchError((Object _) {}).then((_) async {
      try {
        await _reconcile();
      } catch (_) {
        error = 'Some reminders could not be updated. Try again.';
      } finally {
        if (!_disposed) notifyListeners();
        completer.complete();
      }
    });
    return completer.future;
  }

  Future<void> _reconcile() async {
    if (_disposed || workspace.auth.isInitializing) return;
    final nextOwner = workspace.ownerId;
    if (!_loaded || nextOwner != _owner) {
      // Durable active-owner pointer permits cleanup after a process died at logout.
      final previousOwner =
          _owner ?? await storage.read('reminders-active-owner');
      if (previousOwner != null && previousOwner != nextOwner) {
        final raw = await storage.read('reminders-ledger:$previousOwner');
        final old = raw == null
            ? <String, dynamic>{}
            : (jsonDecode(raw) as Map)['events'] as Map? ?? {};
        for (final event in old.values) {
          await adapter.cancel((event as Map)['id'] as int);
        }
      }
      if (_disposed || nextOwner != workspace.ownerId) return;
      _owner = nextOwner;
      _loaded = true;
      _ledger = {};
      _issued.clear();
      target = null;
      device = const DeviceNotificationPreferences();
      if (nextOwner == null) {
        await storage.delete('reminders-active-owner');
        scheduled = 0;
        return;
      }
      await storage.write('reminders-active-owner', nextOwner);
      final settings = await storage.read('reminders-device:$nextOwner');
      if (settings != null) {
        device = DeviceNotificationPreferences.fromJson(
          jsonDecode(settings) as Map<String, dynamic>,
        );
      }
      final ledger = await storage.read('reminders-ledger:$nextOwner');
      if (ledger != null) {
        final data = jsonDecode(ledger) as Map<String, dynamic>;
        _ledger = Map<String, dynamic>.from(data['events'] as Map);
        _issued.addAll((data['issued'] as List).cast<String>());
      }
    }
    if (_owner == null) return;
    final generation = _generation;
    final owner = _owner!;
    bool current() =>
        !_disposed &&
        _owner == owner &&
        workspace.ownerId == owner &&
        generation == _generation;
    await refreshStatus();
    if (!current()) return;
    final clock = now();
    for (final item in _ledger.entries) {
      if ((item.value as Map)['at'] as int <= clock.millisecondsSinceEpoch) {
        _issued.add(item.key);
      }
    }
    final suppressed = <String>{};
    for (final op in workspace.outbox?.operations ?? []) {
      if (op.failure != null) continue;
      for (final item in op.delta.items) {
        if (item.kind == 'tasks' &&
            (item.after == null ||
                item.before == null ||
                [
                  'deadline',
                  'isCompleted',
                  'reminderMinutes',
                  'boardId',
                ].any((k) => item.before![k] != item.after![k]))) {
          suppressed.add(item.id);
        }
        if (item.kind == 'boards' && item.after == null) {
          suppressed.addAll(
            workspace.confirmedSnapshot.tasks
                .where((t) => t.boardId == item.id)
                .map((t) => t.id),
          );
        }
      }
    }
    final expires = workspace.auth.sessionExpiresAt ?? clock;
    outsideSession = planReminders(
      workspace: workspace.confirmedSnapshot,
      owner: owner,
      now: clock,
      expires: DateTime(9999),
      device: device,
      suppressed: suppressed,
    ).where((event) => !event.at.isBefore(expires)).length;
    final plan = planReminders(
      workspace: workspace.confirmedSnapshot,
      owner: owner,
      now: clock,
      expires: expires,
      device: device.copyWith(enabled: device.enabled && permitted),
      suppressed: suppressed,
    );
    final expected = {for (final event in plan) event.key: event};
    for (final key in _ledger.keys.toList()) {
      if (!current()) return;
      if (!expected.containsKey(key)) {
        await adapter.cancel((_ledger[key] as Map)['id'] as int);
        _ledger.remove(key);
      } else if (_issued.contains(key) && !device.showDetails) {
        // Privacy changes also remove old detailed content already in the OS tray.
        await adapter.cancel((_ledger[key] as Map)['id'] as int);
        _ledger.remove(key);
      }
    }
    final remaining = plan.where((e) => !_issued.contains(e.key)).toList();
    eligible = remaining.length;
    final selected = remaining.take(200).toList();
    final selectedKeys = selected.map((e) => e.key).toSet();
    for (final key in _ledger.keys.toList()) {
      if (!_issued.contains(key) && !selectedKeys.contains(key)) {
        await adapter.cancel((_ledger[key] as Map)['id'] as int);
        _ledger.remove(key);
      }
    }
    final usedIds = {
      for (final value in _ledger.values) (value as Map)['id'] as int,
    };
    final immediate = selected.where((e) => !e.at.isAfter(clock)).toList();
    for (final event in selected) {
      if (!current()) return;
      final existing = _ledger[event.key] as Map?;
      if (existing != null && existing['fingerprint'] == event.fingerprint) {
        continue;
      }
      if (_issued.contains(event.key)) continue;
      var id = existing?['id'] as int? ?? event.proposedId;
      while (existing == null && usedIds.contains(id)) {
        id = (id + 1) & 0x7fffffff;
      }
      usedIds.add(id);
      // Reserve before calling the OS: an ambiguous crash must not cause a burst.
      _ledger[event.key] = {
        'id': id,
        'at': event.at.millisecondsSinceEpoch,
        'fingerprint': event.fingerprint,
      };
      await _saveLedger();
      if (!current()) return;
      final native = event.native(id);
      if (immediate.length > 1) {
        _issued.add(event.key);
        if (event != immediate.first) continue;
        native['title'] = 'microplanner';
        native['body'] = '${immediate.length} tasks have approaching deadlines';
      }
      try {
        await adapter.schedule(native);
        if (!current()) {
          await adapter.cancel(id);
          return;
        }
      } catch (_) {
        _ledger.remove(event.key);
        _issued.remove(event.key);
        await _saveLedger();
        rethrow;
      }
    }
    await _saveLedger();
    scheduled = selected.where((e) => e.at.isAfter(clock)).length;
    coverageEnds = selected.isEmpty ? null : selected.last.at;
    // Bound old deduplication data to currently existing task occurrences.
    final currentKeys = {
      for (final task in workspace.confirmedSnapshot.tasks)
        for (final kind in ['advance', 'deadline'])
          '$owner:${task.id}:${task.deadline.toUtc().toIso8601String()}:$kind',
    };
    _issued.removeWhere((key) => !currentKeys.contains(key));
    await _saveLedger();
    await readActivation();
  }

  Future<void> readActivation() async {
    if (workspace.auth.isInitializing || workspace.isLoading) return;
    try {
      final raw = await adapter.launch();
      if (raw == null || raw.isEmpty) return;
      final value = jsonDecode(raw) as Map;
      if (value['owner'] is String &&
          value['task'] is String &&
          value['board'] is String) {
        target = NotificationTarget(
          value['owner'] as String,
          value['task'] as String,
          value['board'] as String,
        );
        if (!_disposed) notifyListeners();
      }
    } catch (_) {
      /* An old or malformed OS payload cannot navigate. */
    }
  }

  void consumeTarget() {
    target = null;
  }

  void retryNavigation() {
    if (target != null && !_disposed) notifyListeners();
  }

  Future<void> test() async {
    try {
      await refreshStatus();
      if (!permitted) return;
      await adapter.schedule({
        'id': 2147483001,
        'at': now().millisecondsSinceEpoch,
        'deadline': now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
        'expires': now().add(const Duration(minutes: 5)).millisecondsSinceEpoch,
        'title': 'microplanner',
        'body': 'Your notifications are working.',
        'payload': '{}',
      });
    } catch (_) {
      error = 'The test notification could not be sent.';
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _debounce?.cancel();
    workspace.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    adapter.onActivated = null;
    super.dispose();
  }
}
