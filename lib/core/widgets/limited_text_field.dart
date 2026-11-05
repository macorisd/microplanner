import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'form_message.dart';

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

class LimitedTextField extends StatefulWidget {
  /// Align adjacent controls with the input surface rather than its message row.
  static double supportingHeightOf(BuildContext context, {int lines = 1}) =>
      FormMessage.heightOf(context, lines: lines) +
      (Theme.of(context).useMaterial3 ? 4 : 8);

  final TextEditingController controller;
  final int limit;
  final String? Function(String?) validator;
  final InputDecoration decoration;
  final bool autofocus;
  final bool validateOnBlur;
  final bool enabled;
  final int? maxLines;
  final int? minLines;
  final bool expands;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final TextStyle? style;
  final TextInputType? keyboardType;
  final String? errorText;
  final int validationLines;
  final List<TextInputFormatter> inputFormatters;
  const LimitedTextField({
    super.key,
    required this.controller,
    required this.limit,
    required this.validator,
    required this.decoration,
    this.autofocus = false,
    this.validateOnBlur = false,
    this.enabled = true,
    this.maxLines = 1,
    this.minLines,
    this.expands = false,
    this.focusNode,
    this.onSubmitted,
    this.style,
    this.keyboardType,
    this.errorText,
    this.validationLines = 1,
    this.inputFormatters = const [],
  });

  @override
  State<LimitedTextField> createState() => _LimitedTextFieldState();
}

class _LimitedTextFieldState extends State<LimitedTextField> {
  final _fieldKey = GlobalKey<FormFieldState<String>>();

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onFocusChange: (focused) {
      if (!focused && widget.validateOnBlur) _fieldKey.currentState?.validate();
    },
    child: _buildField(context),
  );

  Widget _buildField(BuildContext context) {
    final LimitedTextField(
      :controller,
      :autofocus,
      :enabled,
      :maxLines,
      :minLines,
      :expands,
      :focusNode,
      :style,
      :keyboardType,
      :validator,
      :errorText,
      :validationLines,
      :onSubmitted,
      :limit,
      :inputFormatters,
      :decoration,
    ) = widget;
    return TextFormField(
      key: _fieldKey,
      controller: controller,
      autofocus: autofocus,
      enabled: enabled,
      maxLines: maxLines,
      minLines: minLines,
      expands: expands,
      textAlignVertical: expands ? TextAlignVertical.top : null,
      focusNode: focusNode,
      style: style,
      keyboardType: keyboardType,
      textCapitalization:
          Theme.of(context).platform == TargetPlatform.android &&
              (keyboardType == null ||
                  keyboardType == TextInputType.text ||
                  keyboardType == TextInputType.multiline)
          ? TextCapitalization.sentences
          : TextCapitalization.none,
      validator: validator,
      forceErrorText: errorText,
      errorBuilder: (context, error) =>
          FormMessage(message: error, lines: validationLines),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onFieldSubmitted: onSubmitted,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      maxLength: limit,
      maxLengthEnforcement: MaxLengthEnforcement.none,
      inputFormatters: [...inputFormatters, ContractLengthFormatter(limit)],
      buildCounter:
          (
            _, {
            required currentLength,
            required isFocused,
            required maxLength,
          }) => null,
      decoration: decoration.copyWith(
        helper: FormMessage(lines: validationLines),
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
}
