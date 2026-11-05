import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:microplanner/core/theme/app_colors.dart';
import 'package:microplanner/core/widgets/bounded_reorderable_list.dart';
import 'package:microplanner/features/tasks/presentation/widgets/category_editor.dart';

void main() {
  for (final useIcon in [false, true]) {
    testWidgets(
      'Android ${useIcon ? 'type' : 'subject'} handle drags immediately and name requires a hold',
      (tester) async {
        var items = const [
          CategoryDraft(id: 'alpha', name: 'Alpha'),
          CategoryDraft(id: 'beta', name: 'Beta'),
          CategoryDraft(id: 'gamma', name: 'Gamma'),
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => SingleChildScrollView(
                  child: EditableCategoryList(
                    title: useIcon ? 'Task types' : 'Subjects',
                    label: useIcon ? 'task type' : 'subject',
                    useIcon: useIcon,
                    items: items,
                    onChanged: (value) => setState(() => items = value),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final handle = find.descendant(
          of: find.byKey(const ValueKey('beta')),
          matching: find.byIcon(Icons.drag_indicator_rounded),
        );
        final immediate = await tester.startGesture(
          tester.getCenter(handle) + const Offset(20, 0),
        );
        await immediate.moveBy(const Offset(0, 25));
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          find.byKey(const ValueKey('reorder-drag-surface')),
          findsOneWidget,
        );
        await immediate.moveTo(const Offset(500, 600));
        await tester.pump(const Duration(milliseconds: 100));
        await immediate.up();
        await tester.pumpAndSettle();
        expect(items.map((e) => e.id), ['alpha', 'gamma', 'beta']);
        final name = find.text('Beta');
        final quick = await tester.startGesture(tester.getCenter(name));
        await quick.moveBy(const Offset(0, -30));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.byKey(const ValueKey('reorder-drag-surface')),
          findsNothing,
        );
        await quick.up();
        await tester.pumpAndSettle();
        expect(items.map((e) => e.id), ['alpha', 'gamma', 'beta']);
        final held = await tester.startGesture(tester.getCenter(name));
        await tester.pump(const Duration(milliseconds: 1200));
        expect(
          find.text('Edit ${useIcon ? 'task type' : 'subject'}'),
          findsNothing,
        );
        await held.moveTo(const Offset(200, -300));
        await tester.pump(const Duration(milliseconds: 300));
        await held.up();
        await tester.pumpAndSettle();
        expect(items.map((e) => e.id), ['beta', 'alpha', 'gamma']);
        await tester.tap(find.text('Beta'));
        await tester.pumpAndSettle();
        expect(
          find.text(useIcon ? 'Edit task type' : 'Edit subject'),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final scrolled in [false, true]) {
      testWidgets(
        '$platform category drag stays in its visible list and paints complete rows (scrolled=$scrolled)',
        (tester) async {
          tester.view.physicalSize = const Size(620, 760);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final capture = GlobalKey();
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          var items = const [
            CategoryDraft(id: 'alpha', name: 'Alpha'),
            CategoryDraft(id: 'beta', name: 'Beta'),
            CategoryDraft(id: 'gamma', name: 'Gamma'),
          ];
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              home: RepaintBoundary(
                key: capture,
                child: Scaffold(
                  body: SizedBox(
                    height: scrolled ? 320 : 760,
                    child: SingleChildScrollView(
                      controller: scroll,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: StatefulBuilder(
                          builder: (context, setState) => Column(
                            children: [
                              const SizedBox(
                                height: 80,
                                child: Center(child: Text('Editor header')),
                              ),
                              EditableCategoryList(
                                title: 'Task types',
                                label: 'task type',
                                useIcon: true,
                                items: items,
                                onChanged: (value) =>
                                    setState(() => items = value),
                              ),
                              const SizedBox(
                                height: 300,
                                child: Center(child: Text('Footer')),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(PopupMenuButton<int>), findsNothing);
          if (scrolled) {
            scroll.jumpTo(210);
            await tester.pumpAndSettle();
          }
          final area = tester
              .getRect(find.byType(BoundedReorderableList))
              .intersect(tester.getRect(find.byType(SingleChildScrollView)));
          final row = find.byKey(const ValueKey('beta'));
          final handle = find.descendant(
            of: find.byKey(const ValueKey('beta')),
            matching: find.byIcon(Icons.drag_indicator_rounded),
          );
          // The outer edge of the enlarged target must work, not just the glyph.
          final gesture = await tester.startGesture(
            tester.getCenter(handle) + const Offset(20, 0),
          );
          if (platform == TargetPlatform.android) {
            expect(
              tester.widget<ReorderableDelayedDragStartListener>(row).enabled,
              isTrue,
            );
            await tester.pump(const Duration(milliseconds: 1200));
            expect(find.text('Edit task type'), findsNothing);
          }
          await tester.pump();
          await gesture.moveBy(const Offset(0, 5));
          await tester.pump(const Duration(milliseconds: 300));
          final proxy = find.byKey(const ValueKey('reorder-drag-surface'));
          for (final target in [
            const Offset(-500, -500),
            const Offset(1500, 1500),
          ]) {
            await gesture.moveTo(target);
            await tester.pump(const Duration(milliseconds: 700));
            final card = tester.getRect(proxy);
            expect(card.left, greaterThanOrEqualTo(area.left - .01));
            expect(card.right, lessThanOrEqualTo(area.right + .01));
            expect(card.top, greaterThanOrEqualTo(area.top - .01));
            expect(card.bottom, lessThanOrEqualTo(area.bottom + .01));
            expect(
              find.text('Beta'),
              findsOneWidget,
              reason: 'No drag tooltip duplicates the label',
            );
            final boundary =
                capture.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = (await tester.runAsync(
              () => boundary.toImage(pixelRatio: 1),
            ))!;
            final pixels = (await tester.runAsync(
              () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
            ))!;
            // Every stationary row keeps its own rounded gray surface while a
            // sibling is dragged; ListTile ink must not stay on the dialog material.
            for (final name in ['Alpha', 'Gamma']) {
              final tile = find.ancestor(
                of: find.text(name),
                matching: find.byType(ListTile),
              );
              final rect = tester.getRect(tile);
              final x = (rect.left + 36).round();
              final y = (rect.bottom - 6).round();
              if (!area.contains(Offset(x.toDouble(), y.toDouble()))) continue;
              final index = (y * image.width + x) * 4;
              final color = Color.fromARGB(
                pixels.getUint8(index + 3),
                pixels.getUint8(index),
                pixels.getUint8(index + 1),
                pixels.getUint8(index + 2),
              );
              expect(
                color,
                AppColors.surfaceVariant,
                reason: '$name keeps its background during drag',
              );
            }
            image.dispose();
          }
          await gesture.up();
          await tester.pumpAndSettle();
          expect(items.map((item) => item.id), ['alpha', 'gamma', 'beta']);
          final upward = await tester.startGesture(
            tester.getCenter(handle) + const Offset(20, 0),
          );
          if (platform == TargetPlatform.android) {
            await tester.pump(const Duration(milliseconds: 1200));
          }
          await upward.moveBy(const Offset(0, -5));
          await tester.pump();
          await upward.moveTo(
            Offset(tester.getCenter(handle).dx, area.top - 300),
          );
          await tester.pump(const Duration(milliseconds: 700));
          await upward.up();
          await tester.pumpAndSettle();
          expect(items.map((item) => item.id), ['beta', 'alpha', 'gamma']);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
