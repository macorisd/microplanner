import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../constants/app_config.dart';
import '../data/account_deletion.dart';
import '../data/api_client.dart';
import '../data/private_storage.dart';
import '../data/workspace_snapshot.dart';
import 'notification_adapter.dart';
import 'notification_preferences.dart';
import 'reminder_ledger.dart';

/// No workspace cache, outbox, UI or Google sign-in is opened by a worker.
class BackgroundReminderSync {
  final PrivateStorage storage;
  final NotificationAdapter notifications;
  final ApiClient api;
  final Future<bool> Function() acquire;
  final Future<void> Function() release;
  final DateTime Function() now;
  BackgroundReminderSync({
    required this.storage,
    required this.notifications,
    required this.api,
    required this.acquire,
    required this.release,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  Future<String> run() async {
    final context = await storage.read('reminders-sync-context');
    final raw = await storage.read('session');
    if (context == null || raw == null) return 'disabled';
    final config = jsonDecode(context) as Map;
    final session = jsonDecode(raw) as Map;
    final owner = (session['user'] as Map)['id'] as String;
    if (await storage.read(accountDeletionJournal) != null) return 'paused';
    if (config['owner'] != owner || config['enabled'] != true) {
      return 'disabled';
    }
    // Expired sessions cannot keep waking a worker behind a paused journal.
    if (!DateTime.parse(session['expiresAt'] as String).isAfter(now())) {
      return 'expired';
    }
    if (config['paused'] == true) return 'paused';
    if (await storage.read('reminders-pending:$owner') == 'true') {
      return 'paused';
    }
    final deviceRaw = await storage.read('reminders-device:$owner');
    final device = DeviceNotificationPreferences.fromJson(
      deviceRaw == null ? {} : jsonDecode(deviceRaw) as Map<String, dynamic>,
    );
    if (!device.enabled || !device.backgroundSync) return 'disabled';
    final expires = DateTime.parse(session['expiresAt'] as String);
    var locked = false;
    Future<bool> unchanged() async =>
        await storage.read(accountDeletionJournal) == null &&
        await storage.read('reminders-sync-context') == context &&
        await storage.read('session') == raw &&
        await storage.read('reminders-pending:$owner') != 'true' &&
        await storage.read('reminders-device:$owner') == deviceRaw;
    Future<String> record(String state, {bool success = false}) async {
      final previous = await storage.read('reminders-sync-status:$owner');
      final status = previous == null
          ? <String, dynamic>{}
          : jsonDecode(previous) as Map<String, dynamic>;
      status['state'] = state;
      if (success) status['lastSuccess'] = now().toUtc().toIso8601String();
      await storage.write('reminders-sync-status:$owner', jsonEncode(status));
      return state;
    }

    try {
      if (!expires.isAfter(now())) throw const ApiException(401, 'expired', '');
      // Exactly one bounded read; no retries in a tight loop and no cloud writes.
      final response = await api.request(
        'GET',
        '/workspace',
        token: session['token'] as String,
      );
      final snapshot = WorkspaceSnapshot.fromJson(response);
      if (snapshot.revision < (config['revision'] as int? ?? 0)) return 'stale';
      locked = await acquire();
      if (!locked || !await unchanged()) return 'superseded';
      final status = await notifications.status();
      if (status['enabled'] != true) return await record('permission');
      final ledger = await ReminderLedger.load(storage, notifications, owner);
      await storage.write('reminders-cloud:$owner', jsonEncode(response));
      await ledger.reconcile(
        snapshot: snapshot,
        device: device,
        clock: now(),
        expires: expires,
        current: () => true,
      );
      return await record('updated', success: true);
    } on ApiException catch (error) {
      locked = locked || await acquire();
      if (!locked || !await unchanged()) return 'superseded';
      if (error.status == 401) {
        final key =
            session['accountStatusKey'] as String? ??
            (await readAccountStatusKeys(storage))[owner];
        if (key != null) {
          try {
            if (await accountWasDeleted(api, owner, key) && await unchanged()) {
              // The foreground process owns Hive and completes the device purge.
              await storage.write(
                accountDeletionJournal,
                AccountDeletion(owner).encode(),
              );
              await (await ReminderLedger.load(
                storage,
                notifications,
                owner,
              )).clear();
              return 'deleted';
            }
          } on ApiException {
            // Failure to verify deletion is an ordinary expired session.
          }
        }
        await (await ReminderLedger.load(
          storage,
          notifications,
          owner,
        )).clear();
        return await record('expired');
      }
      return await record(error.isOffline ? 'offline' : 'error');
    } catch (_) {
      if (!locked) locked = await acquire();
      if (!locked || !await unchanged()) return 'superseded';
      return await record('error');
    } finally {
      if (locked) await release();
    }
  }
}

class BackgroundSyncBridge {
  static const channel = MethodChannel('microplanner/backgroundSync');
  Future<void> Function()? onSync;
  String? _configuration;
  BackgroundSyncBridge() {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'sync') {
        await onSync?.call();
        return true;
      }
      throw MissingPluginException();
    });
  }
  Future<void> startForeground() => channel.invokeMethod('foregroundStart');
  Future<void> configure(bool enabled) async {
    final key = '$enabled';
    if (_configuration == key) return;
    await channel.invokeMethod('configure', enabled);
    _configuration = key;
  }

  Future<Map<String, dynamic>> status() async =>
      Map<String, dynamic>.from(await channel.invokeMapMethod('status') ?? {});
}

Future<void> runBackgroundReminderSync() async {
  const channel = BackgroundSyncBridge.channel;
  var state = 'error';
  try {
    state = await BackgroundReminderSync(
      storage: const SecurePrivateStorage(),
      notifications: NativeNotificationAdapter(),
      api: ApiClient(AppConfig.apiUrl),
      acquire: () async => await channel.invokeMethod<bool>('acquire') ?? false,
      release: () => channel.invokeMethod('release'),
    ).run();
  } finally {
    await channel.invokeMethod('complete', state);
  }
}
