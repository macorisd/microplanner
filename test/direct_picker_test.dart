import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_date_picker.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_time_picker.dart';

Future<void> open(
  WidgetTester tester,
  TargetPlatform platform,
  Widget picker,
  void Function(Object?) result, {
  bool use24 = true,
  Size size = const Size(800, 700),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en', 'GB'), Locale('en', 'US')],
      locale: use24 ? const Locale('en', 'GB') : const Locale('en', 'US'),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result(
              await showDialog<Object>(
                context: context,
                builder: (_) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(alwaysUse24HourFormat: use24),
                  child: picker,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets(
      '$platform year and month navigation wait for a day selection',
      (tester) async {
        Object? result;
        await open(
          tester,
          platform,
          TaskDatePickerDialog(
            initialDate: DateTime(2030, 1, 1),
            firstDate: DateTime(2020),
            lastDate: DateTime(2040),
          ),
          (value) => result = value,
        );
        await tester.tap(find.text('January 2030'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('2031'));
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(find.byType(CalendarDatePicker), findsOneWidget);
        await tester.tap(find.byTooltip('Next month'));
        await tester.pumpAndSettle();
        expect(result, isNull);
        await tester.tap(find.text('15').last);
        await tester.pumpAndSettle();
        expect(result, DateTime(2031, 2, 15));
      },
    );
    for (final day in [1, 15]) {
      testWidgets('$platform choosing day $day accepts once without OK', (
        tester,
      ) async {
        Object? result;
        var calls = 0;
        await open(
          tester,
          platform,
          TaskDatePickerDialog(
            initialDate: DateTime(2030, 1, 1),
            firstDate: DateTime(2020),
            lastDate: DateTime(2040),
          ),
          (value) {
            result = value;
            calls++;
          },
        );
        expect(find.text('OK'), findsNothing);
        await tester.tap(find.text('$day').last);
        await tester.pumpAndSettle();
        expect(result, DateTime(2030, 1, day));
        expect(calls, 1);
        expect(find.byType(TaskDatePickerDialog), findsNothing);
      });
    }

    testWidgets(
      '$platform hours advance, minutes accept, including unchanged minute',
      (tester) async {
        Object? result;
        await open(
          tester,
          platform,
          const TaskTimePickerDialog(
            initialTime: TimeOfDay(hour: 13, minute: 25),
          ),
          (value) => result = value,
        );
        expect(find.text('OK'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('hour-0')));
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(find.byKey(const ValueKey('minute-25')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('minute-25')));
        await tester.pumpAndSettle();
        expect(result, const TimeOfDay(hour: 0, minute: 25));
      },
    );

    testWidgets(
      '$platform taps between minute labels retain one-minute precision',
      (tester) async {
        Object? result;
        await open(
          tester,
          platform,
          const TaskTimePickerDialog(
            initialTime: TimeOfDay(hour: 10, minute: 0),
          ),
          (value) => result = value,
        );
        await tester.tap(find.byKey(const ValueKey('hour-10')));
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.byKey(const ValueKey('time-dial')));
        await tester.tapAt(
          rect.center + Offset(rect.width * .26765, -rect.width * .29726),
        );
        await tester.pumpAndSettle();
        expect(result, const TimeOfDay(hour: 10, minute: 7));
      },
    );

    testWidgets(
      '$platform minute drag commits at release with precise minute',
      (tester) async {
        Object? result;
        await open(
          tester,
          platform,
          const TaskTimePickerDialog(
            initialTime: TimeOfDay(hour: 10, minute: 0),
          ),
          (value) => result = value,
        );
        await tester.tap(find.byKey(const ValueKey('hour-10')));
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.byKey(const ValueKey('time-dial')));
        final gesture = await tester.startGesture(
          rect.center + const Offset(0, -100),
        );
        await gesture.moveTo(rect.center + const Offset(75, -30));
        await tester.pump();
        expect(result, isNull);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(result, const TimeOfDay(hour: 10, minute: 11));
      },
    );

    testWidgets(
      '$platform manual time rejects invalid values and Enter applies valid time',
      (tester) async {
        Object? result;
        await open(
          tester,
          platform,
          const TaskTimePickerDialog(
            initialTime: TimeOfDay(hour: 23, minute: 59),
          ),
          (value) => result = value,
          size: const Size(320, 480),
        );
        await tester.ensureVisible(find.byTooltip('Switch to input'));
        await tester.tap(find.byTooltip('Switch to input'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).first, '24');
        await tester.enterText(find.byType(TextFormField).last, '60');
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
              .onPressed,
          isNull,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(find.byType(TaskTimePickerDialog), findsOneWidget);
        await tester.enterText(find.byType(TextFormField).first, '00');
        await tester.enterText(find.byType(TextFormField).last, '01');
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
        await tester.pumpAndSettle();
        expect(result, const TimeOfDay(hour: 0, minute: 1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    '12-hour period remains correct through noon and minute acceptance',
    (tester) async {
      Object? result;
      await open(
        tester,
        TargetPlatform.windows,
        const TaskTimePickerDialog(initialTime: TimeOfDay(hour: 0, minute: 0)),
        (value) => result = value,
        use24: false,
      );
      await tester.tap(find.text('PM'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hour-12')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('minute-0')));
      await tester.pumpAndSettle();
      expect(result, const TimeOfDay(hour: 12, minute: 0));
    },
  );
}
