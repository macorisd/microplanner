import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:microplanner/core/constants/app_constants.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/core/theme/app_colors.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_card.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_transition_visual.dart';
import 'support/fakes.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final name in [
      'Completed task',
      'A completed task title that wraps onto several lines',
    ]) {
      testWidgets(
        '$platform completed strike does not change when arrival ends: $name',
        (tester) async {
          final h = Harness();
          await tester.runAsync(() async {
            await h.initialize();
            await h.login('A');
          });
          final boards = BoardsProvider(h.workspace);
          var now = DateTime.now().subtract(const Duration(minutes: 1));
          final tasks = TasksProvider(h.workspace, boards, now: () => now);
          final original = Task.create(
            id: 'continuity',
            name: name,
            boardId: 'default-board',
            type: TaskType.unassigned,
            priority: TaskPriority.low,
            deadline: DateTime(2030),
          );
          final completed = original.copyWith(isCompleted: true);
          tasks.transitions.update('A', [original], []);
          tasks.transitions.update('A', [completed], []);
          var showingSource = true;
          const key = ValueKey('task-pixels');
          Widget app() => MultiProvider(
            providers: [
              ChangeNotifierProvider<WorkspaceController>.value(
                value: h.workspace,
              ),
              ChangeNotifierProvider<BoardsProvider>.value(value: boards),
              ChangeNotifierProvider<TasksProvider>.value(value: tasks),
            ],
            child: MaterialApp(
              theme: ThemeData(
                platform: platform,
                textTheme: const TextTheme(
                  titleMedium: TextStyle(
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 280,
                    child: RepaintBoundary(
                      key: key,
                      child: TaskCard(
                        task: showingSource ? original : completed,
                        onToggleComplete: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpWidget(app());
          await tester.pump();
          expect(
            find.byType(AnimatedTaskTitle),
            paints..line(color: AppColors.textTertiary),
          );
          showingSource = false;
          now = now.add(const Duration(milliseconds: 1001));
          tasks.transitions.update('A', [completed], []);
          await tester.pumpWidget(app());
          await tester.pump();
          expect(
            find.byType(AnimatedTaskTitle),
            paints..line(color: AppColors.textTertiary),
          );
          final titleRect = tester.getRect(find.text(name));
          final animated = await _pixels(tester, key, find.text(name));
          tasks.transitions.seed('A', [completed], now);
          await tester.pumpWidget(app());
          await tester.pumpAndSettle();
          expect(tester.getRect(find.text(name)), titleRect);
          final settled = await _pixels(tester, key, find.text(name));
          expect(settled.length, animated.length);
          var changed = 0;
          for (var i = 0; i < settled.length; i++) {
            if (settled[i] != animated[i]) changed++;
          }
          expect(
            changed,
            0,
            reason:
                'Finishing the arrival must not change the rendered strike.',
          );
          expect(
            tester.binding.transientCallbackCount,
            0,
            reason: 'Settled titles must not keep an animation ticker running.',
          );
          await tester.pumpWidget(const SizedBox());
          tasks.dispose();
          boards.dispose();
          h.dispose();
        },
      );
    }
  }
}

Future<Uint8List> _pixels(WidgetTester tester, Key key, Finder title) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final rect = tester.getRect(title).shift(-tester.getTopLeft(find.byKey(key)));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final rgba = bytes!.buffer.asUint8List();
      final left = (rect.left * 2).floor();
      final top = (rect.top * 2).floor();
      final width = (rect.right * 2).ceil() - left;
      final height = (rect.bottom * 2).ceil() - top;
      final result = Uint8List(width * height * 4);
      for (var row = 0; row < height; row++) {
        result.setRange(
          row * width * 4,
          (row + 1) * width * 4,
          rgba,
          ((top + row) * image.width + left) * 4,
        );
      }
      return result;
    } finally {
      image.dispose();
    }
  }))!;
}
