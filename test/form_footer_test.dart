import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:microplanner/core/theme/app_theme.dart';
import 'package:microplanner/core/widgets/form_actions.dart';
import 'package:microplanner/features/auth/data/auth_service.dart';
import 'package:microplanner/features/auth/presentation/login_screen.dart';
import 'package:microplanner/features/tasks/presentation/widgets/form_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/picker_actions.dart';

import 'support/fakes.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final scale in [1.0, 2.0]) {
      for (final width in [360.0, 800.0]) {
        testWidgets(
          '$platform rounded actions have balanced visible margins and stay fixed at text scale $scale, width $width',
          (tester) async {
            tester.view.physicalSize = Size(width, 700);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetViewInsets);
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.lightTheme.copyWith(platform: platform),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: FormDialog(
                    title: const Text('New default list'),
                    content: Column(
                      children: List.generate(35, (i) => Text('Type $i')),
                    ),
                    actions: [
                      TextButton(onPressed: () {}, child: const Text('Cancel')),
                      ElevatedButton(
                        onPressed: () {},
                        child: const Text('Create default list'),
                      ),
                    ],
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final footer = find.byType(FormFooter);
            final before = tester.getRect(footer);
            final cancel = find.widgetWithText(TextButton, 'Cancel');
            final proceed = find.widgetWithText(
              ElevatedButton,
              'Create default list',
            );
            Finder surface(Finder button) =>
                find.descendant(of: button, matching: find.byType(Material));
            final cancelSurface = surface(cancel);
            final proceedSurface = surface(proceed);
            expect(
              tester.widget<Material>(cancelSurface).shape,
              const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            );
            expect(
              tester.widget<Material>(proceedSurface).shape,
              const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            );
            expect(
              tester.getSize(cancelSurface).height,
              tester.getSize(proceedSurface).height,
            );
            expect(
              tester.getSize(cancelSurface).height,
              greaterThanOrEqualTo(
                platform == TargetPlatform.android ? 48 : 40,
              ),
            );
            final actionRect = tester.getRect(proceedSurface);
            expect(
              before.bottom - actionRect.bottom,
              before.right - actionRect.right,
            );
            expect(
              before.bottom - actionRect.bottom,
              platform == TargetPlatform.windows && width >= 600 ? 24 : 16,
            );
            final cancelRect = tester.getRect(cancelSurface);
            if (cancelRect.top == actionRect.top) {
              expect(actionRect.left - cancelRect.right, 8);
            }
            final buttonContext = tester.element(cancelSurface);
            expect(
              TextButtonTheme.of(buttonContext).style!.padding!.resolve({}),
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            );
            final press = await tester.startGesture(tester.getCenter(cancel));
            await tester.pump(const Duration(milliseconds: 120));
            expect(
              tester.widget<Material>(cancelSurface).shape,
              const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            );
            expect(
              tester.getSize(cancelSurface).height,
              tester.getSize(proceedSurface).height,
            );
            await press.up();
            await tester.pumpAndSettle();
            await tester.drag(
              find.byType(SingleChildScrollView),
              const Offset(0, -400),
            );
            await tester.pumpAndSettle();
            expect(tester.getRect(footer), before);
            tester.view.viewInsets = const FakeViewPadding(bottom: 220);
            await tester.pumpAndSettle();
            expect(tester.getRect(footer).bottom, lessThanOrEqualTo(480));
            expect(cancel.hitTestable(), findsOneWidget);
            expect(proceed.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
    for (final padding in [16.0, 24.0]) {
      testWidgets(
        '$platform picker actions keep visible margins balanced at inset $padding',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme.copyWith(platform: platform),
              home: Scaffold(
                body: Dialog(
                  child: Padding(
                    key: const ValueKey('picker-frame'),
                    padding: EdgeInsets.all(padding),
                    child: const PickerActions(
                      modeTooltip: 'Switch mode',
                      modeIcon: Icons.calendar_today,
                      onModeChanged: null,
                      onCancel: null,
                      showApply: true,
                      onApply: null,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final dialog = tester.getRect(
            find.byKey(const ValueKey('picker-frame')),
          );
          Finder surface(Type type) => find.descendant(
            of: find.byType(type),
            matching: find.byType(Material),
          );
          final apply = tester.getRect(surface(FilledButton));
          final cancel = tester.getRect(surface(TextButton));
          expect(dialog.bottom - apply.bottom, padding);
          expect(dialog.right - apply.right, padding);
          expect(cancel.height, apply.height);
          expect(cancel.center.dy, apply.center.dy);
          expect(apply.left - cancel.right, 8);
          expect(
            tester.widget<Material>(surface(FilledButton)).shape,
            const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'failed sign-in returns to the available Google action without an in-app Cancel',
    (tester) async {
      final h = Harness();
      await tester.runAsync(h.initialize);
      final pending = Completer<Map<String, dynamic>?>();
      h.google.pending = pending;
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: h.auth,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in with Google'));
      await tester.runAsync(settleAsync);
      await tester.pump(const Duration(milliseconds: 300));
      expect(h.auth.isLoading, isTrue);
      expect(find.text('Cancel'), findsNothing);
      await tester.runAsync(() async {
        pending.completeError(StateError('Provider failed'));
        await settleAsync();
      });
      await tester.pumpAndSettle();
      expect(h.auth.isLoading, isFalse);
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((widget) => widget is FilledButton),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text('Cancel'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      h.dispose();
    },
  );
}
