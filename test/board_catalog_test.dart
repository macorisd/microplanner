import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:microplanner/features/boards/data/board_catalog.dart';
import 'package:microplanner/core/theme/app_colors.dart';
import 'package:microplanner/features/boards/data/models/board.dart';
import 'package:microplanner/features/tasks/presentation/widgets/category_editor.dart';

void main() {
  test(
    'new boards default to the final gray without recoloring legacy boards',
    () {
      expect(
        Board.create(id: 'new', name: 'New board').color,
        boardColors.last,
      );
      expect(
        Board(id: 'old', name: 'Legacy board', createdAt: DateTime(2026)).color,
        0xff7986cb,
      );
    },
  );

  for (final useIcon in [false, true]) {
    testWidgets(
      'Windows category rows center their markers with breathing room, icon=$useIcon',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              platform: TargetPlatform.windows,
              visualDensity: VisualDensity.compact,
            ),
            home: Scaffold(
              body: SizedBox(
                width: 430,
                child: EditableCategoryList(
                  title: useIcon ? 'Task types' : 'Subjects',
                  label: useIcon ? 'task type' : 'subject',
                  useIcon: useIcon,
                  items: const [
                    CategoryDraft(id: 'one', name: 'A sample name'),
                    CategoryDraft(
                      id: 'two',
                      name:
                          'A longer name that wraps across multiple lines in a compact list',
                    ),
                  ],
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final title in [
          'A sample name',
          'A longer name that wraps across multiple lines in a compact list',
        ]) {
          final row = find.ancestor(
            of: find.text(title),
            matching: find.byType(ListTile),
          );
          final marker = find.descendant(
            of: row,
            matching: find.byWidgetPredicate(
              (widget) => widget is Icon && widget.size == 20,
            ),
          );
          final iconRect = tester.getRect(marker);
          final textRect = tester.getRect(find.text(title));
          expect(iconRect.center.dy, closeTo(textRect.center.dy, .5));
          expect(textRect.left - iconRect.right, greaterThanOrEqualTo(16));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('initial lists contain valid selectable icons and distinct names', () {
    expect(initialTypeLists.length, 5);
    expect(initialTypeLists.map((list) => list.name).toSet().length, 5);
    for (final list in initialTypeLists) {
      expect(list.types.length, lessThanOrEqualTo(25));
      expect(
        list.types.map((type) => type.name.toLowerCase()).toSet().length,
        list.types.length,
      );
      for (final type in list.types) {
        expect(boardIcons, contains(type.icon));
      }
    }
  });

  test('boards and subjects use the same existing pastel palette', () {
    expect(boardColors.length, 21);
    expect(boardColors.toSet().length, 21);
    for (final color in retiredCategoryColors.keys) {
      expect(boardColors, isNot(contains(color)));
    }
    expect(
      boardColors,
      AppColors.subjectColors.map((color) => color.toARGB32()).toList(),
    );
  });

  test('new palette additions are readable on their pastel backgrounds', () {
    for (final value in [0xffad7c32, 0xffa86178, 0xff568578, 0xff687f9c]) {
      final color = Color(value);
      final ratio =
          (boardRowBackground(color).computeLuminance() + .05) /
          (color.computeLuminance() + .05);
      expect(ratio, greaterThanOrEqualTo(3));
    }
  });

  test('chromatic presets follow the rainbow with neutral tones last', () {
    final hues = AppColors.subjectColors
        .take(19)
        .map((color) => HSVColor.fromColor(color).hue)
        .toList();
    expect(hues, orderedEquals([...hues]..sort()));
    expect(boardColors.skip(19), [0xffa1887f, 0xff90a4ae]);
  });

  for (final (platform, width) in [
    (TargetPlatform.windows, 432.0),
    (TargetPlatform.android, 328.0),
    (TargetPlatform.android, 256.0),
  ]) {
    testWidgets(
      '$platform color selector fits $width with consistent swatches',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: ColorChoices(color: 0xffad7c32, onChanged: (_) {}),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final rects = [
          for (var number = 1; number <= 21; number++)
            tester.getRect(find.byTooltip('Color $number')),
        ];
        expect(rects.map((rect) => rect.size).toSet(), {const Size(40, 40)});
        if (width >= 328) {
          expect(rects.map((rect) => rect.top).toSet().length, 3);
          final columns = platform == TargetPlatform.windows ? 9 : 7;
          for (var row = 0; row < 3; row++) {
            expect(
              rects
                  .skip(row * columns)
                  .take(columns)
                  .map((rect) => rect.top)
                  .toSet()
                  .length,
              1,
            );
          }
          expect(rects[columns].left, rects[0].left);
          expect(rects[1].left - rects[0].right, 8);
        }
        expect(rects.every((rect) => rect.right <= width), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('board backgrounds are pale tints of the existing palette', () {
    for (final value in [...boardColors, 0xff172b4d, 0xff000000, 0xffffffff]) {
      final color = Color(value);
      final background = boardRowBackground(color);
      expect(background.a, 1);
      expect(background.computeLuminance(), greaterThanOrEqualTo(.7));
      expect(
        background.computeLuminance(),
        greaterThanOrEqualTo(color.computeLuminance()),
      );
    }
  });
}
