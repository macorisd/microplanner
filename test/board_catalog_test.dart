import 'package:flutter_test/flutter_test.dart';
import 'package:microplanner/features/boards/data/board_catalog.dart';

void main() {
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
}
