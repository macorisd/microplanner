import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:microplanner/features/tasks/presentation/widgets/date_digits_formatter.dart';

TextEditingValue value(String text, [int? caret]) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: caret ?? text.length),
);

void main() {
  const formatter = DateDigitsFormatter();
  test(
    'typing eight digits inserts slashes and leaves caret after each separator',
    () {
      var old = value('');
      for (final digit in '19112026'.split('')) {
        old = formatter.formatEditUpdate(old, value(old.text + digit));
        expect(old.selection.baseOffset, old.text.length);
      }
      expect(old.text, '19/11/2026');
      expect(
        formatter.formatEditUpdate(value(''), value('19a/11-2026é٩9999')).text,
        '19/11/2026',
      );
    },
  );
  test(
    'backspace and forward delete on separators edit neighboring digits',
    () {
      expect(formatter.formatEditUpdate(value('19/'), value('19')), value('1'));
      expect(
        formatter.formatEditUpdate(value('19/11/', 3), value('1911/', 2)),
        value('11/1', 1),
      );
      expect(
        formatter.formatEditUpdate(
          value('19/11/2026', 2),
          value('1911/2026', 2),
        ),
        value('19/12/026', 3),
      );
    },
  );
  test(
    'middle replacements preserve digit positions and ignored keys preserve text',
    () {
      final old = value('19/11/2026', 6);
      expect(formatter.formatEditUpdate(old, value('19/11/x2026', 7)), old);
      expect(
        formatter.formatEditUpdate(old, value('19/12/2026', 5)),
        value('19/12/2026', 6),
      );
      final selected = formatter.formatEditUpdate(
        old,
        const TextEditingValue(
          text: '19/11/2026',
          selection: TextSelection(baseOffset: 3, extentOffset: 5),
        ),
      );
      expect(
        selected.selection,
        const TextSelection(baseOffset: 3, extentOffset: 6),
      );
    },
  );
}
