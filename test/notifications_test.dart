import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:microplanner/core/constants/app_constants.dart';
import 'package:microplanner/core/data/workspace_delta.dart';
import 'package:microplanner/core/data/workspace_snapshot.dart';
import 'package:microplanner/core/data/workspace_storage.dart';
import 'package:microplanner/core/notifications/notification_adapter.dart';
import 'package:microplanner/core/notifications/notification_controller.dart';
import 'package:microplanner/core/notifications/notification_preferences.dart';
import 'package:microplanner/core/notifications/reminder_planner.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'support/fakes.dart';

class _Journal extends MemoryCache implements WorkspaceJournal {
  final entries = <String, String>{};
  @override
  Future<String?> readJournal(String owner) async => entries[owner];
  @override
  Future<void> writeJournal(String owner, String value) async {
    entries[owner] = value;
  }
}

class FakeNotifications implements NotificationAdapter {
  final events = <int, Map<String, dynamic>>{};
  final calls = <Map<String, dynamic>>[];
  bool enabled = true, fail = false;
  String? activation;
  @override
  void Function()? onActivated;
  @override
  Future<Map<String, dynamic>> status({bool request = false}) async => {
    'enabled': enabled,
    'precise': true,
  };
  @override
  Future<void> schedule(Map<String, dynamic> event) async {
    if (fail) throw StateError('failed');
    calls.add(event);
    events[event['id'] as int] = event;
  }

  @override
  Future<void> cancel(int id) async {
    events.remove(id);
  }

  @override
  Future<List<String>> pending() async =>
      events.keys.map((id) => '$id').toList();
  @override
  Future<String?> launch() async {
    final value = activation;
    activation = null;
    return value;
  }

  @override
  Future<void> settings({bool exact = false}) async {}
}

