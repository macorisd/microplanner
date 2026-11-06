import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:microplanner/core/constants/app_constants.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/core/data/workspace_storage.dart';
import 'package:microplanner/features/auth/data/auth_service.dart';
import 'package:microplanner/features/boards/data/models/board.dart';
import 'package:microplanner/features/boards/data/models/subject.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'package:microplanner/features/tasks/presentation/widgets/sidebar.dart';

import 'support/fakes.dart';

class _Journal extends MemoryCache implements WorkspaceJournal {
  final entries = <String, String>{};
  @override
  Future<String?> readJournal(String ownerId) async => entries[ownerId];
  @override
  Future<void> writeJournal(String ownerId, String value) async =>
      entries[ownerId] = value;
}

Future<BoardsProvider> _initialize(Harness h) async {
  h.server.states['A'] = h.server.states['A']!.copyWith(
    boards: [
      ...h.server.states['A']!.boards,
      Board(id: 'beta', name: 'Beta', createdAt: DateTime(2027), sortOrder: 1),
      Board(
        id: 'gamma',
        name: 'Gamma',
        createdAt: DateTime(2028),
        sortOrder: 2,
      ),
    ],
  );
  await h.initialize();
  await h.login('A');
  return BoardsProvider(h.workspace);
}

Widget _app(Harness h, BoardsProvider boards, TargetPlatform platform) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: h.auth),
        ChangeNotifierProvider<WorkspaceController>.value(value: h.workspace),
        ChangeNotifierProvider<BoardsProvider>.value(value: boards),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        home: const Scaffold(
          body: SizedBox(width: 400, child: Sidebar(inDrawer: true)),
        ),
      ),
    );

