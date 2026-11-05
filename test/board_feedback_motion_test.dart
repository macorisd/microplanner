import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/core/widgets/board_sync_glow.dart';
import 'package:microplanner/features/auth/data/auth_service.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/presentation/widgets/sidebar.dart';
import 'support/fakes.dart';

void main() {
  testWidgets(
    'sidebar reverses smoothly, excludes collapsed controls and respects reduced motion',
    (tester) async {
      final h = Harness();
      await tester.runAsync(() async {
        await h.initialize();
        await h.login('A');
      });
      final boards = BoardsProvider(h.workspace);
      var reduced = false;
      late StateSetter update;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: h.auth),
            ChangeNotifierProvider<WorkspaceController>.value(
              value: h.workspace,
            ),
            ChangeNotifierProvider<BoardsProvider>.value(value: boards),
          ],
          child: MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: reduced),
                  child: const Scaffold(body: Sidebar()),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = find.byType(SizeTransition);
      double height() => tester.getSize(list).height;
      final expanded = height();
      await tester.tap(find.text('Boards'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final halfway = height();
      expect(halfway, inExclusiveRange(0, expanded));
      expect(
        tester
            .widget<IgnorePointer>(
              find
                  .descendant(of: list, matching: find.byType(IgnorePointer))
                  .first,
            )
            .ignoring,
        isTrue,
      );
      await tester.tap(find.text('Boards'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(height(), greaterThan(halfway));
      await tester.pumpAndSettle();
      expect(height(), expanded);
      await tester.tap(find.text('Boards'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      update(() => reduced = true);
      await tester.pumpAndSettle();
      expect(find.text('A private'), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.tap(find.text('Boards'));
      await tester.pumpAndSettle();
      expect(find.text('A private'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
      boards.dispose();
      h.dispose();
    },
  );

  testWidgets(
    'sync sheen stops its ticker for reduced motion, hidden surfaces and completion',
    (tester) async {
      var active = true;
      var reduced = false;
      var visible = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduced),
                child: TickerMode(
                  enabled: visible,
                  child: BoardSyncGlow(
                    active: active,
                    child: const SizedBox(width: 200, height: 48),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      update(() => visible = false);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      update(() {
        visible = true;
        reduced = true;
      });
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      update(() => reduced = false);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      update(() => active = false);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
}
