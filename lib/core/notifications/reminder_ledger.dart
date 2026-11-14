import 'dart:convert';
import '../data/private_storage.dart';
import '../data/workspace_snapshot.dart';
import 'notification_adapter.dart';
import 'notification_preferences.dart';
import 'reminder_planner.dart';

class ReminderCoverage {
  final int eligible, scheduled;
  final DateTime? ends;
  const ReminderCoverage(this.eligible, this.scheduled, this.ends);
}

/// The foreground and short background runs share the same durable scheduler.
class ReminderLedger {
  final PrivateStorage storage;
  final NotificationAdapter adapter;
  final String owner;
  final Map<String, dynamic> ledger;
  final Set<String> issued;
  ReminderLedger._(
    this.storage,
    this.adapter,
    this.owner,
    this.ledger,
    this.issued,
  );
  static Future<ReminderLedger> load(
    PrivateStorage storage,
    NotificationAdapter adapter,
    String owner,
  ) async {
    final raw = await storage.read('reminders-ledger:$owner');
    final data = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    return ReminderLedger._(
      storage,
      adapter,
      owner,
      Map<String, dynamic>.from(data['events'] as Map? ?? {}),
      Set<String>.from(data['issued'] as List? ?? []),
    );
  }

  Future<void> save() => storage.write(
    'reminders-ledger:$owner',
    jsonEncode({'events': ledger, 'issued': issued.toList()}),
  );
  Future<void> clear() async {
    for (final event in ledger.values) {
      await adapter.cancel((event as Map)['id'] as int);
    }
    ledger.clear();
    issued.clear();
    await save();
  }

  Future<ReminderCoverage?> reconcile({
    required WorkspaceSnapshot snapshot,
    required DeviceNotificationPreferences device,
    required DateTime clock,
    required DateTime expires,
    required bool Function() current,
    Set<String> suppressed = const {},
  }) async {
    for (final item in ledger.entries) {
      if ((item.value as Map)['at'] as int <= clock.millisecondsSinceEpoch) {
        issued.add(item.key);
      }
    }
    final plan = planReminders(
      workspace: snapshot,
      owner: owner,
      now: clock,
      expires: expires,
      device: device,
      suppressed: suppressed,
    );
    final expected = {for (final event in plan) event.key: event};
    for (final key in ledger.keys.toList()) {
      if (!current()) return null;
      if (!expected.containsKey(key)) {
        await adapter.cancel((ledger[key] as Map)['id'] as int);
        ledger.remove(key);
      } else if (issued.contains(key) && !device.showDetails) {
        // Privacy changes also remove old detailed content already in the OS tray.
        await adapter.cancel((ledger[key] as Map)['id'] as int);
        ledger.remove(key);
      }
    }
    final remaining = plan.where((e) => !issued.contains(e.key)).toList();
    final eligible = remaining.length;
    final selected = remaining.take(200).toList();
    final selectedKeys = selected.map((e) => e.key).toSet();
    for (final key in ledger.keys.toList()) {
      if (!issued.contains(key) && !selectedKeys.contains(key)) {
        await adapter.cancel((ledger[key] as Map)['id'] as int);
        ledger.remove(key);
      }
    }
    final usedIds = {
      for (final value in ledger.values) (value as Map)['id'] as int,
    };
    final immediate = selected.where((e) => !e.at.isAfter(clock)).toList();
    for (final event in selected) {
      if (!current()) return null;
      final existing = ledger[event.key] as Map?;
      if (existing != null && existing['fingerprint'] == event.fingerprint) {
        continue;
      }
      if (issued.contains(event.key)) continue;
      var id = existing?['id'] as int? ?? event.proposedId;
      while (existing == null && usedIds.contains(id)) {
        id = (id + 1) & 0x7fffffff;
      }
      usedIds.add(id);
      // Reserve before calling the OS: an ambiguous crash must not cause a burst.
      ledger[event.key] = {
        'id': id,
        'at': event.at.millisecondsSinceEpoch,
        'fingerprint': event.fingerprint,
      };
      await save();
      if (!current()) return null;
      final native = event.native(id);
      if (immediate.length > 1) {
        issued.add(event.key);
        if (event != immediate.first) continue;
        native['title'] = 'microplanner';
        native['body'] = '${immediate.length} tasks have approaching deadlines';
        native.remove('boardName');
      }
      try {
        await adapter.schedule(native);
        if (!current()) {
          await adapter.cancel(id);
          return null;
        }
      } catch (_) {
        ledger.remove(event.key);
        issued.remove(event.key);
        await save();
        rethrow;
      }
    }
    await save();
    final scheduled = selected.where((e) => e.at.isAfter(clock)).length;
    final coverageEnds = selected.isEmpty ? null : selected.last.at;
    // Bound old deduplication data to currently existing task occurrences.
    final currentKeys = {
      for (final task in snapshot.tasks)
        for (final kind in ['advance', 'deadline'])
          '$owner:${task.id}:${task.deadline.toUtc().toIso8601String()}:$kind',
    };
    issued.removeWhere((key) => !currentKeys.contains(key));
    await save();
    return ReminderCoverage(eligible, scheduled, coverageEnds);
  }
}
