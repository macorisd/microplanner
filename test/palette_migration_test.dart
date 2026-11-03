import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:microplanner/core/data/workspace_storage.dart';
import 'package:microplanner/core/data/workspace_snapshot.dart';
import 'package:microplanner/features/boards/data/board_catalog.dart';
import 'package:microplanner/features/boards/data/models/subject.dart';
import 'support/fakes.dart';

class _Cache extends MemoryCache implements WorkspaceJournal {
  final journals = <String, String>{};
  @override
  Future<String?> readJournal(String ownerId) async => journals[ownerId];
  @override
  Future<void> writeJournal(String ownerId, String value) async =>
      journals[ownerId] = value;
}

WorkspaceSnapshot _retired() {
  final base = snapshot('Retired colors');
  return base.copyWith(
    schemaVersion: 2,
    boards: [base.boards.single.copyWith(color: 0xfffff176)],
    subjects: [
      for (final entry in retiredCategoryColors.entries)
        Subject(
          id: 'subject-${entry.key}',
          boardId: 'default-board',
          name: 'Subject ${entry.key}',
          color: entry.key,
        ),
      const Subject(
        id: 'unchanged',
        boardId: 'default-board',
        name: 'Keep me',
        color: 0xff64b5f6,
      ),
    ],
  );
}

class _ConflictServer extends FakeServer {
  bool first = true;
  @override
  Future<http.Response> handle(http.Request request) async {
    if (first && request.method == 'PUT') {
      first = false;
      final base = states['A']!;
      states['A'] = base.copyWith(
        boards: [
          base.boards.single.copyWith(name: 'Renamed on another device'),
        ],
      );
      states['A'] = WorkspaceSnapshot.fromJson({
        ...states['A']!.toJson(),
        'revision': base.revision + 1,
      });
      return jsonResponse({
        'code': 'revision_conflict',
        'message': 'Changed elsewhere',
      }, 409);
    }
    return super.handle(request);
  }
}

void main() {
  test(
    'retired colors migrate through the journal once without losing relationships',
    () async {
      final h = Harness(cache: _Cache());
      h.server.states['A'] = _retired();
      await h.initialize();
      await h.login('A');
      await h.workspace.outbox!.idle;
      await settleAsync();
      final saved = h.server.states['A']!;
      expect(saved.boards.single.color, 0xffad7c32);
      expect(
        saved.subjects.take(3).map((subject) => subject.color),
        retiredCategoryColors.values,
      );
      expect(saved.subjects.last.color, 0xff64b5f6);
      expect(
        saved.subjects.map(
          (subject) => (subject.id, subject.name, subject.boardId),
        ),
        _retired().subjects.map(
          (subject) => (subject.id, subject.name, subject.boardId),
        ),
      );
      expect(h.workspace.snapshot.hasRetiredCategoryColors, isFalse);
      final writes = h.server.writes;
      await h.workspace.refresh();
      expect(h.server.writes, writes);
      h.dispose();
    },
  );

  test('cached retired colors wait for connection before migrating', () async {
    final cache = _Cache();
    cache.values['A'] = _retired();
    final h = Harness(cache: cache);
    h.server.states['A'] = _retired();
    h.server.offline = true;
    await h.initialize();
    await h.login('A');
    expect(h.workspace.snapshot.hasRetiredCategoryColors, isTrue);
    expect(h.server.writes, 0);
    h.server.offline = false;
    await h.workspace.refresh();
    expect(h.server.states['A']!.hasRetiredCategoryColors, isFalse);
    expect(h.workspace.snapshot.subjects.length, 4);
    h.dispose();
  });

  test(
    'palette migration preserves a concurrent rename after a revision conflict',
    () async {
      final server = _ConflictServer();
      server.states['A'] = _retired();
      final h = Harness(server: server, cache: _Cache());
      await h.initialize();
      await h.login('A');
      await h.workspace.outbox!.idle;
      await settleAsync();
      expect(
        server.states['A']!.boards.single.name,
        'Renamed on another device',
      );
      expect(server.states['A']!.boards.single.color, 0xffad7c32);
      expect(h.workspace.outbox!.hasFailures, isFalse);
      h.dispose();
    },
  );

  test(
    'late migration response cannot replace another account workspace',
    () async {
      final h = Harness(cache: _Cache());
      h.server.states['A'] = _retired();
      final gate = Completer<http.Response>();
      h.server.nextWrite = gate;
      await h.initialize();
      await h.login('A');
      final response = h.server.states['A']!;
      await h.auth.signOut();
      await h.login('B');
      gate.complete(jsonResponse(response.toJson()));
      await settleAsync();
      expect(h.workspace.ownerId, 'B');
      expect(h.workspace.snapshot.boards.single.name, 'B private');
      expect(h.workspace.snapshot.subjects, isEmpty);
      h.dispose();
    },
  );
}
