import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lets Enter invoke the picker's own confirmation and validation logic.
class PickerEnterConfirmation extends StatefulWidget {
  final Widget child;
  const PickerEnterConfirmation({super.key, required this.child});

  @override
  State<PickerEnterConfirmation> createState() =>
      _PickerEnterConfirmationState();
}

class _PickerEnterConfirmationState extends State<PickerEnterConfirmation> {
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_handle);
  }

  KeyEventResult _handle(KeyEvent event) {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        (event.logicalKey != LogicalKeyboardKey.enter &&
            event.logicalKey != LogicalKeyboardKey.numpadEnter) ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    VoidCallback? confirm;
    final label = MaterialLocalizations.of(context).okButtonLabel;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is ButtonStyleButton &&
          widget.child is Text &&
          (widget.child as Text).data == label) {
        confirm = widget.onPressed;
      }
      if (confirm == null) element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    if (confirm == null) return KeyEventResult.handled;
    if (event is KeyDownEvent) confirm!();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handle);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
