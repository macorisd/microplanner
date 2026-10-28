import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Uses the API's UTF-16 length without splitting emoji or composed characters.
class ContractLengthFormatter extends TextInputFormatter {
  final int limit;
  const ContractLengthFormatter(this.limit);
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text.length > limit &&
        (!oldValue.composing.isValid || oldValue.composing.isCollapsed)) {
      return newValue.text.length <= oldValue.text.length ? newValue : oldValue;
    }
    if (newValue.text.length <= limit ||
        (newValue.composing.isValid && !newValue.composing.isCollapsed)) {
      return newValue;
    }
    var units = 0;
    for (final character in newValue.text.characters) {
      if (units + character.length > limit) break;
      units += character.length;
    }
    return newValue.copyWith(
      text: newValue.text.substring(0, units),
      selection: newValue.selection.copyWith(
        baseOffset: newValue.selection.baseOffset.clamp(-1, units),
        extentOffset: newValue.selection.extentOffset.clamp(-1, units),
      ),
      composing: TextRange.empty,
    );
  }
}

class LimitedTextField extends StatelessWidget {
  final TextEditingController controller;
  final int limit;
  final String? Function(String?) validator;
  final InputDecoration decoration;
  final bool autofocus;
  final bool enabled;
  final int? maxLines;
  final int? minLines;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final TextStyle? style;
  final TextInputType? keyboardType;
  const LimitedTextField({
    super.key,
    required this.controller,
    required this.limit,
    required this.validator,
    required this.decoration,
    this.autofocus = false,
    this.enabled = true,
    this.maxLines = 1,
    this.minLines,
    this.focusNode,
    this.onSubmitted,
    this.style,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    autofocus: autofocus,
    enabled: enabled,
    maxLines: maxLines,
    minLines: minLines,
    focusNode: focusNode,
    style: style,
    keyboardType: keyboardType,
    validator: validator,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    onFieldSubmitted: onSubmitted,
    onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
    maxLength: limit,
    maxLengthEnforcement: MaxLengthEnforcement.none,
    inputFormatters: [ContractLengthFormatter(limit)],
    buildCounter:
        (_, {required currentLength, required isFocused, required maxLength}) =>
            null,
    decoration: decoration.copyWith(
      suffix: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => value.text.length < limit * 0.8
            ? const SizedBox.shrink()
            : Text(
                '${value.text.length}/$limit',
                semanticsLabel: '${value.text.length} of $limit characters',
                style: Theme.of(context).textTheme.labelSmall,
              ),
      ),
    ),
  );
}
