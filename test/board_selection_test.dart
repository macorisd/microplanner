import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:microplanner/core/data/workspace_snapshot.dart';
import 'package:microplanner/features/boards/data/board_selection_storage.dart';
import 'package:microplanner/features/boards/data/models/board.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/features/auth/data/auth_service.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';
import 'package:microplanner/features/tasks/presentation/account_dashboard.dart';
import 'package:microplanner/features/tasks/presentation/dashboard_screen.dart';
import 'support/fakes.dart';

WorkspaceSnapshot data(String owner) => WorkspaceSnapshot(
  boards: [
    Board.create(id: '$owner-first', name: '$owner first', sortOrder: 0),
    Board.create(id: '$owner-last', name: '$owner last', sortOrder: 1),
  ],
);

void main() {
  testWidgets(
    'startup waits for the stored selection instead of displaying the wrong board first',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = await tester.runAsync(_harness);
      final read = Completer<String?>();
      final store = _Selection()..onRead = (_) => read.future;
      final boards = BoardsProvider(h!.workspace, selectionStorage: store);
      final tasks = TasksProvider(h.workspace, boards);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: h.auth),
            ChangeNotifierProvider<WorkspaceController>.value(
              value: h.workspace,
            ),
            ChangeNotifierProvider<BoardsProvider>.value(value: boards),
            ChangeNotifierProvider<TasksProvider>.value(value: tasks),
          ],
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.windows),
            home: const AccountDashboard(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(DashboardScreen), findsNothing);
      expect(find.text('A first'), findsNothing);
      read.complete('A-last');
      await tester.runAsync(settleAsync);
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(boards.currentBoardId, 'A-last');
      await tester.pumpWidget(const SizedBox());
      tasks.dispose();
      boards.dispose();
      h.dispose();
    },
  );
  test(
    'stored selection survives provider recreation without cloud writes',
    () async {
      final h = await _harness();
      final store = _Selection();
      var boards = BoardsProvider(h.workspace, selectionStorage: store);
      await settleAsync();
      boards.selectBoard('A-last');
      await settleAsync();
      boards.dispose();
      boards = BoardsProvider(h.workspace, selectionStorage: store);
      expect(boards.isRestoringSelection, isTrue);
      await settleAsync();
      expect(boards.currentBoardId, 'A-last');
      expect(h.server.writes, 0);
      boards.dispose();
      h.dispose();
    },
  );

  test('accounts keep separate preferences through sign-out/sign-in', () async {
    final h = await _harness();
    final store = _Selection()..values['B'] = 'B-last';
    final boards = BoardsProvider(h.workspace, selectionStorage: store);
    await settleAsync();
    boards.selectBoard('A-last');
    await h.auth.signOut();
    expect(boards.currentBoardId, isNull);
    await h.login('B');
    expect(boards.currentBoardId, 'B-last');
    await h.auth.signOut();
    await h.login('A');
    expect(boards.currentBoardId, 'A-last');
    boards.dispose();
    h.dispose();
  });

  test('two devices do not change one another\'s starting board', () async {
    final h = await _harness();
    final first = BoardsProvider(h.workspace, selectionStorage: _Selection());
    final second = BoardsProvider(h.workspace, selectionStorage: _Selection());
    await settleAsync();
    first.selectBoard('A-last');
    await settleAsync();
    await h.workspace.refresh();
    expect(first.currentBoardId, 'A-last');
    expect(second.currentBoardId, 'A-first');
    expect(h.server.writes, 0);
    first.dispose();
    second.dispose();
    h.dispose();
  });

  test(
    'renaming/reordering keep the ID; creation and deletion remember their resulting selection',
    () async {
      final h = await _harness();
      final store = _Selection()..values['A'] = 'A-last';
      final boards = BoardsProvider(h.workspace, selectionStorage: store);
      await settleAsync();
      await boards.updateBoard(boards.currentBoard!.copyWith(name: 'Renamed'));
      await boards.reorderBoards(1, 0);
      expect(boards.currentBoardId, 'A-last');
      expect(boards.currentBoard!.name, 'Renamed');
      await boards.addBoard(name: 'New');
      await settleAsync();
      final created = boards.currentBoardId!;
      expect(store.values['A'], created);
      await boards.deleteBoard(created);
      await settleAsync();
      expect(boards.currentBoardId, 'A-last');
      expect(store.values['A'], 'A-last');
      boards.dispose();
      h.dispose();
    },
  );

  test(
    'a missing cache entry does not overwrite a preference before cloud confirmation',
    () async {
      final h = Harness();
      h.server.states['A'] = data('A');
      h.cache.values['A'] = data(
        'A',
      ).copyWith(boards: [data('A').boards.first]);
      final read = Completer<http.Response>();
      h.server.nextRead = read;
      final store = _Selection()..values['A'] = 'A-last';
      await h.initialize();
      final boards = BoardsProvider(h.workspace, selectionStorage: store);
      await h.login('A');
      expect(boards.currentBoardId, 'A-first');
      expect(store.writes, isEmpty);
      read.complete(jsonResponse(h.server.states['A']!.toJson()));
      await settleAsync();
      expect(boards.currentBoardId, 'A-last');
      expect(store.values['A'], 'A-last');
      expect(store.writes, isEmpty);
      boards.dispose();
      h.dispose();
    },
  );

  test(
    'a confirmed missing board falls back to the first board in the current order',
    () async {
      final h = await _harness();
      final store = _Selection()..values['A'] = 'deleted';
      final boards = BoardsProvider(h.workspace, selectionStorage: store);
      await settleAsync();
      expect(boards.currentBoardId, 'A-first');
      expect(store.values['A'], 'A-first');
      boards.dispose();
      h.dispose();
    },
  );

  test(
    'offline startup restores the selected account board from its cache',
    () async {
      final h = await _harness();
      h.server.offline = true;
      await h.workspace.refresh();
      final store = _Selection()..values['A'] = 'A-last';
      final boards = BoardsProvider(h.workspace, selectionStorage: store);
      await settleAsync();
      expect(boards.currentBoardId, 'A-last');
      expect(store.writes, isEmpty);
      expect(h.workspace.canWrite, isFalse);
      boards.dispose();
      h.dispose();
    },
  );

  test(
    'a late preference read cannot undo a newer deliberate selection',
    () async {
      final h = await _harness();
      final read = Completer<String?>();
      final store = _Selection()..onRead = (_) => read.future;
      final boards = BoardsProvider(h.workspace, selectionStorage: store);
      boards.selectBoard('A-last');
      read.complete('A-first');
      await settleAsync();
      expect(boards.currentBoardId, 'A-last');
      expect(store.values['A'], 'A-last');
      boards.dispose();
      h.dispose();
    },
  );

  test(
    'a late preference from the previous account never appears in the next account',
    () async {
      final h = await _harness();
      final read = Completer<String?>();
      final store = _Selection()
        ..onRead = (owner) =>
            owner == 'A' ? read.future : Future.value('B-last');
      final boards = BoardsProvider(h.workspace, selectionStorage: store);
      await settleAsync();
      await h.auth.signOut();
      await h.login('B');
      read.complete('A-last');
      await settleAsync();
      expect(boards.currentBoardId, 'B-last');
      boards.dispose();
      h.dispose();
    },
  );

  test(
    'rapid selections serialize preference writes, preserving the final choice',
    () async {
      final h = await _harness();
      final firstWrite = Completer<void>();
      final store = _Selection()
        ..values['A'] = 'A-first'
        ..nextWrite = firstWrite;
      final boards = BoardsProvider(h.workspace, selectionStorage: store);
      await settleAsync();
      boards.selectBoard('A-last');
      await settleAsync();
      boards.selectBoard('A-first');
      boards.selectBoard('A-last');
      await settleAsync();
      expect(store.writes.length, 1);
      firstWrite.complete();
      await settleAsync();
      expect(store.writes, ['A:A-last', 'A:A-first', 'A:A-last']);
      expect(store.values['A'], 'A-last');
      boards.dispose();
      h.dispose();
    },
  );

  test(
    'failed storage leaves navigation usable without overwriting an unread preference',
    () async {
      final h = await _harness();
      final store = _Selection()
        ..fail = true
        ..values['A'] = 'A-last';
      final boards = BoardsProvider(h.workspace, selectionStorage: store);
      await settleAsync();
      expect(boards.currentBoardId, 'A-first');
      expect(store.writes, isEmpty);
      boards.selectBoard('A-last');
      await settleAsync();
      expect(boards.currentBoardId, 'A-last');
      expect(h.server.writes, 0);
      boards.dispose();
      h.dispose();
    },
  );

  test(
    'a stalled read cannot indefinitely block startup or overwrite its preference',
    () async {
      final h = await _harness();
      final read = Completer<String?>();
      final store = _Selection()..onRead = (_) => read.future;
      final boards = BoardsProvider(h.workspace, selectionStorage: store);
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      expect(boards.isRestoringSelection, isFalse);
      expect(boards.currentBoardId, 'A-first');
      expect(store.writes, isEmpty);
      read.complete('A-last');
      await settleAsync();
      expect(boards.currentBoardId, 'A-first');
      boards.dispose();
      h.dispose();
    },
  );

  test(
    'persistent adapter separates accounts and leaves authentication storage intact',
    () async {
      final secure = MemoryPrivateStorage()..values['session'] = 'unchanged';
      final store = PrivateBoardSelectionStorage(secure);
      await store.write('A', 'a');
      await store.write('B', 'b');
      final reopened = PrivateBoardSelectionStorage(secure);
      expect(await reopened.read('A'), 'a');
      expect(await reopened.read('B'), 'b');
      expect(secure.values['session'], 'unchanged');
      expect(await reopened.read('C'), isNull);
    },
  );
}

Future<Harness> _harness() async {
  final h = Harness();
  h.server.states['A'] = data('A');
  h.server.states['B'] = data('B');
  await h.initialize();
  await h.login('A');
  return h;
}

class _Selection implements BoardSelectionStorage {
  final values = <String, String>{};
  final writes = <String>[];
  Future<String?> Function(String)? onRead;
  Completer<void>? nextWrite;
  bool fail = false;
  @override
  Future<String?> read(String ownerId) async {
    if (fail) throw StateError('storage unavailable');
    return onRead == null ? values[ownerId] : onRead!(ownerId);
  }

  @override
  Future<void> write(String ownerId, String boardId) async {
    if (fail) throw StateError('storage unavailable');
    writes.add('$ownerId:$boardId');
    final blocked = nextWrite;
    nextWrite = null;
    if (blocked != null) await blocked.future;
    values[ownerId] = boardId;
  }
}
