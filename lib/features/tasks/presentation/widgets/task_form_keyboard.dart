import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Route-scoped submission also works when a picker leaves focus on its scope.
/// Handle it before focused buttons consume Enter, without intercepting popups.
class TaskFormKeyboard extends StatefulWidget {
  final FocusNode descriptionFocus;
  final bool canSubmit;
  final VoidCallback onSubmit;
  final Widget child;
  const TaskFormKeyboard({
    super.key,
    required this.descriptionFocus,
    required this.canSubmit,
    required this.onSubmit,
    required this.child,
  });

  @override
  State<TaskFormKeyboard> createState() => _TaskFormKeyboardState();
}

class _TaskFormKeyboardState extends State<TaskFormKeyboard> {
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_handle);
  }

  KeyEventResult _handle(KeyEvent event) {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        (event.logicalKey != LogicalKeyboardKey.enter &&
            event.logicalKey != LogicalKeyboardKey.numpadEnter)) {
      return KeyEventResult.ignored;
    }
    if (widget.descriptionFocus.hasFocus &&
        !(Theme.of(context).platform == TargetPlatform.windows &&
            HardwareKeyboard.instance.isControlPressed)) {
      return KeyEventResult.ignored;
    }
    if (!widget.canSubmit) return KeyEventResult.ignored;
    if (event is KeyDownEvent) widget.onSubmit();
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
