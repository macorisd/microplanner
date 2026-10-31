import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:microplanner/core/data/workspace_limits.dart';
import 'package:microplanner/core/data/workspace_snapshot.dart';
import 'package:microplanner/core/widgets/limited_text_field.dart';
import 'package:microplanner/features/boards/data/models/board.dart';
import 'package:microplanner/features/boards/data/models/subject.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'support/fakes.dart';

String repeat(String text, int count) => List.filled(count, text).join();
final sample = Task(
  id: 'sample',
  name: 'Sample',
  deadline: DateTime(2030),
  createdAt: DateTime(2026),
  typeIndex: 0,
  priorityIndex: 0,
  subject: '',
  boardId: 'default-board',
);

void main() {
  test('board title boundaries preserve unchanged legacy names', () async {
    expect(WorkspaceLimits.boardNameError(repeat('x', 50)), isNull);
    expect(WorkspaceLimits.boardNameError(repeat('x', 51)), isNotNull);
    final h = Harness();
    await h.initialize();
    await h.login('A');
    expect(
      await h.workspace.mutate(
        (s) => s.copyWith(
          boards: [s.boards.single.copyWith(name: repeat('x', 51))],
        ),
      ),
      isFalse,
    );
    expect(h.server.writes, 0);
    expect(
      await h.workspace.mutate(
        (s) => s.copyWith(
          boards: [s.boards.single.copyWith(name: repeat('x', 50))],
        ),
      ),
      isTrue,
    );
    final legacy = snapshot(repeat('x', 100));
    expect(WorkspaceLimits.validate(legacy, previous: legacy), isNull);
    expect(WorkspaceLimits.validate(legacy), isNotNull);
    expect(
      WorkspaceLimits.validate(snapshot(repeat('y', 100)), previous: legacy),
      isNotNull,
    );
    h.dispose();
  });

  test(
    'Unicode length enforcement respects the API limit without splitting a grapheme',
    () {
      const formatter = ContractLengthFormatter(300);
      TextEditingValue paste(String text) => formatter.formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      );
      expect(paste(repeat('a', 301)).text, repeat('a', 300));
      expect(paste(repeat('😀', 151)).text, repeat('😀', 150));
      expect(paste("${repeat('a', 299)}😀").text, repeat('a', 299));
      expect(paste("${repeat('a', 299)}e\u0301").text, repeat('a', 299));
      expect(paste(repeat('😀', 151)).selection.extentOffset, 300);
      final old = TextEditingValue(text: repeat('a', 350));
      expect(
        formatter.formatEditUpdate(old, TextEditingValue(text: '${old.text}b')),
        old,
      );
      final corrected = formatter.formatEditUpdate(
        old,
        TextEditingValue(text: repeat('a', 349)),
      );
      expect(
        corrected.text.length,
        349,
        reason: 'Do not silently truncate existing data.',
      );
      final composing = TextEditingValue(
        text: repeat('a', 301),
        composing: const TextRange(start: 299, end: 301),
      );
      expect(
        formatter.formatEditUpdate(TextEditingValue.empty, composing),
        composing,
      );
      expect(WorkspaceLimits.nameError(composing.text), isNotNull);
      expect(
        formatter
            .formatEditUpdate(
              composing,
              composing.copyWith(composing: TextRange.empty),
            )
            .text
            .length,
        300,
      );
    },
  );

  testWidgets(
    'existing oversized values stay intact and can be corrected explicitly',
    (tester) async {
      final controller = TextEditingController(text: repeat('x', 350));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LimitedTextField(
              controller: controller,
              limit: 300,
              validator: WorkspaceLimits.nameError,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
          ),
        ),
      );
      expect(controller.text.length, 350);
      await tester.enterText(find.byType(TextFormField), repeat('x', 349));
      await tester.pump();
      expect(controller.text.length, 349);
      expect(find.text('Use at most 300 characters.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Corrected');
      await tester.pump();
      expect(find.text('Use at most 300 characters.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  test(
    'boundary names and descriptions accepted by the server can be saved',
    () async {
      final h = Harness();
      await h.initialize();
      await h.login('A');
      final data = snapshot(repeat('😀', 25)).copyWith(
        tasks: [
          sample.copyWith(
            name: repeat('a', 300),
            description: repeat('z', 20000),
          ),
        ],
      );
      expect(await h.workspace.mutate((_) => data), isTrue);
      expect(h.server.writes, 1);
      h.dispose();
    },
  );

  final invalid = <String, WorkspaceSnapshot>{
    'blank name': snapshot('   '),
    'long name': snapshot(repeat('x', 301)),
    'long emoji name': snapshot(repeat('😀', 151)),
    'description': snapshot(
      'Board',
    ).copyWith(tasks: [sample.copyWith(description: repeat('x', 20001))]),
    'no boards': const WorkspaceSnapshot(),
    'too many boards': WorkspaceSnapshot(
      boards: List.generate(301, (i) => Board.create(id: 'b$i', name: 'Board')),
    ),
    'too many subjects': snapshot('Board').copyWith(
      subjects: List.generate(
        3001,
        (i) => Subject(id: 's$i', name: 'Subject', boardId: 'default-board'),
      ),
    ),
    'too many tasks': snapshot(
      'Board',
    ).copyWith(tasks: List.generate(10001, (i) => sample.copyWith(id: 't$i'))),
    'duplicate identifiers': snapshot(
      'Board',
    ).copyWith(tasks: [sample, sample]),
    'missing board': snapshot(
      'Board',
    ).copyWith(tasks: [sample.copyWith(boardId: 'missing')]),
    'missing subject': snapshot(
      'Board',
    ).copyWith(tasks: [sample.copyWith(subjectId: 'missing')]),
    'invalid color': snapshot('Board').copyWith(
      subjects: [
        const Subject(
          id: 's',
          name: 'Subject',
          boardId: 'default-board',
          color: -1,
        ),
      ],
    ),
    'unsupported date': snapshot(
      'Board',
    ).copyWith(tasks: [sample.copyWith(deadline: DateTime(10000))]),
    'invalid enum': snapshot('Board').copyWith(
      tasks: [
        Task(
          id: 't',
          name: 'Bad enum',
          deadline: DateTime(2030),
          createdAt: DateTime(2026),
          typeIndex: 7,
          priorityIndex: 0,
          subject: '',
          boardId: 'default-board',
        ),
      ],
    ),
    'unsafe identifier': snapshot(
      'Board',
    ).copyWith(tasks: [sample.copyWith(id: 'invalid/id')]),
    'oversized payload': snapshot('Board').copyWith(
      tasks: List.generate(
        201,
        (i) => sample.copyWith(id: 't$i', description: repeat('x', 20000)),
      ),
    ),
  };
  for (final entry in invalid.entries) {
    test(
      '${entry.key} is rejected before sending, keeping confirmed data',
      () async {
        final h = Harness();
        await h.initialize();
        await h.login('A');
        expect(await h.workspace.mutate((_) => entry.value), isFalse);
        expect(h.server.writes, 0);
        expect(h.workspace.error, isNotEmpty);
        expect(h.workspace.snapshot.boards.single.name, 'A private');
        expect(h.workspace.isOnline, isTrue);
        h.dispose();
      },
    );
  }

  test(
    'invalid legacy data do not consume the import or modify the originals',
    () async {
      final h = Harness();
      h.legacy.exists = true;
      h.legacy.contents = snapshot(repeat('x', 301));
      await h.initialize();
      await h.login('A');
      expect(await h.workspace.importLegacy(), isFalse);
      expect(h.legacy.contents!.boards.single.name.length, 301);
      expect(h.legacy.importedBy, isNull);
      expect(h.workspace.canImport, isTrue);
      expect(h.server.writes, 0);
      h.dispose();
    },
  );
}
