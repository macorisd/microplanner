import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import '../data/private_storage.dart';
import '../data/workspace_controller.dart';
import '../data/workspace_snapshot.dart';
import 'notification_preferences.dart';
import 'notification_adapter.dart';
import 'reminder_planner.dart';
import 'reminder_ledger.dart';
import 'background_sync.dart';

class NotificationTarget {
  final String owner, task, board;
  const NotificationTarget(this.owner, this.task, this.board);
}

class NotificationController extends ChangeNotifier
    with WidgetsBindingObserver {
  final WorkspaceController workspace;
  final PrivateStorage storage;
  final NotificationAdapter adapter;
  final BackgroundSyncBridge? background;
  Timer? _periodic;
  DateTime? lastBackgroundSync;
  String backgroundState = 'waiting';
  bool backgroundRegistered = false;
  DateTime? _lastSeenSync;
  String? backgroundError;
  String get backgroundStatusText =>
      backgroundError ??
      (!backgroundRegistered
          ? 'Background sync could not be scheduled. Reopen microplanner to retry.'
          : switch (backgroundState) {
              'expired' => 'Sign in again to keep reminders up to date.',
              'offline' =>
                'The last check could not connect. Existing reminders are kept; the system will try again.',
              'error' =>
                'The last check did not finish. The system will try again.',
              'permission' => 'Allow system notifications to update reminders.',
              _ => 'Automatic checks are enabled.',
            });
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
  Future<void> _tail = Future.value();
  Future<void>? _deviceWrite;
  final Set<String> _deletedOwners = {};
  bool _disposed = false;
  int _generation = 0;
  Timer? _debounce;
  NotificationController({
    required this.workspace,
    required this.storage,
    required this.adapter,
    this.background,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now {
    workspace.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    adapter.onActivated = readActivation;
    if (background != null) {
      background!.onSync = synchronizeInBackground;
      _periodic = Timer.periodic(const Duration(minutes: 30), (_) {
        unawaited(synchronizeInBackground());
      });
    }
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

  Future<void> refreshStatus({bool request = false}) async {
    try {
      final status = await adapter.status(request: request);
      permitted = status['enabled'] == true;
      precise = status['precise'] == true;
      if (background != null) {
        try {
          final state = await background!.status();
          backgroundRegistered = state['registered'] == true;
          final raw = _owner == null
              ? null
              : await storage.read('reminders-sync-status:$_owner');
          final saved = raw == null
              ? <String, dynamic>{}
              : jsonDecode(raw) as Map<String, dynamic>;
          lastBackgroundSync = DateTime.tryParse(
            saved['lastSuccess'] as String? ?? '',
          )?.toLocal();
          backgroundState = saved['state'] as String? ?? 'waiting';
          backgroundError = null;
        } catch (_) {
          backgroundError =
              'Background sync status is unavailable. Reopen microplanner to retry.';
        }
      }
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
      final write = storage.write(
        'reminders-device:$owner',
        jsonEncode(next.toJson()),
      );
      _deviceWrite = write;
      await write;
      if (owner != workspace.ownerId) return false;
      device = next;
      _generation++;
      error = null;
      await reconcile();
      return true;
    } catch (_) {
      error = 'Could not save notification settings. Try again.';
      return false;
    } finally {
      _deviceWrite = null;
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
        await (await ReminderLedger.load(
          storage,
          adapter,
          previousOwner,
        )).clear();
      }
      if (_disposed || nextOwner != workspace.ownerId) return;
      _owner = nextOwner;
      _loaded = true;
      target = null;
      device = const DeviceNotificationPreferences();
      lastBackgroundSync = null;
      backgroundState = 'waiting';
      if (nextOwner == null) {
        if (background != null) {
          await storage.delete('reminders-sync-context');
          await background!.configure(false);
        }
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
    if (background != null) {
      final enabled =
          device.enabled &&
          device.backgroundSync &&
          workspace.auth.sessionValid;
      await storage.write(
        'reminders-sync-context',
        jsonEncode({
          'owner': owner,
          'enabled': enabled,
          'paused':
              workspace.isLoading ||
              (workspace.outbox?.hasPending ?? false) ||
              workspace.outbox?.storageError != null,
          'revision': workspace.confirmedSnapshot.revision,
        }),
      );
      try {
        await background!.configure(enabled);
        backgroundRegistered = enabled;
        backgroundError = null;
      } catch (_) {
        backgroundError =
            'Background sync could not be scheduled. Reopen microplanner to retry.';
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
    if (workspace.isLoading) return;
    var reminderSnapshot = workspace.confirmedSnapshot;
    if (background != null) {
      final raw = await storage.read('reminders-cloud:$owner');
      if (raw != null) {
        final latest = WorkspaceSnapshot.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (latest.revision > reminderSnapshot.revision) {
          reminderSnapshot = latest;
        }
      }
    }
    outsideSession = planReminders(
      workspace: reminderSnapshot,
      owner: owner,
      now: clock,
      expires: DateTime(9999),
      device: device,
      suppressed: suppressed,
    ).where((event) => !event.at.isBefore(expires)).length;
    final ledger = await ReminderLedger.load(storage, adapter, owner);
    final coverage = await ledger.reconcile(
      snapshot: reminderSnapshot,
      device: device.copyWith(enabled: device.enabled && permitted),
      clock: clock,
      expires: expires,
      suppressed: suppressed,
      current: current,
    );
    if (coverage != null && current()) {
      eligible = coverage.eligible;
      scheduled = coverage.scheduled;
      coverageEnds = coverage.ends;
      final seen = workspace.cachedSeenAt;
      if (background != null &&
          workspace.isOnline &&
          seen != null &&
          seen != _lastSeenSync) {
        _lastSeenSync = seen;
        lastBackgroundSync = seen;
        backgroundState = 'updated';
        await storage.write(
          'reminders-sync-status:$owner',
          jsonEncode({
            'state': 'updated',
            'lastSuccess': seen.toUtc().toIso8601String(),
          }),
        );
      }
    }
    await readActivation();
  }

  Future<void> eraseAccount(String owner) async {
    _deletedOwners.add(owner);
    await _tail;
    await _deviceWrite?.catchError((Object _) {});
    await (await ReminderLedger.load(storage, adapter, owner)).clear();
    final context = await storage.read('reminders-sync-context');
    if (context != null && (jsonDecode(context) as Map)['owner'] == owner) {
      await storage.delete('reminders-sync-context');
      await background?.configure(false);
    }
    if (await storage.read('reminders-active-owner') == owner) {
      await storage.delete('reminders-active-owner');
    }
    if (target?.owner == owner) target = null;
    for (final category in ['ledger', 'device', 'cloud', 'sync-status']) {
      await storage.delete('reminders-$category:$owner');
    }
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
        if (_deletedOwners.contains(value['owner'])) return;
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

  bool _syncing = false;
  Future<void> synchronizeInBackground() async {
    if (_syncing ||
        _disposed ||
        !device.enabled ||
        !device.backgroundSync ||
        workspace.auth.isInitializing ||
        workspace.isLoading ||
        (workspace.outbox?.hasPending ?? false)) {
      return;
    }
    _syncing = true;
    try {
      await workspace.refresh(silent: true);
      await reconcile();
      if (_owner != null && workspace.isOnline) {
        await storage.write(
          'reminders-sync-status:$_owner',
          jsonEncode({
            'state': 'updated',
            'lastSuccess': now().toUtc().toIso8601String(),
          }),
        );
        await refreshStatus();
      }
    } finally {
      _syncing = false;
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
    _periodic?.cancel();
    background?.onSync = null;
    workspace.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    adapter.onActivated = null;
    super.dispose();
  }
}
