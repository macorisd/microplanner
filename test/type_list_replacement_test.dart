import 'package:flutter_test/flutter_test.dart';
import 'package:microplanner/features/boards/data/type_list_replacement.dart';

void main() {
  test('preserves unambiguous assignments and reports only affected tasks', () {
    const old = [
      BoardTypeEntry(id: 'homework', name: 'Homework', icon: 'book'),
      BoardTypeEntry(id: 'exam', name: 'Exam', icon: 'quiz'),
    ];
    final result = replaceTypeList(
      existing: old,
      replacement: const [
        TypeListEntry(name: ' homework ', icon: 'work'),
        TypeListEntry(name: 'Reading', icon: 'book'),
      ],
      newId: () => 'new-reading',
    );
    expect(result.types.map((type) => type.id), ['homework', 'new-reading']);
    expect(result.types.first.icon, 'work');
    expect(result.removedIds, {'exam'});
    expect(result.affectedTasks(['exam', 'homework', null, 'exam']), 2);
    expect(old.first.icon, 'book');
  });

  test('ambiguous names do not transfer assignments to an arbitrary type', () {
    var next = 0;
    final result = replaceTypeList(
      existing: const [
        BoardTypeEntry(id: 'a', name: 'Review', icon: 'one'),
        BoardTypeEntry(id: 'b', name: ' review ', icon: 'two'),
        BoardTypeEntry(id: 'c', name: 'Draft', icon: 'three'),
      ],
      replacement: const [
        TypeListEntry(name: 'REVIEW', icon: 'one'),
        TypeListEntry(name: 'Draft', icon: 'two'),
        TypeListEntry(name: 'draft', icon: 'three'),
      ],
      newId: () => 'new-${next++}',
    );
    expect(result.types.map((type) => type.id), ['new-0', 'new-1', 'new-2']);
    expect(result.removedIds, {'a', 'b', 'c'});
    expect(result.affectedTasks(['a', 'b', 'c', null]), 3);
  });

  test(
    'an empty list removes all existing types without affecting unassigned tasks',
    () {
      final result = replaceTypeList(
        existing: const [BoardTypeEntry(id: 'a', name: 'A', icon: 'one')],
        replacement: const [],
        newId: () => throw StateError('No IDs are needed'),
      );
      expect(result.types, isEmpty);
      expect(result.affectedTasks([null, 'a']), 1);
    },
  );
}
