import 'package:flutter/material.dart';

import '../../../../core/widgets/form_actions.dart';
import 'editor_panel.dart';

/// A scrolling dialog body with the same fixed actions as named editors.
class FormDialog extends StatelessWidget {
  const FormDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => EditorPanel(
    dialog: true,
    footer: FormActions(children: actions),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DefaultTextStyle(
          style: Theme.of(context).textTheme.headlineSmall!,
          child: title,
        ),
        const SizedBox(height: 16),
        content,
      ],
    ),
  );
}
