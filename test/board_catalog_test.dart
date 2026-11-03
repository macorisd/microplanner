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
