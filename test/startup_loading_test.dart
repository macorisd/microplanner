import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:microplanner/core/data/api_client.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/core/widgets/animated_app_logo.dart';
import 'package:microplanner/core/widgets/app_bootstrap.dart';
import 'package:microplanner/core/widgets/startup_loading_screen.dart';
import 'package:microplanner/features/auth/data/auth_service.dart';
import 'package:microplanner/features/auth/presentation/login_screen.dart';
import 'package:microplanner/features/auth/presentation/session_gate.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';
import 'package:microplanner/features/tasks/presentation/dashboard_screen.dart';
import 'support/fakes.dart';

void main() {
  _windowsTest(
    'loading logo shares the native full-window center despite system insets',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(padding: EdgeInsets.only(top: 32, bottom: 12)),
            child: StartupLoadingScreen(),
          ),
        ),
      );
      expect(
        tester.getCenter(find.byType(AnimatedAppLogo)),
        const Offset(160, 350),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  _windowsTest(
    'logo motion continues when bootstrap hands off to a new session tree',
    (tester) async {
      final ready = Completer<Widget>();
      await tester.pumpWidget(AppBootstrap(initialize: () => ready.future));
      await tester.pump(const Duration(milliseconds: 500));
      final before = await _frame(tester);
      ready.complete(
        const KeyedSubtree(
          key: ValueKey('restored-session'),
          child: MaterialApp(home: StartupLoadingScreen()),
        ),
      );
      await tester.pump();
      expect(listEquals(before, await _frame(tester)), isTrue);
      await tester.pump(const Duration(milliseconds: 200));
      expect(listEquals(before, await _frame(tester)), isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  _windowsTest(
    'shared logo ticker stops when loading ends or motion is reduced',
    (tester) async {
      Widget app({bool loading = true, bool reduced = false}) => LogoMotionHost(
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: loading ? const StartupLoadingScreen() : const Text('Ready'),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(app(loading: false));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(app(reduced: true));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  _windowsTest(
    'the shuffle keeps moving throughout a turn without parked intervals',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: StartupLoadingScreen()));
      var previous = await _frame(tester);
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 75));
        final current = await _frame(tester);
        expect(
          listEquals(previous, current),
          isFalse,
          reason: 'Motion paused at ${(i + 1) * 75}ms',
        );
        previous = current;
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  _windowsTest(
    'the first logo frame is painted before platform initialization starts',
    (tester) async {
      final ready = Completer<Widget>();
      var paintedBeforeInitialization = false;
      await tester.pumpWidget(
        AppBootstrap(
          initialize: () {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find
                  .descendant(
                    of: find.byType(AnimatedAppLogo),
                    matching: find.byType(RepaintBoundary),
                  )
                  .first,
            );
            paintedBeforeInitialization = !boundary.debugNeedsPaint;
            return ready.future;
          },
        ),
      );
      expect(paintedBeforeInitialization, isTrue);
      _expectOnlyLogo();
      final first = await _frame(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(listEquals(first, await _frame(tester)), isFalse);
      ready.complete(const MaterialApp(home: Text('Ready')));
      await tester.pump();
      expect(find.text('Ready'), findsOneWidget);
      expect(find.byType(StartupLoadingScreen), findsNothing);
    },
  );

  _windowsTest(
    'platform initialization can be retried without duplicate attempts',
    (tester) async {
      final ready = Completer<Widget>();
      var attempts = 0;
      await tester.pumpWidget(
        AppBootstrap(
          initialize: () {
            attempts++;
            if (attempts == 1) throw StateError('Unavailable platform storage');
            return ready.future;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(StartupLoadingScreen), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(attempts, 2);
      _expectOnlyLogo();
      ready.complete(const MaterialApp(home: Text('Ready')));
      await tester.pumpAndSettle();
      expect(find.text('Ready'), findsOneWidget);
    },
  );

  _windowsTest(
    'finishing bootstrap after disposal does not update an unmounted view',
    (tester) async {
      final ready = Completer<Widget>();
      await tester.pumpWidget(AppBootstrap(initialize: () => ready.future));
      await tester.pumpWidget(const SizedBox());
      ready.completeError(StateError('Initialization finished after shutdown'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final offline in [false, true]) {
      _windowsTest(
        '$platform keeps cached startup behind the logo until sync ${offline ? 'fails' : 'finishes'}',
        (tester) async {
          final f = _Startup();
          f.storage.block = false;
          f.storage.values['session'] = jsonEncode(session('A'));
          f.cache.values['A'] = snapshot('Cached board');
          final initialRead = Completer<http.Response>();
          f.server.nextRead = initialRead;
          await tester.pumpWidget(f.app(platform));
          await tester.runAsync(() async {
            await f.auth.initialize();
            await settleAsync();
          });
          expect(f.workspace.hasData, isTrue);
          expect(f.workspace.isLoading, isTrue);
          await tester.pump(const Duration(seconds: 2));
          _expectOnlyLogo();
          expect(find.text('Loading your data'), findsNothing);
          await tester.runAsync(() async {
            if (offline) {
              initialRead.completeError(http.ClientException('offline'));
            } else {
              initialRead.complete(
                jsonResponse(snapshot('Synced board').toJson()),
              );
            }
            await settleAsync();
          });
          await tester.pumpAndSettle();
          expect(find.byType(StartupLoadingScreen), findsNothing);
          expect(find.byType(DashboardScreen), findsOneWidget);
          expect(
            find.text(offline ? 'Cached board' : 'Synced board'),
            findsWidgets,
          );
          expect(find.text('Loading your data'), findsNothing);
          expect(f.workspace.canWrite, !offline);

          // Later refreshes keep the workspace and its floating progress notice.
          final refreshRead = Completer<http.Response>();
          f.server.nextRead = refreshRead;
          final refresh = f.workspace.refresh();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(DashboardScreen), findsOneWidget);
          expect(find.byType(StartupLoadingScreen), findsNothing);
          expect(find.text('Loading your data'), findsOneWidget);
          await tester.runAsync(() async {
            refreshRead.complete(
              jsonResponse(snapshot('Synced board').toJson()),
            );
            await refresh;
          });
          await tester.pumpAndSettle();
          expect(find.text('Loading your data'), findsNothing);
          expect(f.server.writes, 0);
          await tester.pumpWidget(const SizedBox());
          f.dispose();
        },
      );
    }
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    _windowsTest(
      'icon-only startup reaches the workspace without login flash on $platform',
      (tester) async {
        final f = _Startup();
        final read = Completer<http.Response>();
        f.server.nextRead = read;
        f.legacy.exists = true;
        await tester.pumpWidget(f.app(platform));
        _expectOnlyLogo();
        late Future<void> initializing;
        await tester.runAsync(() async {
          initializing = f.auth.initialize();
          await settleAsync();
        });
        await tester.pump(const Duration(milliseconds: 500));
        _expectOnlyLogo();
        await tester.runAsync(() async {
          f.storage.sessionRead.complete(jsonEncode(session('A')));
          await initializing;
          await settleAsync();
        });
        await tester.pump(const Duration(milliseconds: 300));
        _expectOnlyLogo();
        expect(find.text('Loading your data'), findsNothing);
        expect(find.textContaining('Local data from before'), findsNothing);
        await tester.runAsync(() async {
          read.complete(jsonResponse(snapshot('Ready board').toJson()));
          await settleAsync();
        });
        // The dashboard is not held until the animation finishes its cycle.
        await tester.pump();
        expect(find.byType(StartupLoadingScreen), findsNothing);
        expect(find.byType(DashboardScreen), findsOneWidget);
        await tester.pumpAndSettle();
        expect(find.text('Ready board'), findsWidgets);
        expect(f.server.writes, 0);
        await tester.pumpWidget(const SizedBox());
        f.dispose();
      },
    );
  }

  _windowsTest(
    'signed-out startup keeps interactive Google sign-in and cancellation',
    (tester) async {
      final f = _Startup();
      f.storage.block = false;
      await tester.pumpWidget(f.app(TargetPlatform.android));
      await tester.runAsync(f.auth.initialize);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(f.auth.isInitializing, isFalse);
      f.google.pending = Completer<Map<String, dynamic>?>();
      late Future<bool> signingIn;
      await tester.runAsync(() async {
        signingIn = f.auth.signInWithGoogle();
        await settleAsync();
      });
      await tester.pump();
      expect(find.byType(StartupLoadingScreen), findsNothing);
      expect(find.text('Connecting…'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.runAsync(() async {
        f.google.pending!.complete(null);
        await signingIn;
      });
      await tester.pumpAndSettle();
      expect(find.text('Sign in with Google'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  _windowsTest(
    'failed session restore exits loading and exposes sign-in recovery',
    (tester) async {
      final f = _Startup();
      f.storage.block = false;
      f.storage.fail = true;
      await tester.pumpWidget(f.app(TargetPlatform.windows));
      await tester.runAsync(f.auth.initialize);
      await tester.pumpAndSettle();
      expect(find.byType(StartupLoadingScreen), findsNothing);
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(
        find.textContaining('Could not restore your session'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  for (final cached in [false, true]) {
    _windowsTest(
      'offline startup exposes ${cached ? 'cached data' : 'retry and sign out'}',
      (tester) async {
        final f = _Startup();
        f.storage.block = false;
        f.storage.values['session'] = jsonEncode(session('A'));
        if (cached) f.cache.values['A'] = snapshot('Offline board');
        f.server.offline = true;
        await tester.pumpWidget(f.app(TargetPlatform.android));
        await tester.runAsync(() async {
          await f.auth.initialize();
          await settleAsync();
        });
        await tester.pumpAndSettle();
        expect(find.byType(StartupLoadingScreen), findsNothing);
        if (cached) {
          expect(find.byType(DashboardScreen), findsOneWidget);
          expect(find.text('Offline board'), findsWidgets);
          expect(f.workspace.canWrite, isFalse);
        } else {
          expect(find.text('Retry').hitTestable(), findsWidgets);
          expect(find.text('Sign out'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        f.dispose();
      },
    );
  }

  _windowsTest(
    'logo motion changes frames and closes its loop without a jump',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: StartupLoadingScreen()));
      final start = await _frame(tester);
      await tester.pump(const Duration(milliseconds: 500));
      final middle = await _frame(tester);
      expect(listEquals(start, middle), isFalse);
      await tester.pump(const Duration(milliseconds: 3100));
      expect(listEquals(start, await _frame(tester)), isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  _windowsTest('reducing motion stops and restores the static logo', (
    tester,
  ) async {
    Widget app(bool reduced) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: const StartupLoadingScreen(),
      ),
    );
    await tester.pumpWidget(app(true));
    final still = await _frame(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(listEquals(still, await _frame(tester)), isTrue);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(app(false));
    await tester.pump(const Duration(milliseconds: 600));
    expect(listEquals(still, await _frame(tester)), isFalse);
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(listEquals(still, await _frame(tester)), isTrue);
    expect(tester.hasRunningAnimations, isFalse);
  });

  _windowsTest(
    'icon-only screen fits small windows and exposes one loading description',
    (tester) async {
      tester.view.physicalSize = const Size(220, 180);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(3)),
            child: StartupLoadingScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      _expectOnlyLogo();
      expect(find.bySemanticsLabel('Loading microplanner'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );
}

void _expectOnlyLogo() {
  expect(find.byType(StartupLoadingScreen), findsOneWidget);
  expect(find.byType(AnimatedAppLogo), findsOneWidget);
  expect(find.byType(LoginScreen), findsNothing);
  expect(find.byType(DashboardScreen), findsNothing);
  expect(find.byType(Text), findsNothing);
  expect(find.byType(CircularProgressIndicator), findsNothing);
}

Future<Uint8List> _frame(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find
        .descendant(
          of: find.byType(AnimatedAppLogo),
          matching: find.byType(RepaintBoundary),
        )
        .first,
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }))!;
}

class _StartupStorage extends MemoryPrivateStorage {
  bool block = true;
  bool fail = false;
  late final sessionRead = Completer<String?>();
  @override
  Future<String?> read(String key) async {
    if (fail && key == 'session') throw StateError('Unavailable storage');
    return block && key == 'session' ? sessionRead.future : super.read(key);
  }
}

class _Startup {
  final storage = _StartupStorage();
  final google = FakeGoogle();
  final server = FakeServer();
  final cache = MemoryCache();
  final legacy = FakeLegacy();
  late final api = ApiClient(
    'http://localhost:3000',
    client: MockClient(server.handle),
  );
  late final auth = AuthService(api: api, storage: storage, google: google);
  late final workspace = WorkspaceController(
    auth: auth,
    api: api,
    cache: cache,
    legacy: legacy,
  );
  late final boards = BoardsProvider(workspace);
  late final tasks = TasksProvider(workspace, boards);
  Widget app(TargetPlatform platform) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthService>.value(value: auth),
      ChangeNotifierProvider<WorkspaceController>.value(value: workspace),
      ChangeNotifierProvider<BoardsProvider>.value(value: boards),
      ChangeNotifierProvider<TasksProvider>.value(value: tasks),
    ],
    child: MaterialApp(
      theme: ThemeData(platform: platform),
      home: const SessionGate(),
    ),
  );
  void dispose() {
    tasks.dispose();
    boards.dispose();
    workspace.dispose();
    auth.dispose();
  }
}

void _windowsTest(
  String description,
  Future<void> Function(WidgetTester) body,
) => testWidgets(
  description,
  body,
  variant: TargetPlatformVariant.only(TargetPlatform.windows),
);
