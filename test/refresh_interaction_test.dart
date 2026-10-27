import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/features/auth/data/auth_service.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';
import 'package:microplanner/features/tasks/presentation/account_dashboard.dart';
import 'package:microplanner/features/tasks/presentation/widgets/add_task_dialog.dart';
import 'support/fakes.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      'New Task survives focus returning during a click on $platform',
      (tester) async {
        tester.view.physicalSize = Size(
          platform == TargetPlatform.android ? 393 : 1280,
          800,
        );
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = _Fixture();
        await tester.runAsync(f.initialize);
        await tester.pumpWidget(f.app(platform));
        await tester.pumpAndSettle();
        final reads = f.h.server.reads;
        final pending = Completer<http.Response>();
        f.h.server.nextRead = pending;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(FloatingActionButton)),
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 350));
        final opened = find.byType(AddTaskDialog).evaluate().isNotEmpty;
        expect(f.h.server.reads, reads);
        pending.complete(jsonResponse(f.h.server.states['A']!.toJson()));
        await tester.runAsync(settleAsync);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        f.dispose();
        expect(
          opened,
          isTrue,
          reason: 'The first click must open the form, even as focus returns.',
        );
      },
    );

    testWidgets('New Task opens during a background refresh on $platform', (
      tester,
    ) async {
      tester.view.physicalSize = Size(
        platform == TargetPlatform.android ? 393 : 1280,
        900,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = _Fixture();
      await tester.runAsync(f.initialize);
      await tester.pumpWidget(f.app(platform));
      await tester.pumpAndSettle();
      final reads = f.h.server.reads;
      final pending = Completer<http.Response>();
      f.h.server.nextRead = pending;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(settleAsync);
      await tester.pump();
      expect(f.h.server.reads, reads + 1);
      expect(f.h.workspace.isLoading, isTrue);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(AddTaskDialog), findsOneWidget);
      pending.complete(jsonResponse(f.h.server.states['A']!.toJson()));
      await tester.runAsync(settleAsync);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    });
  }
}

class _Fixture {
  final h = Harness();
  late final boards = BoardsProvider(h.workspace);
  late final tasks = TasksProvider(h.workspace, boards);
  Future<void> initialize() async {
    await h.initialize();
    boards;
    tasks;
    await h.login('A');
  }

  Widget app(TargetPlatform platform) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthService>.value(value: h.auth),
      ChangeNotifierProvider<WorkspaceController>.value(value: h.workspace),
      ChangeNotifierProvider<BoardsProvider>.value(value: boards),
      ChangeNotifierProvider<TasksProvider>.value(value: tasks),
    ],
    child: MaterialApp(
      theme: ThemeData(platform: platform),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'GB')],
      home: const AccountDashboard(),
    ),
  );
  void dispose() {
    tasks.dispose();
    boards.dispose();
    h.dispose();
  }
}
