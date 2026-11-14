import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:microplanner/core/data/api_client.dart';
import 'package:microplanner/core/data/workspace_snapshot.dart';
import 'package:microplanner/core/notifications/background_sync.dart';
import 'package:microplanner/core/notifications/notification_preferences.dart';
import 'package:microplanner/core/notifications/reminder_ledger.dart';
import 'notifications_test.dart' as reminders;
import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final clock = DateTime(2026, 11, 14, 10);
  final expires = clock.add(const Duration(days: 20));
  late MemoryPrivateStorage storage;
  late reminders.FakeNotifications adapter;
  late WorkspaceSnapshot cloud;
  var requests = 0, locks = 0, releases = 0;
  late Future<http.Response> Function(http.Request) handle;
  setUp(() {
    storage = MemoryPrivateStorage();
    adapter = reminders.FakeNotifications();
    cloud = snapshot('Private board', revision: 5).copyWith(
      tasks: [reminders.task('old', clock.add(const Duration(days: 7)))],
    );
    requests = locks = releases = 0;
    storage.values.addAll({
      'session': jsonEncode(session('A', expires: expires)),
      'reminders-sync-context': jsonEncode({
        'owner': 'A',
        'enabled': true,
        'paused': false,
        'revision': 5,
      }),
      'reminders-device:A': jsonEncode(
        const DeviceNotificationPreferences(enabled: true).toJson(),
      ),
    });
    handle = (request) async {
      requests++;
      expect(request.method, 'GET');
      expect(request.url.path, '/workspace');
      expect(request.headers['authorization'], 'Bearer token-A');
      return jsonResponse(cloud.toJson());
    };
  });
  BackgroundReminderSync runner({Future<bool> Function()? acquire}) =>
      BackgroundReminderSync(
        storage: storage,
        notifications: adapter,
        now: () => clock,
        api: ApiClient(
          'https://example.test',
          client: MockClient((r) => handle(r)),
        ),
        acquire:
            acquire ??
            () async {
              locks++;
              return true;
            },
        release: () async {
          releases++;
        },
      );
  Future<void> seed() async {
    final ledger = await ReminderLedger.load(storage, adapter, 'A');
    await ledger.reconcile(
      snapshot: cloud,
      device: const DeviceNotificationPreferences(enabled: true),
      clock: clock,
      expires: expires,
      current: () => true,
    );
    adapter.calls.clear();
  }

  test(
    'closed-app deletion cancels alarms and repeated sync does not duplicate',
    () async {
      await seed();
      expect(adapter.events, isNotEmpty);
      cloud = WorkspaceSnapshot.fromJson({
        ...cloud.toJson(),
        "revision": 6,
        "tasks": [],
      });
      expect(await runner().run(), 'updated');
      expect(adapter.events, isEmpty);
      expect(await runner().run(), 'updated');
      expect(adapter.calls, isEmpty);
      expect(requests, 2);
      expect(locks, 2);
      expect(releases, 2);
      expect(
        jsonDecode(storage.values['reminders-sync-status:A']!)['lastSuccess'],
        clock.toUtc().toIso8601String(),
      );
    },
  );
  test(
    'completion, deadline edits and new tasks use shared scheduler and preserve privacy',
    () async {
      await seed();
      final oldId = adapter.events.keys.single;
      storage.values['reminders-device:A'] = jsonEncode(
        const DeviceNotificationPreferences(
          enabled: true,
          showDetails: false,
        ).toJson(),
      );
      cloud = cloud.copyWith(
        tasks: [
          reminders.task(
            'old',
            clock.add(const Duration(days: 7)),
            completed: true,
          ),
          reminders.task('new', clock.add(const Duration(days: 3))),
        ],
      );
      expect(await runner().run(), 'updated');
      expect(adapter.events.containsKey(oldId), isFalse);
      expect(adapter.calls.single['title'], 'microplanner');
      expect(adapter.calls.single.containsKey('boardName'), isFalse);
      cloud = cloud.copyWith(
        tasks: [reminders.task('new', clock.add(const Duration(days: 4)))],
      );
      expect(await runner().run(), 'updated');
      expect(adapter.events.length, 1);
      expect(
        adapter.events.values.single['deadline'],
        clock.add(const Duration(days: 4)).millisecondsSinceEpoch,
      );
      final calls = adapter.calls.length;
      expect(await runner().run(), 'updated');
      expect(adapter.calls.length, calls);
    },
  );
  test(
    'offline preserves alarms and last success; revoked session cancels only its ledger',
    () async {
      await seed();
      storage.values['reminders-sync-status:A'] = jsonEncode({
        'lastSuccess': clock
            .subtract(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
      });
      handle = (_) async {
        throw http.ClientException('offline');
      };
      expect(await runner().run(), 'offline');
      expect(adapter.events, isNotEmpty);
      expect(
        jsonDecode(storage.values['reminders-sync-status:A']!)['lastSuccess'],
        clock.subtract(const Duration(days: 1)).toUtc().toIso8601String(),
      );
      handle = (_) async => jsonResponse({'code': 'unauthorized'}, 401);
      expect(await runner().run(), 'expired');
      expect(adapter.events, isEmpty);
      expect(storage.values['session'], isNotNull);
    },
  );
  test(
    'pending writes, disabled device, wrong account and expired session stop safely',
    () async {
      final context = storage.values['reminders-sync-context']!;
      storage.values['reminders-sync-context'] = jsonEncode({
        'owner': 'A',
        'enabled': true,
        'paused': true,
      });
      expect(await runner().run(), 'paused');
      expect(requests, 0);
      storage.values['reminders-sync-context'] = context;
      storage.values['reminders-pending:A'] = 'true';
      expect(await runner().run(), 'paused');
      expect(requests, 0);
      storage.values.remove('reminders-pending:A');
      storage.values['reminders-device:A'] = jsonEncode(
        const DeviceNotificationPreferences(
          enabled: true,
          backgroundSync: false,
        ).toJson(),
      );
      expect(await runner().run(), 'disabled');
      expect(requests, 0);
      storage.values['reminders-device:A'] = jsonEncode(
        const DeviceNotificationPreferences(enabled: true).toJson(),
      );
      storage.values['session'] = jsonEncode(session('B', expires: expires));
      expect(await runner().run(), 'disabled');
      expect(requests, 0);
      storage.values['session'] = jsonEncode(session('A', expires: clock));
      storage.values['reminders-pending:A'] = 'true';
      expect(await runner().run(), 'expired');
      expect(requests, 0);
    },
  );
  test(
    'foreground handoff and account change during network request prevent stale writes',
    () async {
      await seed();
      final gate = Completer<http.Response>();
      handle = (_) => gate.future;
      final pending = runner().run();
      await settleAsync();
      storage.values['session'] = jsonEncode(session('B', expires: expires));
      gate.complete(
        jsonResponse(
          WorkspaceSnapshot.fromJson({
            ...cloud.toJson(),
            "revision": 6,
            "tasks": [],
          }).toJson(),
        ),
      );
      expect(await pending, 'superseded');
      expect(adapter.events, isNotEmpty);
      expect(releases, 1);
      storage.values['session'] = jsonEncode(session('A', expires: expires));
      handle = (_) async => jsonResponse(
        WorkspaceSnapshot.fromJson({
          ...cloud.toJson(),
          "revision": 6,
          "tasks": [],
        }).toJson(),
      );
      expect(await runner(acquire: () async => false).run(), 'superseded');
      expect(adapter.events, isNotEmpty);
      expect(releases, 1);
    },
  );
  test(
    'stale cloud revision and missing permission never replace valid alarms',
    () async {
      await seed();
      cloud = WorkspaceSnapshot.fromJson({
        ...cloud.toJson(),
        "revision": 4,
        "tasks": [],
      });
      expect(await runner().run(), 'stale');
      expect(locks, 0);
      expect(adapter.events, isNotEmpty);
      cloud = WorkspaceSnapshot.fromJson({...cloud.toJson(), "revision": 6});
      adapter.enabled = false;
      expect(await runner().run(), 'permission');
      expect(adapter.events, isNotEmpty);
    },
  );
  test(
    'OS failure releases the lease and permits a later successful retry',
    () async {
      adapter.fail = true;
      expect(await runner().run(), 'error');
      expect(releases, 1);
      adapter.fail = false;
      expect(await runner().run(), 'updated');
      expect(adapter.events.length, 1);
      expect(releases, 2);
    },
  );
}
