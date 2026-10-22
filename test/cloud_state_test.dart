import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:microplanner/core/data/workspace_snapshot.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';
import 'support/fakes.dart';

void main() {
  test(
    'sign-out clears all visible data before a late read from the old account completes',
    () async {
      final h = Harness();
      await h.initialize();
      await h.login('A');
      final pending = Completer<http.Response>();
      h.server.nextRead = pending;
      final oldRead = h.workspace.refresh();
      await settleAsync();
      final signOut = h.auth.signOut();
      expect(h.workspace.snapshot.boards, isEmpty);
      await signOut;
      await h.login('B');
      pending.complete(jsonResponse(snapshot('A leaked response').toJson()));
      await oldRead;
      expect(h.workspace.ownerId, 'B');
      expect(h.workspace.snapshot.boards.single.name, 'B private');
      h.dispose();
    },
  );
  test(
    'a late save cannot replace another account or write its cache',
    () async {
      final h = Harness();
      await h.initialize();
      await h.login('A');
      final pending = Completer<http.Response>();
      h.server.nextWrite = pending;
      final save = h.workspace.mutate(
        (s) => s.copyWith(boards: [s.boards.single.copyWith(name: 'A edited')]),
      );
      await settleAsync();
      await h.auth.signOut();
      await h.login('B');
      pending.complete(
        jsonResponse(snapshot('A edited', revision: 1).toJson()),
      );
      expect(await save, isFalse);
      expect(h.workspace.snapshot.boards.single.name, 'B private');
      expect(h.cache.values['B']!.boards.single.name, 'B private');
      h.dispose();
    },
  );
  test(
    'offline restore reads only the active account cache and blocks all writes',
    () async {
      final h = Harness();
      h.storage.values['session'] = jsonEncode(session('A'));
      h.cache.values['A'] = snapshot('A cached');
      h.cache.values['B'] = snapshot('B secret');
      h.server.offline = true;
      await h.initialize();
      expect(h.auth.isAuthenticated, isTrue);
      expect(h.workspace.snapshot.boards.single.name, 'A cached');
      expect(h.workspace.canWrite, isFalse);
      expect(await h.workspace.mutate((s) => snapshot('Unsaved')), isFalse);
      expect(h.server.writes, 0);
      h.dispose();
    },
  );
  test('expired or revoked sessions do not expose cached data', () async {
    for (final revoked in [false, true]) {
      final h = Harness();
      h.cache.values['A'] = snapshot('A secret');
      h.storage.values['session'] = jsonEncode(
        session('A', expires: revoked ? null : DateTime(2000)),
      );
      h.server.rejectSession = revoked;
      await h.initialize();
      expect(h.auth.isAuthenticated, isFalse);
      expect(h.workspace.snapshot.boards, isEmpty);
      h.dispose();
    }
  });
  test(
    'failed writes do not change data, and reconnect reloads before editing',
    () async {
      final h = Harness();
      await h.initialize();
      await h.login('A');
      h.server.offline = true;
      expect(await h.workspace.mutate((s) => snapshot('Not saved')), isFalse);
      expect(h.workspace.snapshot.boards.single.name, 'A private');
      expect(h.workspace.canWrite, isFalse);
      h.server.offline = false;
      await h.workspace.refresh();
      expect(h.workspace.canWrite, isTrue);
      h.dispose();
    },
  );
  test(
    'revision conflicts reload remote data and report that the edit did not save',
    () async {
      final h = Harness();
      await h.initialize();
      await h.login('A');
      h.server.states['A'] = snapshot('Changed on Android', revision: 4);
      h.server.conflict = true;
      expect(
        await h.workspace.mutate((s) => snapshot('Stale Windows edit')),
        isFalse,
      );
      expect(h.workspace.snapshot.boards.single.name, 'Changed on Android');
      expect(h.workspace.error, contains('Another device'));
      h.dispose();
    },
  );
  test('older refresh cannot replace a newer response', () async {
    final h = Harness();
    await h.initialize();
    await h.login('A');
    final pending = Completer<http.Response>();
    h.server.nextRead = pending;
    final old = h.workspace.refresh();
    await settleAsync();
    h.server.states['A'] = snapshot('Newest', revision: 3);
    await h.workspace.refresh();
    pending.complete(jsonResponse(snapshot('Old', revision: 1).toJson()));
    await old;
    expect(h.workspace.snapshot.boards.single.name, 'Newest');
    h.dispose();
  });
  test(
    'canceling sign-in rejects and revokes a session that arrives afterwards',
    () async {
      final h = Harness();
      await h.initialize();
      h.google.pending = Completer();
      final signIn = h.auth.signInWithGoogle();
      await settleAsync();
      h.auth.cancelSignIn();
      expect(
        await h.auth.signInWithGoogle(),
        isFalse,
      ); // No overlapping login while the first finishes.
      h.google.pending!.complete(session('A'));
      expect(await signIn, isFalse);
      expect(h.auth.isAuthenticated, isFalse);
      expect(h.storage.values['session'], isNull);
      h.dispose();
    },
  );
  test(
    'confirmed import is bound to the current user and removes the offer',
    () async {
      final h = Harness();
      h.legacy.exists = true;
      await h.initialize();
      await h.login('A');
      expect(h.workspace.canImport, isTrue);
      expect(await h.workspace.importLegacy(), isTrue);
      expect(h.legacy.importedBy, 'A');
      expect(h.workspace.canImport, isFalse);
      await h.auth.signOut();
      await h.login('B');
      expect(h.workspace.canImport, isFalse);
      h.dispose();
    },
  );
  test(
    'board and subject deletion preserve referential integrity and last board',
    () async {
      final h = Harness();
      await h.initialize();
      await h.login('A');
      final boards = BoardsProvider(h.workspace);
      final tasks = TasksProvider(h.workspace, boards);
      expect(await boards.deleteBoard('default-board'), isFalse);
      await boards.addBoard(name: 'Second');
      final secondId = boards.currentBoardId!;
      await boards.addSubject(name: 'Math');
      final subjectId = boards.currentBoardSubjects.single.id;
      final task = Task(
        id: 'task',
        name: 'Homework',
        deadline: DateTime(2026, 11, 1),
        createdAt: DateTime(2026, 10, 22),
        typeIndex: 1,
        priorityIndex: 1,
        subject: '',
        boardId: secondId,
        subjectId: subjectId,
      );
      await h.workspace.mutate((s) => s.copyWith(tasks: [task]));
      await boards.deleteSubject(subjectId);
      expect(h.workspace.snapshot.tasks.single.subjectId, isNull);
      await boards.deleteBoard(secondId);
      expect(h.workspace.snapshot.tasks, isEmpty);
      expect(boards.boards.length, 1);
      tasks.dispose();
      boards.dispose();
      h.dispose();
    },
  );
  test(
    'dates retain their instant and task fields across cloud serialization',
    () {
      final json = snapshot('Dates').toJson();
      json['tasks'] = [
        {
          'id': 'task',
          'name': 'Due',
          'deadline': '2026-10-25T00:55:00+02:00',
          'createdAt': '2026-10-22T12:00:00Z',
          'typeIndex': 2,
          'priorityIndex': 2,
          'isCompleted': true,
          'boardId': 'default-board',
          'subjectId': null,
          'description': 'Description',
        },
      ];
      final parsed = WorkspaceSnapshot.fromJson(json);
      final restored = parsed.clone();
      expect(
        restored.tasks.single.deadline.toUtc(),
        DateTime.utc(2026, 10, 24, 22, 55),
      );
      expect(restored.tasks.single.description, 'Description');
      expect(restored.tasks.single.isCompleted, isTrue);
    },
  );
}
