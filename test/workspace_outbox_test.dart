import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:microplanner/core/constants/app_constants.dart';
import 'package:microplanner/core/data/api_client.dart';
import 'package:microplanner/core/data/workspace_delta.dart';
import 'package:microplanner/core/data/workspace_outbox.dart';
import 'package:microplanner/core/data/workspace_snapshot.dart';
import 'package:microplanner/core/data/workspace_storage.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'support/fakes.dart';

Task _task(String id) => Task.create(
  id: id,
  name: id,
  boardId: 'default-board',
  deadline: DateTime(2030),
  type: TaskType.unassigned,
  priority: TaskPriority.low,
);

WorkspaceSnapshot _response(Map<String, dynamic> body) =>
    WorkspaceSnapshot.fromJson({
      ...Map<String, dynamic>.from(body['data'] as Map),
      'revision': (body['revision'] as int) + 1,
    });

class _Journal implements WorkspaceJournal {
  final data = <String, String>{};
  bool failWrites = false;
  @override
  Future<String?> readJournal(String ownerId) async => data[ownerId];
  @override
  Future<void> writeJournal(String ownerId, String value) async {
    if (failWrites) throw StateError('disk failure');
    data[ownerId] = value;
  }
}

void main() {
  test(
    'retry cannot overlap a newer pending action on the same task',
    () async {
      final journal = _Journal();
      final original = _task('same');
      final base = snapshot('Board').copyWith(tasks: [original]);
      final gate = Completer<WorkspaceSnapshot>();
      var calls = 0;
      final queue = WorkspaceOutbox(
        owner: 'A',
        journal: journal,
        initial: base,
        active: () => true,
        onOffline: (_) {},
        readCloud: () async => base,
        onConfirmed: (_, _) async {},
        send: (body, _) {
          if (++calls == 1) throw const ApiException(400, 'bad', 'Rejected');
          return gate.future;
        },
      );
      await queue.restore();
      queue.updateConfirmed(base, online: true);
      await settleAsync();
      final failed = WorkspaceDelta.between(
        base,
        base.copyWith(tasks: [original.copyWith(name: 'Draft')]),
      );
      expect(await queue.enqueue(failed), isFalse);
      final failedId = queue.operations.single.id;
      final next = WorkspaceDelta.between(
        base,
        base.copyWith(tasks: [original.copyWith(description: 'Later')]),
      );
      final pending = queue.enqueue(next);
      await settleAsync();
      expect(await queue.retry(failedId), isFalse);
      expect(queue.operations.where((item) => item.failure != null).length, 1);
      expect(calls, 2);
      gate.complete(
        base.copyWith(tasks: [original.copyWith(description: 'Later')]),
      );
      expect(await pending, isTrue);
      queue.dispose();
    },
  );
  for (final overlaps in [false, true]) {
    test(
      'definitive conflict ${overlaps ? 'retains an overlapping draft' : 'rebases unrelated fields'}',
      () async {
        final journal = _Journal();
        final original = _task('conflict');
        final base = snapshot('Board').copyWith(tasks: [original]);
        final remoteTask = overlaps
            ? original.copyWith(name: 'Remote edit')
            : original.copyWith(description: 'Remote description');
        final remote = WorkspaceSnapshot.fromJson({
          ...base.copyWith(tasks: [remoteTask]).data,
          'revision': 1,
        });
        final local = original.copyWith(name: 'Local edit');
        final sent = <Map<String, dynamic>>[];
        final queue = WorkspaceOutbox(
          owner: 'A',
          journal: journal,
          initial: base,
          active: () => true,
          onOffline: (_) {},
          readCloud: () async => remote,
          onConfirmed: (_, _) async {},
          send: (body, _) async {
            sent.add(body);
            if (sent.length == 1) {
              throw const ApiException(409, 'revision_conflict', 'Conflict');
            }
            return _response(body);
          },
        );
        await queue.restore();
        queue.updateConfirmed(base, online: true);
        await settleAsync();
        final result = await queue.enqueue(
          WorkspaceDelta.between(base, base.copyWith(tasks: [local])),
        );
        if (overlaps) {
          expect(result, isFalse);
          expect(sent.length, 1);
          expect(queue.operations.single.failure, isNotNull);
          expect(
            queue.operations.single.delta.items.single.after!['name'],
            'Local edit',
          );
        } else {
          expect(result, isTrue);
          expect(sent.length, 2);
          expect(sent.last['revision'], 1);
          expect(queue.projected.tasks.single.name, 'Local edit');
          expect(
            queue.projected.tasks.single.description,
            'Remote description',
          );
        }
        queue.dispose();
      },
    );
  }
  test(
    'independent queued actions persist while a previous request is blocked',
    () async {
      final journal = _Journal();
      final base = snapshot('Board');
      final gate = Completer<WorkspaceSnapshot>();
      final sent = <Map<String, dynamic>>[];
      final queue = WorkspaceOutbox(
        owner: 'A',
        journal: journal,
        initial: base,
        active: () => true,
        onOffline: (_) {},
        readCloud: () async => base,
        onConfirmed: (_, _) async {},
        send: (body, _) {
          sent.add(body);
          return sent.length == 1 ? gate.future : Future.value(_response(body));
        },
      );
      await queue.restore();
      queue.updateConfirmed(base, online: true);
      await settleAsync();
      final first = _task('one');
      final firstResult = queue.enqueue(
        WorkspaceDelta.between(base, base.copyWith(tasks: [first])),
      );
      await settleAsync();
      expect(sent.length, 1);
      final second = _task('two');
      final projected = queue.projected;
      final secondResult = queue.enqueue(
        WorkspaceDelta.between(
          projected,
          projected.copyWith(tasks: [...projected.tasks, second]),
        ),
      );
      await settleAsync();
      expect((jsonDecode(journal.data['A']!)['operations'] as List).length, 2);
      expect(queue.projected.tasks.map((task) => task.id), ['one', 'two']);
      final sameTask = WorkspaceDelta.between(
        projected,
        projected.copyWith(tasks: [first.copyWith(isCompleted: true)]),
      );
      expect(await queue.enqueue(sameTask), isFalse);
      gate.complete(_response(sent.first));
      expect(await firstResult, isTrue);
      expect(await secondResult, isTrue);
      expect(sent.length, 2);
      expect(queue.projected.tasks.map((task) => task.id), ['one', 'two']);
      expect(queue.hasPending, isFalse);
      queue.dispose();
    },
  );

  test(
    'restart retries the exact uncertain request for the same account',
    () async {
      final journal = _Journal();
      final base = snapshot('Board');
      final gate = Completer<WorkspaceSnapshot>();
      final sent = <Map<String, dynamic>>[];
      final firstQueue = WorkspaceOutbox(
        owner: 'A',
        journal: journal,
        initial: base,
        active: () => true,
        onOffline: (_) {},
        readCloud: () async => base,
        onConfirmed: (_, _) async {},
        send: (body, _) {
          sent.add(body);
          return gate.future;
        },
      );
      await firstQueue.restore();
      firstQueue.updateConfirmed(base, online: true);
      await settleAsync();
      final task = _task('one');
      final result = firstQueue.enqueue(
        WorkspaceDelta.between(base, base.copyWith(tasks: [task])),
      );
      await settleAsync();
      expect(sent.length, 1);
      final committed = _response(sent.single);
      firstQueue.dispose();
      expect(await result, isFalse);
      final secondQueue = WorkspaceOutbox(
        owner: 'A',
        journal: journal,
        initial: committed,
        active: () => true,
        onOffline: (_) {},
        readCloud: () async => committed,
        onConfirmed: (_, _) async {},
        send: (body, _) async {
          sent.add(body);
          return committed;
        },
      );
      await secondQueue.restore();
      expect(secondQueue.operations.single.uncertain, isTrue);
      secondQueue.updateConfirmed(committed, online: true);
      await settleAsync();
      expect(sent.length, 2);
      expect(jsonEncode(sent[1]), jsonEncode(sent[0]));
      expect(secondQueue.hasPending, isFalse);
      expect((jsonDecode(journal.data['A']!)['operations'] as List), isEmpty);
      gate.complete(committed);
      await settleAsync();
      expect((jsonDecode(journal.data['A']!)['operations'] as List), isEmpty);
      secondQueue.dispose();
    },
  );

  test(
    'a confirmed rejection retains its draft without blocking unrelated work',
    () async {
      final journal = _Journal();
      final base = snapshot('Board');
      var calls = 0;
      final queue = WorkspaceOutbox(
        owner: 'A',
        journal: journal,
        initial: base,
        active: () => true,
        onOffline: (_) {},
        readCloud: () async => base,
        onConfirmed: (_, _) async {},
        send: (body, _) async {
          calls++;
          if (calls == 1) {
            throw const ApiException(400, 'bad', 'The request was rejected.');
          }
          return _response(body);
        },
      );
      await queue.restore();
      queue.updateConfirmed(base, online: true);
      await settleAsync();
      final first = _task('one');
      final failed = queue.enqueue(
        WorkspaceDelta.between(base, base.copyWith(tasks: [first])),
      );
      expect(await failed, isFalse);
      expect(queue.hasFailures, isTrue);
      expect(queue.operations.single.delta.items.single.after!['name'], 'one');
      final second = _task('two');
      final next = queue.enqueue(
        WorkspaceDelta.between(base, base.copyWith(tasks: [second])),
      );
      expect(await next, isTrue);
      expect(queue.projected.tasks.single.id, 'two');
      expect(queue.hasFailures, isTrue);
      queue.dispose();
    },
  );

  test('a damaged journal is not overwritten or sent', () async {
    final journal = _Journal()..data['A'] = 'not json';
    final base = snapshot('Board');
    var calls = 0;
    final queue = WorkspaceOutbox(
      owner: 'A',
      journal: journal,
      initial: base,
      active: () => true,
      onOffline: (_) {},
      readCloud: () async => base,
      onConfirmed: (_, _) async {},
      send: (body, _) async {
        calls++;
        return _response(body);
      },
    );
    await queue.restore();
    queue.updateConfirmed(base, online: true);
    final task = _task('one');
    expect(
      await queue.enqueue(
        WorkspaceDelta.between(base, base.copyWith(tasks: [task])),
      ),
      isFalse,
    );
    expect(journal.data['A'], 'not json');
    expect(calls, 0);
    expect(queue.storageError, isNotNull);
    queue.dispose();
  });

  test(
    'a disk failure keeps an unsent draft and stops network writes',
    () async {
      final journal = _Journal();
      final base = snapshot('Board');
      var calls = 0;
      final queue = WorkspaceOutbox(
        owner: 'A',
        journal: journal,
        initial: base,
        active: () => true,
        onOffline: (_) {},
        readCloud: () async => base,
        onConfirmed: (_, _) async {},
        send: (body, _) async {
          calls++;
          return _response(body);
        },
      );
      await queue.restore();
      queue.updateConfirmed(base, online: true);
      await settleAsync();
      journal.failWrites = true;
      final task = _task('unsaved');
      final result = queue.enqueue(
        WorkspaceDelta.between(base, base.copyWith(tasks: [task])),
      );
      expect(await result, isFalse);
      await settleAsync();
      expect(calls, 0);
      expect(queue.storageError, isNotNull);
      expect(queue.operations.single.failure, isNotNull);
      expect(
        queue.operations.single.delta.items.single.after!['name'],
        'unsaved',
      );
      final id = queue.operations.single.id;
      journal.failWrites = false;
      expect(await queue.repairStorage(), isTrue);
      expect(queue.storageError, isNull);
      expect(await queue.retry(id), isTrue);
      expect(queue.projected.tasks.single.name, 'unsaved');
      queue.dispose();
    },
  );

  test('a malformed saved intent is retained without being sent', () async {
    final journal = _Journal();
    final base = snapshot('Board');
    journal.data['A'] = jsonEncode({
      'version': 1,
      'operations': [
        {
          'id': 'operation',
          'createdAt': DateTime.now().toIso8601String(),
          'delta': {
            'items': [
              {
                'kind': 'tasks',
                'id': 'wrong',
                'before': null,
                'after': {'id': 'different'},
              },
            ],
          },
        },
      ],
    });
    var calls = 0;
    final queue = WorkspaceOutbox(
      owner: 'A',
      journal: journal,
      initial: base,
      active: () => true,
      onOffline: (_) {},
      readCloud: () async => base,
      onConfirmed: (_, _) async {},
      send: (body, _) async {
        calls++;
        return _response(body);
      },
    );
    final original = journal.data['A'];
    await queue.restore();
    queue.updateConfirmed(base, online: true);
    await settleAsync();
    expect(queue.storageError, isNotNull);
    expect(journal.data['A'], original);
    expect(calls, 0);
    queue.dispose();
  });

  test(
    'a timed-out write retries the identical request when reconnecting',
    () async {
      final journal = _Journal();
      final base = snapshot('Board');
      final sent = <Map<String, dynamic>>[];
      var offline = false;
      final queue = WorkspaceOutbox(
        owner: 'A',
        journal: journal,
        initial: base,
        active: () => true,
        onOffline: (_) => offline = true,
        readCloud: () async => base,
        onConfirmed: (_, _) async {},
        send: (body, _) async {
          sent.add(body);
          if (sent.length == 1) {
            throw const ApiException(0, 'offline', 'Timeout');
          }
          return _response(body);
        },
      );
      await queue.restore();
      queue.updateConfirmed(base, online: true);
      await settleAsync();
      final task = _task('recover');
      final result = queue.enqueue(
        WorkspaceDelta.between(base, base.copyWith(tasks: [task])),
      );
      await settleAsync();
      expect(offline, isTrue);
      expect(queue.operations.single.uncertain, isTrue);
      queue.updateConfirmed(base, online: true);
      expect(await result, isTrue);
      expect(jsonEncode(sent[0]), jsonEncode(sent[1]));
      queue.dispose();
    },
  );

  test(
    'an uncertain revision conflict is never replayed with a new body',
    () async {
      final journal = _Journal();
      final base = snapshot('Board');
      var calls = 0;
      var reads = 0;
      final queue = WorkspaceOutbox(
        owner: 'A',
        journal: journal,
        initial: base,
        active: () => true,
        onOffline: (_) {},
        readCloud: () async {
          reads++;
          return base;
        },
        onConfirmed: (_, _) async {},
        send: (body, _) async {
          calls++;
          throw calls == 1
              ? const ApiException(0, 'offline', 'Timeout')
              : const ApiException(409, 'revision_conflict', 'Conflict');
        },
      );
      await queue.restore();
      queue.updateConfirmed(base, online: true);
      await settleAsync();
      final task = _task('uncertain');
      queue.enqueue(WorkspaceDelta.between(base, base.copyWith(tasks: [task])));
      await settleAsync();
      queue.updateConfirmed(base, online: true);
      await settleAsync();
      expect(calls, 2);
      expect(reads, 0);
      expect(queue.operations.single.uncertain, isTrue);
      expect(queue.waitingForConnection, isTrue);
      queue.dispose();
    },
  );
  test('a reviewed failed draft can replace its rejected intent', () async {
    final journal = _Journal();
    final base = snapshot('Board');
    var calls = 0;
    final queue = WorkspaceOutbox(
      owner: 'A',
      journal: journal,
      initial: base,
      active: () => true,
      onOffline: (_) {},
      readCloud: () async => base,
      onConfirmed: (_, _) async {},
      send: (body, _) async {
        if (++calls == 1) throw const ApiException(400, 'bad', 'Rejected');
        return _response(body);
      },
    );
    await queue.restore();
    queue.updateConfirmed(base, online: true);
    await settleAsync();
    final task = _task('draft');
    expect(
      await queue.enqueue(
        WorkspaceDelta.between(base, base.copyWith(tasks: [task])),
      ),
      isFalse,
    );
    final id = queue.operations.single.id;
    final edited = task.copyWith(name: 'Edited draft');
    expect(
      await queue.replaceFailure(
        id,
        WorkspaceDelta.between(base, base.copyWith(tasks: [edited])),
      ),
      isTrue,
    );
    expect(queue.operations, isEmpty);
    expect(queue.projected.tasks.single.name, 'Edited draft');
    queue.dispose();
  });
}
