import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/core/notifications/notification_controller.dart';
import 'package:microplanner/core/theme/app_theme.dart';
import 'package:microplanner/features/tasks/presentation/widgets/account_pages.dart';
import 'package:microplanner/features/tasks/presentation/widgets/reminder_selector.dart';
import 'notifications_test.dart' show FakeNotifications;
import 'support/fakes.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets(
      '$platform Notifications is a sibling destination and Back preserves Customization',
      (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = Harness();
        final adapter = FakeNotifications()..precise = false;
        late NotificationController controller;
        await tester.runAsync(() async {
          await h.initialize();
          await h.login('A');
          controller = NotificationController(
            workspace: h.workspace,
            storage: h.storage,
            adapter: adapter,
          );
          await controller.reconcile();
        });
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<WorkspaceController>.value(
                value: h.workspace,
              ),
              ChangeNotifierProvider<NotificationController>.value(
                value: controller,
              ),
            ],
            child: MaterialApp(
              theme: ThemeData(
                platform: platform,
                colorScheme: AppTheme.lightColorScheme,
              ),
              home: Scaffold(body: SettingsPage(onBack: () {})),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Notifications'));
        await tester.pumpAndSettle();
        expect(
          find.text('Enable notifications on this device'),
          findsOneWidget,
        );
        expect(find.text('Default reminder'), findsOneWidget);
        await tester.tap(find.text('Enable notifications on this device'));
        await tester.runAsync(settleAsync);
        await tester.pumpAndSettle();
        expect(controller.device.enabled, isTrue);
        expect(
          adapter.exactAccessRequests,
          platform == TargetPlatform.android ? 1 : 0,
        );
        expect(
          find.textContaining('Short deadlines may be missed.'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Quiet hours'));
        await tester.tap(find.text('Quiet hours'));
        await tester.runAsync(settleAsync);
        await tester.pumpAndSettle();
        expect(controller.device.quietHours, isTrue);
        expect(tester.takeException(), isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Customization'), findsOneWidget);
        await tester.tap(find.text('Customization'));
        await tester.pumpAndSettle();
        expect(find.text('Boards'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Notifications'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        h.dispose();
      },
    );
  }
  testWidgets(
    'canceling Custom restores selector and invalid duration cannot save',
    (tester) async {
      int? current;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: AppTheme.lightColorScheme),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ReminderSelector(
                value: current,
                defaultMinutes: 1440,
                onChanged: (v) => setState(() => current = v),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom…').last);
      await tester.pumpAndSettle();
      final field = find.byType(TextFormField);
      await tester.enterText(field, '8');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Save changes'),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.text('Choose a duration from 1 minute to 7 days.'),
        findsWidgets,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(current, isNull);
      expect(find.text('Use default (1 day before)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