Task task(
  String id,
  DateTime deadline, {
  int? advance,
  bool completed = false,
}) => Task(
  id: id,
  name: 'Private $id',
  deadline: deadline,
  createdAt: deadline.subtract(const Duration(days: 1)),
  typeIndex: TaskType.unassigned.index,
  priorityIndex: 0,
  subject: '',
  boardId: 'default-board',
  reminderMinutes: advance,
  isCompleted: completed,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final clock = DateTime(2026, 11, 13, 12);
  WorkspaceSnapshot tasks(
    List<Task> values, {
    NotificationPreferences? preferences,
  }) => snapshot(
    'Private board',
  ).copyWith(tasks: values, notificationPreferences: preferences);
  List<ReminderEvent> plan(
    WorkspaceSnapshot data, {
    DateTime? at,
    DeviceNotificationPreferences device = const DeviceNotificationPreferences(
      enabled: true,
    ),
    Set<String> suppressed = const {},
  }) => planReminders(
    workspace: data,
    owner: 'A',
    now: at ?? clock,
    expires: clock.add(const Duration(days: 30)),
    device: device,
    suppressed: suppressed,
  );

  test(
    'default, overrides, disabled and completed tasks are planned across boards',
    () {
      final values = tasks([
        task('default', clock.add(const Duration(days: 2))),
        task('custom', clock.add(const Duration(hours: 3)), advance: 60),
        task('off', clock.add(const Duration(hours: 1)), advance: 0),
        task('complete', clock.add(const Duration(hours: 1)), completed: true),
        task('late', clock.subtract(const Duration(seconds: 1))),
      ]);
      final events = plan(values);
      expect(events.map((e) => e.taskId), ['custom', 'default']);
      expect(events.first.at, clock.add(const Duration(hours: 2)));
      expect(events.last.at, clock.add(const Duration(days: 1)));
      expect(plan(values, suppressed: {'custom'}).map((e) => e.taskId), [
        'default',
      ]);
    },
  );
  test(
    'deadline event is optional and changing defaults preserves overrides',
    () {
      final data = tasks(
        [
          task('inherit', clock.add(const Duration(hours: 5))),
          task('override', clock.add(const Duration(hours: 5)), advance: 15),
        ],
        preferences: const NotificationPreferences(
          advanceMinutes: 60,
          atDeadline: true,
        ),
      );
      final events = plan(data);
      expect(events.length, 4);
      expect(events.where((e) => e.atDeadline).length, 2);
      expect(events.first.at, clock.add(const Duration(hours: 4)));
      expect(events[1].at, clock.add(const Duration(hours: 4, minutes: 45)));
    },
  );
  test(
    'quiet hours crossing midnight delay advance, skip deadline and avoid overdue delivery',
    () {
      const quiet = DeviceNotificationPreferences(
        enabled: true,
        quietHours: true,
      );
      final now = DateTime(2026, 11, 13, 23);
      final before = tasks([
        task('early', DateTime(2026, 11, 14, 7), advance: 60),
        task('later', DateTime(2026, 11, 14, 10), advance: 600),
      ], preferences: const NotificationPreferences(atDeadline: true));
      final events = plan(before, at: now, device: quiet);
      expect(events.where((e) => e.taskId == 'early'), isEmpty);
      expect(events.first.taskId, 'later');
      expect(events.first.at, DateTime(2026, 11, 14, 8));
      expect(events.last.at, DateTime(2026, 11, 14, 10));
    },
  );
  test(
    'privacy hides title/board and immediate occurrence identity survives clock movement',
    () {
      final data = tasks([task('secret', clock.add(const Duration(hours: 1)))]);
      final first = plan(
        data,
        device: const DeviceNotificationPreferences(
          enabled: true,
          showDetails: false,
        ),
      ).single;
      final second = plan(
        data,
        at: clock.add(const Duration(minutes: 1)),
      ).single;
      expect(first.title, 'microplanner');
      expect(first.body, isNot(contains('Private')));
      expect(first.key, second.key);
      expect(first.proposedId, second.proposedId);
      expect(first.payload, isNot(contains('Private')));
    },
  );
  test(
    'preference delta rebases without erasing independent cloud task changes',
    () {
      final before = tasks([task('one', clock.add(const Duration(days: 2)))]);
      final delta = WorkspaceDelta.between(
        before,
        before.copyWith(
          notificationPreferences: const NotificationPreferences(
            advanceMinutes: 15,
          ),
        ),
      );
      final remote = before.copyWith(
        tasks: [
          before.tasks.single.copyWith(
            name: 'Remote name',
            reminderMinutes: 180,
          ),
        ],
      );
      final after = delta.apply(remote)!;
      expect(after.notificationPreferences!.advanceMinutes, 15);
      expect(after.tasks.single.name, 'Remote name');
      expect(after.tasks.single.reminderMinutes, 180);
      expect(
        WorkspaceDelta.fromJson(delta.toJson()).apply(remote)!.data,
        after.data,
      );
    },
  );

  Future<(Harness, FakeNotifications, NotificationController)> setup({
    int count = 1,
    int lead = 60,
  }) async {
    final h = Harness(cache: _Journal());
    final now = DateTime.now();
    h.server.states['A'] = snapshot('Private board').copyWith(
      tasks: [
        for (var i = 0; i < count; i++)
          task('t$i', now.add(const Duration(hours: 3)), advance: lead),
      ],
    );
    await h.initialize();
    await h.login('A');
    h.storage.values['reminders-device:A'] = jsonEncode(
      const DeviceNotificationPreferences(enabled: true).toJson(),
    );
    final adapter = FakeNotifications();
    final controller = NotificationController(
      workspace: h.workspace,
      storage: h.storage,
      adapter: adapter,
      now: () => now,
    );
    await controller.reconcile();
    return (h, adapter, controller);
  }

  test(
    'schedule is idempotent across refresh and a restored controller',
    () async {
      final (h, adapter, controller) = await setup();
      await controller.reconcile();
      await h.workspace.refresh();
      await controller.reconcile();
      expect(adapter.calls.length, 1);
      controller.dispose();
      final restored = NotificationController(
        workspace: h.workspace,
        storage: h.storage,
        adapter: adapter,
      );
      await restored.reconcile();
      expect(adapter.calls.length, 1);
      restored.dispose();
      h.dispose();
    },
  );
  test(
    'pending completion suppresses before response and a failed write restores once',
    () async {
      final (h, adapter, controller) = await setup();
      final initial = h.server.states['A']!;
      // Use the existing HTTP gate so the confirmed snapshot remains unchanged.
      final responseGate = Completer<http.Response>();
      h.server.nextWrite = responseGate;
      final write = h.workspace.mutate(
        (s) => s.copyWith(tasks: [s.tasks.single.copyWith(isCompleted: true)]),
      );
      await settleAsync();
      await controller.reconcile();
      expect(adapter.events, isEmpty);
      h.server.states['A'] = initial;
      responseGate.complete(
        jsonResponse({'code': 'bad', 'message': 'Rejected'}, 400),
      );
      await write;
      await h.workspace.outbox!.idle;
      await controller.reconcile();
      expect(adapter.events.length, 1);
      expect(adapter.calls.length, 2);
      controller.dispose();
      h.dispose();
    },
  );
  test(
    'disabling and signout remove future schedules and other accounts stay off',
    () async {
      final (h, adapter, controller) = await setup();
      await controller.updateDevice(controller.device.copyWith(enabled: false));
      expect(adapter.events, isEmpty);
      await controller.updateDevice(controller.device.copyWith(enabled: true));
      expect(adapter.events.length, 1);
      await h.auth.signOut();
      await settleAsync();
      await controller.reconcile();
      expect(adapter.events, isEmpty);
      await h.login('B');
      await controller.reconcile();
      expect(controller.device.enabled, isFalse);
      expect(adapter.events, isEmpty);
      controller.dispose();
      h.dispose();
    },
  );
  test(
    'many immediate catchups produce one summary and never replay',
    () async {
      final (h, adapter, controller) = await setup(count: 3, lead: 1440);
      expect(adapter.calls.length, 1);
      expect(
        adapter.calls.single['body'],
        '3 tasks have approaching deadlines',
      );
      await controller.reconcile();
      expect(adapter.calls.length, 1);
      controller.dispose();
      h.dispose();
    },
  );
  test(
    'capacity is visible and future setup failures can be retried',
    () async {
      final (h, adapter, controller) = await setup(count: 201);
      expect(adapter.events.length, 200);
      expect(controller.eligible, 201);
      await controller.updateDevice(controller.device.copyWith(enabled: false));
      adapter.fail = true;
      await controller.updateDevice(controller.device.copyWith(enabled: true));
      expect(controller.error, isNotNull);
      adapter.fail = false;
      await controller.reconcile();
      expect(adapter.events.length, 200);
      controller.dispose();
      h.dispose();
    },
  );
}
