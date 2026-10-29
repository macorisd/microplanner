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
import 'package:microplanner/core/widgets/startup_loading_screen.dart';
import 'package:microplanner/features/auth/data/auth_service.dart';
import 'package:microplanner/features/auth/presentation/login_screen.dart';
import 'package:microplanner/features/auth/presentation/session_gate.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';
import 'package:microplanner/features/tasks/presentation/dashboard_screen.dart';
import 'support/fakes.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
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

  testWidgets(
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

  testWidgets(
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
    testWidgets(
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

  testWidgets('logo motion changes frames and closes its loop without a jump', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: StartupLoadingScreen()));
    final start = await _frame(tester);
    await tester.pump(const Duration(milliseconds: 500));
    final middle = await _frame(tester);
    expect(listEquals(start, middle), isFalse);
    await tester.pump(const Duration(milliseconds: 3100));
    expect(listEquals(start, await _frame(tester)), isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('reducing motion stops and restores the static logo', (
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

  testWidgets(
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