Future<void> _dragFirstLast(
  WidgetTester tester,
  TargetPlatform platform,
  String first,
) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.text(first)),
    kind: platform == TargetPlatform.windows
        ? PointerDeviceKind.mouse
        : PointerDeviceKind.touch,
  );
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(
    tester.getCenter(find.text('Gamma')) + const Offset(0, 90),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await gesture.up();
  await tester.runAsync(settleAsync);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.runAsync(settleAsync);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  test('task synchronization does not block board reordering', () async {
    final h = Harness(cache: _Journal());
    final boards = await _initialize(h);
    final gate = Completer<http.Response>();
    h.server.nextWrite = gate;
    final taskSave = h.workspace.mutate(
      (s) => s.copyWith(
        tasks: [
          ...s.tasks,
          Task.create(
            id: 'task',
            name: 'Task',
            boardId: 'default-board',
            deadline: DateTime(2030),
            type: TaskType.unassigned,
            priority: TaskPriority.low,
          ),
        ],
      ),
    );
    await settleAsync();
    final taskResponse = h.server.states['A']!;
    expect(h.workspace.pendingBoardIds, isEmpty);
    final reorder = boards.reorderBoards(0, 3);
    await settleAsync();
    expect(boards.boards.map((b) => b.id), ['beta', 'gamma', 'default-board']);
    gate.complete(jsonResponse(taskResponse.toJson()));
    expect(await taskSave, isTrue);
    expect(await reorder, isTrue);
    await h.workspace.outbox!.idle;
    expect(h.workspace.snapshot.tasks.single.id, 'task');
    expect(boards.boards.map((b) => b.id), ['beta', 'gamma', 'default-board']);
    boards.dispose();
    h.dispose();
  });
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final reject in [false, true]) {
      testWidgets(
        '$platform dropped board stays in place until ${reject ? 'rejection' : 'confirmation'}',
        (tester) async {
          final h = Harness(cache: _Journal());
          late BoardsProvider boards;
          await tester.runAsync(() async => boards = await _initialize(h));
          final initial = h.server.states['A']!;
          final gate = Completer<http.Response>();
          h.server.nextWrite = gate;
          await tester.pumpWidget(_app(h, boards, platform));
          await tester.pumpAndSettle();
          await _dragFirstLast(tester, platform, 'A private');
          expect(boards.boards.map((b) => b.id), [
            'beta',
            'gamma',
            'default-board',
          ]);
          expect(h.workspace.pendingBoardIds, isEmpty);
          final dropped = tester.getTopLeft(find.text('A private'));
          expect(
            dropped.dy,
            greaterThan(tester.getTopLeft(find.text('Gamma')).dy),
          );
          await tester.pump(const Duration(seconds: 3));
          expect(tester.getTopLeft(find.text('A private')), dropped);
          await tester.runAsync(() async {
            if (reject) h.server.states['A'] = initial;
            gate.complete(
              reject
                  ? jsonResponse({'code': 'bad', 'message': 'Rejected'}, 400)
                  : jsonResponse(h.server.states['A']!.toJson()),
            );
            await h.workspace.outbox!.idle;
          });
          await tester.pumpAndSettle();
          expect(
            boards.boards.map((b) => b.id),
            reject
                ? ['default-board', 'beta', 'gamma']
                : ['beta', 'gamma', 'default-board'],
          );
          if (!reject) {
            expect(tester.getTopLeft(find.text('A private')), dropped);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          boards.dispose();
          h.dispose();
        },
      );

      testWidgets(
        '$platform category-only board save blocks every drag and unlocks after ${reject ? 'rejection' : 'confirmation'}',
        (tester) async {
          final h = Harness(cache: _Journal());
          late BoardsProvider boards;
          await tester.runAsync(() async => boards = await _initialize(h));
          await tester.pumpWidget(_app(h, boards, platform));
          await tester.pumpAndSettle();
          final initial = h.server.states['A']!;
          final gate = Completer<http.Response>();
          h.server.nextWrite = gate;
          await tester.runAsync(() async {
            unawaited(
              h.workspace.mutate(
                (s) => s.copyWith(
                  subjects: [
                    ...s.subjects,
                    const Subject(
                      id: 'subject',
                      name: 'New subject',
                      boardId: 'beta',
                      color: 0xffed7691,
                    ),
                  ],
                ),
              ),
            );
            await settleAsync();
          });
          await tester.pump(const Duration(milliseconds: 100));
          expect(h.workspace.pendingBoardIds, {'beta'});
          await _dragFirstLast(tester, platform, 'A private');
          expect(
            find.byKey(const ValueKey('reorder-drag-surface')),
            findsNothing,
          );
          expect(boards.boards.map((b) => b.id), [
            'default-board',
            'beta',
            'gamma',
          ]);
          expect(await boards.reorderBoards(0, 3), isFalse);
          expect(h.server.writes, 1);
          await tester.tap(find.text('Gamma'));
          await tester.pump(const Duration(milliseconds: 100));
          expect(boards.currentBoardId, 'gamma');
          await tester.runAsync(() async {
            if (reject) h.server.states['A'] = initial;
            gate.complete(
              reject
                  ? jsonResponse({'code': 'bad', 'message': 'Rejected'}, 400)
                  : jsonResponse(h.server.states['A']!.toJson()),
            );
            await h.workspace.outbox!.idle;
          });
          await tester.pumpAndSettle();
          expect(h.workspace.pendingBoardIds, isEmpty);
          await _dragFirstLast(tester, platform, 'A private');
          await tester.runAsync(() async => h.workspace.outbox!.idle);
          await tester.pumpAndSettle();
          expect(boards.boards.map((b) => b.id), [
            'beta',
            'gamma',
            'default-board',
          ]);
          expect(h.server.writes, 2);
          await tester.pumpWidget(const SizedBox());
          boards.dispose();
          h.dispose();
        },
      );
    }
  }

  test(
    'queued drops use visible order and an older confirmation cannot revert a newer drop',
    () async {
      final h = Harness(cache: _Journal());
      final boards = await _initialize(h);
      final firstGate = Completer<http.Response>();
      h.server.nextWrite = firstGate;
      final first = boards.reorderBoards(0, 3);
      await settleAsync();
      final firstResponse = h.server.states['A']!;
      expect(boards.boards.map((b) => b.id), [
        'beta',
        'gamma',
        'default-board',
      ]);
      final second = boards.reorderBoards(0, 3);
      await settleAsync();
      expect(boards.boards.map((b) => b.id), [
        'gamma',
        'default-board',
        'beta',
      ]);
      final secondGate = Completer<http.Response>();
      h.server.nextWrite = secondGate;
      firstGate.complete(jsonResponse(firstResponse.toJson()));
      expect(await first, isTrue);
      await settleAsync();
      expect(boards.boards.map((b) => b.id), [
        'gamma',
        'default-board',
        'beta',
      ]);
      secondGate.complete(jsonResponse(h.server.states['A']!.toJson()));
      expect(await second, isTrue);
      await h.workspace.outbox!.idle;
      expect(h.cache.values['A']!.boards.map((b) => b.id), [
        'gamma',
        'default-board',
        'beta',
      ]);
      boards.dispose();
      h.dispose();
    },
  );
}
