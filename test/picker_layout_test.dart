import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:microplanner/core/theme/app_theme.dart';
import 'package:microplanner/core/utils/task_date_range.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_date_picker.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_time_picker.dart';
import 'package:microplanner/features/tasks/presentation/widgets/picker_actions.dart';

Future<void> open(
  WidgetTester tester,
  TargetPlatform platform,
  double width,
  Widget picker,
) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme.copyWith(platform: platform),
      locale: const Locale('en', 'GB'),
      supportedLocales: const [Locale('en', 'GB')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open'),
            onPressed: () =>
                showDialog<void>(context: context, builder: (_) => picker),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'date bounds remain fixed while legacy picker initials are clamped safely',
    () {
      for (final year in [1, 1899, 1900, 2004, 2999, 3000, 9999]) {
        final deadline = DateTime(year, 6, 15, 23, 55);
        final range = TaskDateRange(deadline);
        expect(range.first, DateTime(1900));
        expect(range.last, DateTime(2999, 12, 31));
        expect(range.initial.isBefore(range.first), isFalse);
        expect(range.initial.isAfter(range.last), isFalse);
        expect(deadline.year, year);
      }
    },
  );

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final width in [320.0, 393.0, 900.0]) {
      testWidgets(
        '$platform $width picker footer controls share a horizontal center',
        (tester) async {
          for (final time in [false, true]) {
            final range = TaskDateRange(DateTime(2004, 4, 2));
            await open(
              tester,
              platform,
              width,
              time
                  ? const TaskTimePickerDialog(
                      initialTime: TimeOfDay(hour: 22, minute: 55),
                    )
                  : TaskDatePickerDialog(
                      initialDate: range.initial,
                      firstDate: range.first,
                      lastDate: range.last,
                    ),
            );
            await tester.ensureVisible(find.byTooltip('Switch to input'));
            final mode = tester.getCenter(find.byTooltip('Switch to input'));
            final inset = platform == TargetPlatform.windows
                ? (width < 600 ? 8 : 12)
                : (time ? 24 : 16);
            if (!time) {
              final calendar = tester.getRect(find.byType(CalendarDatePicker));
              final actions = tester.getRect(find.byType(PickerActions));
              expect(
                actions.top - calendar.bottom,
                platform == TargetPlatform.windows ? inset : 0,
              );
            }
            final footerRight =
                tester
                    .getRect(
                      find
                          .descendant(
                            of: find.byType(Dialog),
                            matching: find.byType(Material),
                          )
                          .first,
                    )
                    .right -
                inset;
            expect(
              tester.getRect(find.widgetWithText(TextButton, 'Cancel')).right,
              closeTo(footerRight, .1),
            );
            expect(
              tester.getCenter(find.widgetWithText(TextButton, 'Cancel')).dy,
              closeTo(mode.dy, .1),
            );
            await tester.tap(find.byTooltip('Switch to input'));
            await tester.pumpAndSettle();
            final toggle = find.byTooltip(
              time ? 'Switch to dial' : 'Switch to calendar',
            );
            await tester.ensureVisible(toggle);
            final center = tester.getCenter(toggle);
            expect(
              tester.getCenter(find.widgetWithText(TextButton, 'Cancel')).dy,
              closeTo(center.dy, .1),
            );
            final apply = find.widgetWithText(FilledButton, 'Apply');
            final applyRect = tester.getRect(apply);
            expect(applyRect.right, closeTo(footerRight, .1));
            final dialogSurface = tester.getRect(
              find
                  .descendant(
                    of: find.byType(Dialog),
                    matching: find.byType(Material),
                  )
                  .first,
            );
            expect(dialogSurface.bottom - applyRect.bottom, closeTo(inset, .1));
            if (width == 320) {
              // The test font has unusually wide glyphs: wrapping is permitted
              // when all controls cannot fit, with every action still reachable.
              expect(applyRect.center.dy, greaterThanOrEqualTo(center.dy));
              expect(applyRect.right, lessThanOrEqualTo(width - 16));
              expect(apply.hitTestable(), findsOneWidget);
            } else {
              expect(applyRect.center.dy, closeTo(center.dy, .1));
            }
            if (time && width >= 393) {
              final input = InputDecorator.containerOf(
                tester.element(find.byType(EditableText).first),
              )!;
              final rect = input.localToGlobal(Offset.zero) & input.size;
              expect(
                tester.getCenter(find.text(':')).dy,
                closeTo(rect.center.dy, .1),
              );
            }
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('Cancel'));
            await tester.pumpAndSettle();
          }
        },
      );
    }

    testWidgets(
      '$platform date entry waits for eight digits and inserts separators',
      (tester) async {
        await open(
          tester,
          platform,
          393,
          TaskDatePickerDialog(
            initialDate: DateTime(2026, 11, 19),
            firstDate: DateTime(1900),
            lastDate: DateTime(2999, 12, 31),
            input: true,
          ),
        );
        final field = find.byType(TextFormField);
        for (final digits in [
          '',
          '1',
          '19',
          '191',
          '1911',
          '19112',
          '191120',
          '1911202',
        ]) {
          await tester.enterText(field, digits);
          await tester.pump();
          expect(find.textContaining('before you were born'), findsNothing);
          expect(find.text('Enter a valid date.'), findsNothing);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Apply'),
                )
                .onPressed,
            isNull,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(find.byType(TaskDatePickerDialog), findsOneWidget);
        }
        await tester.enterText(field, '19x11-2026é٩');
        await tester.pump();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '19/11/2026',
        );
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
              .onPressed,
          isNotNull,
        );
        await tester.enterText(field, '31022026');
        await tester.pump();
        expect(find.text('Enter a valid date.'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
              .onPressed,
          isNull,
        );
        await tester.enterText(field, '3102202');
        await tester.pump();
        expect(find.text('Enter a valid date.'), findsNothing);
      },
    );

    testWidgets(
      '$platform date entry accepts wide bounds and uses friendly boundary errors',
      (tester) async {
        final range = TaskDateRange(DateTime(2004, 4, 2));
        await open(
          tester,
          platform,
          393,
          TaskDatePickerDialog(
            initialDate: range.initial,
            firstDate: range.first,
            lastDate: range.last,
            input: true,
          ),
        );
        for (final date in ['01/01/1900', '02/04/2004', '31/12/2999']) {
          await tester.enterText(find.byType(TextFormField), date);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Apply'),
                )
                .onPressed,
            isNotNull,
          );
        }
        await tester.enterText(find.byType(TextFormField), '31/12/1899');
        await tester.pumpAndSettle();
        expect(
          find.text(
            "A bit odd to plan something before you were born, isn't it?",
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
              .onPressed,
          isNull,
        );
        await tester.enterText(find.byType(TextFormField), '01/01/3000');
        await tester.pumpAndSettle();
        expect(
          find.text(
            "Trust me, you won't have to worry about this task by then.",
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
              .onPressed,
          isNull,
        );
        expect(find.textContaining('Use a date from'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
