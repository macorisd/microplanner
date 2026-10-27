import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:microplanner/core/constants/app_constants.dart';
import 'package:microplanner/features/boards/data/models/board.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';
import 'support/fakes.dart';

void main() {
  test(
    'accepted writes wait for the latest refresh and save in order',
    () async {
      final h = Harness();
      await h.initialize();
      await h.login('A');
      final boards = BoardsProvider(h.workspace);
      final tasks = TasksProvider(h.workspace, boards);
      final older = Completer<http.Response>();
      h.server.nextRead = older;
      final oldRead = h.workspace.refresh();
      await settleAsync();
      final newer = Completer<http.Response>();
      h.server.nextRead = newer;
      final newRead = h.workspace.refresh();
      await settleAsync();
      final added = tasks.addTask(
        name: 'Accepted during refresh',
        deadline: DateTime(2026, 11, 1),
        type: TaskType.unassigned,
        priority: TaskPriority.low,
      );
      final subject = boards.addSubject(name: 'Accepted second');
      older.complete(jsonResponse(snapshot('Old read', revision: 2).toJson()));
      await oldRead;
      await settleAsync();
      expect(h.server.writes, 0);
      h.server.states['A'] = snapshot('Changed on another device', revision: 7);
      final writing = Completer<http.Response>();
      h.server.nextWrite = writing;
      newer.complete(jsonResponse(h.server.states['A']!.toJson()));
      await newRead;
      await settleAsync();
      expect(h.server.writes, 1);
      expect(h.workspace.isSaving, isTrue);
      // Further actions remain accepted while the first save is in flight.
      final board = boards.addBoard(name: 'Accepted third');
      await settleAsync();
      expect(h.server.writes, 1);
      writing.complete(jsonResponse(h.server.states['A']!.toJson()));
      expect(await added, isTrue);
      expect(await subject, isTrue);
      expect(await board, isTrue);
      expect(h.server.writeRevisions, [7, 8, 9]);
      expect(
        h.workspace.snapshot.boards.first.name,
        'Changed on another device',
      );
      expect(h.workspace.snapshot.tasks.single.name, 'Accepted during refresh');
      expect(h.workspace.snapshot.subjects.single.name, 'Accepted second');
      expect(h.workspace.snapshot.boards.last.name, 'Accepted third');
      tasks.dispose();
      boards.dispose();
      h.dispose();
    },
  );

  test(
    'task edit, completion and deletion survive a pending refresh',
    () async {
      final h = Harness();
      await h.initialize();
      await h.login('A');
      final boards = BoardsProvider(h.workspace);
      final tasks = TasksProvider(h.workspace, boards);
      await tasks.addTask(
        name: 'Original',
        deadline: DateTime(2026, 11, 1),
        type: TaskType.unassigned,
        priority: TaskPriority.low,
      );
      final task = h.workspace.snapshot.tasks.single;
      final pending = Completer<http.Response>();
      h.server.nextRead = pending;
      final read = h.workspace.refresh();
      final edit = tasks.updateTask(task.copyWith(name: 'Edited'));
      final complete = tasks.toggleTaskCompletion(task.id);
      await settleAsync();
      expect(h.server.writes, 1);
      pending.complete(jsonResponse(h.server.states['A']!.toJson()));
      await read;
      expect(await edit, isTrue);
      expect(await complete, isTrue);
      expect(h.workspace.snapshot.tasks.single.name, 'Edited');
      expect(h.workspace.snapshot.tasks.single.isCompleted, isTrue);
      final next = Completer<http.Response>();
      h.server.nextRead = next;
      final nextRead = h.workspace.refresh();
      final deleted = tasks.deleteTask(task.id);
      next.complete(jsonResponse(h.server.states['A']!.toJson()));
      await nextRead;
      expect(await deleted, isTrue);
      expect(h.workspace.snapshot.tasks, isEmpty);
      tasks.dispose();
      boards.dispose();
      h.dispose();
    },
  );

  for (final nextOwner in ['A', 'B']) {
    test('queued writes cannot cross sign-out/sign-in to $nextOwner', () async {
      final h = Harness();
      await h.initialize();
      await h.login('A');
      final pending = Completer<http.Response>();
      h.server.nextRead = pending;
      final read = h.workspace.refresh();
      final accepted = h.workspace.mutate((s) => snapshot('Must not save'));
      await settleAsync();
      await h.auth.signOut();
      await h.login(nextOwner);
      expect(await accepted, isFalse);
      // A new session can write without waiting for the old request to finish.
      expect(await h.workspace.mutate((s) => snapshot('New session')), isTrue);
      pending.complete(jsonResponse(snapshot('Late response').toJson()));
      await read;
      expect(h.server.writes, 1);
      expect(h.workspace.snapshot.boards.single.name, 'New session');
      h.dispose();
    });
  }

  test(
    'failed refresh rejects queued writes without changing cached data',
    () async {
      final h = Harness();
      await h.initialize();
      await h.login('A');
      final pending = Completer<http.Response>();
      h.server.nextRead = pending;
      final read = h.workspace.refresh();
      final accepted = h.workspace.mutate((s) => snapshot('Unsaved'));
      await settleAsync();
      pending.completeError(http.ClientException('offline'));
      await read;
      expect(await accepted, isFalse);
      expect(h.workspace.canWrite, isFalse);
      expect(h.server.writes, 0);
      expect(h.workspace.snapshot.boards.single.name, 'A private');
      expect(h.cache.values['A']!.boards.single.name, 'A private');
      h.dispose();
    },
  );

  test(
    'disposing cancels queued writes even with an unfinished refresh',
    () async {
      final h = Harness();
      await h.initialize();
      await h.login('A');
      final pending = Completer<http.Response>();
      h.server.nextRead = pending;
      final read = h.workspace.refresh();
      final accepted = h.workspace.mutate((s) => snapshot('Unsaved'));
      h.workspace.dispose();
      expect(await accepted, isFalse);
      pending.complete(jsonResponse(snapshot('Late').toJson()));
      await read;
      expect(h.server.writes, 0);
      h.auth.dispose();
    },
  );

  test('queued board deletions cannot remove the last board', () async {
    final h = Harness();
    await h.initialize();
    await h.login('A');
    final boards = BoardsProvider(h.workspace);
    await boards.addBoard(name: 'Second');
    final ids = boards.boards.map((b) => b.id).toList();
    final removed = boards.deleteBoard(ids.first);
    final last = boards.deleteBoard(ids.last);
    expect(await removed, isTrue);
    expect(await last, isFalse);
    expect(boards.boards.single.id, ids.last);
    boards.dispose();
    h.dispose();
  });

  test('board actions use stable identities and refreshed order', () async {
    final h = Harness();
    await h.initialize();
    await h.login('A');
    final boards = BoardsProvider(h.workspace);
    await boards.addBoard(name: 'Second');
    await boards.addBoard(name: 'Third');
    final original = [...boards.boards];
    final pending = Completer<http.Response>();
    h.server.nextRead = pending;
    final read = h.workspace.refresh();
    final reordered = boards.reorderBoards(0, 3);
    final added = boards.addBoard();
    h.server.states['A'] = h.server.states['A']!.copyWith(
      boards: [
        original[2],
        original[0],
        original[1],
        Board.create(id: 'remote', name: 'Added remotely', sortOrder: 9),
      ],
    );
    pending.complete(jsonResponse(h.server.states['A']!.toJson()));
    await read;
    expect(await reordered, isTrue);
    expect(await added, isTrue);
    expect(boards.boards.map((b) => b.id).take(4), [
      original[2].id,
      original[1].id,
      'remote',
      original[0].id,
    ]);
    expect(boards.boards.last.name, 'Board 5');
    expect(boards.boards.map((b) => b.sortOrder), [0, 1, 2, 3, 4]);
    boards.dispose();
    h.dispose();
  });
}
