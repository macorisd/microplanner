import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
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
    'sync light travels only around the edge and preserves the interior',
    (tester) async {
      final capture = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: capture,
              child: const DecoratedBox(
                decoration: BoxDecoration(color: Color(0xfff0f0f0)),
                child: BoardSyncGlow(
                  active: true,
                  child: SizedBox(width: 200, height: 48),
                ),
              ),
            ),
          ),
        ),
      );
      var peak = 240;
      for (final elapsed in [80, 400, 400]) {
        await tester.pump(Duration(milliseconds: elapsed));
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final frame = (await tester.runAsync(
          () => boundary.toImage(pixelRatio: 1),
        ))!;
        final pixels = (await tester.runAsync(
          () => frame.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        var lightest = 0;
        for (var x = 12; x < 188; x++) {
          final offset = (24 * frame.width + x) * 4;
          final red = pixels.getUint8(offset);
          expect(pixels.getUint8(offset + 1), red);
          expect(pixels.getUint8(offset + 2), red);
          expect(
            red,
            240,
            reason: 'Pending sync never washes or shades the board interior',
          );
        }
        for (var y = 1; y < 47; y++) {
          for (var x = 1; x < 199; x++) {
            if (y > 3 && y < 44 && x > 3 && x < 196) continue;
            final offset = (y * frame.width + x) * 4;
            final red = pixels.getUint8(offset);
            expect(pixels.getUint8(offset + 1), red);
            expect(pixels.getUint8(offset + 2), red);
            if (red > lightest) lightest = red;
          }
        }
        if (lightest > peak) peak = lightest;
        frame.dispose();
      }
      expect(
        peak,
        greaterThan(246),
        reason:
            'The travelling edge light remains visible on a pale background',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
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
