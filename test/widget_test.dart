import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/core/theme/app_theme.dart';
import 'package:microplanner/features/auth/data/auth_service.dart';
import 'package:microplanner/features/auth/presentation/login_screen.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';
import 'package:microplanner/features/tasks/presentation/account_dashboard.dart';
import 'support/fakes.dart';

void main() {
  for (final width in [1280.0, 360.0]) {
    testWidgets(
      'legacy import actions have readable contrast and require confirmation at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = Harness();
        h.legacy.exists = true;
        await tester.runAsync(() async {
          await h.initialize();
          await h.login('A');
        });
        final boards = BoardsProvider(h.workspace);
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
              // Use the production palette and inherited button color without
              // downloading fonts: this is the combination that hid the actions.
              theme: ThemeData(
                useMaterial3: true,
                colorScheme: AppTheme.lightColorScheme,
                textButtonTheme: TextButtonThemeData(
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.lightColorScheme.primary,
                  ),
                ),
              ),
              home: const AccountDashboard(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expectReadable(tester, 'Local data from before sign-in are available.');
        expectReadable(tester, 'Import…');
        expectReadable(tester, 'Not now');
        expect(h.server.writes, 0);

        await tester.tap(find.text('Import…'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('A@example.com'),
          ),
          findsOneWidget,
        );
        expectReadable(tester, 'Import');
        expectReadable(tester, 'Cancel');
        expect(h.server.writes, 0);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(h.server.writes, 0);
        expect(h.workspace.canImport, isTrue);
        expect(h.legacy.importedBy, isNull);

        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
        expect(find.text('Import…'), findsNothing);
        expect(h.server.writes, 0);
        expect(h.legacy.importedBy, isNull);
        await tester.pumpWidget(const SizedBox());
        tasks.dispose();
        boards.dispose();
        h.dispose();
      },
    );
  }
  testWidgets(
    'Google login fits a small Android viewport and starts real auth abstraction',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = Harness();
      await tester.runAsync(h.initialize);
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: h.auth,
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Sign in with Google'));
      await tester.pumpAndSettle();
      expect(h.auth.currentUser?.id, 'A');
      await tester.pumpWidget(const SizedBox());
      h.dispose();
    },
  );
  testWidgets(
    'dashboard fits Android width and exposes refresh and navigation drawer',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = Harness();
      await tester.runAsync(() async {
        await h.initialize();
        await h.login('A');
      });
      final boards = BoardsProvider(h.workspace);
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
          child: const MaterialApp(home: AccountDashboard()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Open navigation menu'), findsOneWidget);
      expect(find.byTooltip('Refresh cloud data'), findsOneWidget);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out'), findsOneWidget);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.text('Sign out'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('New Task'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      tasks.dispose();
      boards.dispose();
      h.dispose();
    },
  );
}

void expectReadable(WidgetTester tester, String label) {
  final text = find.text(label);
  final richText = tester.widget<RichText>(
    find.descendant(of: text, matching: find.byType(RichText)),
  );
  final foreground = richText.text.style!.color!;
  var background = Colors.transparent;
  for (final material in tester.widgetList<Material>(
    find.ancestor(of: text, matching: find.byType(Material)),
  )) {
    if (material.color != null) {
      background = Color.alphaBlend(background, material.color!);
      if (background.a == 1) break;
    }
  }
  expect(background.a, 1, reason: 'Opaque background behind $label');
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  final ratio = first > second
      ? (first + 0.05) / (second + 0.05)
      : (second + 0.05) / (first + 0.05);
  expect(ratio, greaterThanOrEqualTo(4.5), reason: 'Contrast for $label');
}
