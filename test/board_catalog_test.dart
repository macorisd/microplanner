import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:microplanner/features/boards/data/board_catalog.dart';
import 'package:microplanner/core/theme/app_colors.dart';

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

  test('boards and subjects use the same existing pastel palette', () {
    expect(
      boardColors,
      AppColors.subjectColors.map((color) => color.toARGB32()).toList(),
    );
  });

  test('the palest board colors stay legible without changing their color', () {
    for (final value in boardColors) {
      final foreground = Color(value);
      if (!boardRowUsesDarkBackground(foreground)) continue;
      for (final selected in [false, true]) {
        final background = boardRowBackground(
          foreground,
          selected: selected,
          hovered: false,
        );
        final contrast =
            (foreground.computeLuminance() + .05) /
            (background.computeLuminance() + .05);
        expect(
          contrast,
          greaterThanOrEqualTo(3),
          reason: value.toRadixString(16),
        );
      }
    }
  });
}
