import 'package:flutter/services.dart';

/// Accept ASCII digits and insert the separators of a dd/MM/yyyy date.
class DateDigitsFormatter extends TextInputFormatter {
  const DateDigitsFormatter();
  static final _digit = RegExp('[0-9]');

  static String _digits(String text) =>
      _digit.allMatches(text).map((m) => m[0]!).join();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = _digits(newValue.text);
    int countBefore(int offset) => _digits(
      newValue.text.substring(0, offset.clamp(0, newValue.text.length)),
    ).length;
    var base = countBefore(newValue.selection.baseOffset);
    var extent = countBefore(newValue.selection.extentOffset);
    // Backspace/Delete on an inserted slash edits the neighboring digit rather
    // than trapping the caret behind a separator that immediately reappears.
    if (oldValue.selection.isCollapsed &&
        newValue.selection.isCollapsed &&
        newValue.text.length == oldValue.text.length - 1 &&
        digits == _digits(oldValue.text)) {
      final backspace =
          newValue.selection.baseOffset < oldValue.selection.baseOffset;
      final index = backspace ? base - 1 : base;
      if (index >= 0 && index < digits.length) {
        digits = digits.replaceRange(index, index + 1, '');
        base = extent = index;
      }
    }
    if (digits.length > 8) digits = digits.substring(0, 8);
    final text = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      text.write(digits[i]);
      if (i == 1 || i == 3) text.write('/');
    }
    int caret(int count) {
      final n = count.clamp(0, digits.length);
      return n + (n >= 2 ? 1 : 0) + (n >= 4 ? 1 : 0);
    }

    return TextEditingValue(
      text: text.toString(),
      selection: TextSelection(
        baseOffset: caret(base),
        extentOffset: caret(extent),
      ),
    );
  }
}
