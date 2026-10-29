import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/features/auth/data/auth_service.dart';
import 'package:microplanner/features/boards/data/board_column_storage.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';
import 'package:microplanner/features/tasks/presentation/account_dashboard.dart';
import 'package:microplanner/features/tasks/presentation/dashboard_screen.dart';
import 'package:microplanner/features/tasks/presentation/widgets/android_board_carousel.dart';
import 'package:microplanner/core/widgets/animated_app_logo.dart';
import 'package:microplanner/core/widgets/android_startup_reveal.dart';
import 'package:microplanner/core/widgets/startup_loading_screen.dart';
import 'support/fakes.dart';

void main() {
  testWidgets(
    'account waits for column memory, reveals that page, and never replays on refresh',
    (tester) async {
      _viewport(tester, const Size(393, 850));
      final h = Harness();
      await tester.runAsync(() async {
        await h.initialize();
        await h.login('A');
      });
      final memory = _DelayedColumns();
      final boards = BoardsProvider(h.workspace, columnStorage: memory);
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
            theme: ThemeData(platform: TargetPlatform.android),
            home: const AccountDashboard(),
          ),
        ),
      );
      expect(find.byType(StartupLoadingScreen), findsOneWidget);
      expect(find.byType(DashboardScreen), findsNothing);
      memory.readGate.complete({'default-board': 1});
      await tester.pump();
      expect(
        tester
            .widget<AndroidStartupReveal>(find.byType(AndroidStartupReveal))
            .column,
        1,
      );
      expect(
        tester
            .widget<AndroidBoardCarousel>(find.byType(AndroidBoardCarousel))
            .initialColumn,
        1,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Completed'));
      await tester.pumpAndSettle();
      expect(boards.currentColumnIndex, 0);
      await tester.runAsync(h.workspace.refresh);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('startup-zoom-overlay')), findsNothing);
      expect(boards.currentColumnIndex, 0);
      expect(h.server.writes, 0);
      await tester.pumpWidget(const SizedBox());
      tasks.dispose();
      boards.dispose();
      h.dispose();
    },
  );

  testWidgets(
    'Android waits with a centered static mark and no active ticker',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: const StartupLoadingScreen(),
        ),
      );
      final first = await _logoFrame(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(listEquals(first, await _logoFrame(tester)), isTrue);
      expect(
        tester.widget<AnimatedAppLogo>(find.byType(AnimatedAppLogo)).animate,
        isFalse,
      );
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.byType(Text), findsNothing);
    },
  );

  for (var column = 0; column < 3; column++) {
    testWidgets(
      'column $column starts at the original logo and zooms into its own color',
      (tester) async {
        _viewport(tester, const Size(393, 850));
        final key = GlobalKey();
        Widget app(Widget child) => MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: RepaintBoundary(key: key, child: child),
        );
        await tester.pumpWidget(app(const StartupLoadingScreen()));
        final initial = await _capture(tester, key);
        await tester.pumpWidget(
          app(
            AndroidStartupReveal(
              column: column,
              child: const ColoredBox(
                color: Colors.white,
                child: Center(child: Text('Destination')),
              ),
            ),
          ),
        );
        expect(listEquals(initial, await _capture(tester, key)), isTrue);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 480));
        final rgba = await _capture(
          tester,
          key,
          format: ui.ImageByteFormat.rawRgba,
        );
        for (final point in [
          const Offset(0, 0),
          const Offset(392, 0),
          const Offset(0, 849),
          const Offset(392, 849),
          const Offset(196, 425),
        ]) {
          final offset = (point.dy.toInt() * 393 + point.dx.toInt()) * 4;
          final actual = Color.fromARGB(
            rgba[offset + 3],
            rgba[offset],
            rgba[offset + 1],
            rgba[offset + 2],
          );
          expect(actual, AppLogoArt.colors[column], reason: 'Cover at $point');
        }
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('startup-zoom-overlay')),
          findsNothing,
        );
        expect(find.text('Destination'), findsOneWidget);
        expect(tester.hasRunningAnimations, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'destination is built once, blocked during zoom and preserved after it',
    (tester) async {
      var builds = 0;
      var presses = 0;
      final destination = Builder(
        builder: (_) {
          builds++;
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => presses++,
                child: const Text('Destination'),
              ),
            ),
          );
        },
      );
      Widget app(int column) => MaterialApp(
        home: AndroidStartupReveal(column: column, child: destination),
      );
      await tester.pumpWidget(app(0));
      expect(builds, 1);
      await tester.tap(find.text('Destination'), warnIfMissed: false);
      expect(presses, 0);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pumpAndSettle();
      expect(builds, 1);
      await tester.tap(find.text('Destination'));
      expect(presses, 1);
      await tester.pumpWidget(app(2));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('startup-zoom-overlay')), findsNothing);
    },
  );

  for (final size in [const Size(220, 180), const Size(900, 393)]) {
    testWidgets('reveal fits $size and can be disposed in motion', (
      tester,
    ) async {
      _viewport(tester, size);
      await tester.pumpWidget(
        const MaterialApp(
          home: AndroidStartupReveal(
            column: 1,
            child: ColoredBox(color: Colors.white),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'reduced motion skips the reveal and exposes the destination immediately',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: AndroidStartupReveal(column: 1, child: Text('Destination')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('startup-zoom-overlay')), findsNothing);
      expect(find.text('Destination'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    },
  );
}

class _DelayedColumns implements BoardColumnStorage {
  final readGate = Completer<Map<String, int>>();
  @override
  Future<Map<String, int>> read(String owner) async => readGate.future;
  @override
  Future<void> write(String owner, Map<String, int> columns) async {}
}

void _viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<Uint8List> _logoFrame(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find
        .descendant(
          of: find.byType(AnimatedAppLogo),
          matching: find.byType(RepaintBoundary),
        )
        .first,
  );
  return _bytes(tester, boundary, ui.ImageByteFormat.png);
}

Future<Uint8List> _capture(
  WidgetTester tester,
  GlobalKey key, {
  ui.ImageByteFormat format = ui.ImageByteFormat.png,
}) => _bytes(
  tester,
  key.currentContext!.findRenderObject()! as RenderRepaintBoundary,
  format,
);

Future<Uint8List> _bytes(
  WidgetTester tester,
  RenderRepaintBoundary boundary,
  ui.ImageByteFormat format,
) async => (await tester.runAsync(() async {
  final image = await boundary.toImage();
  try {
    return (await image.toByteData(format: format))!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}))!;
