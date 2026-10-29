import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:microplanner/core/data/workspace_snapshot.dart';
import 'package:microplanner/features/boards/data/board_column_storage.dart';
import 'package:microplanner/features/boards/data/models/board.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'support/fakes.dart';

WorkspaceSnapshot _data() => WorkspaceSnapshot(
  boards: [
    Board.create(id: 'first', name: 'First'),
    Board.create(id: 'second', name: 'Second', sortOrder: 1),
  ],
);

Future<Harness> _harness() async {
  final h = Harness();
  h.server.states['A'] = _data();
  h.server.states['B'] = _data();
  await h.initialize();
  await h.login('A');
  return h;
}

void main() {
  test(
    'each board restores its column after navigation and provider recreation without cloud writes',
    () async {
      final h = await _harness();
      final store = _Columns()..values['A'] = {'first': 1, 'second': 0};
      var boards = BoardsProvider(h.workspace, columnStorage: store);
      expect(boards.isRestoringColumns, isTrue);
      await settleAsync();
      expect(boards.currentColumnIndex, 1);
      boards.selectColumn(0);
      boards.selectBoard('second');
      expect(boards.currentColumnIndex, 0);
      boards.selectColumn(2);
      boards.selectBoard('first');
      expect(boards.currentColumnIndex, 0);
      await settleAsync();
      boards.dispose();
      boards = BoardsProvider(h.workspace, columnStorage: store);
      await settleAsync();
      expect(boards.currentColumnIndex, 0);
      boards.selectBoard('second');
      expect(boards.currentColumnIndex, 2);
      expect(h.server.writes, 0);
      boards.dispose();
      h.dispose();
    },
  );

  test(
    'accounts and independent devices keep separate column histories',
    () async {
      final h = await _harness();
      final store = _Columns()..values['B'] = {'first': 1};
      final boards = BoardsProvider(h.workspace, columnStorage: store);
      final otherDevice = BoardsProvider(
        h.workspace,
        columnStorage: _Columns(),
      );
      await settleAsync();
      boards.selectColumn(0);
      await settleAsync();
      expect(otherDevice.currentColumnIndex, 2);
      await h.auth.signOut();
      await h.login('B');
      await settleAsync();
      expect(boards.currentColumnIndex, 1);
      boards.selectColumn(2);
      await h.auth.signOut();
      await h.login('A');
      await settleAsync();
      expect(boards.currentColumnIndex, 0);
      expect(h.server.writes, 0);
      otherDevice.dispose();
      boards.dispose();
      h.dispose();
    },
  );

  test(
    'rapid selections are serialized and old-account writes stay with their owner',
    () async {
      final h = await _harness();
      final gate = Completer<void>();
      final store = _Columns()..nextWrite = gate;
      final boards = BoardsProvider(h.workspace, columnStorage: store);
      await settleAsync();
      boards.selectColumn(0);
      boards.selectColumn(1);
      boards.selectColumn(2);
      await settleAsync();
      await h.auth.signOut();
      await h.login('B');
      await settleAsync();
      boards.selectColumn(1);
      await settleAsync();
      expect(store.values['B']!['first'], 1);
      gate.complete();
      await settleAsync();
      expect(store.values['A']!['first'], 2);
      expect(boards.currentColumnIndex, 1);
      boards.dispose();
      h.dispose();
    },
  );

  test(
    'a late restore cannot cross account boundaries or notify after disposal',
    () async {
      final h = await _harness();
      final gate = Completer<Map<String, int>>();
      final store = _Columns()..nextRead = gate;
      final boards = BoardsProvider(h.workspace, columnStorage: store);
      await settleAsync();
      await h.auth.signOut();
      await h.login('B');
      await settleAsync();
      boards.selectColumn(1);
      gate.complete({'first': 0});
      await settleAsync();
      expect(boards.currentColumnIndex, 1);
      final disposedGate = Completer<Map<String, int>>();
      final another = BoardsProvider(
        h.workspace,
        columnStorage: _Columns()..nextRead = disposedGate,
      );
      await settleAsync();
      another.dispose();
      disposedGate.complete({'first': 0});
      await settleAsync();
      boards.dispose();
      h.dispose();
    },
  );

  test(
    'failed initial storage falls back and does not clobber another board on recovery',
    () async {
      final h = await _harness();
      final store = _Columns()
        ..values['A'] = {'second': 0}
        ..failNextRead = true;
      final boards = BoardsProvider(h.workspace, columnStorage: store);
      await settleAsync();
      expect(boards.isRestoringColumns, isFalse);
      expect(boards.currentColumnIndex, 2);
      boards.selectColumn(1);
      await settleAsync();
      expect(store.values['A'], {'first': 1, 'second': 0});
      boards.dispose();
      h.dispose();
    },
  );

  test(
    'refresh and offline navigation preserve columns without new preference reads',
    () async {
      final h = await _harness();
      final store = _Columns();
      final boards = BoardsProvider(h.workspace, columnStorage: store);
      await settleAsync();
      boards.selectColumn(0);
      await settleAsync();
      await h.workspace.refresh();
      expect(boards.currentColumnIndex, 0);
      h.server.offline = true;
      await h.workspace.refresh();
      boards.selectBoard('second');
      boards.selectColumn(1);
      boards.selectBoard('first');
      expect(boards.currentColumnIndex, 0);
      expect(store.reads, 1);
      expect(h.server.writes, 0);
      boards.dispose();
      h.dispose();
    },
  );

  test(
    'invalid selections are ignored and missing or deleted boards use a valid fallback',
    () async {
      final h = await _harness();
      final boards = BoardsProvider(h.workspace, columnStorage: _Columns());
      await settleAsync();
      boards.selectColumn(-1);
      boards.selectColumn(3);
      expect(boards.currentColumnIndex, 2);
      boards.selectBoard('second');
      boards.selectColumn(0);
      boards.selectBoard('first');
      h.server.states['A'] = WorkspaceSnapshot(boards: [_data().boards.last]);
      await h.workspace.refresh();
      expect(boards.currentBoardId, 'second');
      expect(boards.currentColumnIndex, 0);
      boards.dispose();
      h.dispose();
    },
  );

  test('a stalled preference read cannot block access forever', () async {
    final h = await _harness();
    final gate = Completer<Map<String, int>>();
    final boards = BoardsProvider(
      h.workspace,
      columnStorage: _Columns()..nextRead = gate,
    );
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    expect(boards.isRestoringColumns, isFalse);
    expect(boards.currentColumnIndex, 2);
    gate.complete({'first': 0});
    await settleAsync();
    expect(boards.currentColumnIndex, 2);
    boards.dispose();
    h.dispose();
  });

  test(
    'private storage uses isolated keys and filters invalid column values',
    () async {
      final vault = MemoryPrivateStorage();
      final store = PrivateBoardColumnStorage(vault);
      await store.write('account-a', {'first': 1});
      final firstKey = vault.values.keys.single;
      expect(firstKey.contains('account-a'), isFalse);
      vault.values[firstKey] = jsonEncode({
        'first': 9,
        'second': 0,
        'bad': '1',
      });
      expect(await store.read('account-a'), {'second': 0});
      expect(await store.read('account-b'), isEmpty);
      await store.write('account-b', {'first': 2});
      expect(vault.values.length, 2);
      vault.values[firstKey] = 'not json';
      await expectLater(store.read('account-a'), throwsFormatException);
    },
  );
}

class _Columns implements BoardColumnStorage {
  final values = <String, Map<String, int>>{};
  int reads = 0;
  bool failNextRead = false;
  Completer<Map<String, int>>? nextRead;
  Completer<void>? nextWrite;
  @override
  Future<Map<String, int>> read(String owner) async {
    reads++;
    if (failNextRead) {
      failNextRead = false;
      throw StateError('Unavailable');
    }
    final gate = nextRead;
    nextRead = null;
    return gate != null ? gate.future : Map.of(values[owner] ?? {});
  }

  @override
  Future<void> write(String owner, Map<String, int> columns) async {
    final gate = nextWrite;
    nextWrite = null;
    if (gate != null) await gate.future;
    values[owner] = Map.of(columns);
  }
}
